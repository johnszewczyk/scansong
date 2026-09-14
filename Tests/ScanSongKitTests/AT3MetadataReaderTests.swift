import Foundation
import MetaManCore
import SQLite3
import Testing
@testable import ScanSongKit

@Test("AT3 content routing uses the direct reader only for ATRAC3 RIFF codecs")
func at3RoutingSeparatesNonATRAC3RIFFAliases() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-at3-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let atracURL = directory.appendingPathComponent("music.at3")
    try makeAT3Wave(sampleCount: 44_100).write(to: atracURL)
    #expect(BuiltInScannerPlugins.registry.route(forPath: atracURL.path)?.pluginID == "at3-direct")

    let otherCodecURL = directory.appendingPathComponent("other.at3")
    try makeAT3Wave(sampleCount: 44_100, codec: 0x0001).write(to: otherCodecURL)
    #expect(BuiltInScannerPlugins.registry.route(forPath: otherCodecURL.path)?.pluginID == "vgmstream")
}

@Test(
    "MetaMan AT3 metadata matches all saved CocoaSpice rows and vgmstream",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_AT3_LIVE_DB"] != nil,
        "Set SCANSONG_AT3_LIVE_DB and SCANSONG_VGMSTREAM_CLI to compare MetaMan, ScanSong's adapter, the saved catalog, and vgmstream."
    )
)
func cocoaSpiceAT3LiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_AT3_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_AT3_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveAT3Archives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    #expect(!archives.isEmpty)

    let decoderEnabled = ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil
    let decoderRoute = ScannerRoute(
        pluginID: "vgmstream",
        formatExtension: "at3",
        structurePolicy: .knownSingle,
        metadataPolicy: .decoder
    )
    let decoderHandler = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream parity reference",
        supportedExtensions: ["at3"],
        structurePolicy: .knownSingle,
        metadataPolicy: .decoder
    ))

    let extractor = StandaloneArchiveExtractor()
    var exactMetaManRows = 0
    var exactSavedRows = 0
    var exactDecoderRows = 0
    var directNanoseconds: UInt64 = 0
    var decoderNanoseconds: UInt64 = 0
    var mismatches: [String] = []
    let totalRows = archives.reduce(0) { $0 + $1.files.count }

    for (archiveIndex, liveArchive) in archives.enumerated() {
        let extraction = try await extractor.extractForScan(
            archiveURL: URL(fileURLWithPath: liveArchive.path),
            registry: BuiltInScannerPlugins.registry
        )
        defer { extractor.discard(extraction) }
        let members = Dictionary(
            extraction.members.map { (normalizeAT3Entry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )

        for liveFile in liveArchive.files {
            guard let fileURL = members[normalizeAT3Entry(liveFile.entryPath)] else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): archive extraction omitted saved member")
                }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "at3-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): content-aware route did not select at3-direct")
                }
                continue
            }

            let directStart = DispatchTime.now().uptimeNanoseconds
            let document = try MetaManCore.read(fileURL: fileURL)
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            let metaManMetadata = ScannerMetadata(
                metadataDocument: document,
                includeDateAndEncodedByInComment: false
            )
            if AT3LiveMetadata(metaManMetadata) == liveFile.metadata {
                exactMetaManRows += 1
            } else if mismatches.count < 20 {
                mismatches.append("\(liveFile.entryPath): MetaMan differs from saved catalog")
            }

            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            guard let direct = directInspection.tracks.first?.metadata,
                  directInspection.tracks.count == 1,
                  directInspection.tracks[0].trackIndex == liveFile.trackIndex,
                  directInspection.tracks[0].trackCount == liveFile.trackCount else {
                if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): direct reader structure differs from saved row")
                }
                continue
            }
            if direct != metaManMetadata, mismatches.count < 20 {
                mismatches.append("\(liveFile.entryPath): ScanSong adapter differs from MetaMan")
            }

            if AT3LiveMetadata(direct) == liveFile.metadata {
                exactSavedRows += 1
            } else if mismatches.count < 20 {
                mismatches.append("\(liveFile.entryPath): direct metadata differs from saved catalog")
            }

            if decoderEnabled {
                let decoderStart = DispatchTime.now().uptimeNanoseconds
                let decoded = try await decoderHandler.inspect(fileURL: fileURL, route: decoderRoute)
                decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
                if decoded.tracks.first?.metadata == metaManMetadata, decoded.tracks.count == 1 {
                    exactDecoderRows += 1
                } else if mismatches.count < 20 {
                    mismatches.append("\(liveFile.entryPath): MetaMan differs from vgmstream")
                }
            }
        }
        print("AT3 parity progress: archive \(archiveIndex + 1)/\(archives.count), \(liveArchive.files.count) rows")
    }

    #expect(exactMetaManRows == totalRows, "\(exactMetaManRows)/\(totalRows) AT3 rows exactly match saved catalog metadata through MetaMan")
    #expect(exactSavedRows == totalRows, "\(exactSavedRows)/\(totalRows) AT3 rows exactly match saved catalog metadata through the ScanSong adapter")
    if decoderEnabled {
        #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) AT3 rows exactly match vgmstream")
    }
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let directAverageMs = Double(directNanoseconds) / Double(max(1, totalRows)) / 1_000_000
    let decoderAverageMs = decoderEnabled
        ? Double(decoderNanoseconds) / Double(max(1, totalRows)) / 1_000_000
        : 0
    print(
        "AT3 corpus: \(totalRows) rows / \(archives.count) archives; "
            + "MetaMan/catalog adapter/vgmstream exact \(exactMetaManRows)/\(exactSavedRows)/\(exactDecoderRows); "
            + String(format: "mean direct %.3f ms", directAverageMs)
            + (decoderEnabled ? String(format: ", mean vgmstream CLI %.3f ms", decoderAverageMs) : "")
    )
}

private struct AT3LiveMetadata: Equatable {
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
        game = at3SQLiteText(statement, firstColumn)
        song = at3SQLiteText(statement, firstColumn + 1)
        system = at3SQLiteText(statement, firstColumn + 2)
        author = at3SQLiteText(statement, firstColumn + 3)
        comment = at3SQLiteText(statement, firstColumn + 4)
        introLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 5))
        loopLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 6))
        playLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 7))
        fadeLengthMs = Int(sqlite3_column_int64(statement, firstColumn + 8))
    }
}

private struct AT3LiveFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: AT3LiveMetadata
}

private struct AT3LiveArchive {
    let path: String
    var files: [AT3LiveFile]
}

private func readLiveAT3Archives(databaseURL: URL, rootID: Int) throws -> [AT3LiveArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the AT3 catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongAT3Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'at3'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongAT3Tests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongAT3Tests", code: 3)
    }

    var archives: [AT3LiveArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = at3SQLiteText(statement, 0)
        let file = AT3LiveFile(
            entryPath: at3SQLiteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: AT3LiveMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(AT3LiveArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongAT3Tests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeAT3Entry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func at3SQLiteText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func makeAT3Wave(
    sampleCount: UInt32,
    sampleSkip: UInt32 = 0,
    loopStart: UInt32? = nil,
    loopEnd: UInt32? = nil,
    wsmpLoopStart: UInt32? = nil,
    wsmpLoopLength: UInt32? = nil,
    extensible: Bool = false,
    codec: UInt16 = 0x0270
) -> Data {
    var format = Data()
    at3AppendUInt16LE(extensible ? 0xFFFE : codec, to: &format)
    at3AppendUInt16LE(2, to: &format)
    at3AppendUInt32LE(44_100, to: &format)
    at3AppendUInt32LE(24_000, to: &format)
    at3AppendUInt16LE(0x0600, to: &format)
    at3AppendUInt16LE(0, to: &format)
    if extensible {
        at3AppendUInt16LE(0x16, to: &format)
        at3AppendUInt16LE(16, to: &format)
        at3AppendUInt32LE(3, to: &format)
        format.append(contentsOf: [
            0xBF, 0xAA, 0x23, 0xE9, 0x58, 0xCB, 0x71, 0x44,
            0xA1, 0x19, 0xFF, 0xFA, 0x01, 0xE4, 0xCE, 0x62
        ])
    }

    var fact = Data()
    at3AppendUInt32LE(sampleCount, to: &fact)
    at3AppendUInt32LE(sampleSkip, to: &fact)

    var chunks = at3RIFFChunk("fmt ", payload: format)
    chunks.append(at3RIFFChunk("fact", payload: fact))
    if let loopStart, let loopEnd {
        var smpl = Data(repeating: 0, count: 0x3C)
        at3WriteUInt32LE(1, into: &smpl, at: 0x1C)
        at3WriteUInt32LE(loopStart, into: &smpl, at: 0x2C)
        at3WriteUInt32LE(loopEnd, into: &smpl, at: 0x30)
        chunks.append(at3RIFFChunk("smpl", payload: smpl))
    }
    if let wsmpLoopStart, let wsmpLoopLength {
        var wsmp = Data(repeating: 0, count: 0x24)
        at3WriteUInt32LE(0x14, into: &wsmp, at: 0x00)
        at3WriteUInt32LE(1, into: &wsmp, at: 0x10)
        at3WriteUInt32LE(0x10, into: &wsmp, at: 0x14)
        at3WriteUInt32LE(wsmpLoopStart, into: &wsmp, at: 0x1C)
        at3WriteUInt32LE(wsmpLoopLength, into: &wsmp, at: 0x20)
        chunks.append(at3RIFFChunk("wsmp", payload: wsmp))
    }
    chunks.append(at3RIFFChunk("data", payload: Data([0, 0, 0, 0])))

    var body = Data("WAVE".utf8)
    body.append(chunks)
    var result = Data("RIFF".utf8)
    at3AppendUInt32LE(UInt32(body.count), to: &result)
    result.append(body)
    return result
}

private func at3RIFFChunk(_ identifier: String, payload: Data) -> Data {
    var result = Data(identifier.utf8)
    at3AppendUInt32LE(UInt32(payload.count), to: &result)
    result.append(payload)
    if payload.count % 2 == 1 { result.append(0) }
    return result
}

private func at3AppendUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
}

private func at3AppendUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}

private func at3WriteUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
    data[offset] = UInt8(truncatingIfNeeded: value)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}
