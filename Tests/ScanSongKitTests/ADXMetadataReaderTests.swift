import Foundation
import SQLite3
import Testing
@testable import ScanSongKit

@Test("ADX routing separates CRI streams from Ogg files that reuse the extension")
func adxRoutingSniffsOggAlias() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "adx")?.pluginID == "adx-direct")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-adx-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let oggURL = directory.appendingPathComponent("vorbis.adx")
    try Data("OggS".utf8).write(to: oggURL)
    #expect(registry.route(forPath: oggURL.path)?.pluginID == "vgmstream")

    let riffURL = directory.appendingPathComponent("remember11.adx")
    try Data("RIFF".utf8).write(to: riffURL)
    #expect(registry.route(forPath: riffURL.path)?.pluginID == "vgmstream")

    let criURL = directory.appendingPathComponent("battle.adx")
    try makeCRIADX(version: 0x0400).write(to: criURL)
    #expect(registry.route(forPath: criURL.path)?.pluginID == "adx-direct")

    let monsterURL = directory.appendingPathComponent("xenoblade.adx")
    try makeMonsterADX().write(to: monsterURL)
    #expect(registry.route(forPath: monsterURL.path)?.pluginID == "adx-direct")

    let aliasURL = directory.appendingPathComponent("unknown-alias.adx")
    try Data("other format".utf8).write(to: aliasURL)
    #expect(registry.route(forPath: aliasURL.path)?.pluginID == "vgmstream")

    let invalidURL = directory.appendingPathComponent("invalid.adx")
    try Data([0x80, 0x00, 0x00, 0x7C]).write(to: invalidURL)
    #expect(registry.route(forPath: invalidURL.path)?.pluginID == "adx-direct")
}

@Test("MetaMan ADX documents preserve ScanSong's existing catalog projection")
func adxMetadataAdapterPreservesCatalogProjection() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-adx-adapter-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("Battle Theme.adx")
    try makeCRIADX(version: 0x0400).write(to: fileURL)
    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)

    #expect(inspection.tracks.count == 1)
    #expect(inspection.tracks[0].trackIndex == 0)
    #expect(inspection.tracks[0].trackCount == 1)
    #expect(inspection.tracks[0].metadata == ScannerMetadata(
        game: "",
        song: "Battle Theme",
        system: "",
        author: "",
        comment: "CRI ADX header (type 04)",
        introLengthMs: 0,
        loopLengthMs: 2_000,
        playLengthMs: 15_000,
        fadeLengthMs: 0
    ))
}

@Test(
    "MetaMan ADX metadata matches all saved CocoaSpice rows and vgmstream",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_ADX_LIVE_DB"] != nil,
        "Set SCANSONG_ADX_LIVE_DB to run read-only ADX corpus parity. Set SCANSONG_VGMSTREAM_CLI to also compare the decoder directly."
    )
)
func cocoaSpiceADXLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_ADX_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_ADX_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveADXArchives(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    #expect(!archives.isEmpty)

    let decoderEnabled = ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil
    let decoderRoute = ScannerRoute(
        pluginID: "vgmstream",
        formatExtension: "adx",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    let decoderHandler = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream parity reference",
        supportedExtensions: ["adx"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))

    let extractor = StandaloneArchiveExtractor()
    var exactSavedRows = 0
    var exactDecoderRows = 0
    var decoderNanoseconds: UInt64 = 0
    var directNanoseconds: UInt64 = 0
    var mismatches: [String] = []
    let totalRows = archives.reduce(0) { $0 + $1.files.count }

    for (archiveIndex, liveArchive) in archives.enumerated() {
        let extraction = try await extractor.extractForScan(
            archiveURL: URL(fileURLWithPath: liveArchive.path),
            registry: BuiltInScannerPlugins.registry
        )
        defer { extractor.discard(extraction) }
        let members = Dictionary(
            extraction.members.map { (normalizeADXEntry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        for liveFile in liveArchive.files {
            guard let fileURL = members[normalizeADXEntry(liveFile.entryPath)] else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): archive extraction omitted saved member")
                }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "adx-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): content-aware route did not select adx-direct")
                }
                continue
            }

            let directStart = DispatchTime.now().uptimeNanoseconds
            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            guard let direct = directInspection.tracks.first?.metadata,
                  directInspection.tracks.count == 1,
                  directInspection.tracks[0].trackIndex == 0,
                  directInspection.tracks[0].trackCount == 1 else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): direct reader did not return exactly one track")
                }
                continue
            }

            if LiveADXMetadata(direct) == liveFile.metadata {
                exactSavedRows += 1
            } else if mismatches.count < 20 {
                mismatches.append("\(liveFile.entryPath): direct metadata differs from saved catalog")
            }

            if decoderEnabled {
                let decoderStart = DispatchTime.now().uptimeNanoseconds
                let decoderInspection = try await decoderHandler.inspect(fileURL: fileURL, route: decoderRoute)
                decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
                if decoderInspection.tracks.first?.metadata == direct,
                   decoderInspection.tracks.count == 1 {
                    exactDecoderRows += 1
                } else if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): direct metadata differs from vgmstream")
                }
            }
        }
        print("ADX parity progress: archive \(archiveIndex + 1)/\(archives.count), \(liveArchive.files.count) rows")
    }

    #expect(exactSavedRows == totalRows, "\(exactSavedRows)/\(totalRows) ADX rows exactly match saved catalog metadata")
    if decoderEnabled {
        #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) ADX rows exactly match vgmstream")
    }
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let directAverageMs = Double(directNanoseconds) / Double(max(1, totalRows)) / 1_000_000
    let decoderAverageMs = decoderEnabled
        ? Double(decoderNanoseconds) / Double(max(1, totalRows)) / 1_000_000
        : 0
    print(
        "ADX corpus: \(totalRows) rows / \(archives.count) archives; "
            + "catalog exact \(exactSavedRows); vgmstream exact \(exactDecoderRows); "
            + String(format: "mean direct %.3f ms", directAverageMs)
            + (decoderEnabled ? String(format: ", mean vgmstream CLI %.3f ms", decoderAverageMs) : "")
    )
}

private struct LiveADXMetadata: Equatable {
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
        game = sqliteText(statement, firstColumn)
        song = sqliteText(statement, firstColumn + 1)
        system = sqliteText(statement, firstColumn + 2)
        author = sqliteText(statement, firstColumn + 3)
        comment = sqliteText(statement, firstColumn + 4)
        introLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 5))
        loopLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 6))
        playLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 7))
        fadeLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 8))
    }
}

private struct LiveADXFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveADXMetadata
}

private struct LiveADXArchive {
    let path: String
    var files: [LiveADXFile]
}

private func readLiveADXArchives(databaseURL: URL, rootID: Int) throws -> [LiveADXArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the ADX catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongADXTests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'adx'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongADXTests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongADXTests", code: 3)
    }

    var archives: [LiveADXArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let file = LiveADXFile(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: LiveADXMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveADXArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongADXTests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeADXEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func makeCRIADX(
    version: UInt16,
    loopFlag: Int32 = 1,
    sampleRate: Int32 = 44_100,
    sampleCount: Int32 = 441_000
) -> Data {
    let dataOffset = 0x80
    var data = Data(repeating: 0, count: dataOffset + 0x20)
    putUInt16BE(&data, at: 0, value: 0x8000)
    putUInt16BE(&data, at: 0x02, value: UInt16(dataOffset - 4))
    data[0x04] = 0x03
    data[0x05] = 0x12
    data[0x06] = 4
    data[0x07] = 2
    putUInt32BE(&data, at: 0x08, value: UInt32(bitPattern: sampleRate))
    putUInt32BE(&data, at: 0x0C, value: UInt32(bitPattern: sampleCount))
    putUInt16BE(&data, at: 0x10, value: 500)
    putUInt16BE(&data, at: 0x12, value: version)

    let headerVersion = [UInt16(0x0408), 0x0409].contains(version) ? 0x0400 : version
    if headerVersion == 0x0300 {
        putUInt32BE(&data, at: 0x18, value: UInt32(bitPattern: loopFlag))
        putUInt32BE(&data, at: 0x1C, value: 44_100)
        putUInt32BE(&data, at: 0x24, value: 132_300)
    } else if headerVersion == 0x0400 {
        putUInt32BE(&data, at: 0x24, value: UInt32(bitPattern: loopFlag))
        putUInt32BE(&data, at: 0x28, value: 44_100)
        putUInt32BE(&data, at: 0x30, value: 132_300)
    }
    data.replaceSubrange((dataOffset - 6)..<dataOffset, with: Data("(c)CRI".utf8))
    return data
}

private func makeMonsterADX() -> Data {
    var data = Data(repeating: 0, count: 0x100)
    putUInt32BE(&data, at: 0x00, value: 0x0200_0000)
    putUInt32LE(&data, at: 0x00, value: 2)
    putUInt16LE(&data, at: 0x6E, value: 1)
    putUInt32LE(&data, at: 0x70, value: 32_000)
    putUInt32LE(&data, at: 0x74, value: 128_000)
    putUInt32LE(&data, at: 0x78, value: 32_000)
    putUInt32LE(&data, at: 0x7C, value: 96_000)
    putUInt32LE(&data, at: 0x34, value: 0x80)
    putUInt32LE(&data, at: 0x68, value: 0x80)
    return data
}

private func putUInt16BE(_ data: inout Data, at offset: Int, value: UInt16) {
    data[offset] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 1] = UInt8(truncatingIfNeeded: value)
}

private func putUInt16LE(_ data: inout Data, at offset: Int, value: UInt16) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

private func putUInt32BE(_ data: inout Data, at offset: Int, value: UInt32) {
    data[offset] = UInt8(truncatingIfNeeded: value >> 24)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 3] = UInt8(truncatingIfNeeded: value)
}

private func putUInt32LE(_ data: inout Data, at offset: Int, value: UInt32) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}
