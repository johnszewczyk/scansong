import Foundation
import SQLite3
import Testing
@testable import ScanSongKit

@Test("Sony MSF content routing preserves non-Sony MSF aliases")
func sonyMSFRoutingKeepsTamaSoftOnVGMStream() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "msf")?.pluginID == "sony-msf-direct")
    #expect(!BuiltInScannerPlugins.directVGMStreamExtensions.contains("msf"))
    #expect(registry.descriptors.first(where: { $0.pluginID == "vgmstream" })?.supportedExtensions.contains("msf") == true)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-msf-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (name, signature, expectedPlugin) in [
        ("sony.msf", Array("MSF0".utf8), "sony-msf-direct"),
        ("konami.msf", Array("MSFC".utf8), "sony-msf-direct"),
        ("tamasoft.msf", Array("MSF ".utf8), "vgmstream"),
        ("unknown.msf", Array("OTHER".utf8), "vgmstream")
    ] {
        let url = directory.appendingPathComponent(name)
        try Data(signature + [UInt8](repeating: 0, count: 0x3C)).write(to: url)
        #expect(registry.route(forPath: url.path)?.pluginID == expectedPlugin, Comment(rawValue: name))
    }
}

@Test(
    "Sony MSF rows match CocoaSpice and vgmstream for the live archive corpus",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_MSF_LIVE_DB"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil,
        "Set SCANSONG_MSF_LIVE_DB and SCANSONG_VGMSTREAM_CLI to compare the read-only catalog, direct reader, and decoder."
    )
)
func cocoaSpiceMSFLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_MSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_MSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveMSFArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    let requestedEntry = ProcessInfo.processInfo.environment["SCANSONG_MSF_ENTRY"]
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
        formatExtension: "msf",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    let decoder = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream Sony MSF reference",
        supportedExtensions: ["msf"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))
    let extractor = StandaloneArchiveExtractor()
    var exactCatalogRows = 0
    var exactDecoderRows = 0
    var exactDirectDecoderRows = 0
    var directNanoseconds: UInt64 = 0
    var decoderNanoseconds: UInt64 = 0
    var codecCounts: [UInt32: Int] = [:]
    var mismatches: [String] = []
    let totalRows = selectedArchives.reduce(0) { $0 + $1.files.count }

    for (archiveIndex, archive) in selectedArchives.enumerated() {
        let extraction = try await extractor.extractForScan(
            archiveURL: URL(fileURLWithPath: archive.path),
            registry: BuiltInScannerPlugins.registry
        )
        defer { extractor.discard(extraction) }
        let members = Dictionary(
            extraction.members.map { (normalizeMSFEntry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        let expectedByEntry = Dictionary(grouping: archive.files, by: \.entryPath)

        for (entryPath, expectedRows) in expectedByEntry.sorted(by: { $0.key < $1.key }) {
            guard let fileURL = members[normalizeMSFEntry(entryPath)] else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): archive extraction omitted saved MSF member") }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "sony-msf-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): content route did not select sony-msf-direct") }
                continue
            }
            if let codec = msfCodec(fileURL) { codecCounts[codec, default: 0] += 1 }

            let directStart = DispatchTime.now().uptimeNanoseconds
            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            let catalogRows = expectedRows.map(LiveMSFRow.init).sorted { $0.trackIndex < $1.trackIndex }
            let directRows = directInspection.tracks.map(LiveMSFRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if directRows == catalogRows {
                exactCatalogRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): direct structure/metadata differs from saved catalog: saved=\(catalogRows), direct=\(directRows)")
            }

            let decoderStart = DispatchTime.now().uptimeNanoseconds
            let decoderInspection = try await decoder.inspect(fileURL: fileURL, route: decoderRoute)
            decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
            let decoderRows = decoderInspection.tracks.map(LiveMSFRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if decoderRows == catalogRows { exactDecoderRows += catalogRows.count }
            if directRows == decoderRows {
                exactDirectDecoderRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): direct structure/metadata differs from vgmstream: direct=\(directRows), vgmstream=\(decoderRows)")
            }
        }
        print("MSF parity progress: archive \(archiveIndex + 1)/\(selectedArchives.count), \(archive.files.count) catalog rows")
    }

    #expect(exactCatalogRows == totalRows, "\(exactCatalogRows)/\(totalRows) MSF rows exactly match saved catalog metadata")
    #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) MSF rows exactly match vgmstream")
    #expect(exactDirectDecoderRows == totalRows, "\(exactDirectDecoderRows)/\(totalRows) MSF rows exactly match between direct and decoder")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let fileCount = selectedArchives.reduce(0) { $0 + Set($1.files.map(\.entryPath)).count }
    let directAverageMs = Double(directNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let decoderAverageMs = Double(decoderNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let codecs = codecCounts.sorted { $0.key < $1.key }
        .map { "0x\(String($0.key, radix: 16)):\($0.value)" }
        .joined(separator: ", ")
    print(
        "MSF corpus: \(totalRows) rows / \(fileCount) files / \(selectedArchives.count) archives; "
            + "codecs [\(codecs)]; exact catalog/decoder/direct \(exactCatalogRows)/\(exactDecoderRows)/\(exactDirectDecoderRows); "
            + String(format: "mean direct %.3f ms/file, vgmstream CLI %.3f ms/file", directAverageMs, decoderAverageMs)
    )
}

private struct LiveMSFMetadata: Equatable {
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
        game = sqliteMSFText(statement, firstColumn)
        song = sqliteMSFText(statement, firstColumn + 1)
        system = sqliteMSFText(statement, firstColumn + 2)
        author = sqliteMSFText(statement, firstColumn + 3)
        comment = sqliteMSFText(statement, firstColumn + 4)
        introLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 5))
        loopLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 6))
        playLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 7))
        fadeLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 8))
    }
}

private struct LiveMSFRow: Equatable {
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveMSFMetadata?

    init(_ track: ScanTrackMetadata) {
        trackIndex = track.trackIndex
        trackCount = track.trackCount
        metadata = track.metadata.map(LiveMSFMetadata.init)
    }

    init(_ file: LiveMSFFile) {
        trackIndex = file.trackIndex
        trackCount = file.trackCount
        metadata = file.metadata
    }
}

private struct LiveMSFFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveMSFMetadata
}

private struct LiveMSFArchive {
    let path: String
    var files: [LiveMSFFile]
}

private func readLiveMSFArchives(databaseURL: URL, rootID: Int) throws -> [LiveMSFArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the MSF catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongMSFTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'msf'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongMSFTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongMSFTests", code: 3)
    }

    var archives: [LiveMSFArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteMSFText(statement, 0)
        let file = LiveMSFFile(
            entryPath: sqliteMSFText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: LiveMSFMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveMSFArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongMSFTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeMSFEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func sqliteMSFText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func msfCodec(_ fileURL: URL) -> UInt32? {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8), data.count == 8 else { return nil }
    return UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
}
