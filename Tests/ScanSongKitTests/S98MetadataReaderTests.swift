import Foundation
import SQLite3
import Testing
import VGMBoyCLibVGM
@testable import ScanSongKit

@Test("S98 v1 legacy title and event timing match libvgm")
func s98LegacyTitleAndTimingMatchLibVGM() throws {
    let commands: [UInt8] = [0xFF, 0x00, 0x23, 0x45, 0xFE, 0x00, 0xFD]
    let data = makeS98(
        version: 1,
        tickMultiplier: 100,
        tickDivisor: 7,
        loopCommandIndex: 4,
        commands: commands,
        tags: Array("Song title\0".utf8)
    )

    let direct = try S98MetadataReader.read(data: data)
    #expect(direct.song == "Song title")
    #expect(direct.system == "S98 v1.00")
    #expect(direct.introLengthMs == 200)
    #expect(direct.loopLengthMs == 200)
    #expect(direct.playLengthMs == 300)
    #expect(direct.fadeLengthMs == 0)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 v0 timing defaults and CP932 legacy tags are read directly")
func s98V0DefaultsAndCP932Title() throws {
    let title = try #require("曲".data(using: .shiftJIS))
    let data = makeS98(
        version: 0,
        tickMultiplier: 999,
        tickDivisor: 999,
        commands: [0xFE, 0x00, 0xFD],
        tags: Array(title) + [0]
    )

    let direct = try S98MetadataReader.read(data: data)
    #expect(direct.song == "曲")
    #expect(direct.system == "S98 v0.00")
    #expect(direct.playLengthMs == 20)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 v1 long CP932 title is decoded like libvgm")
func s98LongCP932TitleMatchesLibVGM() throws {
    let title: [UInt8] = [
        0x5B, 0x53, 0x4F, 0x52, 0x43, 0x45, 0x52, 0x49, 0x41, 0x4E, 0x20, 0x56, 0x41, 0x5D, 0x20,
        0x89, 0x46, 0x92, 0x88, 0x82, 0xA9, 0x82, 0xE7, 0x82, 0xCC, 0x96, 0x4B, 0x96, 0xE2, 0x8E,
        0xD2, 0x20, 0x88, 0xA4, 0x82, 0xC6, 0x94, 0xDF, 0x82, 0xB5, 0x82, 0xDD, 0x82, 0xCC, 0xCA,
        0xDE, 0xDD, 0xCA, 0xDF, 0xB2, 0xB1, 0x20, 0x2D, 0x20, 0xB1, 0xB0, 0xB8, 0xC3, 0xDE, 0xB0,
        0xD3, 0xDD
    ]
    let data = makeS98(version: 1, commands: [0xFD], tags: title + [0])
    let direct = try S98MetadataReader.read(data: data)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 v3 UTF-8 tags and comment projection match libvgm")
func s98V3UTF8TagsMatchLibVGM() throws {
    let tagText = "[S98]\u{FEFF}\nTITLE=Theme\nGAME=Game\nARTIST=Composer\nSYSTEM=YM2612\nCOMMENT=Mix\nYEAR=1998\nS98BY=Encoder\n"
    let data = makeS98(
        version: 3,
        tickMultiplier: 20,
        tickDivisor: 1_000,
        commands: [0xFE, 0x01, 0xFD],
        tags: Array(tagText.utf8) + [0]
    )

    let direct = try S98MetadataReader.read(data: data)
    #expect(direct.game == "Game")
    #expect(direct.song == "Theme")
    #expect(direct.author == "Composer")
    #expect(direct.system == "YM2612")
    #expect(direct.comment == "Mix | Date: 1998 | Encoded By: Encoder")
    #expect(direct.playLengthMs == 60)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 v2 device sentinel precedes the command stream")
func s98V2DeviceTableIsSkipped() throws {
    let data = makeS98(
        version: 2,
        tickMultiplier: 30,
        tickDivisor: 1_000,
        commands: [0xFF, 0xFF, 0xFD],
        v2Terminator: true
    )

    let direct = try S98MetadataReader.read(data: data)
    #expect(direct.system == "S98 v2.00")
    #expect(direct.playLengthMs == 60)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 ignores malformed optional v3 tags but keeps valid timing")
func s98MalformedOptionalTagsDoNotDiscardTiming() throws {
    let data = makeS98(version: 3, commands: [0xFF, 0xFD], tags: Array("not an S98 tag".utf8) + [0])
    let metadata = try S98MetadataReader.read(data: data)
    #expect(metadata.song.isEmpty)
    #expect(metadata.system == "S98 v3.00")
    #expect(metadata.playLengthMs == 10)
    let reference = try inspectLibVGM(data: data)
    #expect(metadata == reference)
}

@Test("S98 malformed headers and truncated events fail safely")
func s98MalformedInputsFailSafely() {
    #expect(throws: ScannerInspectionError.self) {
        try S98MetadataReader.read(data: Data("S98X".utf8))
    }
    #expect(throws: ScannerInspectionError.self) {
        try S98MetadataReader.read(data: makeS98(version: 1, commands: [0xFE, 0x80]))
    }
}

@Test("S98 length pass preserves libvgm's partial final register-write acceptance")
func s98PartialFinalRegisterWriteMatchesLibVGM() throws {
    let data = makeS98(version: 1, commands: [0x01, 0xFF])
    let direct = try S98MetadataReader.read(data: data)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test(
    "S98 direct metadata and timing match libvgm across the CocoaSpice corpus",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_S98_LIVE_DB"] != nil,
        "Set SCANSONG_S98_LIVE_DB to run read-only S98 corpus parity against the live CocoaSpice catalog and libvgm."
    )
)
func cocoaSpiceS98LiveRowsMatchLibVGM() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_S98_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_S98_LIVE_ROOT_ID"] ?? "1") ?? 1
    var archives = try readLiveS98Archives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    if let match = ProcessInfo.processInfo.environment["SCANSONG_S98_LIVE_MATCH"]?.lowercased(), !match.isEmpty {
        archives = archives.compactMap { archive in
            let files = archive.files.filter { $0.entryPath.lowercased().contains(match) }
            return files.isEmpty ? nil : S98LiveArchive(archivePath: archive.archivePath, files: files)
        }
    }
    #expect(!archives.isEmpty)

    let registry = BuiltInScannerPlugins.registry
    let extractor = StandaloneArchiveExtractor()
    var totalRows = 0
    var exactRows = 0
    var rejectedByBoth = 0
    var directTimes: [UInt64] = []
    var libVgmTimes: [UInt64] = []
    var mismatches: [String] = []
    let route = try #require(registry.route(pathExtension: "s98", archiveMember: true))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))

    for liveArchive in archives {
        var extracted: ExtractedScanArchive?
        var members: [String: URL] = [:]
        if let archivePath = liveArchive.archivePath {
            let extraction = try await extractor.extractForScan(
                archiveURL: URL(fileURLWithPath: archivePath),
                registry: registry
            )
            extracted = extraction
            members = Dictionary(
                extraction.members.map { (normalizeS98Entry($0.entryPath), $0.fileURL) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        defer {
            if let extracted { extractor.discard(extracted) }
        }

        for liveFile in liveArchive.files {
            totalRows += 1
            let fileURL: URL?
            if liveArchive.archivePath != nil {
                fileURL = members[normalizeS98Entry(liveFile.entryPath)]
            } else {
                fileURL = liveFile.sourcePath.map { URL(fileURLWithPath: $0) }
            }
            guard let fileURL else {
                if mismatches.count < 30 { mismatches.append("\(liveFile.entryPath): source member is unavailable") }
                continue
            }

            let directStart: UInt64
            let decoderStart: UInt64
            let directResult: Result<ScanInspection, Error>
            let decoderResult: Result<(ScannerMetadata, Int32), Error>
            if totalRows.isMultiple(of: 2) {
                directStart = DispatchTime.now().uptimeNanoseconds
                directResult = await result { try await handler.inspect(fileURL: fileURL, route: route) }
                directTimes.append(DispatchTime.now().uptimeNanoseconds &- directStart)
                decoderStart = DispatchTime.now().uptimeNanoseconds
                decoderResult = result { try inspectLibVGM(fileURL: fileURL) }
                libVgmTimes.append(DispatchTime.now().uptimeNanoseconds &- decoderStart)
            } else {
                decoderStart = DispatchTime.now().uptimeNanoseconds
                decoderResult = result { try inspectLibVGM(fileURL: fileURL) }
                libVgmTimes.append(DispatchTime.now().uptimeNanoseconds &- decoderStart)
                directStart = DispatchTime.now().uptimeNanoseconds
                directResult = await result { try await handler.inspect(fileURL: fileURL, route: route) }
                directTimes.append(DispatchTime.now().uptimeNanoseconds &- directStart)
            }

            switch (directResult, decoderResult) {
            case let (.success(inspection), .success((decoderMetadata, decoderTrackCount))):
                guard inspection.tracks.count == 1,
                      inspection.tracks[0].trackIndex == liveFile.trackIndex,
                      inspection.tracks[0].trackCount == liveFile.trackCount,
                      decoderTrackCount == Int32(inspection.tracks[0].trackCount),
                      let directMetadata = inspection.tracks[0].metadata else {
                    if mismatches.count < 30 { mismatches.append("\(liveFile.entryPath): track structure differs") }
                    continue
                }
                if directMetadata == decoderMetadata {
                    exactRows += 1
                } else if mismatches.count < 30 {
                    mismatches.append(
                        "\(liveFile.entryPath): \(metadataDifferences(directMetadata, decoderMetadata)); \(s98Debug(fileURL))"
                    )
                }
            case (.failure, .failure):
                rejectedByBoth += 1
            case let (.success, .failure(decoderError)):
                if mismatches.count < 30 {
                    mismatches.append("\(liveFile.entryPath): direct accepted but libvgm rejected: \(decoderError)")
                }
            case let (.failure(directError), .success):
                if mismatches.count < 30 {
                    mismatches.append("\(liveFile.entryPath): direct rejected but libvgm accepted: \(directError)")
                }
            }
        }
    }

    #expect(exactRows + rejectedByBoth == totalRows, "\(exactRows) exact and \(rejectedByBoth) commonly rejected out of \(totalRows) S98 rows")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))
    print(
        "S98 corpus: \(totalRows) rows / \(archives.count) source containers; exact \(exactRows); rejected by both \(rejectedByBoth); "
            + "direct median \(milliseconds(median(directTimes))) ms, libvgm median \(milliseconds(median(libVgmTimes))) ms; "
            + "direct p95 \(milliseconds(percentile95(directTimes))) ms, libvgm p95 \(milliseconds(percentile95(libVgmTimes))) ms"
    )
}

private func inspectLibVGM(fileURL: URL) throws -> (ScannerMetadata, Int32) {
    var metadata = libvgm_metadata_t()
    var trackCount: Int32 = 0
    var errorMessage: UnsafeMutablePointer<CChar>?
    let status = fileURL.path.withCString {
        libvgm_inspect_file($0, &metadata, &trackCount, &errorMessage)
    }
    defer { libvgm_metadata_clear(&metadata) }
    guard status == 0 else {
        let message = errorMessage.map { String(cString: $0) } ?? "libvgm rejected the S98 source."
        if let errorMessage { libvgm_error_message_free(errorMessage) }
        throw NSError(domain: "ScanSongS98Tests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
    if let errorMessage { libvgm_error_message_free(errorMessage) }
    return (
        ScannerMetadata(
            game: metadata.game.map { String(cString: $0) } ?? "",
            song: metadata.title.map { String(cString: $0) } ?? "",
            system: metadata.system.map { String(cString: $0) } ?? "",
            author: metadata.artist.map { String(cString: $0) } ?? "",
            comment: metadata.comment.map { String(cString: $0) } ?? "",
            introLengthMs: Int(metadata.intro_length_ms),
            loopLengthMs: Int(metadata.loop_length_ms),
            playLengthMs: Int(metadata.play_length_ms),
            fadeLengthMs: Int(metadata.fade_length_ms)
        ),
        trackCount
    )
}

private func inspectLibVGM(data: Data) throws -> ScannerMetadata {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-s98-oracle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("fixture.s98")
    try data.write(to: fileURL)
    return try inspectLibVGM(fileURL: fileURL).0
}

private func makeS98(
    version: UInt8,
    tickMultiplier: UInt32 = 0,
    tickDivisor: UInt32 = 0,
    loopCommandIndex: Int? = nil,
    commands: [UInt8],
    tags: [UInt8] = [],
    v2Terminator: Bool = false
) -> Data {
    var data = Data(repeating: 0, count: 0x20)
    data[0] = 0x53
    data[1] = 0x39
    data[2] = 0x38
    data[3] = 0x30 + version
    writeLE32(tickMultiplier, to: &data, at: 0x04)
    writeLE32(tickDivisor, to: &data, at: 0x08)

    if version == 2, v2Terminator {
        data.append(contentsOf: [UInt8](repeating: 0, count: 0x10))
    }
    if version == 3 {
        writeLE32(0, to: &data, at: 0x1C)
    }
    let dataOffset = data.count
    if let loopCommandIndex {
        writeLE32(UInt32(dataOffset + loopCommandIndex), to: &data, at: 0x18)
    }
    data.append(contentsOf: commands)
    if !tags.isEmpty {
        writeLE32(UInt32(data.count), to: &data, at: 0x10)
        data.append(contentsOf: tags)
    }
    writeLE32(UInt32(dataOffset), to: &data, at: 0x14)
    return data
}

private func writeLE32(_ value: UInt32, to data: inout Data, at offset: Int) {
    for byteIndex in 0..<4 {
        data[offset + byteIndex] = UInt8(truncatingIfNeeded: value >> (byteIndex * 8))
    }
}

private struct S98LiveFile {
    let entryPath: String
    let sourcePath: String?
    let trackIndex: Int
    let trackCount: Int
}

private struct S98LiveArchive {
    let archivePath: String?
    var files: [S98LiveFile]
}

private func readLiveS98Archives(databaseURL: URL, rootID: Int) throws -> [S98LiveArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the S98 catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongS98Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.archive_path, t.path, COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count
          FROM tracks t
         WHERE t.root_id = ?1 AND lower(t.extension) = 's98'
         ORDER BY COALESCE(t.archive_path, t.path), t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongS98Tests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongS98Tests", code: 3)
    }

    var archives: [S98LiveArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let archivePath = s98SQLiteText(statement, 0)
        let sourcePath = s98SQLiteText(statement, 1)
        let entryPath = s98SQLiteText(statement, 2)
        let file = S98LiveFile(
            entryPath: entryPath,
            sourcePath: sourcePath.isEmpty ? nil : sourcePath,
            trackIndex: Int(sqlite3_column_int64(statement, 3)),
            trackCount: Int(sqlite3_column_int64(statement, 4))
        )
        if archivePath.isEmpty {
            let key = "file:\(sourcePath)"
            if let index = indexes[key] {
                archives[index].files.append(file)
            } else {
                indexes[key] = archives.count
                archives.append(S98LiveArchive(archivePath: nil, files: [file]))
            }
        } else if let index = indexes[archivePath] {
            archives[index].files.append(file)
        } else {
            indexes[archivePath] = archives.count
            archives.append(S98LiveArchive(archivePath: archivePath, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongS98Tests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeS98Entry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func s98SQLiteText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func metadataDifferences(_ direct: ScannerMetadata, _ reference: ScannerMetadata) -> String {
    let fields: [(String, String, String)] = [
        ("game", direct.game, reference.game),
        ("song", direct.song, reference.song),
        ("system", direct.system, reference.system),
        ("author", direct.author, reference.author),
        ("comment", direct.comment, reference.comment),
        ("intro", String(direct.introLengthMs), String(reference.introLengthMs)),
        ("loop", String(direct.loopLengthMs), String(reference.loopLengthMs)),
        ("play", String(direct.playLengthMs), String(reference.playLengthMs)),
        ("fade", String(direct.fadeLengthMs), String(reference.fadeLengthMs))
    ]
    return fields
        .filter { $0.1 != $0.2 }
        .map { "\($0.0) direct=\(short($0.1)) libvgm=\(short($0.2))" }
        .joined(separator: "; ")
}

private func s98Debug(_ fileURL: URL) -> String {
    guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), data.count >= 0x20 else {
        return "header unavailable"
    }
    let version = data[3] >= 0x30 ? data[3] - 0x30 : 0xFF
    let tagOffset = Int(readLE32(data, at: 0x10))
    guard tagOffset > 0, tagOffset < data.count else {
        return "version \(version), no tag block"
    }
    var end = tagOffset
    while end < data.count, data[end] != 0, end - tagOffset < 120 { end += 1 }
    let tagBytes = data.subdata(in: tagOffset..<end)
    let text = String(data: tagBytes, encoding: .utf8)
        ?? String(data: tagBytes, encoding: .shiftJIS)
        ?? "<undecodable>"
    let hex = tagBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    return "version \(version), tag bytes [\(hex)], text [\(text)]"
}

private func readLE32(_ data: Data, at offset: Int) -> UInt32 {
    guard offset >= 0, offset <= data.count - 4 else { return 0 }
    return UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
}

private func short(_ value: String) -> String {
    value.count <= 100 ? value : String(value.prefix(100)) + "…"
}

private func result<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
    do { return .success(try await operation()) }
    catch { return .failure(error) }
}

private func result<Value>(_ operation: () throws -> Value) -> Result<Value, Error> {
    do { return .success(try operation()) }
    catch { return .failure(error) }
}

private func median(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

private func percentile95(_ values: [UInt64]) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, (sorted.count * 95) / 100)]
}

private func milliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}
