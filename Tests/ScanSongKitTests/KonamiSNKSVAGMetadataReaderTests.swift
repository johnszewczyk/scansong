import Foundation
import SQLite3
import Testing
@testable import ScanSongKit

@Test("SVAG content routing recognizes both MetaMan layouts and preserves aliases")
func svagRoutingPreservesOtherAliases() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "svag")?.pluginID == "svag-direct")
    #expect(!BuiltInScannerPlugins.directVGMStreamExtensions.contains("svag"))
    #expect(registry.descriptors.first(where: { $0.pluginID == "vgmstream" })?.supportedExtensions.contains("svag") == true)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-svag-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (name, data, expectedPlugin) in [
        ("konami.svag", Data("Svag".utf8), "svag-direct"),
        ("snk.svag", Data("VAGm".utf8), "svag-direct"),
        ("unknown.svag", Data("OTHER".utf8), "vgmstream")
    ] {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        #expect(registry.route(forPath: url.path)?.pluginID == expectedPlugin, Comment(rawValue: name))
    }
}

@Test(
    "Konami SVAG rows match CocoaSpice and vgmstream for the live archive corpus",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SVAG_LIVE_DB"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil,
        "Set SCANSONG_SVAG_LIVE_DB and SCANSONG_VGMSTREAM_CLI to compare MetaMan plus the ScanSong adapter with the read-only catalog and decoder."
    )
)
func cocoaSpiceSVAGLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_SVAG_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_SVAG_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveSVAGArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    let requestedEntry = ProcessInfo.processInfo.environment["SCANSONG_SVAG_ENTRY"]
    let selectedArchives = requestedEntry.map { entry in
        archives.filter { archive in
            archive.files.contains {
                $0.entryPath == entry || URL(fileURLWithPath: $0.entryPath).lastPathComponent == entry
            }
        }
    } ?? archives
    #expect(!selectedArchives.isEmpty)

    let decoderRoute = ScannerRoute(
        pluginID: "vgmstream",
        formatExtension: "svag",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    let decoder = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream Konami/SNK SVAG reference",
        supportedExtensions: ["svag"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))
    let extractor = StandaloneArchiveExtractor()
    var exactCatalogRows = 0
    var exactDecoderRows = 0
    var exactLegacyRows = 0
    var exactDirectDecoderRows = 0
    var directNanoseconds: UInt64 = 0
    var legacyNanoseconds: UInt64 = 0
    var decoderNanoseconds: UInt64 = 0
    var headerCounts: [String: Int] = [:]
    var mismatches: [String] = []
    let totalRows = selectedArchives.reduce(0) { $0 + $1.files.count }

    for (archiveIndex, archive) in selectedArchives.enumerated() {
        let extraction = try await extractor.extractForScan(
            archiveURL: URL(fileURLWithPath: archive.path),
            registry: BuiltInScannerPlugins.registry
        )
        defer { extractor.discard(extraction) }
        let members = Dictionary(
            extraction.members.map { (normalizeSVAGEntry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        let expectedByEntry = Dictionary(grouping: archive.files, by: \.entryPath)

        for (entryPath, expectedRows) in expectedByEntry.sorted(by: { $0.key < $1.key }) {
            guard let fileURL = members[normalizeSVAGEntry(entryPath)] else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): archive extraction omitted saved SVAG member") }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "svag-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): content route did not select svag-direct") }
                continue
            }

            let catalogRows = expectedRows.map(LiveSVAGRow.init).sorted { $0.trackIndex < $1.trackIndex }
            let directStart = DispatchTime.now().uptimeNanoseconds
            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            let directRows = directInspection.tracks.map(LiveSVAGRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if directRows == catalogRows {
                exactCatalogRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): MetaMan projection differs from saved catalog: saved=\(catalogRows), MetaMan=\(directRows)")
            }

            let legacyStart = DispatchTime.now().uptimeNanoseconds
            let legacyMetadata = try legacyKonamiSVAGMetadata(fileURL: fileURL)
            legacyNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- legacyStart
            let legacyRows = [LiveSVAGRow(ScanTrackMetadata(
                trackIndex: 0,
                trackCount: 1,
                metadata: legacyMetadata
            ))]
            if directRows == legacyRows {
                exactLegacyRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): MetaMan projection differs from the former in-process ScanSong reader: legacy=\(legacyRows), MetaMan=\(directRows)")
            }

            let decoderStart = DispatchTime.now().uptimeNanoseconds
            let decoderInspection = try await decoder.inspect(fileURL: fileURL, route: decoderRoute)
            decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
            let decoderRows = decoderInspection.tracks.map(LiveSVAGRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if decoderRows == catalogRows { exactDecoderRows += catalogRows.count }
            if directRows == decoderRows {
                exactDirectDecoderRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): MetaMan projection differs from vgmstream: MetaMan=\(directRows), vgmstream=\(decoderRows)")
            }
            headerCounts[directRows.first?.metadata?.comment ?? "no row"] =
                (headerCounts[directRows.first?.metadata?.comment ?? "no row"] ?? 0) + 1
        }
        print("SVAG parity progress: archive \(archiveIndex + 1)/\(selectedArchives.count), \(archive.files.count) catalog rows")
    }

    #expect(exactCatalogRows == totalRows, "\(exactCatalogRows)/\(totalRows) SVAG rows exactly match saved catalog metadata")
    #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) SVAG rows exactly match vgmstream")
    #expect(exactLegacyRows == totalRows, "\(exactLegacyRows)/\(totalRows) SVAG rows exactly match the former in-process reader")
    #expect(exactDirectDecoderRows == totalRows, "\(exactDirectDecoderRows)/\(totalRows) SVAG rows exactly match between direct and decoder")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let fileCount = selectedArchives.reduce(0) { $0 + Set($1.files.map(\.entryPath)).count }
    let directAverageMs = Double(directNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let legacyAverageMs = Double(legacyNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let decoderAverageMs = Double(decoderNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    print(
        "SVAG corpus: \(totalRows) rows / \(fileCount) files / \(selectedArchives.count) archives; "
            + "headers [\(headerCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ", "))]; "
            + "exact catalog/decoder/legacy/MetaMan \(exactCatalogRows)/\(exactDecoderRows)/\(exactLegacyRows)/\(exactDirectDecoderRows); "
            + String(format: "mean MetaMan+adapter %.3f ms/file, former in-process reader %.3f ms/file, vgmstream CLI %.3f ms/file", directAverageMs, legacyAverageMs, decoderAverageMs)
    )
}

private struct LiveSVAGMetadata: Equatable {
    let game: String
    let song: String
    let system: String
    let author: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int

    init(_ metadata: ScannerMetadata) {
        game = metadata.game
        song = metadata.song
        system = metadata.system
        author = metadata.author
        comment = metadata.comment
        introLengthMs = metadata.introLengthMs
        loopLengthMs = metadata.loopLengthMs
        playLengthMs = metadata.playLengthMs
        fadeLengthMs = metadata.fadeLengthMs
    }

    init(statement: OpaquePointer, firstColumn: Int32) {
        game = sqliteSVAGText(statement, firstColumn)
        song = sqliteSVAGText(statement, firstColumn + 1)
        system = sqliteSVAGText(statement, firstColumn + 2)
        author = sqliteSVAGText(statement, firstColumn + 3)
        comment = sqliteSVAGText(statement, firstColumn + 4)
        introLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 5))
        loopLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 6))
        playLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 7))
        fadeLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 8))
    }
}

private struct LiveSVAGRow: Equatable {
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveSVAGMetadata?

    init(_ track: ScanTrackMetadata) {
        trackIndex = track.trackIndex
        trackCount = track.trackCount
        metadata = track.metadata.map(LiveSVAGMetadata.init)
    }

    init(_ file: LiveSVAGFile) {
        trackIndex = file.trackIndex
        trackCount = file.trackCount
        metadata = file.metadata
    }
}

private struct LiveSVAGFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveSVAGMetadata
}

private struct LiveSVAGArchive {
    let path: String
    var files: [LiveSVAGFile]
}

private func readLiveSVAGArchives(databaseURL: URL, rootID: Int) throws -> [LiveSVAGArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the SVAG catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongSVAGTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'svag'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongSVAGTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongSVAGTests", code: 3)
    }

    var archives: [LiveSVAGArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteSVAGText(statement, 0)
        let file = LiveSVAGFile(
            entryPath: sqliteSVAGText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: LiveSVAGMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveSVAGArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongSVAGTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeSVAGEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func sqliteSVAGText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

/// Test-only copy of the former ScanSong in-process projection. It is kept
/// beside the live parity oracle to measure the ownership move on identical
/// extracted files; production has only the MetaMan implementation.
private func legacyKonamiSVAGMetadata(fileURL: URL) throws -> ScannerMetadata {
    let file = try FileHandle(forReadingFrom: fileURL)
    defer { try? file.close() }
    let data = try file.read(upToCount: 0x404) ?? Data()
    guard data.count >= 0x20, data.prefix(4) == Data("Svag".utf8) else {
        throw NSError(domain: "ScanSongSVAGTests", code: 5)
    }

    let dataSize = UInt64(legacySVAGUInt32(data, 0x04))
    let sampleRate = Int64(legacySVAGUInt32(data, 0x08))
    let channels = Int64(legacySVAGUInt16(data, 0x0C))
    let loopFlag = legacySVAGUInt32(data, 0x14) == 1
    guard channels > 0, channels <= 64, (300...192_000).contains(sampleRate) else {
        throw NSError(domain: "ScanSongSVAGTests", code: 6)
    }
    let sampleCount = Int64(dataSize / UInt64(channels) / 0x10 * 28)
    guard sampleCount > 0, sampleCount <= 1_000_000_000 else {
        throw NSError(domain: "ScanSongSVAGTests", code: 7)
    }

    let marker = data.count >= 0x404 ? legacySVAGUInt32BE(data, 0x400) : 0
    guard channels <= 1 || marker == 0 || marker == 0x5376_6167 || marker == 0x4465_7369 else {
        throw NSError(domain: "ScanSongSVAGTests", code: 8)
    }
    var loopStart = loopFlag ? Int64(legacySVAGUInt32(data, 0x18)) / 0x10 * 28 : 0
    var loopEnd = loopFlag ? sampleCount : 0
    if loopFlag && (loopStart < 0 || loopEnd <= loopStart || loopEnd > sampleCount) {
        loopStart = 0
        loopEnd = 0
    }
    let loopLength = loopEnd > loopStart ? loopEnd - loopStart : 0
    let playSamples = loopLength > 0
        ? loopStart + loopLength * 2 + sampleRate * 10
        : sampleCount
    let title = URL(fileURLWithPath: fileURL.lastPathComponent)
        .deletingPathExtension()
        .lastPathComponent
    return ScannerMetadata(
        game: "",
        song: title,
        system: "",
        author: "",
        comment: "Konami SVAG header",
        introLengthMs: 0,
        loopLengthMs: Int(loopLength * 1_000 / sampleRate),
        playLengthMs: Int(playSamples * 1_000 / sampleRate),
        fadeLengthMs: 0
    )
}

private func legacySVAGUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func legacySVAGUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
}

private func legacySVAGUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
}
