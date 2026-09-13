import Foundation
import MetaManCore
import SQLite3
import Testing
@testable import ScanSongKit

private struct LiveVGMRow {
    let archivePath: String
    let sourcePath: String
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let expected: ScannerMetadata
}

@Test(
    "MetaMan VGM/VGZ projection comparison classifies GD3 system-label deltas",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_VGM_LIVE_DB"] != nil,
        "Set SCANSONG_VGM_LIVE_DB to run read-only VGM/VGZ parity against the live CocoaSpice catalog."
    )
)
func metaManVGMMatchesLiveCatalogRows() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_VGM_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_VGM_LIVE_ROOT_ID"] ?? "1") ?? 1
    let match = ProcessInfo.processInfo.environment["SCANSONG_VGM_LIVE_MATCH"]?.lowercased()
    var rows = try readLiveVGMRows(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    if let match, !match.isEmpty {
        rows = rows.filter { "\($0.archivePath) \($0.entryPath)".lowercased().contains(match) }
    }
    #expect(!rows.isEmpty, "No VGM/VGZ catalog rows matched root \(rootID).")

    let registry = BuiltInScannerPlugins.registry
    let extractor = StandaloneArchiveExtractor()
    let route = try #require(registry.route(pathExtension: "vgm", archiveMember: true))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    var exactRows = 0
    var gd3SystemDifferences = 0
    var unavailableRows = 0
    var mismatches: [String] = []
    var inspectionTimes: [UInt64] = []

    var groups: [String: [LiveVGMRow]] = [:]
    for row in rows {
        let key = row.archivePath.isEmpty ? "file:\(row.sourcePath)" : row.archivePath
        groups[key, default: []].append(row)
    }

    for (sourceKey, sourceRows) in groups.sorted(by: { $0.key < $1.key }) {
        let archivePath = sourceRows[0].archivePath
        var extracted: ExtractedScanArchive?
        var members: [String: URL] = [:]
        if !archivePath.isEmpty {
            let extraction = try await extractor.extractForScan(
                archiveURL: URL(fileURLWithPath: archivePath),
                registry: registry
            )
            extracted = extraction
            members = Dictionary(
                extraction.members.map { (normalizeVGMEntry($0.entryPath), $0.fileURL) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        defer {
            if let extracted { extractor.discard(extracted) }
        }

        for row in sourceRows {
            let fileURL: URL?
            if archivePath.isEmpty {
                fileURL = URL(fileURLWithPath: row.sourcePath)
            } else {
                fileURL = members[normalizeVGMEntry(row.entryPath)]
            }
            guard let fileURL else {
                unavailableRows += 1
                if mismatches.count < 30 { mismatches.append("\(sourceKey)#\(row.entryPath): source member unavailable") }
                continue
            }

            let start = DispatchTime.now().uptimeNanoseconds
            let inspection: ScanInspection
            do {
                inspection = try await handler.inspect(fileURL: fileURL, route: route)
            } catch {
                if mismatches.count < 30 { mismatches.append("\(sourceKey)#\(row.entryPath): parser rejected source: \(error.localizedDescription)") }
                continue
            }
            inspectionTimes.append(DispatchTime.now().uptimeNanoseconds &- start)

            guard inspection.tracks.count == 1,
                  let track = inspection.tracks.first,
                  track.trackIndex == row.trackIndex,
                  track.trackCount == row.trackCount,
                  let actual = track.metadata else {
                if mismatches.count < 30 { mismatches.append("\(sourceKey)#\(row.entryPath): track structure changed") }
                continue
            }
            guard actual == row.expected else {
                do {
                    if try isGD3SystemOnlyDifference(
                        actual: actual,
                        catalog: row.expected,
                        fileURL: fileURL
                    ) {
                        gd3SystemDifferences += 1
                        continue
                    }
                } catch {
                    if mismatches.count < 30 {
                        mismatches.append("\(sourceKey)#\(row.entryPath): GD3 system verification failed: \(error.localizedDescription)")
                    }
                    continue
                }
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): \(metadataDelta(actual, row.expected))")
                }
                continue
            }
            exactRows += 1
        }
    }

    #expect(unavailableRows == 0, "\(unavailableRows) of \(rows.count) catalog members could not be found.")
    #expect(
        exactRows + gd3SystemDifferences == rows.count,
        "\(exactRows) exact rows and \(gd3SystemDifferences) GD3 system-label-only differences out of \(rows.count)."
    )
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))
    print(
        "VGM/VGZ catalog comparison: root \(rootID), \(exactRows) exact, \(gd3SystemDifferences) GD3 system-label-only differences / \(rows.count); "
            + "\(groups.count) source containers; inspection median \(milliseconds(median(inspectionTimes))) ms, "
            + "p95 \(milliseconds(percentile95(inspectionTimes))) ms per member"
    )
}

private func readLiveVGMRows(databaseURL: URL, rootID: Int) throws -> [LiveVGMRow] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the VGM catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongVGMLiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.archive_path, t.path, COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count,
               m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) IN ('vgm', 'vgz')
         ORDER BY COALESCE(t.archive_path, t.path), t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongVGMLiveTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongVGMLiveTests", code: 3)
    }

    var rows: [LiveVGMRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let expected = ScannerMetadata(
            game: liveVGMText(statement, 5),
            song: liveVGMText(statement, 6),
            system: liveVGMText(statement, 7),
            author: liveVGMText(statement, 8),
            comment: liveVGMText(statement, 9),
            introLengthMs: Int(sqlite3_column_int64(statement, 10)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 11)),
            playLengthMs: Int(sqlite3_column_int64(statement, 12)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 13))
        )
        rows.append(LiveVGMRow(
            archivePath: liveVGMText(statement, 0),
            sourcePath: liveVGMText(statement, 1),
            entryPath: liveVGMText(statement, 2),
            trackIndex: Int(sqlite3_column_int64(statement, 3)),
            trackCount: Int(sqlite3_column_int64(statement, 4)),
            expected: expected
        ))
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongVGMLiveTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return rows
}

private func liveVGMText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func normalizeVGMEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func metadataDelta(_ actual: ScannerMetadata, _ expected: ScannerMetadata) -> String {
    let fields: [(String, String, String)] = [
        ("game", actual.game, expected.game),
        ("title", actual.song, expected.song),
        ("system", actual.system, expected.system),
        ("author", actual.author, expected.author),
        ("comment", actual.comment, expected.comment),
        ("intro", String(actual.introLengthMs), String(expected.introLengthMs)),
        ("loop", String(actual.loopLengthMs), String(expected.loopLengthMs)),
        ("play", String(actual.playLengthMs), String(expected.playLengthMs)),
        ("fade", String(actual.fadeLengthMs), String(expected.fadeLengthMs))
    ]
    return fields.filter { $0.1 != $0.2 }
        .map { "\($0.0): actual=\($0.1) catalog=\($0.2)" }
        .joined(separator: "; ")
}

private func isGD3SystemOnlyDifference(
    actual: ScannerMetadata,
    catalog: ScannerMetadata,
    fileURL: URL
) throws -> Bool {
    guard actual.system != catalog.system,
          actual.game == catalog.game,
          actual.song == catalog.song,
          actual.author == catalog.author,
          actual.comment == catalog.comment,
          actual.introLengthMs == catalog.introLengthMs,
          actual.loopLengthMs == catalog.loopLengthMs,
          actual.playLengthMs == catalog.playLengthMs,
          actual.fadeLengthMs == catalog.fadeLengthMs else { return false }

    let document = try MetaManCore.read(fileURL: fileURL)
    guard document.fields.system == actual.system,
          document.value(forTag: "system_english") == actual.system else {
        throw NSError(
            domain: "ScanSongVGMLiveTests",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "MetaMan system projection does not match the retained English GD3 system tag."]
        )
    }
    return true
}

private func median(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

private func percentile95(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
}

private func milliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}
