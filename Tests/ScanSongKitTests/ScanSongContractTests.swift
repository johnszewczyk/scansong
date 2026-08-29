import Foundation
import SQLite3
import Testing
import zlib
@testable import ScanSongKit

@Test func builtInPoliciesPreserveRequiredStructureWork() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "spc")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: ".NSF")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "gbs")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "flac")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "txtp")?.structurePolicy == .dependencyEnumerate)
    #expect(registry.route(pathExtension: "sid")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "sid")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "sndh")?.pluginID == "psgplay")
    #expect(registry.route(pathExtension: "sndh")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "sndh")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "mdx")?.pluginID == "mdx")
    #expect(registry.route(pathExtension: "mdx")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "pdx") == nil)
    #expect(registry.route(pathExtension: "ogg")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "ogg")?.pluginID == "standard-audio")
    #expect(registry.route(pathExtension: "ogg")?.pluginID != "vgmstream")
    #expect(registry.route(pathExtension: "qsf")?.pluginID == "qsf")
    #expect(registry.route(pathExtension: "miniqsf")?.pluginID == "qsf-mini")
    #expect(registry.route(pathExtension: "miniqsf")?.structurePolicy == .dependencyEnumerate)
    #expect(BuiltInScannerPlugins.archiveExtensions.contains("zst"))
    #expect(StandaloneArchiveExtractor.isSupportedArchive(URL(fileURLWithPath: "track.vgm.zst")))
    #expect(StandaloneArchiveExtractor.isSupportedArchive(URL(fileURLWithPath: "set.tar.zst")))
    #expect(StandaloneArchiveExtractor.isStandaloneSupportFile(URL(fileURLWithPath: "bank.PDX.zst")))
    for sidecar in ["bank.2sflib.zst", "bank.ssflib.zst", "bank.usflib.zst"] {
        #expect(StandaloneArchiveExtractor.isStandaloneSupportFile(URL(fileURLWithPath: sidecar)))
    }
    #expect(!StandaloneArchiveExtractor.isStandaloneSupportFile(URL(fileURLWithPath: "track.MDX.zst")))
    #expect(StandaloneArchiveExtractor.standaloneEntryPath(
        for: URL(fileURLWithPath: "track.vgm.zst"),
        registry: registry
    ) == "track.vgm")
    #expect(StandaloneArchiveExtractor.standaloneEntryPath(
        for: URL(fileURLWithPath: "set.tar.zst"),
        registry: registry
    ) == nil)
    #expect(registry.route(pathExtension: "strm")?.pluginID == "vgmstream")
    #expect(registry.route(pathExtension: "ahx")?.pluginID == "vgmstream")
    #expect(registry.route(pathExtension: "xmd")?.pluginID == "vgmstream")
    #expect(registry.route(pathExtension: "hd")?.pluginID == "vgmstream-hd-bank")
    for ext in BuiltInScannerPlugins.gameCubeVGMStreamExtensions {
        #expect(registry.route(pathExtension: ext)?.pluginID == "vgmstream")
    }
    #expect(registry.route(pathExtension: "txth") == nil)
    #expect(registry.route(pathExtension: "sbb") == nil)
    #expect(ScannerFormatPolicy.defaultIgnoredExtensions.contains("sgc"))
    #expect(ScannerFormatPolicy.defaultIgnoredExtensions.contains("minincsf"))
    #expect(ScannerFormatPolicy.defaultIgnoredExtensions.contains("mus"))
}

@Test(
    "MDX fixture publishes one native-duration track",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_MDX_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_MDX_INSPECT"] != nil,
        "Set SCANSONG_MDX_FIXTURE and SCANSONG_MDX_INSPECT to run the MDX scanner check."
    )
)
func mdxFixtureInspectsThroughVGMBoy() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_MDX_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: fileURL.pathExtension))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(inspection.tracks.count == 1)
    #expect(inspection.tracks.first?.trackIndex == 0)
    #expect(inspection.tracks.first?.trackCount == 1)
    #expect((inspection.tracks.first?.metadata?.playLengthMs ?? 0) > 0)
    #expect(inspection.tracks.first?.metadata?.system == "Sharp X68000")
}

@Test(
    "SNDH fixture publishes PSGPlay subtunes and timing",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SNDH_FIXTURE"] != nil,
        "Set SCANSONG_SNDH_FIXTURE to run the Zone Warrior scanner check."
    )
)
func sndhFixtureInspectsThroughPSGPlay() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_SNDH_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: fileURL.pathExtension))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(!inspection.tracks.isEmpty)
    #expect(inspection.tracks.allSatisfy { $0.trackCount == inspection.tracks.count })
    #expect(inspection.tracks.map(\.trackIndex) == Array(0..<inspection.tracks.count))
    #expect(inspection.tracks.allSatisfy { ($0.metadata?.playLengthMs ?? 0) > 0 })
    #expect(inspection.tracks.first?.metadata?.system == "Atari ST")
}

@Test(
    "HES fixture applies its sibling M3U to publish authored music and SFX",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_HES_FIXTURE"] != nil,
        "Set SCANSONG_HES_FIXTURE to run the archive-backed Bloody Wolf HES check."
    )
)
func hesFixtureInspectsCompanionPlaylist() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_HES_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: fileURL.pathExtension))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)

    #expect(inspection.tracks.count == 17)
    #expect(inspection.tracks[0].metadata?.song == "Title")
    #expect(inspection.tracks[0].metadata?.playLengthMs == 20_000)
    #expect(inspection.tracks[12].metadata?.song == "Stage Clear")
    #expect(inspection.tracks[12].metadata?.playLengthMs == 4_000)
}

@Test(
    "Core Audio inspection publishes FLAC metadata and duration",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_FLAC_FIXTURE"] != nil,
        "Set SCANSONG_FLAC_FIXTURE to run the archive-backed FLAC metadata check."
    )
)
func flacFixturePublishesStandardMetadata() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_FLAC_FIXTURE"])
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "flac"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: URL(fileURLWithPath: path), route: route)
    let metadata = try #require(inspection.tracks.first?.metadata)
    #expect(metadata.system == "Standard audio")
    #expect(metadata.song == "Credits")
    #expect(metadata.game == "NeuroDancer - Journey into the Neuronet!")
    #expect(metadata.playLengthMs > 0)
}

@Test(
    "GameCube routes open through the bundled inspector with real timing",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_GAMECUBE_FIXTURES"] != nil,
        "Set SCANSONG_GAMECUBE_FIXTURES to run the archive-backed GameCube scanner checks."
    )
)
func gameCubeFixturesInspectThroughVGMStream() async throws {
    let rootPath = try #require(ProcessInfo.processInfo.environment["SCANSONG_GAMECUBE_FIXTURES"])
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsPackageDescendants]
    ))
    let admitted = BuiltInScannerPlugins.gameCubeVGMStreamExtensions.union(["txtp"])
    let fixtures = enumerator.compactMap { $0 as? URL }.filter {
        admitted.contains($0.pathExtension.lowercased())
    }
    #expect(Set(fixtures.map { $0.pathExtension.lowercased() }) == admitted)

    for fixture in fixtures.sorted(by: { $0.path < $1.path }) {
        let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: fixture.pathExtension))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
        let inspection = try await handler.inspect(fileURL: fixture, route: route)
        #expect(!inspection.tracks.isEmpty, Comment(rawValue: fixture.lastPathComponent))
        #expect(inspection.tracks.allSatisfy {
            ($0.metadata?.playLengthMs ?? 0) > 0
        }, Comment(rawValue: fixture.lastPathComponent))
    }
}

@Test func txtpPreparationRetainsDependenciesWithoutPublishingDuplicateSources() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-txtp-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bank = root.appendingPathComponent("Bgm", isDirectory: true)
    try FileManager.default.createDirectory(at: bank, withIntermediateDirectories: true)
    let directDependency = bank.appendingPathComponent("direct.adp")
    let flattenedDependency = root.appendingPathComponent("flattened.rsf")
    try Data([0]).write(to: directDependency)
    try Data([0]).write(to: flattenedDependency)
    try Data("Bgm/direct.adp\nBgm/flattened.rsf #I 0 1000\n".utf8)
        .write(to: root.appendingPathComponent("game.txtp"))

    let dependencies = try TXTPDependencyResolver().prepareDependencies(in: root)
    let alias = bank.appendingPathComponent("flattened.rsf")
    #expect(FileManager.default.fileExists(atPath: alias.path))
    #expect(dependencies == Set([
        directDependency.standardizedFileURL.path,
        flattenedDependency.standardizedFileURL.path,
        alias.standardizedFileURL.path
    ]))
}

@Test func ignoredFileTypePolicySkipsOnlyConfiguredExtensions() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-ignore-policy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 4).write(to: root.appendingPathComponent("Game.sgc"))
    try Data(repeating: 0, count: 4).write(to: root.appendingPathComponent("Game.strm"))

    let candidates = try await ScanFilesystemDiscovery.discover(
        rootID: 1,
        rootURL: root,
        registry: BuiltInScannerPlugins.registry,
        isArchive: { _ in false },
        ignoredFileExtensions: ScannerFormatPolicy.defaultIgnoredExtensions
    )
    #expect(candidates.map(\.sourceURL.lastPathComponent) == ["Game.strm"])
}

@Test func archiveEnumerationReportsUnknownMembersWithoutSupportFileNoise() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-archive-members-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0]).write(to: root.appendingPathComponent("notes.xyz"))
    try Data([0]).write(to: root.appendingPathComponent("music.qsflib"))
    try Data([0]).write(to: root.appendingPathComponent("music.usflib"))
    try Data([0]).write(to: root.appendingPathComponent("music.ssflib"))
    try Data([0]).write(to: root.appendingPathComponent("music.2sflib"))
    try Data([0]).write(to: root.appendingPathComponent("music.sbb"))
    try Data([0]).write(to: root.appendingPathComponent("ReadMe.TXT"))
    try Data([0]).write(to: root.appendingPathComponent("extensionless"))

    let listing = try ArchiveMemberEnumerator().enumerate(
        payloadURL: root,
        registry: BuiltInScannerPlugins.registry,
        ignoredFileExtensions: [],
        dependencyPaths: []
    )

    #expect(listing.members.isEmpty)
    #expect(listing.skipped.map(\.entryPath) == ["notes.xyz"])
    #expect(listing.skipped.first?.reason == .unsupportedFormat)
}

@Test func sidHeaderReaderPublishesCommodore64Metadata() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-sid-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    var header = Data(repeating: 0, count: 0x7C)
    header.replaceSubrange(0..<4, with: Data("PSID".utf8))
    header[0x04] = 0; header[0x05] = 2            // version 2
    header[0x06] = 0; header[0x07] = 0x7C          // data offset
    header[0x08] = 0x08; header[0x09] = 0x00       // load address
    header[0x0E] = 0; header[0x0F] = 1             // number of songs
    header[0x10] = 0; header[0x11] = 1             // start song
    let name = Data("Willow".utf8); header.replaceSubrange(0x16..<(0x16 + name.count), with: name)
    let author = Data("Tester".utf8); header.replaceSubrange(0x2E..<(0x2E + author.count), with: author)
    header[0x76] = 0; header[0x77] = 30            // PAL play length 30s
    header[0x78] = 0; header[0x79] = 0

    let fileURL = root.appendingPathComponent("Willow.sid")
    try header.write(to: fileURL)

    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "sid"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    let metadata = try #require(inspection.tracks.first?.metadata)
    #expect(inspection.tracks.count == 1)
    #expect(metadata.system == "Commodore 64")
    #expect(metadata.song == "Willow")
    #expect(metadata.author == "Tester")
    #expect(metadata.playLengthMs == 30_000)
}

@Test func psfStyleReaderHarvestsQSFTagsAndTimingWithoutOpeningTheEngine() throws {
    var data = Data([0x50, 0x53, 0x46, 0x41])
    data.append(Data(repeating: 0, count: 12))
    data.append(Data("[TAG]\ntitle=Cyberbot\ngame=Cyberbots\nartist=Capcom\nlength=1:23.500\nfade=4.250\n".utf8))

    let fileURL = try writeSPCTestFile(data, name: "cyberbot.qsf")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let result = try #require(try PSFTagReader.readResult(fileURL: fileURL))

    #expect(result.tags["title"] == "Cyberbot")
    #expect(result.metadata.game == "Cyberbots")
    #expect(result.metadata.author == "Capcom")
    #expect(result.metadata.playLengthMs == 83_500)
    #expect(result.metadata.fadeLengthMs == 4_250)
}

@Test func gameMusicHeaderReaderHarvestsNSFAndGBSTextWithoutEmulation() throws {
    var nsf = Data(repeating: 0, count: 128)
    nsf.replaceSubrange(0..<5, with: Data([0x4E, 0x45, 0x53, 0x4D, 0x1A]))
    nsf[0x06] = 3
    writeBytes(&nsf, at: 0x0E, value: "Famicom Quest")
    writeBytes(&nsf, at: 0x2E, value: "Composer")
    writeBytes(&nsf, at: 0x4E, value: "1989")
    let nsfURL = try writeSPCTestFile(nsf, name: "quest.nsf")
    defer { try? FileManager.default.removeItem(at: nsfURL) }

    let nsfResult = try #require(try GameMusicMetadataReader.read(fileURL: nsfURL))
    #expect(nsfResult.trackCount == 3)
    #expect(nsfResult.metadata.game == "Famicom Quest")
    #expect(nsfResult.metadata.author == "Composer")
    #expect(nsfResult.metadata.comment == "1989")

    var gbs = Data(repeating: 0, count: 0x70)
    gbs.replaceSubrange(0..<3, with: Data("GBS".utf8))
    gbs[0x04] = 5
    writeBytes(&gbs, at: 0x10, value: "Pocket Quest")
    writeBytes(&gbs, at: 0x30, value: "Composer")
    let gbsURL = try writeSPCTestFile(gbs, name: "quest.gbs")
    defer { try? FileManager.default.removeItem(at: gbsURL) }

    let gbsResult = try #require(try GameMusicMetadataReader.read(fileURL: gbsURL))
    #expect(gbsResult.trackCount == 5)
    #expect(gbsResult.metadata.game == "Pocket Quest")
    #expect(gbsResult.metadata.system == "Nintendo Game Boy")
}

@Test func vgmAndVGZReadersHarvestNativeGD3AndTiming() async throws {
    var data = Data(repeating: 0, count: 0x40)
    data.replaceSubrange(0..<4, with: Data("Vgm ".utf8))
    writeLittleEndian(&data, at: 0x18, value: 44_100)
    writeLittleEndian(&data, at: 0x1C, value: 1)
    writeLittleEndian(&data, at: 0x20, value: 22_050)
    let gd3Strings = ["Song", "", "Game", "", "System", "", "Artist", "", "", "", "Comment"]
    var gd3Payload: [UInt8] = []
    for string in gd3Strings {
        for unit in string.utf16 {
            gd3Payload.append(UInt8(unit & 0xFF))
            gd3Payload.append(UInt8(unit >> 8))
        }
        gd3Payload.append(contentsOf: [0, 0])
    }
    var gd3 = Data("Gd3 ".utf8)
    gd3.append(contentsOf: [0x00, 0x01, 0x00, 0x00])
    gd3.append(contentsOf: littleEndianBytes(UInt32(gd3Payload.count)))
    gd3.append(contentsOf: gd3Payload)
    let gd3Offset = data.count - 0x14
    writeLittleEndian(&data, at: 0x14, value: UInt32(gd3Offset))
    data.append(gd3)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-vgm-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let vgmURL = root.appendingPathComponent("Song.vgm")
    let vgzURL = root.appendingPathComponent("Song.vgz")
    try data.write(to: vgmURL)
    try writeGZip(data, to: vgzURL)

    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "vgm"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    for fixture in [vgmURL, vgzURL] {
        let inspection = try await handler.inspect(
            fileURL: fixture,
            route: route
        )
        let metadata = try #require(inspection.tracks.first?.metadata)
        #expect(metadata.song == "Song")
        #expect(metadata.game == "Game")
        #expect(metadata.author == "Artist")
        #expect(metadata.playLengthMs == 1_000)
        #expect(metadata.loopLengthMs == 500)
    }
}

@Test func spcReaderParsesBinaryID666LengthAndFade() throws {
    var data = makeSPCFile(id666Flag: 0x1A)
    writeBytes(&data, at: 0x2E, value: "Binary Song")
    writeBytes(&data, at: 0x4E, value: "Binary Game")
    writeBytes(&data, at: 0xB0, value: "Binary Artist")

    // Binary ID666: seconds at 0xA9 as LE16 and fade milliseconds at 0xAC as LE24.
    data[0xA9] = 30
    data[0xAA] = 0
    data[0xAB] = 0
    data[0xAC] = 0x88
    data[0xAD] = 0x13
    data[0xAE] = 0
    data[0xAF] = 0

    let fileURL = try writeSPCTestFile(data, name: "binary.spc")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Binary Song")
    #expect(metadata.game == "Binary Game")
    #expect(metadata.author == "Binary Artist")
    #expect(metadata.playLengthMs == 30_000)
    #expect(metadata.fadeLengthMs == 5_000)
}

@Test func spcReaderParsesTextID666LengthAndFade() throws {
    var data = makeSPCFile(id666Flag: 0x1A)
    writeBytes(&data, at: 0x2E, value: "Text Song")
    writeBytes(&data, at: 0x9E, value: "01/02/2003")
    writeBytes(&data, at: 0xA9, value: "045")
    writeBytes(&data, at: 0xAC, value: "00600")
    writeBytes(&data, at: 0xB1, value: "Text Artist")

    let fileURL = try writeSPCTestFile(data, name: "text.spc")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "Text Song")
    #expect(metadata.author == "Text Artist")
    #expect(metadata.playLengthMs == 45_000)
    #expect(metadata.fadeLengthMs == 600)
}

@Test func spcReaderAggregatesXID6SegmentsAndSkipsUnknownItems() throws {
    var data = makeSPCFile(id666Flag: 0x27)
    data.append(contentsOf: makeXID6Chunk(items: [
        makeXID6Item(id: 0x02, type: 1, payload: Array("xID6 Game".utf8)),
        makeXID6Item(id: 0x01, type: 1, payload: Array("xID6 Song".utf8)),
        makeXID6Item(id: 0x03, type: 1, payload: Array("xID6 Artist".utf8)),
        makeXID6Item(id: 0x55, type: 2, payload: [0xAA, 0xBB]),
        makeXID6Item(id: 0x30, type: 4, payload: littleEndianBytes(128_000)), // 2 seconds
        makeXID6Item(id: 0x31, type: 4, payload: littleEndianBytes(192_000)), // 3 seconds
        makeXID6Item(id: 0x32, type: 4, payload: littleEndianBytes(256_000)), // 4 seconds
        makeXID6Item(id: 0x33, type: 4, payload: littleEndianBytes(320_000)), // 5 seconds
        makeXID6Item(id: 0x35, type: 0, payload: [2, 0])
    ]))

    let fileURL = try writeSPCTestFile(data, name: "xid6.spc")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let metadata = try #require(try SPCMetadataReader.read(fileURL: fileURL))

    #expect(metadata.song == "xID6 Song")
    #expect(metadata.game == "xID6 Game")
    #expect(metadata.author == "xID6 Artist")
    #expect(metadata.introLengthMs == 2_000)
    #expect(metadata.loopLengthMs == 3_000)
    #expect(metadata.playLengthMs == 12_000) // intro + loop * 2 + end
    #expect(metadata.fadeLengthMs == 5_000)
}

@Test(
    "Archive-backed SPC fixtures publish native lengths",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SPC_FIXTURES"] != nil,
        "Set SCANSONG_SPC_FIXTURES to run the archive-backed SPC metadata check."
    )
)
func spcFixturesPublishNativeLengths() async throws {
    let rootPath = try #require(ProcessInfo.processInfo.environment["SCANSONG_SPC_FIXTURES"])
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "spc"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let expectedLengths: [String: Int] = ["ar-01.spc": 62_000, "ar-02.spc": 83_000, "ar-12.spc": 6_000]

    for (name, expectedLength) in expectedLengths {
        let fixture = URL(fileURLWithPath: rootPath).appendingPathComponent(name)
        let inspection = try await handler.inspect(fileURL: fixture, route: route)
        let metadata = try #require(inspection.tracks.first?.metadata)
        #expect(metadata.playLengthMs == expectedLength, Comment(rawValue: name))
    }
}

@Test func catalogScannerPersistsTheNativeSPCPlayLength() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-spc-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Library", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    var data = makeSPCFile(id666Flag: 0x1A)
    writeBytes(&data, at: 0x2E, value: "Stored SPC")
    data[0xA9] = 62
    data[0xAA] = 0
    data[0xAB] = 0
    try data.write(to: root.appendingPathComponent("Stored.spc"))

    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    let result = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(result.trackCount == 1)
    #expect(result.failures.isEmpty)

    var database: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let row = try querySingleRow(
        database: try #require(database),
        sql: "SELECT play_length_ms, fade_length_ms FROM track_metadata LIMIT 1;"
    )
    sqlite3_close(database)
    #expect(row == ["62000", "0"])
}

@Test func multiRootScanPublishesOneStableSourceTotal() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-multi-root-progress-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstRoot = directory.appendingPathComponent("First", isDirectory: true)
    let secondRoot = directory.appendingPathComponent("Second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    try makeSPCFile(id666Flag: 0x1A).write(to: firstRoot.appendingPathComponent("First.spc"))
    try makeSPCFile(id666Flag: 0x1A).write(to: secondRoot.appendingPathComponent("Second.spc"))

    let progress = ProgressCapture()
    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    let results = try await CatalogScanner(databaseURL: databaseURL).scan(
        rootURLs: [firstRoot, secondRoot],
        mode: .newScan,
        progress: progress.append
    )
    #expect(results.count == 2)
    #expect(results.allSatisfy { $0.trackCount == 1 })

    let updates = progress.values()
    #expect(updates.contains { $0.phase == .planning && $0.discovered == 2 && $0.processed == 0 })
    #expect(updates.filter { $0.phase != .discovery }.allSatisfy { $0.discovered == 2 })
    #expect(updates.last?.discovered == 2)
    #expect(updates.last?.processed == 2)
    #expect(zip(updates, updates.dropFirst()).allSatisfy { $0.0.processed <= $0.1.processed })
}

@Test func dryRunReportsTypedRoutesWithoutWritingADataStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-probe-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("SNES-SPC700 Sound File Data".utf8).write(to: root.appendingPathComponent("Track.spc"))
    try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))

    let result = try DryRunProbe().run(paths: [root.path], recursive: true, strict: true)
    #expect(result.hasErrors)
    #expect(result.events.contains { $0.route?.pluginID == "gme" })
    #expect(result.events.contains { $0.diagnostic?.code == "source.unrecognized" })
    #expect(result.events.last?.discovered == 2)

    try Data("SGC".utf8).write(to: root.appendingPathComponent("ignored.sgc"))
    let ignored = try DryRunProbe().run(paths: [root.appendingPathComponent("ignored.sgc").path], recursive: false, strict: true)
    #expect(!ignored.hasErrors)
    #expect(ignored.events.contains { $0.diagnostic?.code == "source.ignored" })
}

@Test func dryRunStopsBeforeWorkWhenCancellationIsRequested() throws {
    #expect(throws: CancellationError.self) {
        try DryRunProbe().run(
            paths: [FileManager.default.temporaryDirectory.path],
            recursive: true,
            strict: false,
            isCancelled: { true }
        )
    }
}

@Test func everyEventCarriesTheProcessContractVersion() throws {
    let event = ScannerEvent(kind: .sessionStarted, sequence: 0)
    let data = try JSONEncoder().encode(event)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["contract"] as? String == ScanSongContract.name)
    #expect(json["version"] as? Int == ScanSongContract.version)
}

@Test func inspectorProcessRunnerRejectsExcessiveOutput() async throws {
    await #expect(throws: ScannerInspectionError.self) {
        _ = try await InspectorProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["123456789"],
            standardOutputLimit: 4
        )
    }
}

@Test func inspectorProcessRunnerTerminatesTimedOutTools() async throws {
    let clock = ContinuousClock()
    let started = clock.now
    await #expect(throws: ScannerInspectionError.self) {
        _ = try await InspectorProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: .milliseconds(20)
        )
    }
    #expect(started.duration(to: clock.now) < .seconds(2))
}

@Test func canonicalCatalogValidationAcceptsOnlyTheSharedSchema() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    try createCanonicalCatalog(at: databaseURL)

    let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
    #expect(summary.schemaVersion == CanonicalCatalog.schemaVersion)
    #expect(summary.rootCount == 1)
    #expect(summary.trackCount == 2)
    #expect(summary.path == databaseURL.standardizedFileURL.path)
}

@Test func canonicalCatalogValidationRejectsAnUnrelatedSQLiteFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-invalid-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Other.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, "PRAGMA user_version = 1;", nil, nil, nil) == SQLITE_OK)

    #expect(throws: Error.self) {
        try CanonicalCatalog.inspect(databaseURL: databaseURL)
    }
}

@Test func catalogScannerCreatesAndPublishesAHostReadableSchema23Catalog() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-writer-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Library", isDirectory: true)
    let game = root
        .appendingPathComponent("Sony PlayStation", isDirectory: true)
        .appendingPathComponent("Castlevania", isDirectory: true)
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: game.appendingPathComponent("Prologue.wav"))
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    let result = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(result.discoveredSourceCount == 1)
    #expect(result.trackCount == 1)
    #expect(result.failures.isEmpty)

    let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
    #expect(summary.schemaVersion == 23)
    #expect(summary.rootCount == 1)
    #expect(summary.trackCount == 1)

    var database: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let row = try querySingleRow(
        database: try #require(database),
        sql: "SELECT browser_game, browser_system, filename FROM tracks LIMIT 1;"
    )
    let journalMode = try querySingleRow(
        database: try #require(database),
        sql: "PRAGMA journal_mode;"
    )
    sqlite3_close(database)
    #expect(row == ["Castlevania", "Sony PlayStation", "Prologue.wav"])
    #expect(journalMode == ["delete"])
}

@Test func catalogWriterLeaseExcludesOtherScannersButAllowsPlayerReaders() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-writer-lease-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    do {
        let firstWriter = try CanonicalCatalogWriter(databaseURL: databaseURL)
        _ = try CanonicalCatalogReader(databaseURL: databaseURL)
        #expect(throws: CatalogWriterError.self) {
            _ = try CanonicalCatalogWriter(databaseURL: databaseURL)
        }
        withExtendedLifetime(firstWriter) {}
    }

    _ = try CanonicalCatalogWriter(databaseURL: databaseURL)
}

@Test func catalogWriterPreservesWALForConcurrentPlayerReads() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-wal-writer-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    let firstRoot = directory.appendingPathComponent("First", isDirectory: true)
    let secondRoot = directory.appendingPathComponent("Second", isDirectory: true)
    let thirdRoot = directory.appendingPathComponent("Third", isDirectory: true)
    try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: thirdRoot, withIntermediateDirectories: true)

    do {
        let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
        _ = try writer.addRoot(path: firstRoot.path)
        withExtendedLifetime(writer) {}
    }

    var setup: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &setup) == SQLITE_OK)
    let setupDatabase = try #require(setup)
    #expect(sqlite3_exec(setupDatabase, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)

    // Keep the setup connection open while the first WAL transaction creates
    // the sidecars required by a query-only player connection.
    do {
        let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
        _ = try writer.addRoot(path: secondRoot.path)
        withExtendedLifetime(writer) {}
    }

    var player: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &player, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let playerDatabase = try #require(player)
    defer { sqlite3_close(playerDatabase) }
    #expect(sqlite3_exec(playerDatabase, "BEGIN;", nil, nil, nil) == SQLITE_OK)
    _ = try querySingleRow(database: playerDatabase, sql: "SELECT COUNT(*) FROM library_roots;")
    sqlite3_close(setupDatabase)

    do {
        let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
        _ = try writer.addRoot(path: thirdRoot.path)
        withExtendedLifetime(writer) {}
    }
    #expect(sqlite3_exec(playerDatabase, "COMMIT;", nil, nil, nil) == SQLITE_OK)

    var verification: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &verification, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let verificationDatabase = try #require(verification)
    defer { sqlite3_close(verificationDatabase) }
    #expect(try querySingleRow(database: verificationDatabase, sql: "PRAGMA journal_mode;") == ["wal"])
}

@Test func linkTestingRetainsMissingRowsAndClearDeadLinksPurgesThem() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-links-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Library", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let media = root.appendingPathComponent("Track.wav")
    try Data("fixture".utf8).write(to: media)
    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    _ = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)

    let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
    let reader = try CanonicalCatalogReader(databaseURL: databaseURL)
    let rootID = try #require(try reader.roots().first?.id)
    let beforeLinkCheck = try reader.scanTally(rootID: rootID)
    #expect(beforeLinkCheck.sourceCount == 1)
    #expect(beforeLinkCheck.activeSourceCount == 1)
    #expect(beforeLinkCheck.successfulSourceCount == 1)
    #expect(beforeLinkCheck.failedSourceCount == 0)
    #expect(beforeLinkCheck.inactiveSourceCount == 0)
    try FileManager.default.removeItem(at: media)
    let tested = try writer.testFiles()
    #expect(tested.testedSourceCount == 1)
    #expect(tested.missingSourceCount == 1)
    #expect(try writer.roots().first?.deadSourceCount == 1)
    #expect(try CanonicalCatalog.inspect(databaseURL: databaseURL).trackCount == 1)

    let afterLinkCheck = try CanonicalCatalogReader(databaseURL: databaseURL).scanTally(rootID: rootID)
    #expect(afterLinkCheck.sourceCount == 1)
    #expect(afterLinkCheck.activeSourceCount == 0)
    #expect(afterLinkCheck.inactiveSourceCount == 1)

    #expect(try writer.clearDeadLinks() == 1)
    #expect(try writer.roots().first?.deadSourceCount == 0)
    #expect(try CanonicalCatalog.inspect(databaseURL: databaseURL).trackCount == 0)
}

@Test func resetCatalogEmptiesRootsAndIndexedTracksWithoutDeletingTheDatabaseFile() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-reset-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Library", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: root.appendingPathComponent("Track.wav"))
    let databaseURL = directory.appendingPathComponent("Library.sqlite")
    _ = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)

    let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
    try writer.resetCatalog()

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect(try writer.roots().isEmpty)
    #expect(try CanonicalCatalog.inspect(databaseURL: databaseURL).trackCount == 0)
}

@Test func scannerMetadataRoundTripsWithoutAHostModel() throws {
    let metadata = ScannerMetadata(
        game: "Castlevania",
        song: "Prologue",
        system: "Sony PlayStation",
        author: "Konami",
        comment: "",
        introLengthMs: 1_000,
        loopLengthMs: 2_000,
        playLengthMs: 180_000,
        fadeLengthMs: 5_000
    )
    let encoded = try JSONEncoder().encode(metadata)
    #expect(try JSONDecoder().decode(ScannerMetadata.self, from: encoded) == metadata)
}

@Test func standaloneZstandardExtractionProducesOneImplicitPlayableMember() async throws {
    let zstandardPath = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    guard let zstandardPath else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-standalone-zst-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("track.vgm")
    let archive = root.appendingPathComponent("track.vgm.zst")
    try Data("standalone-vgm-payload".utf8).write(to: source)

    let compressor = Process()
    compressor.executableURL = URL(fileURLWithPath: zstandardPath)
    compressor.arguments = ["-q", "-f", source.path, "-o", archive.path]
    try compressor.run()
    compressor.waitUntilExit()
    #expect(compressor.terminationStatus == 0)

    let extracted = try await StandaloneArchiveExtractor().extractForScan(archiveURL: archive)
    defer { StandaloneArchiveExtractor().discard(extracted) }
    #expect(extracted.members.map(\.entryPath) == ["track.vgm"])
    #expect(String(data: try Data(contentsOf: extracted.members[0].fileURL), encoding: .utf8) == "standalone-vgm-payload")
}

@Test func standaloneMDXZstandardMaterializesItsCompressedPDXSibling() async throws {
    let zstandardPath = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    guard let zstandardPath else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-standalone-mdx-pdx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var mdx = Data("[TITLE] Test MDX\r\n".utf8)
    mdx.append(contentsOf: [0x1A])
    mdx.append(contentsOf: Data("foo.pdx".utf8))
    mdx.append(0)
    mdx.append(contentsOf: [0, 0, 0, 0])
    let pdx = Data(repeating: 0x5A, count: 1_024)
    let rawMDX = root.appendingPathComponent("song.MDX")
    let rawPDX = root.appendingPathComponent("FOO.PDX")
    try mdx.write(to: rawMDX)
    try pdx.write(to: rawPDX)

    func compress(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zstandardPath)
        process.arguments = ["-q", "-f", source.path, "-o", destination.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    let mdxArchive = root.appendingPathComponent("song.MDX.zst")
    let pdxArchive = root.appendingPathComponent("FOO.PDX.zst")
    try compress(rawMDX, to: mdxArchive)
    try compress(rawPDX, to: pdxArchive)
    try FileManager.default.removeItem(at: rawMDX)
    try FileManager.default.removeItem(at: rawPDX)

    let report = try await ScanFilesystemDiscovery.discoverReport(
        rootID: 1,
        rootURL: root,
        registry: BuiltInScannerPlugins.registry,
        isArchive: StandaloneArchiveExtractor.isSupportedArchive
    )
    #expect(report.candidates.map(\.sourceURL.lastPathComponent) == ["song.MDX.zst"])

    let extracted = try await StandaloneArchiveExtractor().extractForScan(
        archiveURL: mdxArchive,
        registry: BuiltInScannerPlugins.registry
    )
    defer { StandaloneArchiveExtractor().discard(extracted) }
    #expect(extracted.members.map(\.entryPath) == ["song.MDX"])
    let materializedPDX = extracted.scratchURL
        .appendingPathComponent("payload", isDirectory: true)
        .appendingPathComponent("foo.pdx")
    #expect(try Data(contentsOf: materializedPDX) == pdx)
}

@Test func standaloneMDXResolvesRootScopedShiftJISPDXDependency() async throws {
    let zstandardPath = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    guard let zstandardPath else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-mdx-root-pdx-\(UUID().uuidString)", isDirectory: true)
    let bankDirectory = root.appendingPathComponent("PDX Banks", isDirectory: true)
    try FileManager.default.createDirectory(at: bankDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let dependencyName = "音楽.pdx"
    var mdx = Data("[TITLE] Shift-JIS MDX\r\n".utf8)
    mdx.append(contentsOf: [0x1A])
    mdx.append(contentsOf: try #require(dependencyName.data(using: .shiftJIS)))
    mdx.append(0)
    mdx.append(contentsOf: [0, 0, 0, 0])
    let pdx = Data(repeating: 0x3C, count: 1_024)
    let rawMDX = root.appendingPathComponent("song.MDX")
    let rawPDX = bankDirectory.appendingPathComponent(dependencyName.uppercased())
    try mdx.write(to: rawMDX)
    try pdx.write(to: rawPDX)

    func compress(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zstandardPath)
        process.arguments = ["-q", "-f", source.path, "-o", destination.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    let mdxArchive = root.appendingPathComponent("song.MDX.zst")
    let pdxArchive = bankDirectory.appendingPathComponent("\(dependencyName.uppercased()).zst")
    try compress(rawMDX, to: mdxArchive)
    try compress(rawPDX, to: pdxArchive)
    try FileManager.default.removeItem(at: rawMDX)
    try FileManager.default.removeItem(at: rawPDX)

    let extracted = try await StandaloneArchiveExtractor().extractForScan(
        archiveURL: mdxArchive,
        registry: BuiltInScannerPlugins.registry,
        dependencySearchRoot: root
    )
    defer { StandaloneArchiveExtractor().discard(extracted) }
    let materializedPDX = extracted.scratchURL
        .appendingPathComponent("payload", isDirectory: true)
        .appendingPathComponent(dependencyName)
    #expect(try Data(contentsOf: materializedPDX) == pdx)
}

@Test func catalogBrowserSystemComesOnlyFromTheCollectionPath() {
    let source = "/Audio/Sony PlayStation 2/Castlevania/track.psf2"
    #expect(CatalogIdentity.browserSystem(sourcePath: source, rootPath: "/Audio") == "Sony PlayStation 2")
}

@Test func catalogBrowserSystemUsesTheParentConsoleFolderForGameArchives() {
    let source = "/Audio/JoshW/Nintendo DS/Castlevania.tar.zst"
    #expect(CatalogIdentity.browserSystem(sourcePath: source, rootPath: "/Audio/JoshW") == "Nintendo DS")
}

@Test func incrementalRescanReusesAnUnchangedCompletedSource() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-reuse-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Library", isDirectory: true)
    let game = root.appendingPathComponent("Nintendo NES", isDirectory: true)
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: game.appendingPathComponent("Castlevania.wav"))
    let databaseURL = directory.appendingPathComponent("Library.sqlite")

    let first = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(first.scannedSourceCount == 1)
    #expect(first.reusedSourceCount == 0)
    #expect(first.failures.isEmpty)

    let second = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .incremental)
    #expect(second.reusedSourceCount == 1)
    #expect(second.scannedSourceCount == 0)
    #expect(second.trackCount == 1)
    #expect(second.failures.isEmpty)

    let full = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(full.scannedSourceCount == 1)
    #expect(full.reusedSourceCount == 0)
    #expect(full.failures.isEmpty)
}

@Test func sharedDiscoveryFindsSupportedFilesAndHostRecognizedArchives() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-discovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: root.appendingPathComponent("game.nsf"))
    try Data().write(to: root.appendingPathComponent("album.customarchive"))
    try Data().write(to: root.appendingPathComponent("notes.txt"))

    let discovered = try await ScanFilesystemDiscovery.discover(
        rootID: 3,
        rootURL: root,
        registry: BuiltInScannerPlugins.registry,
        isArchive: { $0.pathExtension == "customarchive" }
    )
    #expect(discovered.map(\.sourceURL.lastPathComponent) == ["album.customarchive", "game.nsf"])
    #expect(discovered.first?.route == nil)
    #expect(discovered.last?.route?.structurePolicy == .enumerate)
}

@Test(
    "JoshW Resident Evil 2 tar.zst scans all PSF members and reports progress",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_RE2_ARCHIVE"] != nil,
        "Set SCANSONG_RE2_ARCHIVE to run the JoshW Resident Evil 2 archive check."
    )
)
func joshWResidentEvil2ArchiveScansThroughTarZstandard() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_RE2_ARCHIVE"])
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-re2-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archiveURL = root.appendingPathComponent("Resident Evil 2.tar.zst")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: archivePath), to: archiveURL)

    let progress = ProgressCapture()
    let databaseURL = root.appendingPathComponent("Library.sqlite")
    let result = try await CatalogScanner(
        databaseURL: databaseURL,
        inspectionPermits: 4,
        archivePipelineLimit: 1
    ).scan(rootURL: root, mode: .newScan) { progress.append($0) }

    #expect(result.discoveredSourceCount == 1)
    #expect(result.trackCount == 75)
    #expect(result.failures.isEmpty)
    #expect(result.skipped.isEmpty)

    let updates = progress.values()
    #expect(updates.contains { $0.phase == .archiveListing })
    #expect(updates.contains { $0.phase == .materialization })
    #expect(updates.contains { $0.phase == .persistence && $0.processed == 1 && $0.discovered == 1 })
    #expect(updates.last?.processed == 1)
    #expect(updates.last?.discovered == 1)

    var database: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let row = try querySingleRow(
        database: try #require(database),
        sql: "SELECT m.play_length_ms, m.fade_length_ms FROM tracks t INNER JOIN track_metadata m ON m.track_id=t.id WHERE t.archive_entry='11 Secure Place.psf';"
    )
    sqlite3_close(database)
    #expect(row == ["43000", "10000"])
}

@Test(
    "JoshW Dungeons and Dragons QSF archive scans all miniQSF members",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_QSF_ARCHIVE"] != nil,
        "Set SCANSONG_QSF_ARCHIVE to run the archive-backed QSF scanner check."
    )
)
func joshWQSFArchiveScansAllMiniQSFMembers() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_QSF_ARCHIVE"])
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-qsf-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archiveURL = root.appendingPathComponent("Dungeons & Dragons QSF.tar.zst")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: archivePath), to: archiveURL)

    let result = try await CatalogScanner(
        databaseURL: root.appendingPathComponent("Library.sqlite"),
        inspectionPermits: 4,
        archivePipelineLimit: 1
    ).scan(rootURL: root, mode: .newScan)

    #expect(result.discoveredSourceCount == 1)
    #expect(result.trackCount == 39)
    #expect(result.failures.isEmpty)
    #expect(result.skipped.isEmpty)
}

@Test(
    "JoshW Resident Evil 2 GameCube archive resolves underscore TXTH aliases",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_RE2_GAMECUBE_ARCHIVE"] != nil,
        "Set SCANSONG_RE2_GAMECUBE_ARCHIVE to run the archive-backed GameCube LDAT check."
    )
)
func joshWResidentEvil2GameCubeArchiveResolvesTXTHAliases() async throws {
    let archivePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_RE2_GAMECUBE_ARCHIVE"])
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-re2-gc-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let archiveURL = root.appendingPathComponent("Resident Evil 2 GameCube.7z")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: archivePath), to: archiveURL)

    let result = try await CatalogScanner(
        databaseURL: root.appendingPathComponent("Library.sqlite"),
        inspectionPermits: 4,
        archivePipelineLimit: 1
    ).scan(rootURL: root, mode: .newScan)

    #expect(result.discoveredSourceCount == 1)
    #expect(result.failures.isEmpty)
    #expect(result.trackCount >= 131)
}

@Test func scanLogFormatsDiagnosticsWithoutExpandingArchiveInventories() {
    let fingerprint = ScanFingerprint(fileSize: 1, modifiedAt: .distantPast)
    let archivePath = "/library/NeuroDancer.zip"
    let archiveFailure = ScanFailure(
        identity: ScanItemIdentity(rootID: 1, path: archivePath, archiveEntry: "music/bad.spc"),
        fingerprint: fingerprint,
        route: nil,
        stage: .metadata,
        message: "decoder failed"
    )
    let skippedArchiveMembers = [
        ScanSkippedFile(
            identity: ScanItemIdentity(rootID: 1, path: archivePath, archiveEntry: "music/one.sgc"),
            extensionName: "sgc",
            reason: .explicitlyIgnored
        ),
        ScanSkippedFile(
            identity: ScanItemIdentity(rootID: 1, path: archivePath, archiveEntry: "music/two.sgc"),
            extensionName: "sgc",
            reason: .explicitlyIgnored
        )
    ]
    let lines = ScanLogFormatter.lines(
        status: "complete",
        summary: "4 discovered, 2 tracks, 1 reused, 2 skipped",
        rootPath: "/library",
        failures: [archiveFailure],
        skipped: skippedArchiveMembers + [
            ScanSkippedFile(
                identity: ScanItemIdentity(rootID: 1, path: "/library/notes.xyz", archiveEntry: nil),
                extensionName: "xyz",
                reason: .unsupportedFormat
            )
        ]
    )

    #expect(lines[0] == "status | detail | path")
    #expect(lines[1] == "complete | 4 discovered, 2 tracks, 1 reused, 2 skipped | .")
    #expect(lines.contains("archive-error | metadata: decoder failed | NeuroDancer.zip#music/bad.spc"))
    #expect(lines.contains("ignored | explicit ignore (.sgc, 2 archive members) | NeuroDancer.zip"))
    #expect(lines.contains("unrecognized | unsupported format (.xyz) | notes.xyz"))
    #expect(!lines.contains(where: { $0.contains("music/one.sgc") || $0.contains("music/two.sgc") }))

    let scratchFailure = ScanFailure(
        identity: ScanItemIdentity(rootID: 1, path: "/library/Silent Hill HD Collection.tar.zst", archiveEntry: "sh3_bgm_02.hd"),
        fingerprint: fingerprint,
        route: nil,
        stage: .metadata,
        message: "failed opening /private/var/folders/example/T/ScanSong-ScanScratch/CB56DFBC-58F8-4BDC-87C0-9F0E79FFBA63/payload/sh3_bgm_02.hd"
    )
    #expect(scratchFailure.message == "failed opening sh3_bgm_02.hd")
    let scratchLines = ScanLogFormatter.lines(
        status: "complete",
        summary: "1 discovered, 0 tracks, 0 reused, 1 failed",
        rootPath: "/library",
        failures: [scratchFailure],
        skipped: []
    )
    #expect(scratchLines.contains("archive-error | metadata: failed opening | Silent Hill HD Collection.tar.zst#sh3_bgm_02.hd"))
    #expect(!scratchLines.contains(where: { $0.contains("ScanSong-ScanScratch") || $0.contains("/private/var") }))

    let duplicateMemberFailure = ScanFailure(
        identity: ScanItemIdentity(rootID: 1, path: "/library/Hard Corps.tar.zst", archiveEntry: "Stage01_Active.txtp"),
        fingerprint: fingerprint,
        route: nil,
        stage: .metadata,
        message: "vgmstream returned invalid metadata for Stage01_Active.txtp"
    )
    let duplicateLines = ScanLogFormatter.lines(
        status: "complete",
        summary: "1 discovered, 0 tracks, 0 reused, 1 failed",
        rootPath: "/library",
        failures: [duplicateMemberFailure],
        skipped: []
    )
    #expect(duplicateLines.contains("archive-error | metadata: vgmstream returned invalid metadata | Hard Corps.tar.zst#Stage01_Active.txtp"))
}

@Test func sharedLifecycleAndAccumulatorUseOneCrossHostVocabulary() async throws {
    #expect(ScanLifecyclePhase.infer(from: "Discovering files") == .discovery)
    #expect(ScanLifecyclePhase.infer(from: "Publishing scan") == .publication)

    let identity = ScanItemIdentity(rootID: 1, path: "/library/game.spc", archiveEntry: nil)
    let fingerprint = ScanFingerprint(fileSize: 1, modifiedAt: .distantPast)
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "spc"))
    let candidate = ScanCandidate(
        identity: identity,
        fingerprint: fingerprint,
        sourceURL: URL(fileURLWithPath: identity.path),
        route: route
    )
    let accumulator = ScanResultAccumulator(discovered: 2)
    try await accumulator.accept(.success(candidate, ScanInspection(
        route: route,
        tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)]
    )))
    try await accumulator.accept(.failure(ScanFailure(
        identity: identity,
        fingerprint: fingerprint,
        route: route,
        stage: .metadata,
        message: "decoder failed"
    )))
    let summary = await accumulator.summary
    #expect(summary.discovered == 2)
    #expect(summary.successful == 1)
    #expect(summary.failed == 1)
}

private enum SchedulerTestError: Error {
    case expected
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [CatalogScanProgress] = []

    func append(_ update: CatalogScanProgress) {
        lock.withLock { captured.append(update) }
    }

    func values() -> [CatalogScanProgress] {
        lock.withLock { captured }
    }
}

private func createCanonicalCatalog(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw NSError(domain: "ScanSongTests", code: 1)
    }
    defer { sqlite3_close(database) }
    let statements = [
        "PRAGMA user_version = 23;",
        "CREATE TABLE library_roots (id INTEGER PRIMARY KEY, is_attached INTEGER NOT NULL);",
        "CREATE TABLE tracks (id INTEGER PRIMARY KEY);",
        "CREATE TABLE track_metadata (track_id INTEGER PRIMARY KEY);",
        "CREATE TABLE scan_items (id INTEGER PRIMARY KEY);",
        "CREATE TABLE scan_staging_roots (id INTEGER PRIMARY KEY);",
        "CREATE TABLE scan_source_checkpoints (id INTEGER PRIMARY KEY);",
        "CREATE TABLE dead_sources (id INTEGER PRIMARY KEY);",
        "CREATE TABLE game_sidebar_buckets (id INTEGER PRIMARY KEY);",
        "CREATE TABLE file_sidebar_buckets (id INTEGER PRIMARY KEY);",
        "INSERT INTO library_roots (id, is_attached) VALUES (1, 1), (2, 0);",
        "INSERT INTO tracks (id) VALUES (1), (2);"
    ]
    for statement in statements {
        guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
            throw NSError(
                domain: "ScanSongTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
            )
        }
    }
}

private func querySingleRow(database: OpaquePointer, sql: String) throws -> [String] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw NSError(
            domain: "ScanSongTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw NSError(domain: "ScanSongTests", code: 4)
    }
    return (0..<sqlite3_column_count(statement)).map { index in
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }
}

@Test func sharedSchedulerReleasesItsPermitAfterPluginFailure() async throws {
    let scheduler = ScanResourceScheduler(permits: 1)
    await #expect(throws: SchedulerTestError.self) {
        try await scheduler.withPermit { throw SchedulerTestError.expected } as Void
    }
    #expect(try await scheduler.withPermit { 42 } == 42)
}

@Test func sharedSchedulerRemovesCancelledWaitersBeforePluginWorkStarts() async throws {
    let scheduler = ScanResourceScheduler(permits: 1)
    let first = Task {
        try await scheduler.withPermit {
            try await Task.sleep(for: .milliseconds(100))
            return 1
        }
    }
    try await Task.sleep(for: .milliseconds(10))
    let queued = Task { try await scheduler.withPermit { 2 } }
    try await Task.sleep(for: .milliseconds(10))
    queued.cancel()
    guard case .failure(let error) = await queued.result else {
        Issue.record("Cancelled scanner waiter unexpectedly ran")
        return
    }
    #expect(error is CancellationError)
    #expect(try await first.value == 1)
    #expect(try await scheduler.withPermit { 3 } == 3)
}

private func makeSPCFile(id666Flag: UInt8) -> Data {
    var data = Data(repeating: 0, count: 0x10200)
    data.replaceSubrange(0..<27, with: Data("SNES-SPC700 Sound File Data".utf8))
    data[0x23] = id666Flag
    return data
}

private func writeBytes(_ data: inout Data, at offset: Int, value: String) {
    let bytes = Array(value.utf8)
    data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
}

private func writeSPCTestFile(_ data: Data, name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-\(UUID().uuidString)-\(name)")
    try data.write(to: url)
    return url
}

private func makeXID6Chunk(items: [[UInt8]]) -> Data {
    let payload = items.flatMap { $0 }
    var chunk = Data("xid6".utf8)
    chunk.append(contentsOf: littleEndianBytes(UInt32(payload.count)))
    chunk.append(contentsOf: payload)
    return chunk
}

private func makeXID6Item(id: UInt8, type: UInt8, payload: [UInt8]) -> [UInt8] {
    var item = [id, type, UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)]
    if type != 0 {
        item.append(contentsOf: payload)
        item.append(contentsOf: repeatElement(0, count: (4 - (payload.count % 4)) % 4))
    }
    return item
}

private func littleEndianBytes(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
}

private func writeLittleEndian(_ data: inout Data, at offset: Int, value: UInt32) {
    data.replaceSubrange(offset..<(offset + 4), with: littleEndianBytes(value))
}

private func writeGZip(_ data: Data, to url: URL) throws {
    guard let handle = gzopen(url.path, "wb") else {
        throw NSError(domain: "ScanSongTests", code: 1)
    }
    defer { _ = gzclose(handle) }
    let written = data.withUnsafeBytes { bytes in
        gzwrite(handle, bytes.baseAddress, UInt32(data.count))
    }
    guard written == data.count else {
        throw NSError(domain: "ScanSongTests", code: 2)
    }
}
