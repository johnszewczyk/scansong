import Foundation
import MetaManCore
import SQLite3
import Testing
@testable import ScanSongKit

@Test("AUS content routing uses the direct reader only for Atomic Planet headers")
func atomicPlanetAUSRoutingPreservesAliases() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "aus")?.pluginID == "aus-direct")
    #expect(!BuiltInScannerPlugins.directVGMStreamExtensions.contains("aus"))
    #expect(registry.descriptors.first(where: { $0.pluginID == "vgmstream" })?.supportedExtensions.contains("aus") == true)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-aus-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let atomicPlanet = directory.appendingPathComponent("native.aus")
    try makeAUS(codec: 0, channels: 2, sampleRate: 48_000, samples: 48_000)
        .write(to: atomicPlanet)
    #expect(registry.route(forPath: atomicPlanet.path)?.pluginID == "aus-direct")

    let alias = directory.appendingPathComponent("alias.aus")
    try Data("OTHER".utf8).write(to: alias)
    #expect(registry.route(forPath: alias.path)?.pluginID == "vgmstream")
}

@Test(
    "Atomic Planet AUS rows match CocoaSpice and vgmstream for the live archive",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_AUS_LIVE_DB"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil,
        "Set SCANSONG_AUS_LIVE_DB and SCANSONG_VGMSTREAM_CLI to compare the read-only catalog, direct reader, and decoder."
    )
)
func cocoaSpiceAUSLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_AUS_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_AUS_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveAUSArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    let requestedEntry = ProcessInfo.processInfo.environment["SCANSONG_AUS_ENTRY"]
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
        formatExtension: "aus",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    let decoder = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream Atomic Planet AUS reference",
        supportedExtensions: ["aus"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))
    let extractor = StandaloneArchiveExtractor()
    var exactCatalogRows = 0
    var exactMetaManRows = 0
    var exactDecoderRows = 0
    var exactDirectDecoderRows = 0
    var directNanoseconds: UInt64 = 0
    var decoderNanoseconds: UInt64 = 0
    var mismatches: [String] = []
    let totalRows = selectedArchives.reduce(0) { $0 + $1.files.count }

    for (archiveIndex, archive) in selectedArchives.enumerated() {
        let extraction = try await extractor.extractForScan(
            archiveURL: URL(fileURLWithPath: archive.path),
            registry: BuiltInScannerPlugins.registry
        )
        defer { extractor.discard(extraction) }
        let members = Dictionary(
            extraction.members.map { (normalizeAUSEntry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        let expectedByEntry = Dictionary(grouping: archive.files, by: \.entryPath)

        for (entryPath, expectedRows) in expectedByEntry.sorted(by: { $0.key < $1.key }) {
            guard let fileURL = members[normalizeAUSEntry(entryPath)] else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): archive extraction omitted saved AUS member") }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "aus-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): content route did not select aus-direct") }
                continue
            }

            let catalogRows = expectedRows.map(LiveAUSRow.init).sorted { $0.trackIndex < $1.trackIndex }
            let directStart = DispatchTime.now().uptimeNanoseconds
            let document = try MetaManCore.read(fileURL: fileURL)
            let metaManRows = [LiveAUSRow(ScanTrackMetadata(
                trackIndex: 0,
                trackCount: 1,
                metadata: ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            ))]
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            if metaManRows == catalogRows {
                exactMetaManRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): MetaMan differs from saved catalog: saved=\(catalogRows), MetaMan=\(metaManRows)")
            }

            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            let directRows = directInspection.tracks.map(LiveAUSRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if directRows == catalogRows {
                exactCatalogRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): ScanSong adapter differs from saved catalog: saved=\(catalogRows), adapter=\(directRows)")
            }
            if metaManRows != directRows, mismatches.count < 20 {
                mismatches.append("\(entryPath): ScanSong projection differs from MetaMan: MetaMan=\(metaManRows), adapter=\(directRows)")
            }

            let decoderStart = DispatchTime.now().uptimeNanoseconds
            let decoderInspection = try await decoder.inspect(fileURL: fileURL, route: decoderRoute)
            decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
            let decoderRows = decoderInspection.tracks.map(LiveAUSRow.init).sorted { $0.trackIndex < $1.trackIndex }
            if decoderRows == catalogRows { exactDecoderRows += catalogRows.count }
            if metaManRows == decoderRows {
                exactDirectDecoderRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): MetaMan differs from vgmstream: MetaMan=\(metaManRows), vgmstream=\(decoderRows)")
            }
        }
        print("AUS parity progress: archive \(archiveIndex + 1)/\(selectedArchives.count), \(archive.files.count) catalog rows")
    }

    #expect(exactMetaManRows == totalRows, "\(exactMetaManRows)/\(totalRows) AUS rows exactly match saved catalog metadata through MetaMan")
    #expect(exactCatalogRows == totalRows, "\(exactCatalogRows)/\(totalRows) AUS rows exactly match saved catalog metadata through the ScanSong adapter")
    #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) AUS rows exactly match vgmstream")
    #expect(exactDirectDecoderRows == totalRows, "\(exactDirectDecoderRows)/\(totalRows) AUS rows exactly match between direct and decoder")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let fileCount = selectedArchives.reduce(0) { $0 + Set($1.files.map(\.entryPath)).count }
    let directAverageMs = Double(directNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let decoderAverageMs = Double(decoderNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    print(
        "AUS corpus: \(totalRows) rows / \(fileCount) files / \(selectedArchives.count) archives; "
            + "exact MetaMan/catalog-adapter/decoder/MetaMan-vs-decoder \(exactMetaManRows)/\(exactCatalogRows)/\(exactDecoderRows)/\(exactDirectDecoderRows); "
            + String(format: "mean direct %.3f ms/file, vgmstream CLI %.3f ms/file", directAverageMs, decoderAverageMs)
    )
}

private struct LiveAUSMetadata: Equatable {
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
        game = sqliteAUSText(statement, firstColumn)
        song = sqliteAUSText(statement, firstColumn + 1)
        system = sqliteAUSText(statement, firstColumn + 2)
        author = sqliteAUSText(statement, firstColumn + 3)
        comment = sqliteAUSText(statement, firstColumn + 4)
        introLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 5))
        loopLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 6))
        playLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 7))
        fadeLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 8))
    }
}

private struct LiveAUSRow: Equatable {
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveAUSMetadata?

    init(_ track: ScanTrackMetadata) {
        trackIndex = track.trackIndex
        trackCount = track.trackCount
        metadata = track.metadata.map(LiveAUSMetadata.init)
    }

    init(_ file: LiveAUSFile) {
        trackIndex = file.trackIndex
        trackCount = file.trackCount
        metadata = file.metadata
    }
}

private struct LiveAUSFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveAUSMetadata
}

private struct LiveAUSArchive {
    let path: String
    var files: [LiveAUSFile]
}

private func readLiveAUSArchives(databaseURL: URL, rootID: Int) throws -> [LiveAUSArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the AUS catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongAUSTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'aus'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongAUSTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongAUSTests", code: 3)
    }

    var archives: [LiveAUSArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteAUSText(statement, 0)
        let file = LiveAUSFile(
            entryPath: sqliteAUSText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: LiveAUSMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveAUSArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongAUSTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeAUSEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func sqliteAUSText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func makeAUS(
    codec: UInt16,
    channels: UInt16,
    sampleRate: Int32,
    samples: Int32,
    loopStart: Int32 = 0,
    loopEnd: Int32 = 0,
    legacyLoopFlag: Bool = false,
    loopMarker: Bool = false
) -> Data {
    var data = Data(repeating: 0, count: 0x20)
    data.replaceSubrange(0..<4, with: Data("AUS ".utf8))
    setAUSUInt16(codec, in: &data, at: 0x06)
    setAUSInt32(samples, in: &data, at: 0x08)
    setAUSUInt16(channels, in: &data, at: 0x0C)
    setAUSUInt16(legacyLoopFlag ? 1 : 0, in: &data, at: 0x0E)
    setAUSInt32(sampleRate, in: &data, at: 0x10)
    setAUSInt32(loopStart, in: &data, at: 0x14)
    setAUSInt32(loopEnd, in: &data, at: 0x18)
    setAUSUInt32(loopMarker ? 1 : 0, in: &data, at: 0x1C)
    return data
}

private func setAUSUInt16(_ value: UInt16, in data: inout Data, at offset: Int) {
    data.replaceSubrange(offset..<(offset + 2), with: [UInt8(value & 0xFF), UInt8(value >> 8)])
}

private func setAUSInt32(_ value: Int32, in data: inout Data, at offset: Int) {
    setAUSUInt32(UInt32(bitPattern: value), in: &data, at: offset)
}

private func setAUSUInt32(_ value: UInt32, in data: inout Data, at offset: Int) {
    data.replaceSubrange(
        offset..<(offset + 4),
        with: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8(value >> 24)
        ]
    )
}
