import Foundation
import SQLite3
import Testing
@testable import ScanSongKit

private struct LivePSFRow {
    let archivePath: String
    let sourcePath: String
    let entryPath: String
    let pathExtension: String
    let trackIndex: Int
    let trackCount: Int
    let expected: ScannerMetadata
}

@Test(
    "MetaMan PSF-family projection matches the selected live catalog rows",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_PSF_LIVE_DB"] != nil,
        "Set SCANSONG_PSF_LIVE_DB to run read-only PSF-family parity against the live CocoaSpice catalog."
    )
)
func metaManPSFFamilyMatchesLiveCatalogRows() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_PSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_PSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let match = ProcessInfo.processInfo.environment["SCANSONG_PSF_LIVE_MATCH"]?.lowercased()
    var rows = try readLivePSFRows(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    if let match, !match.isEmpty {
        rows = rows.filter { "\($0.archivePath) \($0.entryPath)".lowercased().contains(match) }
    }
    #expect(!rows.isEmpty, "No PSF-family catalog rows matched root \(rootID).")

    let registry = BuiltInScannerPlugins.registry
    let extractor = StandaloneArchiveExtractor()
    var exactRows = 0
    var unavailableRows = 0
    var mismatches: [String] = []
    var inspectionTimes: [UInt64] = []
    var countsByExtension: [String: Int] = [:]

    var groups: [String: [LivePSFRow]] = [:]
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
                extraction.members.map { (normalizePSFEntry($0.entryPath), $0.fileURL) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        defer {
            if let extracted { extractor.discard(extracted) }
        }

        for row in sourceRows {
            let fileURL = archivePath.isEmpty
                ? URL(fileURLWithPath: row.sourcePath)
                : members[normalizePSFEntry(row.entryPath)]
            guard let fileURL else {
                unavailableRows += 1
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): source member unavailable")
                }
                continue
            }

            guard let route = registry.route(pathExtension: row.pathExtension, archiveMember: true),
                  let handler = BuiltInFormatInspectors.registry.handler(for: route) else {
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): no scanner route for .\(row.pathExtension)")
                }
                continue
            }

            let start = DispatchTime.now().uptimeNanoseconds
            let inspection: ScanInspection
            do {
                inspection = try await handler.inspect(fileURL: fileURL, route: route)
            } catch {
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): parser rejected source: \(error.localizedDescription)")
                }
                continue
            }
            inspectionTimes.append(DispatchTime.now().uptimeNanoseconds &- start)
            countsByExtension[row.pathExtension, default: 0] += 1

            guard inspection.tracks.count == 1,
                  let track = inspection.tracks.first,
                  track.trackIndex == row.trackIndex,
                  track.trackCount == row.trackCount,
                  let actual = track.metadata else {
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): track structure or metadata changed")
                }
                continue
            }
            guard actual == row.expected else {
                if mismatches.count < 30 {
                    mismatches.append("\(sourceKey)#\(row.entryPath): \(psfMetadataDelta(actual, row.expected))")
                }
                continue
            }
            exactRows += 1
        }
    }

    #expect(unavailableRows == 0, "\(unavailableRows) of \(rows.count) catalog members could not be found.")
    #expect(exactRows == rows.count, "\(exactRows) exact rows out of \(rows.count).")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))
    let extensionSummary = countsByExtension.sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
    print(
        "PSF-family catalog parity: root \(rootID), \(exactRows) exact / \(rows.count); "
            + "\(groups.count) source containers [\(extensionSummary)]; inspection median "
            + "\(psfMilliseconds(psfMedian(inspectionTimes))) ms, p95 "
            + "\(psfMilliseconds(psfPercentile95(inspectionTimes))) ms per member"
    )
}

private func readLivePSFRows(databaseURL: URL, rootID: Int) throws -> [LivePSFRow] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the PSF catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongPSFLiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.archive_path, t.path, COALESCE(t.archive_entry, t.filename), lower(t.extension),
               t.track_index, t.track_count,
               m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) IN
               ('ssf', 'minissf', 'usf', 'miniusf', '2sf', 'mini2sf', 'psf', 'minipsf', 'psf2', 'minipsf2')
         ORDER BY COALESCE(t.archive_path, t.path), t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongPSFLiveTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongPSFLiveTests", code: 3)
    }

    var rows: [LivePSFRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let expected = ScannerMetadata(
            game: livePSFText(statement, 6),
            song: livePSFText(statement, 7),
            system: livePSFText(statement, 8),
            author: livePSFText(statement, 9),
            comment: livePSFText(statement, 10),
            introLengthMs: Int(sqlite3_column_int64(statement, 11)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 12)),
            playLengthMs: Int(sqlite3_column_int64(statement, 13)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 14))
        )
        rows.append(LivePSFRow(
            archivePath: livePSFText(statement, 0),
            sourcePath: livePSFText(statement, 1),
            entryPath: livePSFText(statement, 2),
            pathExtension: livePSFText(statement, 3),
            trackIndex: Int(sqlite3_column_int64(statement, 4)),
            trackCount: Int(sqlite3_column_int64(statement, 5)),
            expected: expected
        ))
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongPSFLiveTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return rows
}

private func livePSFText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func normalizePSFEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func psfMetadataDelta(_ actual: ScannerMetadata, _ expected: ScannerMetadata) -> String {
    let fields: [(String, String, String)] = [
        ("game", actual.game, expected.game), ("title", actual.song, expected.song),
        ("system", actual.system, expected.system), ("author", actual.author, expected.author),
        ("comment", actual.comment, expected.comment), ("intro", String(actual.introLengthMs), String(expected.introLengthMs)),
        ("loop", String(actual.loopLengthMs), String(expected.loopLengthMs)),
        ("play", String(actual.playLengthMs), String(expected.playLengthMs)), ("fade", String(actual.fadeLengthMs), String(expected.fadeLengthMs))
    ]
    return fields.filter { $0.1 != $0.2 }
        .map { "\($0.0): actual=\($0.1) catalog=\($0.2)" }
        .joined(separator: "; ")
}

private func psfMedian(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    return values.sorted()[values.count / 2]
}

private func psfPercentile95(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
}

private func psfMilliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}
