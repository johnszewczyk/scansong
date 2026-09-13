import Foundation
import SQLite3
import Testing
@testable import ScanSongKit

@Test("Sony XA direct reader preserves sample modes and single-track naming")
func xaMetadataReaderPreservesHeaderContract() throws {
    let fourBit = try XAMetadataReader.read(
        data: makeXARaw([makeXASector(), makeXASector(), makeXASector()]),
        displayName: "Opening Theme.xa"
    )
    #expect(fourBit.count == 1)
    #expect(fourBit[0].trackIndex == 0)
    #expect(fourBit[0].trackCount == 1)
    #expect(fourBit[0].metadata == ScannerMetadata(
            game: "",
            song: "Opening Theme",
            system: "",
            author: "",
            comment: "Sony XA header",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: 160,
            fadeLengthMs: 0
        ))

    let fourBitForm1 = try XAMetadataReader.read(
        data: makeXARaw((0..<3).map { _ in makeXASector(submode: 0x44, header: 0x05) }),
        displayName: "Form 1.xa"
    )
    #expect(fourBitForm1[0].metadata?.playLengthMs == 284)

    let eightBitStereo = try XAMetadataReader.read(
        data: makeXARaw((0..<3).map { _ in makeXASector(header: 0x11) }),
        displayName: "8-bit.xa"
    )
    #expect(eightBitStereo[0].metadata?.playLengthMs == 80)
}

@Test("Sony XA direct reader follows interleaved channel EOF and subsong order")
func xaMetadataReaderEnumeratesInterleavedSubsongs() throws {
    let sectors = [
        makeXASector(file: 1, channel: 0),
        makeXASector(file: 1, channel: 1),
        makeXASector(file: 1, channel: 0),
        makeXASector(file: 1, channel: 0, submode: 0xE4),
        makeXASector(file: 1, channel: 0)
    ]
    let tracks = try XAMetadataReader.read(data: makeXARaw(sectors), displayName: "BGM.XA")
    #expect(tracks.map(\.trackIndex) == [0, 1, 2])
    #expect(tracks.map(\.trackCount) == [3, 3, 3])
    #expect(tracks.compactMap(\.metadata?.song) == ["0100", "0101", "0100"])
    #expect(tracks.compactMap(\.metadata?.playLengthMs) == [160, 53, 53])
}

@Test("Sony XA reader matches tolerated short sources and rejects invalid sector headers")
func xaMetadataReaderHandlesWrappedAndMalformedSources() throws {
    let wrapped = makeXARIFF(makeXARaw((0..<3).map { _ in makeXASector() }))
    let tracks = try XAMetadataReader.read(data: wrapped, displayName: "wrapped.xa")
    #expect(tracks.count == 1)
    #expect(tracks[0].metadata?.playLengthMs == 160)

    let oneSector = try XAMetadataReader.read(data: makeXARaw([makeXASector()]), displayName: "short.xa")
    #expect(oneSector.count == 1)
    #expect(oneSector[0].metadata?.playLengthMs == 53)

    let truncated = try XAMetadataReader.read(
        data: Data(makeXASector().prefix(100)),
        displayName: "partial-sector.xa"
    )
    #expect(truncated.count == 1)
    #expect(truncated[0].metadata?.playLengthMs == 53)

    var badFrame = makeXASector()
    badFrame[0x18] = 0xF1
    #expect(throws: ScannerInspectionError.self) {
        try XAMetadataReader.read(
            data: makeXARaw([badFrame, makeXASector(), makeXASector()]),
            displayName: "bad-frame.xa"
        )
    }

    #expect(throws: ScannerInspectionError.self) {
        try XAMetadataReader.read(
            data: makeXARaw((0..<3).map { _ in makeXASector(header: 0x03) }),
            displayName: "bad-channels.xa"
        )
    }
}

@Test(
    "Legacy vgmstream and direct reader agree on sparse raw XA probes",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil,
        "Set SCANSONG_VGMSTREAM_CLI to compare sparse and truncated raw-XA boundaries against the legacy inspector."
    )
)
func legacyVGMStreamMatchesSparseRawXAProbe() async throws {
    _ = try #require(ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"])
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-xa-legacy-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let probes: [(String, Data)] = [
        ("one-audio-sector", makeXARaw([makeXASector()])),
        ("two-audio-sectors", makeXARaw([makeXASector(), makeXASector()])),
        ("audio-then-non-audio", makeXARaw([makeXASector(), makeXASector(submode: 0x08)])),
        ("truncated-100-byte", Data(makeXASector().prefix(100)))
    ]
    let handler = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream malformed XA reference",
        supportedExtensions: ["xa"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))
    let route = ScannerRoute(
        pluginID: "vgmstream",
        formatExtension: "xa",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    for (name, bytes) in probes {
        let fileURL = directory.appendingPathComponent("\(name).xa")
        try bytes.write(to: fileURL)
        let directTracks = try XAMetadataReader.read(fileURL: fileURL)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let legacyInspection = try await handler.inspect(fileURL: fileURL, route: route)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        print(String(format: "Legacy XA probe %@ elapsed %.3f seconds", name, elapsedSeconds))
        #expect(legacyInspection.tracks.count == directTracks.count, "\(name): track count")
        #expect(legacyInspection.tracks.map(\.trackIndex) == directTracks.map(\.trackIndex), "\(name): track indexes")
        #expect(legacyInspection.tracks.map(\.trackCount) == directTracks.map(\.trackCount), "\(name): track counts")
        #expect(legacyInspection.tracks.map(\.metadata) == directTracks.map(\.metadata), "\(name): metadata")
    }
}

@Test("XA routing recognizes Sony raw and RIFF sectors but preserves other aliases")
func xaRoutingKeepsNonSonyAliasesOnVgmstream() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "xa")?.pluginID == "xa-direct")
    #expect(registry.route(pathExtension: "xa")?.metadataPolicy == .direct)
    #expect(!BuiltInScannerPlugins.directVGMStreamExtensions.contains("xa"))
    #expect(registry.descriptors.first(where: { $0.pluginID == "vgmstream" })?.supportedExtensions.contains("xa") == true)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-xa-route-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let rawURL = directory.appendingPathComponent("raw.xa")
    try makeXARaw((0..<3).map { _ in makeXASector() }).write(to: rawURL)
    #expect(registry.route(forPath: rawURL.path, archiveMember: true)?.pluginID == "xa-direct")

    let riffURL = directory.appendingPathComponent("riff.xa")
    try makeXARIFF(makeXARaw((0..<3).map { _ in makeXASector() })).write(to: riffURL)
    #expect(registry.route(forPath: riffURL.path)?.pluginID == "xa-direct")

    for (name, bytes) in [
        ("maxis.xa", Data([0x58, 0x41, 0x00, 0x00])),
        ("reflections.xa", Data("XA30".utf8)),
        ("aiff.xa", Data("FORM".utf8)),
        ("unknown.xa", Data("other format".utf8))
    ] {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        #expect(registry.route(forPath: url.path)?.pluginID == "vgmstream")
    }
}

@Test(
    "Sony XA direct metadata matches CocoaSpice rows and vgmstream",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_XA_LIVE_DB"] != nil,
        "Set SCANSONG_XA_LIVE_DB to run read-only XA catalog parity. Set SCANSONG_VGMSTREAM_CLI to compare against the decoder."
    )
)
func cocoaSpiceXALiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_XA_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_XA_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveXAArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    #expect(!archives.isEmpty)

    let decoderEnabled = ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"] != nil
    let decoderRoute = ScannerRoute(
        pluginID: "vgmstream",
        formatExtension: "xa",
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    )
    let decoderHandler = VGMStreamCLIInspector(descriptor: ScannerPluginDescriptor(
        pluginID: "vgmstream",
        displayName: "vgmstream XA parity reference",
        supportedExtensions: ["xa"],
        structurePolicy: .enumerate,
        metadataPolicy: .decoder
    ))
    let extractor = StandaloneArchiveExtractor()
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
            extraction.members.map { (normalizeXAEntry($0.entryPath), $0.fileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        let expectedByEntry = Dictionary(grouping: liveArchive.files, by: \.entryPath)

        for (entryPath, expectedRows) in expectedByEntry.sorted(by: { $0.key < $1.key }) {
            guard let fileURL = members[normalizeXAEntry(entryPath)] else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): archive extraction omitted saved XA member") }
                continue
            }
            guard let directRoute = BuiltInScannerPlugins.registry.route(
                forPath: fileURL.path,
                archiveMember: true
            ), directRoute.pluginID == "xa-direct",
                  let directHandler = BuiltInFormatInspectors.registry.handler(for: directRoute) else {
                if mismatches.count < 20 { mismatches.append("\(entryPath): content-aware route did not select xa-direct") }
                continue
            }

            let directStart = DispatchTime.now().uptimeNanoseconds
            let directInspection = try await directHandler.inspect(fileURL: fileURL, route: directRoute)
            directNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- directStart
            let catalogRows = expectedRows.map(LiveXARow.init).sorted { $0.trackIndex < $1.trackIndex }
            let directRows = directInspection.tracks.map(LiveXARow.init).sorted { $0.trackIndex < $1.trackIndex }
            if directRows == catalogRows {
                exactSavedRows += catalogRows.count
            } else if mismatches.count < 20 {
                mismatches.append("\(entryPath): direct structure/metadata differs from saved catalog")
            }

            if decoderEnabled {
                let decoderStart = DispatchTime.now().uptimeNanoseconds
                let decoderInspection = try await decoderHandler.inspect(fileURL: fileURL, route: decoderRoute)
                decoderNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- decoderStart
                let decoderRows = decoderInspection.tracks.map(LiveXARow.init).sorted { $0.trackIndex < $1.trackIndex }
                if directRows == decoderRows {
                    exactDecoderRows += catalogRows.count
                } else if mismatches.count < 20 {
                    mismatches.append("\(entryPath): direct structure/metadata differs from vgmstream")
                }
            }
        }
        print("XA parity progress: archive \(archiveIndex + 1)/\(archives.count), \(liveArchive.files.count) catalog rows")
    }

    #expect(exactSavedRows == totalRows, "\(exactSavedRows)/\(totalRows) XA rows exactly match saved catalog metadata")
    if decoderEnabled {
        #expect(exactDecoderRows == totalRows, "\(exactDecoderRows)/\(totalRows) XA rows exactly match vgmstream")
    }
    #expect(mismatches.isEmpty, Comment(rawValue: mismatches.joined(separator: "\n")))

    let fileCount = archives.reduce(0) { $0 + Set($1.files.map(\.entryPath)).count }
    let directAverageMs = Double(directNanoseconds) / Double(max(1, fileCount)) / 1_000_000
    let decoderAverageMs = decoderEnabled
        ? Double(decoderNanoseconds) / Double(max(1, fileCount)) / 1_000_000
        : 0
    print(
        "XA corpus: \(totalRows) rows / \(fileCount) files / \(archives.count) archives; "
            + "catalog exact \(exactSavedRows); vgmstream exact \(exactDecoderRows); "
            + String(format: "mean direct %.3f ms/file", directAverageMs)
            + (decoderEnabled ? String(format: ", mean vgmstream CLI %.3f ms/file", decoderAverageMs) : "")
    )
}

private struct LiveXAMetadata: Equatable {
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

private struct LiveXARow: Equatable {
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveXAMetadata?

    init(_ track: ScanTrackMetadata) {
        trackIndex = track.trackIndex
        trackCount = track.trackCount
        metadata = track.metadata.map(LiveXAMetadata.init)
    }

    init(_ row: LiveXAFile) {
        trackIndex = row.trackIndex
        trackCount = row.trackCount
        metadata = row.metadata
    }
}

private struct LiveXAFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let metadata: LiveXAMetadata
}

private struct LiveXAArchive {
    let path: String
    var files: [LiveXAFile]
}

private func readLiveXAArchives(databaseURL: URL, rootID: Int) throws -> [LiveXAArchive] {
    var database: OpaquePointer?
    let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard status == SQLITE_OK, let database else {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the XA catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongXATests", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT COALESCE(t.archive_path, t.path), COALESCE(t.archive_entry, t.filename),
               t.track_index, t.track_count, m.game, m.title, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms, m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'xa'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongXATests", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongXATests", code: 3)
    }

    var archives: [LiveXAArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let file = LiveXAFile(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            metadata: LiveXAMetadata(statement: statement, firstColumn: 4)
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveXAArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongXATests", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func normalizeXAEntry(_ entry: String) -> String {
    entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
}

private func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
}

private func makeXARaw(_ sectors: [Data]) -> Data {
    sectors.reduce(into: Data()) { $0.append($1) }
}

private func makeXARIFF(_ payload: Data) -> Data {
    var wrapped = Data(repeating: 0, count: 0x2C)
    wrapped.replaceSubrange(0..<4, with: Data("RIFF".utf8))
    wrapped.replaceSubrange(0x08..<0x0C, with: Data("CDXA".utf8))
    wrapped.replaceSubrange(0x0C..<0x10, with: Data("fmt ".utf8))
    wrapped.append(payload)
    return wrapped
}

private func makeXASector(
    file: UInt8 = 0,
    channel: UInt8 = 0,
    submode: UInt8 = 0x64,
    header: UInt8 = 0x01
) -> Data {
    var sector = Data(repeating: 0, count: 0x930)
    sector.replaceSubrange(0..<12, with: Data([0x00] + Array(repeating: 0xFF, count: 10) + [0x00]))
    let subheader = Data([file, channel, submode, header])
    sector.replaceSubrange(0x10..<0x14, with: subheader)
    sector.replaceSubrange(0x14..<0x18, with: subheader)
    let frameHeader = Data([0x11, 0x22, 0x31, 0x12, 0x11, 0x22, 0x31, 0x12,
                            0x11, 0x22, 0x31, 0x12, 0x11, 0x22, 0x31, 0x12])
    for frame in 0..<(0x900 / 0x80) {
        let offset = 0x18 + frame * 0x80
        sector.replaceSubrange(offset..<(offset + frameHeader.count), with: frameHeader)
    }
    return sector
}
