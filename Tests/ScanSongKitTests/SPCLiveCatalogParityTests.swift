import Foundation
import MetaManCore
import SQLite3
import Testing
@testable import ScanSongKit

private struct LiveSPCRow {
    let archivePath: String
    let sourcePath: String
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let expected: ScannerMetadata
}

@Test(
    "MetaMan SPC projection compares selected live rows with catalog and libgme",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SPC_LIVE_DB"] != nil,
        "Set SCANSONG_SPC_LIVE_DB to run read-only SPC parity against the live CocoaSpice catalog."
    )
)
func metaManSPCMatchesLiveCatalogRows() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_SPC_LIVE_DB"])
    let rootIDs = (ProcessInfo.processInfo.environment["SCANSONG_SPC_LIVE_ROOT_IDS"] ?? "1,8")
        .split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    #expect(!rootIDs.isEmpty)

    let registry = BuiltInScannerPlugins.registry
    let extractor = StandaloneArchiveExtractor()
    for rootID in rootIDs {
        var rows = try readLiveSPCRows(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
        let sourceMatch = ProcessInfo.processInfo.environment["SCANSONG_SPC_LIVE_MATCH"]?.lowercased()
        if let sourceMatch, !sourceMatch.isEmpty {
            rows = rows.filter { "\($0.archivePath) \($0.entryPath)".lowercased().contains(sourceMatch) }
        }
        #expect(!rows.isEmpty, "No SPC rows found for live root \(rootID).")
        var groups: [String: [LiveSPCRow]] = [:]
        for row in rows {
            let key = row.archivePath.isEmpty ? "file:\(row.sourcePath)" : row.archivePath
            groups[key, default: []].append(row)
        }

        var catalogExactRows = 0
        var decoderExactRows = 0
        var decoderCatalogExactRows = 0
        var explainedDecoderDifferenceRows = 0
        var extendedTimingImprovementRows = 0
        var textID666LengthRows = 0
        var id666FadeRows = 0
        var fiveDigitID666FadeRows = 0
        var taggedZeroTimingDefaultRows = 0
        var unexplainedDecoderRows = 0
        var unexplainedCatalogRows = 0
        var decoderUnavailableRows = 0
        var unavailableRows = 0
        var inspectedRows = 0
        var routeContractFailureRows = 0
        var differences: [String] = []
        var unexplainedDecoderSamples: [String] = []
        var unexplainedCatalogSamples: [String] = []
        var inspectionTimes: [UInt64] = []
        var decoderInspectionTimes: [UInt64] = []

        for (groupIndex, group) in groups.sorted(by: { $0.key < $1.key }).enumerated() {
            let (sourceKey, sourceRows) = group
            let archivePath = sourceRows[0].archivePath
            var extracted: ExtractedScanArchive?
            var members: [String: URL] = [:]
            if !archivePath.isEmpty {
                do {
                    let extraction = try await extractor.extractForScan(
                        archiveURL: URL(fileURLWithPath: archivePath),
                        registry: registry
                    )
                    extracted = extraction
                    members = Dictionary(
                        extraction.members.map { (normalizeSPCEntry($0.entryPath), $0.fileURL) },
                        uniquingKeysWith: { first, _ in first }
                    )
                } catch {
                    unavailableRows += sourceRows.count
                    if differences.count < 30 {
                        differences.append("\(sourceKey): archive extraction failed: \(error.localizedDescription)")
                    }
                    continue
                }
            }
            defer {
                if let extracted { extractor.discard(extracted) }
            }

            for row in sourceRows {
                let fileURL = archivePath.isEmpty
                    ? URL(fileURLWithPath: row.sourcePath)
                    : members[normalizeSPCEntry(row.entryPath)]
                guard let fileURL else {
                    unavailableRows += 1
                    if differences.count < 30 {
                        differences.append("\(sourceKey)#\(row.entryPath): source member unavailable")
                    }
                    continue
                }

                guard let route = registry.route(pathExtension: "spc", archiveMember: true),
                      let handler = BuiltInFormatInspectors.registry.handler(for: route) else {
                    routeContractFailureRows += 1
                    if differences.count < 30 { differences.append("No scanner route for SPC member \(sourceKey)#\(row.entryPath).") }
                    continue
                }

                let started = DispatchTime.now().uptimeNanoseconds
                let inspection: ScanInspection
                do {
                    inspection = try await handler.inspect(fileURL: fileURL, route: route)
                } catch {
                    routeContractFailureRows += 1
                    if differences.count < 30 {
                        differences.append("\(sourceKey)#\(row.entryPath): MetaMan rejected source: \(error.localizedDescription)")
                    }
                    continue
                }
                inspectionTimes.append(DispatchTime.now().uptimeNanoseconds &- started)
                inspectedRows += 1

                guard inspection.tracks.count == 1,
                      let track = inspection.tracks.first,
                      track.trackIndex == row.trackIndex,
                      track.trackCount == row.trackCount,
                      let actual = track.metadata else {
                    routeContractFailureRows += 1
                    if differences.count < 30 { differences.append("\(sourceKey)#\(row.entryPath): track structure or metadata changed") }
                    continue
                }

                let sourceDocument = try MetaManCore.read(fileURL: fileURL)
                let decoderStarted = DispatchTime.now().uptimeNanoseconds
                let legacy = gmeInfoOnlyMetadata(fileURL: fileURL)?.first
                decoderInspectionTimes.append(DispatchTime.now().uptimeNanoseconds &- decoderStarted)
                if let legacy {
                    if actual == legacy {
                        decoderExactRows += 1
                    } else {
                        let unexplainedFields = spcUnexplainedDecoderDifferences(
                            document: sourceDocument,
                            actual: actual,
                            legacy: legacy
                        )
                        if unexplainedFields.isEmpty {
                            explainedDecoderDifferenceRows += 1
                            if sourceDocument.rawMetadataBlocks?["xid6"] != nil,
                               sourceDocument.tags.contains(where: {
                                   ["Intro Length (ms)", "Loop Length (ms)", "End Length (ms)", "Fade Length (ms)"]
                                       .contains($0.name)
                               }),
                               spcMetadataDifferenceFields(actual, legacy).contains(where: { ["intro", "loop", "play", "fade"].contains($0) }) {
                                extendedTimingImprovementRows += 1
                            }
                            let differentFields = spcMetadataDifferenceFields(actual, legacy)
                            if differentFields.contains("play"), actual.playLengthMs.isMultiple(of: 1_000),
                               ["text", "text-fallback"].contains(sourceDocument.technicalFacts["id666PlayTimingLayout"] ?? ""),
                               spcHasNumericTag(sourceDocument, "Length (seconds)", value: actual.playLengthMs / 1_000) {
                                textID666LengthRows += 1
                            }
                            if differentFields.contains("fade"),
                               spcHasNumericTag(sourceDocument, "Fade (milliseconds)", value: actual.fadeLengthMs) {
                                id666FadeRows += 1
                                if sourceDocument.values(forTag: "Fade (milliseconds)").contains(where: { $0.count == 5 }) {
                                    fiveDigitID666FadeRows += 1
                                }
                            }
                            let differences = differentFields
                            if (differences.contains("intro") && actual.introLengthMs == 0)
                                || (differences.contains("loop") && actual.loopLengthMs == 0),
                               sourceDocument.technicalFacts["hasID666"] == "true"
                                || sourceDocument.technicalFacts["hasXID6"] == "true" {
                                taggedZeroTimingDefaultRows += 1
                            }
                        } else {
                            unexplainedDecoderRows += 1
                            if unexplainedDecoderSamples.count < 30 {
                                unexplainedDecoderSamples.append(
                                    "\(sourceKey)#\(row.entryPath): fields [\(unexplainedFields.joined(separator: ", "))]; "
                                        + spcMetadataDelta(actual, legacy)
                                )
                            }
                            if differences.count < 30 {
                                differences.append(
                                    "\(sourceKey)#\(row.entryPath): UNEXPLAINED MetaMan/libgme difference "
                                        + "[\(unexplainedFields.joined(separator: ", "))]; "
                                        + spcMetadataDelta(actual, legacy)
                                )
                            }
                        }
                    }
                    if legacy == row.expected { decoderCatalogExactRows += 1 }
                } else {
                    decoderUnavailableRows += 1
                    if differences.count < 30 {
                        differences.append("\(sourceKey)#\(row.entryPath): libgme info-only rejected source")
                    }
                }

                if actual == row.expected {
                    catalogExactRows += 1
                } else {
                    if let legacy {
                        let unexplainedFields = spcUnexplainedCatalogDifferences(
                            document: sourceDocument,
                            actual: actual,
                            catalog: row.expected,
                            legacy: legacy
                        )
                        if !unexplainedFields.isEmpty {
                            unexplainedCatalogRows += 1
                            if unexplainedCatalogSamples.count < 30 {
                                unexplainedCatalogSamples.append(
                                    "\(sourceKey)#\(row.entryPath): catalog fields [\(unexplainedFields.joined(separator: ", "))]; "
                                        + spcMetadataDelta(actual, row.expected)
                                )
                            }
                        }
                    }
                    if differences.count < 30 {
                        let classification: String
                        if let legacy, actual == legacy {
                            classification = "catalog differs; MetaMan=libgme"
                        } else if let legacy, legacy == row.expected {
                            classification = "MetaMan differs; catalog=libgme"
                        } else {
                            classification = "catalog differs from MetaMan and libgme"
                        }
                        differences.append(
                            "\(sourceKey)#\(row.entryPath): \(classification); "
                                + "MetaMan/catalog: \(spcMetadataDelta(actual, row.expected))"
                        )
                    }
                }
            }

            if (groupIndex + 1).isMultiple(of: 250) {
                print("SPC live parity progress: root \(rootID), \(groupIndex + 1)/\(groups.count) sources, \(catalogExactRows) catalog-exact rows.")
            }
        }

        #expect(unavailableRows == 0, "\(unavailableRows) of \(rows.count) root-\(rootID) SPC members could not be read.")
        #expect(inspectedRows == rows.count, "\(inspectedRows) of \(rows.count) root-\(rootID) SPC members reached the direct route.")
        #expect(routeContractFailureRows == 0, "\(routeContractFailureRows) root-\(rootID) rows failed route or track-structure validation.\n\(differences.joined(separator: "\n"))")
        #expect(decoderUnavailableRows == 0, "libgme info-only could not read \(decoderUnavailableRows) root-\(rootID) SPC members.")
        #expect(unexplainedDecoderRows == 0, "\(unexplainedDecoderRows) root-\(rootID) rows differ from libgme without a supported source explanation.\n\(unexplainedDecoderSamples.joined(separator: "\n"))")
        #expect(unexplainedCatalogRows == 0, "\(unexplainedCatalogRows) root-\(rootID) catalog differences are not either libgme-equivalent or source-explained.\n\(unexplainedCatalogSamples.joined(separator: "\n"))")
        print(
            "SPC live parity: root \(rootID), \(rows.count) rows, \(groups.count) source containers; "
                + "MetaMan/catalog exact \(catalogExactRows), MetaMan/libgme exact \(decoderExactRows), "
                + "catalog/libgme exact \(decoderCatalogExactRows), format-explained MetaMan/libgme differences \(explainedDecoderDifferenceRows) "
                + "(xID6 timing \(extendedTimingImprovementRows), text ID666 length \(textID666LengthRows), "
                + "ID666 fade \(id666FadeRows), five-digit fade \(fiveDigitID666FadeRows), "
                + "tagged zero timing defaults \(taggedZeroTimingDefaultRows)), "
                + "unexplained MetaMan/libgme differences \(unexplainedDecoderRows), "
                + "unexplained MetaMan/catalog differences \(unexplainedCatalogRows); MetaMan median/p95 "
                + "\(spcMilliseconds(spcMedian(inspectionTimes)))/\(spcMilliseconds(spcPercentile95(inspectionTimes))) ms, "
                + "libgme info-only median/p95 \(spcMilliseconds(spcMedian(decoderInspectionTimes)))/\(spcMilliseconds(spcPercentile95(decoderInspectionTimes))) ms per member."
        )
        if !differences.isEmpty {
            print("SPC live parity differences (first \(differences.count), capped at 30):\n" + differences.joined(separator: "\n"))
        }
    }
}

private func readLiveSPCRows(databaseURL: URL, rootID: Int) throws -> [LiveSPCRow] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the SPC catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongSPCLiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
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
         WHERE t.root_id = ?1 AND lower(t.extension) = 'spc'
         ORDER BY COALESCE(t.archive_path, t.path), t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongSPCLiveTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongSPCLiveTests", code: 3)
    }

    var rows: [LiveSPCRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        rows.append(LiveSPCRow(
            archivePath: spcColumnText(statement, 0),
            sourcePath: spcColumnText(statement, 1),
            entryPath: spcColumnText(statement, 2),
            trackIndex: Int(sqlite3_column_int64(statement, 3)),
            trackCount: Int(sqlite3_column_int64(statement, 4)),
            expected: ScannerMetadata(
                game: spcColumnText(statement, 5),
                song: spcColumnText(statement, 6),
                system: spcColumnText(statement, 7),
                author: spcColumnText(statement, 8),
                comment: spcColumnText(statement, 9),
                introLengthMs: Int(sqlite3_column_int64(statement, 10)),
                loopLengthMs: Int(sqlite3_column_int64(statement, 11)),
                playLengthMs: Int(sqlite3_column_int64(statement, 12)),
                fadeLengthMs: Int(sqlite3_column_int64(statement, 13))
            )
        ))
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongSPCLiveTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return rows
}

private func spcColumnText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func normalizeSPCEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func spcMetadataDelta(_ actual: ScannerMetadata, _ expected: ScannerMetadata) -> String {
    let fields: [(String, String, String)] = [
        ("game", actual.game, expected.game), ("title", actual.song, expected.song),
        ("system", actual.system, expected.system), ("author", actual.author, expected.author),
        ("comment", actual.comment, expected.comment), ("intro", String(actual.introLengthMs), String(expected.introLengthMs)),
        ("loop", String(actual.loopLengthMs), String(expected.loopLengthMs)),
        ("play", String(actual.playLengthMs), String(expected.playLengthMs)),
        ("fade", String(actual.fadeLengthMs), String(expected.fadeLengthMs))
    ]
    return fields.filter { $0.1 != $0.2 }
        .map { "\($0.0): actual=\($0.1) catalog=\($0.2)" }
        .joined(separator: "; ")
}

private func spcUnexplainedDecoderDifferences(
    document: MetadataDocument,
    actual: ScannerMetadata,
    legacy: ScannerMetadata
) -> [String] {
    let differingFields = spcMetadataDifferenceFields(actual, legacy)
    let tags = document.tags
    let hasXID6 = document.rawMetadataBlocks?["xid6"] != nil
    let hasFlaggedMetadata = document.technicalFacts["hasID666"] == "true"
        || document.technicalFacts["hasXID6"] == "true"
    let hasXID6Timing = hasXID6 && [
        "Intro Length (ms)", "Loop Length (ms)", "End Length (ms)", "Fade Length (ms)"
    ].contains { name in tags.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
    func hasTag(_ name: String, matching value: String) -> Bool {
        tags.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.value == value }
    }

    return differingFields.filter { field in
        let hasExplanation: Bool
        switch field {
        case "game": hasExplanation = !actual.game.isEmpty && hasTag("Game", matching: actual.game)
        case "title": hasExplanation = !actual.song.isEmpty && hasTag("Song", matching: actual.song)
        case "author": hasExplanation = !actual.author.isEmpty && hasTag("Artist", matching: actual.author)
        case "comment": hasExplanation = !actual.comment.isEmpty && hasTag("Comment", matching: actual.comment)
        case "intro":
            hasExplanation = hasTag("Intro Length (ms)", matching: String(actual.introLengthMs))
                || (hasFlaggedMetadata && actual.introLengthMs == 0)
        case "loop":
            // Preserve the former direct reader's established xID6 projection:
            // when an xID6 timing set exists, an omitted component defaults to
            // zero, while libgme reports it as unknown (-1).
            hasExplanation = hasTag("Loop Length (ms)", matching: String(actual.loopLengthMs))
                || (hasXID6Timing && actual.loopLengthMs == 0)
                || (hasFlaggedMetadata && actual.loopLengthMs == 0)
        case "fade":
            hasExplanation = hasTag("Fade Length (ms)", matching: String(actual.fadeLengthMs))
                || spcHasNumericTag(document, "Fade (milliseconds)", value: actual.fadeLengthMs)
        case "play":
            let hasTimingSource = ["Intro Length (ms)", "Loop Length (ms)", "End Length (ms)"]
                .contains { name in tags.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
            let hasTextID666Length = ["text", "text-fallback"].contains(document.technicalFacts["id666PlayTimingLayout"] ?? "")
                && actual.playLengthMs.isMultiple(of: 1_000)
                && spcHasNumericTag(document, "Length (seconds)", value: actual.playLengthMs / 1_000)
            hasExplanation = (hasTimingSource && document.timing?.playLengthMs == actual.playLengthMs)
                || hasTextID666Length
        default:
            hasExplanation = false
        }
        return !hasExplanation
    }
}

private func spcUnexplainedCatalogDifferences(
    document: MetadataDocument,
    actual: ScannerMetadata,
    catalog: ScannerMetadata,
    legacy: ScannerMetadata
) -> [String] {
    let unsupportedDecoderFields = Set(spcUnexplainedDecoderDifferences(
        document: document,
        actual: actual,
        legacy: legacy
    ))
    return spcMetadataDifferenceFields(actual, catalog).filter { field in
        // When MetaMan agrees with libgme, the catalog difference is drift from
        // both current readers. When it differs, require the same raw-source
        // explanation used by the decoder-parity assertion above.
        scannerValue(actual, field: field) != scannerValue(legacy, field: field)
            && unsupportedDecoderFields.contains(field)
    }
}

private func scannerValue(_ metadata: ScannerMetadata, field: String) -> String {
    switch field {
    case "game": metadata.game
    case "title": metadata.song
    case "system": metadata.system
    case "author": metadata.author
    case "comment": metadata.comment
    case "intro": String(metadata.introLengthMs)
    case "loop": String(metadata.loopLengthMs)
    case "play": String(metadata.playLengthMs)
    case "fade": String(metadata.fadeLengthMs)
    default: ""
    }
}

private func spcHasNumericTag(_ document: MetadataDocument, _ name: String, value: Int) -> Bool {
    document.tags.contains {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
            && Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines)) == value
    }
}

private func spcMetadataDifferenceFields(_ actual: ScannerMetadata, _ expected: ScannerMetadata) -> [String] {
    [
        ("game", actual.game != expected.game), ("title", actual.song != expected.song),
        ("system", actual.system != expected.system), ("author", actual.author != expected.author),
        ("comment", actual.comment != expected.comment), ("intro", actual.introLengthMs != expected.introLengthMs),
        ("loop", actual.loopLengthMs != expected.loopLengthMs), ("play", actual.playLengthMs != expected.playLengthMs),
        ("fade", actual.fadeLengthMs != expected.fadeLengthMs)
    ].compactMap { $0.1 ? $0.0 : nil }
}

private func spcMedian(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    return values.sorted()[values.count / 2]
}

private func spcPercentile95(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
}

private func spcMilliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}
