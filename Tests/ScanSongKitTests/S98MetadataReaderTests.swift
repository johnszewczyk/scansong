import Foundation
import MetaManCore
import SQLite3
import Testing
import VGMBoyCLibVGM
@testable import ScanSongKit

@Test("S98 v1 direct timing separates intro and loop duration")
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

    let direct = try readS98Metadata(data)
    #expect(direct.song == "Song title")
    #expect(direct.system == "S98 v1.00")
    #expect(direct.introLengthMs == 100)
    #expect(direct.loopLengthMs == 200)
    #expect(direct.playLengthMs == 300)
    #expect(direct.fadeLengthMs == 0)
    let reference = try inspectLibVGM(data: data)
    #expect(direct != reference)
    #expect(reference.introLengthMs == direct.loopLengthMs)
}

@Test("S98 loop pointers after the end command are ignored")
func s98StaleLoopPointerAfterTerminatorIsIgnored() throws {
    let data = makeS98(
        version: 1,
        tickMultiplier: 10,
        tickDivisor: 1_000,
        loopCommandIndex: 2,
        commands: [0xFF, 0xFD, 0xFF]
    )
    let document = try MetaManCore.read(data: data, formatHint: "s98")

    #expect(document.timing?.introLengthMs == 0)
    #expect(document.timing?.loopLengthMs == 0)
    #expect(document.timing?.playLengthMs == 10)
    #expect(document.technicalFacts["loopOffsetRecognized"] == "false")
    #expect(document.diagnostics.contains { $0.contains("loop offset does not identify") })
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

    let direct = try readS98Metadata(data)
    #expect(direct.song == "曲")
    #expect(direct.system == "S98 v0.00")
    #expect(direct.playLengthMs == 20)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 v1 long CP932 title is decoded instead of preserving libvgm's UTF-8 fallback")
func s98LongCP932TitleUsesTheDeclaredLegacyEncoding() throws {
    let title: [UInt8] = [
        0x5B, 0x53, 0x4F, 0x52, 0x43, 0x45, 0x52, 0x49, 0x41, 0x4E, 0x20, 0x56, 0x41, 0x5D, 0x20,
        0x89, 0x46, 0x92, 0x88, 0x82, 0xA9, 0x82, 0xE7, 0x82, 0xCC, 0x96, 0x4B, 0x96, 0xE2, 0x8E,
        0xD2, 0x20, 0x88, 0xA4, 0x82, 0xC6, 0x94, 0xDF, 0x82, 0xB5, 0x82, 0xDD, 0x82, 0xCC, 0xCA,
        0xDE, 0xDD, 0xCA, 0xDF, 0xB2, 0xB1, 0x20, 0x2D, 0x20, 0xB1, 0xB0, 0xB8, 0xC3, 0xDE, 0xB0,
        0xD3, 0xDD
    ]
    let data = makeS98(version: 1, commands: [0xFD], tags: title + [0])
    let direct = try readS98Metadata(data)
    let reference = try inspectLibVGM(data: data)
    #expect(direct.song == "[SORCERIAN VA] 宇宙からの訪問者 愛と悲しみのﾊﾞﾝﾊﾟｲｱ - ｱｰｸﾃﾞｰﾓﾝ")
    #expect(direct.song != reference.song)
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

    let direct = try readS98Metadata(data)
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

    let direct = try readS98Metadata(data)
    #expect(direct.system == "S98 v2.00")
    #expect(direct.playLengthMs == 60)
    let reference = try inspectLibVGM(data: data)
    #expect(direct == reference)
}

@Test("S98 ignores malformed optional v3 tags but keeps valid timing")
func s98MalformedOptionalTagsDoNotDiscardTiming() throws {
    let data = makeS98(version: 3, commands: [0xFF, 0xFD], tags: Array("not an S98 tag".utf8) + [0])
    let metadata = try readS98Metadata(data)
    #expect(metadata.song.isEmpty)
    #expect(metadata.system == "S98 v3.00")
    #expect(metadata.playLengthMs == 10)
    let reference = try inspectLibVGM(data: data)
    #expect(metadata == reference)
}

@Test("S98 DATE retains a full date independently from YEAR in the catalog projection")
func s98FullDateAndYearSurviveScanSongProjection() throws {
    let tagText = "[S98]\u{FEFF}TITLE=Theme\nDATE=1998-07-26\nYEAR=1998\nCOMMENT=Original note\n"
    let data = makeS98(version: 3, commands: [0xFD], tags: Array(tagText.utf8) + [0])
    let document = try MetaManCore.read(data: data, formatHint: "s98")
    let projected = ScannerMetadata(metadataDocument: document)

    #expect(document.fields.date == "1998-07-26")
    #expect(document.fields.year == "1998")
    #expect(projected.comment == "Original note | Date: 1998-07-26")
}

@Test("S98 malformed headers and truncated events fail safely")
func s98MalformedInputsFailSafely() {
    #expect(throws: MetadataReadError.self) {
        try readS98Metadata(Data("S98X".utf8))
    }
    #expect(throws: MetadataReadError.self) {
        try readS98Metadata(makeS98(version: 1, commands: [0xFE, 0x80]))
    }
}

@Test("S98 partial final register writes preserve completed timing with a diagnostic")
func s98PartialFinalRegisterWritePreservesCompletedEvents() throws {
    let data = makeS98(version: 1, commands: [0x01, 0xFF])
    let document = try MetaManCore.read(data: data, formatHint: "s98")
    #expect(document.timing?.playLengthMs == 0)
    #expect(document.diagnostics.contains { $0.contains("truncated register-write") })
}

@Test(
    "S98 metadata matches the catalog oracle except documented reader improvements",
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
    var improvedRows = 0
    var timingImprovements = 0
    var staleLoopImprovements = 0
    var dateImprovements = 0
    var titleImprovements = 0
    var titleTrimImprovements = 0
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
                } else if let document = try? MetaManCore.read(fileURL: fileURL),
                          let improvement = knownS98Improvements(
                              direct: directMetadata,
                              reference: decoderMetadata,
                              document: document
                          ), improvement.hasImprovement {
                    improvedRows += 1
                    if improvement.timing { timingImprovements += 1 }
                    if improvement.staleLoop { staleLoopImprovements += 1 }
                    if improvement.date { dateImprovements += 1 }
                    if improvement.title { titleImprovements += 1 }
                    if improvement.titleTrim { titleTrimImprovements += 1 }
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
                    mismatches.append("\(liveFile.entryPath): direct rejected but libvgm accepted: \(directError); \(s98Debug(fileURL))")
                }
            }
        }
    }

    #expect(exactRows + improvedRows + rejectedByBoth == totalRows, "\(exactRows) exact, \(improvedRows) intentionally improved, and \(rejectedByBoth) commonly rejected out of \(totalRows) S98 rows")
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))
    print(
        "S98 corpus: \(totalRows) rows / \(archives.count) source containers; exact \(exactRows); improved \(improvedRows) (timing \(timingImprovements), stale loop offsets \(staleLoopImprovements), full DATE \(dateImprovements), Shift_JIS decode \(titleImprovements), edge-space cleanup \(titleTrimImprovements)); rejected by both \(rejectedByBoth); "
            + "direct median \(milliseconds(median(directTimes))) ms, libvgm median \(milliseconds(median(libVgmTimes))) ms; "
            + "direct p95 \(milliseconds(percentile95(directTimes))) ms, libvgm p95 \(milliseconds(percentile95(libVgmTimes))) ms"
    )
}

private func readS98Metadata(_ data: Data) throws -> ScannerMetadata {
    ScannerMetadata(metadataDocument: try MetaManCore.read(data: data, formatHint: "s98"))
}

private func knownS98Improvements(
    direct: ScannerMetadata,
    reference: ScannerMetadata,
    document: MetadataDocument
) -> (hasImprovement: Bool, timing: Bool, staleLoop: Bool, date: Bool, title: Bool, titleTrim: Bool)? {
    let timingImproved = direct.introLengthMs != reference.introLengthMs
        || direct.loopLengthMs != reference.loopLengthMs
    let staleLoopImproved = timingImproved
        && direct.introLengthMs == 0
        && direct.loopLengthMs == 0
        && reference.introLengthMs == reference.loopLengthMs
        && direct.playLengthMs == reference.introLengthMs
        && document.technicalFacts["loopOffsetRecognized"] == "false"
    let dateImproved = direct.comment != reference.comment
    let titleChanged = direct.song != reference.song
    let titleTrimImproved = titleChanged && direct.song == trimS98TestWhitespace(reference.song)
    let titleImproved = titleChanged && !titleTrimImproved
    guard timingImproved || dateImproved || titleChanged,
          direct.game == reference.game,
          direct.system == reference.system,
          direct.author == reference.author,
          direct.playLengthMs == reference.playLengthMs,
          direct.fadeLengthMs == reference.fadeLengthMs else { return nil }

    if timingImproved {
        let validLoopIntroCorrection = direct.loopLengthMs == reference.loopLengthMs
            && document.technicalFacts["loopStartTicks"] != nil
            && reference.introLengthMs == direct.loopLengthMs
        guard validLoopIntroCorrection || staleLoopImproved else { return nil }
    }

    if dateImproved {
        guard document.fields.date != document.fields.year,
              reference.comment == s98LegacyComment(document.fields) else { return nil }
    }

    if titleChanged {
        guard document.fields.title == direct.song,
              document.sourceEncoding == "Shift_JIS",
              direct.song == s98TitleDecodedFromRaw(document) else { return nil }
    }

    return (true, timingImproved, staleLoopImproved, dateImproved, titleImproved, titleTrimImproved)
}

private func s98TitleDecodedFromRaw(_ document: MetadataDocument) -> String? {
    guard let rawBlock = document.rawTagBlock,
          document.sourceEncoding == "Shift_JIS" else { return nil }
    var bytes = Array(rawBlock)
    if document.technicalFacts["version"] == "3" {
        guard bytes.starts(with: Array("[S98]".utf8)) else { return nil }
        bytes.removeFirst(5)
        guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else { return nil }
        guard let line = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
            .first(where: { String(decoding: $0.prefix(6), as: UTF8.self).lowercased() == "title=" }) else {
            return nil
        }
        guard let equals = line.firstIndex(of: 0x3D) else { return nil }
        bytes = Array(line[line.index(after: equals)...])
    }
    guard let decoded = String(data: Data(bytes), encoding: .shiftJIS) else { return nil }
    return trimS98TestWhitespace(decoded)
}

private func trimS98TestWhitespace(_ string: String) -> String {
    let bytes = Array(string.utf8)
    var start = 0
    var end = bytes.count
    while start < end, bytes[start] <= 0x20 { start += 1 }
    while end > start, bytes[end - 1] <= 0x20 { end -= 1 }
    return String(decoding: bytes[start..<end], as: UTF8.self)
}

private func s98LegacyComment(_ fields: MetadataFields) -> String {
    var result = fields.comment ?? ""
    if let year = fields.year, !year.isEmpty {
        if !result.isEmpty { result += " | " }
        result += "Date: \(year)"
    }
    if let encodedBy = fields.encodedBy, !encodedBy.isEmpty {
        if !result.isEmpty { result += " | " }
        result += "Encoded By: \(encodedBy)"
    }
    return result
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
    let dataOffset = Int(readLE32(data, at: 0x14))
    let loopOffset = Int(readLE32(data, at: 0x18))
    let offsets = "version \(version), size \(data.count), dataOffset \(dataOffset), loopOffset \(loopOffset), tagOffset \(tagOffset)"
    let commandEnd = tagOffset > dataOffset && tagOffset <= data.count ? tagOffset : data.count
    let tailStart = max(dataOffset, commandEnd - 12)
    let commandTail = tailStart < commandEnd
        ? data[tailStart..<commandEnd].map { String(format: "%02X", $0) }.joined(separator: " ")
        : ""
    let loopBytes = loopOffset >= 0 && loopOffset < data.count
        ? data[loopOffset..<min(data.count, loopOffset + 8)].map { String(format: "%02X", $0) }.joined(separator: " ")
        : "outside file"
    guard tagOffset > 0, tagOffset < data.count else {
        return "\(offsets), command tail [\(commandTail)], loop bytes [\(loopBytes)], no tag block"
    }
    var end = tagOffset
    while end < data.count, data[end] != 0, end - tagOffset < 120 { end += 1 }
    let tagBytes = data.subdata(in: tagOffset..<end)
    let text = String(data: tagBytes, encoding: .utf8)
        ?? String(data: tagBytes, encoding: .shiftJIS)
        ?? "<undecodable>"
    let hex = tagBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    return "\(offsets), command tail [\(commandTail)], loop bytes [\(loopBytes)], tag bytes [\(hex)], text [\(text)]"
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
