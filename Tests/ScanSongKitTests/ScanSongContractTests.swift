import CGameMusicEmu
import Foundation
import SQLite3
import Testing
import VGMBoyFormatDataCore
import zlib
@testable import ScanSongKit

@Test func builtInPoliciesPreserveRequiredStructureWork() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "spc")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "spc")?.pluginID == "spc-direct")
    #expect(registry.route(pathExtension: ".NSF")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: ".NSF")?.pluginID == "game-music-direct")
    #expect(registry.route(pathExtension: "gbs")?.pluginID == "game-music-direct")
    #expect(registry.route(pathExtension: "nsf")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "gbs")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "nsfe")?.pluginID == "nsfe-direct")
    #expect(registry.route(pathExtension: "nsfe")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "nsfe")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "kss")?.pluginID == "kss-direct")
    #expect(registry.route(pathExtension: "kss")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "kss")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "hes")?.pluginID == "hes-direct")
    #expect(registry.route(pathExtension: "hes")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "gsf")?.pluginID == "gsf-direct")
    #expect(registry.route(pathExtension: "minigsf")?.pluginID == "gsf-direct")
    #expect(registry.route(pathExtension: "gsf")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "minigsf")?.structurePolicy == .dependencyEnumerate)
    #expect(registry.route(pathExtension: "vgm")?.pluginID == "vgm-direct")
    #expect(registry.route(pathExtension: "vgz")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "vgm")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "gym")?.pluginID == "libvgm")
    #expect(registry.route(pathExtension: "flac")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "txtp")?.structurePolicy == .dependencyEnumerate)
    #expect(registry.route(pathExtension: "sid")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "sid")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "sap")?.pluginID == "sap-direct")
    #expect(registry.route(pathExtension: "sap")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "sap")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "ay")?.pluginID == "ay-direct")
    #expect(registry.route(pathExtension: "ay")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "ay")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "sndh")?.pluginID == "psgplay")
    #expect(registry.route(pathExtension: "sndh")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "sndh")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "mdx")?.pluginID == "mdx")
    #expect(registry.route(pathExtension: "mdx")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "pdx") == nil)
    #expect(registry.route(pathExtension: "ape")?.pluginID == "ape-direct")
    #expect(registry.route(pathExtension: "ape")?.metadataPolicy == .direct)
    #expect(registry.route(forPath: "/tmp/mod.xpose-end")?.pluginID == "amiga-uade")
    #expect(registry.route(forPath: "/tmp/p4x.earth")?.pluginID == "amiga-uade")
    #expect(registry.route(forPath: "/tmp/music.mod")?.pluginID == "openmpt")
    #expect(registry.route(forPath: "/tmp/stage.p4x") == nil)
    #expect(registry.route(pathExtension: "ogg")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "ogg")?.pluginID == "standard-audio")
    #expect(registry.route(pathExtension: "ogg")?.pluginID != "vgmstream")
    #expect(registry.route(pathExtension: "qsf")?.pluginID == "qsf-direct")
    #expect(registry.route(pathExtension: "qsf")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "miniqsf")?.pluginID == "qsf-mini-direct")
    #expect(registry.route(pathExtension: "miniqsf")?.structurePolicy == .dependencyEnumerate)
    #expect(registry.route(pathExtension: "miniqsf")?.metadataPolicy == .direct)
    #expect(BuiltInScannerPlugins.archiveExtensions.contains("zst"))
    #expect(BuiltInScannerPlugins.archiveExtensions.contains("lha"))
    #expect(StandaloneArchiveExtractor.isSupportedArchive(URL(fileURLWithPath: "track.vgm.zst")))
    #expect(StandaloneArchiveExtractor.isSupportedArchive(URL(fileURLWithPath: "amiga.lha")))
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

@Test("KSS direct route preserves libgme info-only headers and slot enumeration")
func kssDirectRoutePreservesInfoOnlyContract() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-kss-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (tag, flags, expectedSystem) in [
        ("KSCC", UInt8(0), "MSX"),
        ("KSCC", UInt8(0x05), "MSX"),
        ("KSCC", UInt8(0x02), "Sega Master System"),
        ("KSSX", UInt8(0x06), "Game Gear"),
        ("KSSX", UInt8(0x07), "Sega Mega Drive")
    ] {
        var data = Data(repeating: 0, count: 0x10)
        data.replaceSubrange(0..<4, with: Data(tag.utf8))
        data[0x0F] = flags
        let fileURL = directory.appendingPathComponent("device-\(flags).kss")
        try data.write(to: fileURL)

        let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
        let inspection = try await handler.inspect(fileURL: fileURL, route: route)
        #expect(route.pluginID == "kss-direct")
        #expect(inspection.tracks.count == 256)
        #expect(inspection.tracks.map(\.trackIndex) == Array(0..<256))
        #expect(inspection.tracks.allSatisfy { $0.trackCount == 256 })
        #expect(inspection.tracks.allSatisfy { track in
            guard let metadata = track.metadata else { return false }
            return metadata.game.isEmpty
                && metadata.song.isEmpty
                && metadata.system == expectedSystem
                && metadata.author.isEmpty
                && metadata.comment.isEmpty
                && metadata.introLengthMs == -1
                && metadata.loopLengthMs == -1
                && metadata.playLengthMs == 150_000
                && metadata.fadeLengthMs == -1
        })
    }
}

@Test("KSS direct route rejects truncated and unrecognized headers")
func kssDirectRouteRejectsMalformedHeaders() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-kss-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (name, data) in [
        ("truncated", Data(repeating: 0, count: 0x0F)),
        ("wrong-signature", Data(repeating: 0, count: 0x10))
    ] {
        let fileURL = directory.appendingPathComponent("\(name).kss")
        try data.write(to: fileURL)
        let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
        await #expect(throws: ScannerInspectionError.self) {
            try await handler.inspect(fileURL: fileURL, route: route)
        }
    }
}

@Test("SAP direct route enumerates declared subsongs without libgme")
func sapDirectRouteInspectsHeaderWithoutGameMusicEmu() async throws {
    var data = Data("SAP\r\n".utf8)
    data.append(Data("AUTHOR \"Composer\"\r\nNAME \"SAP Game\"\r\nSONGS 2\r\nTYPE B\r\nINIT 1CE5\r\nPLAYER 1D09\r\nTIME 00:20.000 LOOP\r\nTIME 00:35.500\r\n".utf8))
    data.append(contentsOf: [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-sap-\(UUID().uuidString)")
        .appendingPathExtension("sap")
    try data.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(route.pluginID == "sap-direct")
    #expect(route.metadataPolicy == .direct)
    #expect(inspection.tracks.count == 2)
    #expect(inspection.tracks.map(\.trackIndex) == [0, 1])
    #expect(inspection.tracks.allSatisfy { $0.trackCount == 2 })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.game == "SAP Game" })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.author == "Composer" })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.system == "Atari XL" })
    #expect(inspection.tracks[0].metadata?.introLengthMs == 20_000)
    #expect(inspection.tracks[0].metadata?.playLengthMs == 150_000)
    #expect(inspection.tracks[1].metadata?.introLengthMs == -1)
    #expect(inspection.tracks[1].metadata?.playLengthMs == 35_500)
}

@Test("AY direct route enumerates native subtunes without libgme")
func ayDirectRouteInspectsHeaderWithoutGameMusicEmu() async throws {
    let data = makeAYData(
        author: "Composer",
        comment: "1987",
        tracks: [("Opening", 125), ("Ending", 50)]
    )
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-ay-\(UUID().uuidString)")
        .appendingPathExtension("ay")
    try data.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(route.pluginID == "ay-direct")
    #expect(route.metadataPolicy == .direct)
    #expect(inspection.tracks.map(\.trackIndex) == [0, 1])
    #expect(inspection.tracks.allSatisfy { $0.trackCount == 2 })
    #expect(inspection.tracks.compactMap(\.metadata).map(\.song) == ["Opening", "Ending"])
    #expect(inspection.tracks.allSatisfy { $0.metadata?.system == "ZX Spectrum" })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.author == "Composer" })
    #expect(inspection.tracks.map { $0.metadata?.playLengthMs } == [2_500, 1_000])
}

@Test(
    "AY direct route matches libgme info-only metadata across the fixture corpus",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_AY_FIXTURE_DIR"] != nil,
        "Set SCANSONG_AY_FIXTURE_DIR to run the corpus-backed AY parity check."
    )
)
func ayFixtureDirectoryMatchesLibGMEInfoOnly() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_AY_FIXTURE_DIR"])
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
    let files = enumerator.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "ay" }
        .sorted { $0.path < $1.path }
    #expect(!files.isEmpty)

    var mismatches: [String] = []
    var matchingFiles = 0
    var legacyAccepted = 0
    var directAccepted = 0
    var directTimings: [UInt64] = []
    var legacyTimings: [UInt64] = []

    for (fileIndex, fileURL) in files.enumerated() {
        let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))

        func readLegacy() -> ([ScannerMetadata]?, UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            let metadata = gmeInfoOnlyMetadata(fileURL: fileURL)
            return (metadata, DispatchTime.now().uptimeNanoseconds &- started)
        }

        func readDirect() async -> ([ScannerMetadata]?, String, [Int], [Int], UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                let inspection = try await handler.inspect(fileURL: fileURL, route: route)
                return (
                    inspection.tracks.compactMap(\.metadata),
                    "",
                    inspection.tracks.map(\.trackIndex),
                    inspection.tracks.map(\.trackCount),
                    DispatchTime.now().uptimeNanoseconds &- started
                )
            } catch {
                return (nil, String(describing: error), [], [], DispatchTime.now().uptimeNanoseconds &- started)
            }
        }

        let reference: [ScannerMetadata]?
        let direct: ([ScannerMetadata]?, String, [Int], [Int], UInt64)
        if fileIndex.isMultiple(of: 2) {
            let legacy = readLegacy()
            reference = legacy.0
            legacyTimings.append(legacy.1)
            direct = await readDirect()
        } else {
            direct = await readDirect()
            let legacy = readLegacy()
            reference = legacy.0
            legacyTimings.append(legacy.1)
        }
        directTimings.append(direct.4)
        if reference != nil { legacyAccepted += 1 }
        if direct.0 != nil { directAccepted += 1 }

        var fileMatches = false
        if let reference, let candidate = direct.0 {
            fileMatches = reference == candidate
                && direct.2 == Array(0..<candidate.count)
                && direct.3.allSatisfy { $0 == candidate.count }
        } else if reference == nil, direct.0 == nil {
            fileMatches = true
        }

        if fileMatches {
            matchingFiles += 1
        } else if mismatches.count < 20 {
            mismatches.append(
                "\(fileURL.lastPathComponent): libgme=\(String(describing: reference?.first)), "
                    + "direct=\(String(describing: direct.0?.first)), error=\(direct.1)"
            )
        }
    }

    #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "; "))")
    #expect(matchingFiles == files.count)
    #expect(legacyAccepted == directAccepted)
    print(
        "AY parity: \(matchingFiles)/\(files.count) file outcomes; "
            + "\(directAccepted) accepted, \(files.count - directAccepted) rejected by both; "
            + "median direct \(medianMilliseconds(directTimings)) ms, "
            + "libgme \(medianMilliseconds(legacyTimings)) ms"
    )
}

@Test(
    "SAP direct route matches libgme info-only metadata across the fixture corpus",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SAP_FIXTURE_DIR"] != nil,
        "Set SCANSONG_SAP_FIXTURE_DIR to run the corpus-backed SAP parity check."
    )
)
func sapFixtureDirectoryMatchesLibGMEInfoOnly() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_SAP_FIXTURE_DIR"])
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
    let files = enumerator.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "sap" }
        .sorted { $0.path < $1.path }
    #expect(!files.isEmpty)

    var mismatches: [String] = []
    var matchingFiles = 0
    var fullyAcceptedFiles = 0
    var libGMEAcceptedFiles = 0
    var directAcceptedFiles = 0
    var directTimings: [UInt64] = []
    var libGMETimings: [UInt64] = []
    for (fileIndex, fileURL) in files.enumerated() {
        let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))

        func readLegacy() -> ([ScannerMetadata]?, UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = gmeInfoOnlyMetadata(fileURL: fileURL)
            return (result, DispatchTime.now().uptimeNanoseconds &- started)
        }

        func readDirect() async -> ([ScannerMetadata]?, String, [Int], [Int], UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                let inspection = try await handler.inspect(fileURL: fileURL, route: route)
                return (
                    inspection.tracks.compactMap(\.metadata),
                    "",
                    inspection.tracks.map(\.trackIndex),
                    inspection.tracks.map(\.trackCount),
                    DispatchTime.now().uptimeNanoseconds &- started
                )
            } catch {
                return (nil, String(describing: error), [], [], DispatchTime.now().uptimeNanoseconds &- started)
            }
        }

        let reference: [ScannerMetadata]?
        let directResult: ([ScannerMetadata]?, String, [Int], [Int], UInt64)
        if fileIndex.isMultiple(of: 2) {
            let legacy = readLegacy()
            reference = legacy.0
            libGMETimings.append(legacy.1)
            directResult = await readDirect()
        } else {
            directResult = await readDirect()
            let legacy = readLegacy()
            reference = legacy.0
            libGMETimings.append(legacy.1)
        }
        directTimings.append(directResult.4)
        let candidate = directResult.0
        if reference != nil { libGMEAcceptedFiles += 1 }
        if candidate != nil { directAcceptedFiles += 1 }
        if reference != nil, candidate != nil { fullyAcceptedFiles += 1 }
        if let candidate,
           (directResult.2 != Array(0..<candidate.count)
               || directResult.3.contains(where: { $0 != candidate.count })) {
            mismatches.append("\(fileURL.lastPathComponent): track indexing/count")
        }
        var fileMatches = false
        if let reference, let candidate {
            let facts = try SAPFormatDataReader.read(
                data: Data(contentsOf: fileURL, options: .mappedIfSafe),
                displayName: fileURL.lastPathComponent
            )
            fileMatches = reference.count == candidate.count && facts.tracks.count == candidate.count
            if fileMatches {
                for index in reference.indices {
                    let expected = reference[index]
                    let actual = candidate[index]
                    let hint = facts.tracks[index].timeHint
                    let expectedIntro = hint.map {
                        $0.loops ? $0.milliseconds : expected.introLengthMs
                    } ?? expected.introLengthMs
                    let expectedPlay = hint.map {
                        $0.loops ? expected.playLengthMs : $0.milliseconds
                    } ?? expected.playLengthMs
                    if expected.game != actual.game
                        || expected.song != actual.song
                        || expected.system != actual.system
                        || expected.author != actual.author
                        || expected.comment != actual.comment
                        || expectedIntro != actual.introLengthMs
                        || expected.loopLengthMs != actual.loopLengthMs
                        || expectedPlay != actual.playLengthMs
                        || expected.fadeLengthMs != actual.fadeLengthMs {
                        fileMatches = false
                        if mismatches.count < 20 {
                            mismatches.append("\(fileURL.lastPathComponent): track \(index) metadata/timing")
                        }
                        break
                    }
                }
            }
        } else if reference == nil, candidate == nil {
            fileMatches = true
        }
        if fileMatches {
            matchingFiles += 1
        } else if mismatches.count < 20 {
            mismatches.append(
                "\(fileURL.lastPathComponent): libgme=\(String(describing: reference?.first)), direct=\(String(describing: candidate?.first)), error=\(directResult.1)"
            )
        }
    }
    #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "; "))")
    #expect(matchingFiles == files.count)
    #expect(libGMEAcceptedFiles == directAcceptedFiles)
    #expect(fullyAcceptedFiles == libGMEAcceptedFiles)
    print(
        "SAP parity: \(matchingFiles)/\(files.count) file outcomes; "
            + "\(fullyAcceptedFiles) accepted, \(files.count - fullyAcceptedFiles) rejected by both; "
            + "median direct \(medianMilliseconds(directTimings)) ms, "
            + "libgme \(medianMilliseconds(libGMETimings)) ms"
    )
}

@Test("NSF direct route enumerates header-declared tracks")
func nsfDirectRouteInspectsWithoutGameMusicEmu() async throws {
    var data = Data(repeating: 0, count: 0x80)
    data.replaceSubrange(0..<5, with: Data([0x4E, 0x45, 0x53, 0x4D, 0x1A]))
    data[0x05] = 1
    data[0x06] = 3
    data.replaceSubrange(0x0E..<0x16, with: Data("Direct NSF".utf8))

    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-nsf-\(UUID().uuidString)")
        .appendingPathExtension("nsf")
    try data.write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(route.pluginID == "game-music-direct")
    #expect(route.metadataPolicy == .direct)
    #expect(inspection.tracks.count == 3)
    #expect(inspection.tracks.map(\.trackIndex) == [0, 1, 2])
    #expect(inspection.tracks.allSatisfy { $0.trackCount == 3 })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.game == "Direct NSF" })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.playLengthMs == 150_000 })
}

@Test("NSFE direct route preserves playlist and authored metadata")
func nsfeDirectRouteInspectsWithoutGameMusicEmu() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-nsfe-\(UUID().uuidString)")
        .appendingPathExtension("nsfe")
    try makeNSFEFixture().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)

    #expect(route.pluginID == "nsfe-direct")
    #expect(inspection.tracks.map(\.trackIndex) == [0, 1, 2])
    #expect(inspection.tracks.map(\.trackCount) == [3, 3, 3])
    #expect(inspection.tracks.map { $0.metadata?.song } == ["Third", "First", "Third"])
    #expect(inspection.tracks.map { $0.metadata?.author } == ["Third Author", "First Author", "Third Author"])
    #expect(inspection.tracks.map { $0.metadata?.playLengthMs } == [150_000, 1_000, 150_000])
    #expect(inspection.tracks.map { $0.metadata?.fadeLengthMs } == [-1, 100, -1])
    #expect(inspection.tracks.allSatisfy { $0.metadata?.game == "NSFE Game" })
}

@Test("GSF direct route validates PSF payloads and resolves the complete miniGSF chain")
func gsfDirectRouteValidatesPayloadsAndPreservesMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-gsf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let libraryURL = directory.appendingPathComponent("shared.gsflib")
    let baseLibraryURL = directory.appendingPathComponent("base.gsflib")
    let secondLibraryURL = directory.appendingPathComponent("secondary.gsflib")
    let miniURL = directory.appendingPathComponent("track.minigsf")
    try makeGSFContainer(
        tags: "",
        executable: makeGSFExecutable(payload: [0x10])
    ).write(to: baseLibraryURL)
    try makeGSFContainer(
        tags: "_lib=base.gsflib\ngame=Shared game\nartist=Shared composer\nlength=9:00\nfade=8.000\n",
        executable: makeGSFExecutable(payload: [0xAA, 0xBB])
    ).write(to: libraryURL)
    try makeGSFContainer(
        tags: "title=Secondary library title\nlength=10:00\nfade=9.000\n",
        executable: makeGSFExecutable(payload: [0x20])
    ).write(to: secondLibraryURL)
    try makeGSFContainer(
        tags: "_lib=shared.gsflib\n_lib2=secondary.gsflib\ntitle=Mini title\nlength=1:23.500\nfade=4.250\n",
        executable: makeGSFExecutable(payload: [0x01, 0x02, 0x03])
    ).write(to: miniURL)

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: miniURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: miniURL, route: route)
    let metadata = try #require(inspection.tracks.first?.metadata)
    #expect(route.pluginID == "gsf-direct")
    #expect(route.metadataPolicy == .direct)
    #expect(inspection.tracks.count == 1)
    #expect(metadata.song == "Mini title")
    #expect(metadata.game == "Shared game")
    #expect(metadata.author == "Shared composer")
    #expect(metadata.system == "Game Boy Advance")
    #expect(metadata.introLengthMs == 600_000)
    #expect(metadata.playLengthMs == 83_500)
    #expect(metadata.fadeLengthMs == 4_250)

    let inheritedTimeURL = directory.appendingPathComponent("inherited-time.minigsf")
    try makeGSFContainer(
        tags: "_lib=shared.gsflib\ntitle=Inherited timing\n",
        executable: makeGSFExecutable(payload: [0x30])
    ).write(to: inheritedTimeURL)
    let inheritedInspection = try await handler.inspect(fileURL: inheritedTimeURL, route: route)
    let inheritedMetadata = try #require(inheritedInspection.tracks.first?.metadata)
    #expect(inheritedMetadata.introLengthMs == 540_000)
    #expect(inheritedMetadata.playLengthMs == 540_000)
    #expect(inheritedMetadata.fadeLengthMs == 8_000)

    let omittedMinuteURL = directory.appendingPathComponent("omitted-minute.minigsf")
    try makeGSFContainer(
        tags: "_lib=shared.gsflib\ntitle=Omitted minute\nlength=0::33\n",
        executable: makeGSFExecutable(payload: [0x40])
    ).write(to: omittedMinuteURL)
    let omittedMinuteInspection = try await handler.inspect(fileURL: omittedMinuteURL, route: route)
    let omittedMinuteMetadata = try #require(omittedMinuteInspection.tracks.first?.metadata)
    #expect(omittedMinuteMetadata.introLengthMs == 540_000)
    #expect(omittedMinuteMetadata.playLengthMs == 33_000)
    #expect(omittedMinuteMetadata.fadeLengthMs == 8_000)

    let duplicateLengthURL = directory.appendingPathComponent("duplicate-length.gsf")
    try makeGSFContainer(
        tags: "title=Duplicate length\nlength=0:05.009\nlength=0:06\n",
        executable: makeGSFExecutable(payload: [0x41])
    ).write(to: duplicateLengthURL)
    let duplicateLengthInspection = try await handler.inspect(fileURL: duplicateLengthURL, route: route)
    let duplicateLengthMetadata = try #require(duplicateLengthInspection.tracks.first?.metadata)
    #expect(duplicateLengthMetadata.introLengthMs == 5_009)
    #expect(duplicateLengthMetadata.playLengthMs == 5_009)

    for (name, timeTag, expectedIntro) in [
        ("comma-seconds", "0:01,5", 1_000),
        ("comma-whole", "2,657", 2_000)
    ] {
        let commaTimeURL = directory.appendingPathComponent("\(name).gsf")
        try makeGSFContainer(
            tags: "title=Comma time\nlength=\(timeTag)\n",
            executable: makeGSFExecutable(payload: [0x50])
        ).write(to: commaTimeURL)
        let commaTimeInspection = try await handler.inspect(fileURL: commaTimeURL, route: route)
        let commaTimeMetadata = try #require(commaTimeInspection.tracks.first?.metadata)
        #expect(commaTimeMetadata.introLengthMs == expectedIntro)
        #expect(commaTimeMetadata.playLengthMs == 0)
    }
}

@Test("GSF direct route rejects missing libraries, invalid bodies, and unrecognized ROM images")
func gsfDirectRouteRejectsBrokenChainsAndBodies() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-gsf-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let missingURL = directory.appendingPathComponent("missing.minigsf")
    try makeGSFContainer(
        tags: "_lib=absent.gsflib\ntitle=Must not become a row\n",
        executable: makeGSFExecutable(payload: [0x01])
    ).write(to: missingURL)
    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: missingURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: missingURL, route: route)
    }

    let badCRCURL = directory.appendingPathComponent("bad-crc.gsf")
    var badCRC = try makeGSFContainer(
        tags: "title=Bad CRC\n",
        executable: makeGSFExecutable(payload: [0x02])
    )
    badCRC[12] ^= 0xFF
    try badCRC.write(to: badCRCURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badCRCURL, route: route)
    }

    let badInflateURL = directory.appendingPathComponent("bad-inflate.gsf")
    var badInflate = try makeGSFContainer(
        tags: "title=Bad zlib\n",
        executable: makeGSFExecutable(payload: [0x03])
    )
    let compressedSize = Int(UInt32(badInflate[8]))
        | Int(UInt32(badInflate[9])) << 8
        | Int(UInt32(badInflate[10])) << 16
        | Int(UInt32(badInflate[11])) << 24
    let compressedRange = 16..<(16 + compressedSize)
    badInflate[16] ^= 0xFF
    let invalidCompressedCRC = badInflate[compressedRange].withUnsafeBytes { bytes in
        crc32(crc32(0, nil, 0), bytes.bindMemory(to: Bytef.self).baseAddress, uInt(compressedSize))
    }
    writeLittleEndian(&badInflate, at: 12, value: UInt32(invalidCompressedCRC))
    try badInflate.write(to: badInflateURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badInflateURL, route: route)
    }

    let badSegmentURL = directory.appendingPathComponent("bad-segment.gsf")
    try makeGSFContainer(tags: "title=Bad segment\n", executable: Data([0x01, 0x02])).write(to: badSegmentURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badSegmentURL, route: route)
    }

    let badROMURL = directory.appendingPathComponent("bad-rom.gsf")
    let unrecognizedROM = Array(repeating: UInt8(0), count: 0xB3)
    try makeGSFContainer(
        tags: "title=Unrecognized ROM\n",
        executable: makeGSFExecutable(payload: unrecognizedROM, gbaHeader: false)
    ).write(to: badROMURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badROMURL, route: route)
    }

    let cycleAURL = directory.appendingPathComponent("cycle-a.gsflib")
    let cycleBURL = directory.appendingPathComponent("cycle-b.gsflib")
    let cycleRootURL = directory.appendingPathComponent("cycle.minigsf")
    try makeGSFContainer(tags: "_lib=cycle-b.gsflib\n", executable: makeGSFExecutable(payload: [0x04])).write(to: cycleAURL)
    try makeGSFContainer(tags: "_lib=cycle-a.gsflib\n", executable: makeGSFExecutable(payload: [0x05])).write(to: cycleBURL)
    try makeGSFContainer(tags: "_lib=cycle-a.gsflib\n", executable: makeGSFExecutable(payload: [0x06])).write(to: cycleRootURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: cycleRootURL, route: route)
    }
}

@Test("QSF direct route validates containers, QSound blocks, libraries, and tags")
func qsfDirectRouteValidatesPayloadsAndPreservesMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-qsf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try makeQSFContainer(tags: "game=Ignored library game\n", program: makeQSFBlock("SMP", offset: 12, payload: [0x10]))
        .write(to: directory.appendingPathComponent("shared.qsflib"))
    try makeQSFContainer(tags: "", program: makeQSFBlock("Z80", offset: 0, payload: [0x20]))
        .write(to: directory.appendingPathComponent("extra.qsflib"))

    let miniURL = directory.appendingPathComponent("track.miniqsf")
    try makeQSFContainer(
        tags: "_lib=shared.qsflib\n_lib2=extra.qsflib\ntitle=Mini title\ntitle=Last title\ngame=QSF game\nartist=Composer\nlength=1:23.500\nfade=0:02.250\n",
        program: makeQSFBlock("Z80", offset: 0, payload: [0x01, 0x02, 0x03])
            + makeQSFBlock("SMP", offset: 128, payload: [0x04, 0x05])
    ).write(to: miniURL)

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: miniURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: miniURL, route: route)
    let metadata = try #require(inspection.tracks.first?.metadata)
    #expect(route.pluginID == "qsf-mini-direct")
    #expect(route.metadataPolicy == .direct)
    #expect(inspection.tracks.count == 1)
    #expect(metadata.song == "Last title")
    #expect(metadata.game == "QSF game")
    #expect(metadata.author == "Composer")
    #expect(metadata.system == "Capcom QSound")
    #expect(metadata.comment.isEmpty)
    #expect(metadata.introLengthMs == 0)
    #expect(metadata.loopLengthMs == 0)
    #expect(metadata.playLengthMs == 83_500)
    #expect(metadata.fadeLengthMs == 2_250)

    let fallbackURL = directory.appendingPathComponent("Filename fallback.qsf")
    try makeQSFContainer(tags: "game=QSF game\n", program: makeQSFBlock("KEY", offset: 0, payload: Array(repeating: 0, count: 11)))
        .write(to: fallbackURL)
    let fallbackRoute = try #require(BuiltInScannerPlugins.registry.route(forPath: fallbackURL.path))
    let fallbackHandler = try #require(BuiltInFormatInspectors.registry.handler(for: fallbackRoute))
    let fallback = try #require(try await fallbackHandler.inspect(fileURL: fallbackURL, route: fallbackRoute).tracks.first?.metadata)
    #expect(fallbackRoute.pluginID == "qsf-direct")
    #expect(fallback.song == "Filename fallback")
}

@Test("QSF direct route rejects invalid containers, blocks, and dependencies")
func qsfDirectRouteRejectsBrokenPayloads() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scansong-qsf-invalid-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let validBlock = makeQSFBlock("Z80", offset: 0, payload: [0x01])
    let validURL = directory.appendingPathComponent("valid.qsf")
    try makeQSFContainer(tags: "", program: validBlock).write(to: validURL)
    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: validURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))

    let missingLibraryURL = directory.appendingPathComponent("missing.miniqsf")
    try makeQSFContainer(tags: "_lib=absent.qsflib\n", program: validBlock).write(to: missingLibraryURL)
    let miniRoute = try #require(BuiltInScannerPlugins.registry.route(forPath: missingLibraryURL.path))
    let miniHandler = try #require(BuiltInFormatInspectors.registry.handler(for: miniRoute))
    await #expect(throws: ScannerInspectionError.self) {
        try await miniHandler.inspect(fileURL: missingLibraryURL, route: miniRoute)
    }

    let escapingLibraryURL = directory.appendingPathComponent("escape.miniqsf")
    try makeQSFContainer(tags: "_lib=../outside.qsflib\n", program: validBlock).write(to: escapingLibraryURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await miniHandler.inspect(fileURL: escapingLibraryURL, route: miniRoute)
    }

    let badVersionURL = directory.appendingPathComponent("bad-version.qsf")
    try makeQSFContainer(tags: "", program: validBlock, version: 0x22).write(to: badVersionURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badVersionURL, route: route)
    }

    var badCRC = try makeQSFContainer(tags: "", program: validBlock)
    badCRC[12] ^= 0xFF
    let badCRCURL = directory.appendingPathComponent("bad-crc.qsf")
    try badCRC.write(to: badCRCURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badCRCURL, route: route)
    }

    var badInflate = try makeQSFContainer(tags: "", program: validBlock)
    let compressedSize = Int(UInt32(badInflate[8]))
        | Int(UInt32(badInflate[9])) << 8
        | Int(UInt32(badInflate[10])) << 16
        | Int(UInt32(badInflate[11])) << 24
    badInflate[16] ^= 0xFF
    let badInflateCRC = badInflate[16..<(16 + compressedSize)].withUnsafeBytes { bytes in
        crc32(crc32(0, nil, 0), bytes.bindMemory(to: Bytef.self).baseAddress, uInt(compressedSize))
    }
    writeLittleEndian(&badInflate, at: 12, value: UInt32(badInflateCRC))
    let badInflateURL = directory.appendingPathComponent("bad-inflate.qsf")
    try badInflate.write(to: badInflateURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: badInflateURL, route: route)
    }

    let truncatedURL = directory.appendingPathComponent("truncated.qsf")
    try makeQSFContainer(tags: "", program: Data([0x5A, 0x38])).write(to: truncatedURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: truncatedURL, route: route)
    }

    let overflowBlock = makeQSFBlock("Z80", offset: 512 * 1_024, payload: [0x01])
    let overflowURL = directory.appendingPathComponent("overflow.qsf")
    try makeQSFContainer(tags: "", program: overflowBlock).write(to: overflowURL)
    await #expect(throws: ScannerInspectionError.self) {
        try await handler.inspect(fileURL: overflowURL, route: route)
    }
}

@Test(
    "CocoaSpice NSFE rows match direct extraction from live archives",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_NSFE_LIVE_DB"] != nil,
        "Set SCANSONG_NSFE_LIVE_DB to run the read-only live-catalog parity check."
    )
)
func cocoaSpiceNSFELiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_NSFE_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_NSFE_LIVE_ROOT_ID"] ?? "1") ?? 1
    let liveFiles = try readLiveNSFEFiles(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    #expect(!liveFiles.isEmpty)

    let registry = BuiltInScannerPlugins.registry
    let archiveRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-live-nsfe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: archiveRoot) }

    var trackCount = 0
    var exactFieldMatches = 0
    var authorImprovements = 0
    var commentImprovements = 0
    var timingImprovements = 0
    var mismatches: [String] = []

    for (fileNumber, liveFile) in liveFiles.enumerated() {
        let archiveDirectory = archiveRoot.appendingPathComponent("archive-\(fileNumber)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        try extractTarZstd(
            archiveURL: URL(fileURLWithPath: liveFile.archivePath),
            into: archiveDirectory
        )
        let memberURL = try findExtractedArchiveMember(
            named: liveFile.archiveEntry,
            under: archiveDirectory
        )
        let route = try #require(registry.route(pathExtension: "nsfe"))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
        let inspection = try await handler.inspect(fileURL: memberURL, route: route)
        let extractedTracks = inspection.tracks

        if extractedTracks.count != liveFile.tracks.count {
            mismatches.append(
                "\(liveFile.archiveEntry): track count direct=\(extractedTracks.count) live=\(liveFile.tracks.count)"
            )
            continue
        }

        for (index, liveTrack) in liveFile.tracks.enumerated() {
            trackCount += 1
            guard let directMetadata = extractedTracks[index].metadata else {
                mismatches.append("\(liveFile.archiveEntry)#\(index): direct metadata missing")
                continue
            }
            func compare(_ field: String, _ directValue: Int, _ liveValue: Int) {
                if directValue == liveValue {
                    exactFieldMatches += 1
                } else {
                    mismatches.append(
                        "\(liveFile.archiveEntry)#\(index) \(field): direct=\(directValue) live=\(liveValue)"
                    )
                }
            }
            func compare(_ field: String, _ directValue: String, _ liveValue: String) {
                if directValue == liveValue {
                    exactFieldMatches += 1
                } else {
                    mismatches.append(
                        "\(liveFile.archiveEntry)#\(index) \(field): direct=\(directValue.debugDescription) live=\(liveValue.debugDescription)"
                    )
                }
            }
            compare("trackIndex", extractedTracks[index].trackIndex, liveTrack.trackIndex)
            compare("trackCount", extractedTracks[index].trackCount, liveTrack.trackCount)
            compare("song", directMetadata.song, liveTrack.song)
            compare("game", directMetadata.game, liveTrack.game)
            compare("system", directMetadata.system, liveTrack.system)
            compare("intro", directMetadata.introLengthMs, liveTrack.introLengthMs)
            compare("loop", directMetadata.loopLengthMs, liveTrack.loopLengthMs)
            compare("play", directMetadata.playLengthMs, liveTrack.playLengthMs)
            if directMetadata.fadeLengthMs == liveTrack.fadeLengthMs {
                exactFieldMatches += 1
            } else if liveTrack.fadeLengthMs == -1 && directMetadata.fadeLengthMs >= 0 {
                timingImprovements += 1
            } else {
                mismatches.append(
                    "\(liveFile.archiveEntry)#\(index) fade: direct=\(directMetadata.fadeLengthMs) live=\(liveTrack.fadeLengthMs)"
                )
            }

            if directMetadata.author == liveTrack.author {
                exactFieldMatches += 1
            } else if isGenericLiveAuthor(liveTrack.author) && !directMetadata.author.isEmpty {
                authorImprovements += 1
            } else {
                mismatches.append(
                    "\(liveFile.archiveEntry)#\(index) author: direct=\(directMetadata.author.debugDescription) live=\(liveTrack.author.debugDescription)"
                )
            }

            if directMetadata.comment == liveTrack.comment {
                exactFieldMatches += 1
            } else if liveTrack.comment.isEmpty && !directMetadata.comment.isEmpty {
                commentImprovements += 1
            } else if !liveTrack.comment.isEmpty && directMetadata.comment.contains(liveTrack.comment) {
                commentImprovements += 1
            } else {
                mismatches.append(
                    "\(liveFile.archiveEntry)#\(index) comment: direct=\(directMetadata.comment.debugDescription) live=\(liveTrack.comment.debugDescription)"
                )
            }
        }
    }

    print(
        "NSFE live parity: \(liveFiles.count) archive members, \(trackCount) tracks, "
            + "\(exactFieldMatches) exact field matches, \(authorImprovements) author improvements, "
            + "\(commentImprovements) comment improvements, \(timingImprovements) timing improvements, "
            + "\(mismatches.count) mismatches"
    )
    for mismatch in mismatches.prefix(20) {
        print("NSFE live parity mismatch: \(mismatch)")
    }
    #expect(mismatches.isEmpty)
}

@Test(
    "CocoaSpice GSF rows match or improve on direct extraction from live archives",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_DB"] != nil,
        "Set SCANSONG_GSF_LIVE_DB to run the read-only GSF/miniGSF catalog parity check."
    )
)
func cocoaSpiceGSFLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let allLiveArchives = try readLiveGSFArchives(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    let archiveFilters = (ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_ARCHIVE_FILTER"] ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    let liveArchives = archiveFilters.isEmpty
        ? allLiveArchives
        : allLiveArchives.filter { archive in
            let path = archive.path.lowercased()
            return archiveFilters.contains { path.contains($0) }
        }
    #expect(!liveArchives.isEmpty)
    print("GSF live parity scope: archives=\(liveArchives.count)/\(allLiveArchives.count)")

    var trackCount = 0
    var exactFieldMatches = 0
    var improvements = 0
    var mismatchCounts: [String: Int] = [:]
    var mismatchSamples: [String] = []
    let concurrency = 2

    for batchStart in stride(from: 0, to: liveArchives.count, by: concurrency) {
        let batchEnd = min(liveArchives.count, batchStart + concurrency)
        let summaries = try await withThrowingTaskGroup(of: GSFParitySummary.self) { group in
            for archiveIndex in batchStart..<batchEnd {
                let archive = liveArchives[archiveIndex]
                group.addTask {
                    try await inspectLiveGSFArchive(archive)
                }
            }
            var batchSummaries: [GSFParitySummary] = []
            for try await summary in group { batchSummaries.append(summary) }
            return batchSummaries
        }
        for summary in summaries {
            trackCount += summary.trackCount
            exactFieldMatches += summary.exactFieldMatches
            improvements += summary.improvements
            for (field, count) in summary.mismatchCounts {
                mismatchCounts[field, default: 0] += count
            }
            mismatchSamples.append(contentsOf: summary.mismatchSamples.prefix(max(0, 20 - mismatchSamples.count)))
        }
    }

    let mismatchCount = mismatchCounts.values.reduce(0, +)
    print("GSF live parity: archives=\(liveArchives.count), tracks=\(trackCount), exactFields=\(exactFieldMatches), improvements=\(improvements), mismatches=\(mismatchCount), byField=\(mismatchCounts)")
    for mismatch in mismatchSamples { print("GSF live parity mismatch: \(mismatch)") }
    #expect(mismatchCount == 0)
}

@Test(
    "CocoaSpice failed GSF rows are classifiable by the direct reader",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_DB"] != nil,
        "Set SCANSONG_GSF_LIVE_DB to inspect existing failed GSF/miniGSF rows."
    )
)
func cocoaSpiceGSFFailedRowsRemainClassifiableWithoutDecoder() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_GSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let failedArchives = try readFailedLiveGSFArchives(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    var rejected: [String] = []
    var newlyReadable: [String] = []
    let extractor = StandaloneArchiveExtractor()
    for archive in failedArchives {
        do {
            let extracted = try await extractor.extractForScan(archiveURL: URL(fileURLWithPath: archive.path))
            defer { extractor.discard(extracted) }
            let payloadURL = extracted.scratchURL.appendingPathComponent("payload", isDirectory: true)
            for entry in archive.entries {
                let memberURL = try findExtractedArchiveMember(named: entry, under: payloadURL)
                do {
                    _ = try GSFMetadataReader.read(fileURL: memberURL)
                    newlyReadable.append("\(archive.path):\(entry)")
                } catch {
                    rejected.append("\(entry): \(error.localizedDescription)")
                }
            }
        }
    }
    print("Existing failed GSF members: \(rejected.count) still rejected, \(newlyReadable.count) newly readable")
    for entry in newlyReadable.prefix(20) {
        print("Previously failed but structurally readable GSF: \(entry)")
    }
    for entry in rejected.prefix(20) {
        print("Previously failed GSF still rejected: \(entry)")
    }
    #expect(rejected.count + newlyReadable.count == failedArchives.reduce(0) { $0 + $1.entries.count })
}

@Test(
    "CocoaSpice QSF rows match or improve on direct extraction from live archives",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_DB"] != nil,
        "Set SCANSONG_QSF_LIVE_DB to run the read-only QSF/miniQSF catalog parity check."
    )
)
func cocoaSpiceQSFLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let allLiveArchives = try readLiveQSFArchives(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    let archiveFilters = ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_ARCHIVE_FILTER"]?
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty } ?? []
    let liveArchives = archiveFilters.isEmpty
        ? allLiveArchives
        : allLiveArchives.filter { archive in
            archiveFilters.contains { archive.path.lowercased().contains($0) }
        }
    #expect(!liveArchives.isEmpty)
    print("QSF live parity scope: archives=\(liveArchives.count)/\(allLiveArchives.count)")

    var summary = QSFParitySummary()
    for (archiveIndex, archive) in liveArchives.enumerated() {
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanSong-live-qsf-\(UUID().uuidString)-\(archiveIndex)", isDirectory: true)
        let archiveSummary = try await inspectLiveQSFArchive(archive, extractionDirectory: extractionDirectory)
        summary.merge(archiveSummary)
    }

    print(
        "QSF live parity: archives=\(liveArchives.count), tracks=\(summary.trackCount), "
            + "exactFields=\(summary.exactFieldMatches), improvements=\(summary.improvements), "
            + "mismatches=\(summary.mismatchCount)"
    )
    for mismatch in summary.mismatchSamples.prefix(20) { print("QSF live parity mismatch: \(mismatch)") }
    #expect(summary.mismatchCount == 0)
}

@Test(
    "CocoaSpice failed QSF rows remain classifiable by the direct reader",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_DB"] != nil,
        "Set SCANSONG_QSF_LIVE_DB to inspect existing failed QSF/miniQSF rows."
    )
)
func cocoaSpiceQSFFailedRowsRemainClassifiableWithoutDecoder() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_QSF_LIVE_ROOT_ID"] ?? "1") ?? 1
    let failedArchives = try readFailedLiveQSFArchives(
        databaseURL: URL(fileURLWithPath: databasePath),
        rootID: rootID
    )
    let archiveRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-failed-qsf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: archiveRoot) }

    var rejected: [String] = []
    var newlyReadable: [String] = []
    for (archiveIndex, archive) in failedArchives.enumerated() {
        let extractionDirectory = archiveRoot.appendingPathComponent("archive-\(archiveIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try extractTarZstd(archiveURL: URL(fileURLWithPath: archive.path), into: extractionDirectory)
        for entry in archive.entries {
            let memberURL = try findExtractedArchiveMember(named: entry, under: extractionDirectory)
            do {
                _ = try QSFMetadataReader.read(fileURL: memberURL)
                newlyReadable.append("\(archive.path):\(entry)")
            } catch {
                rejected.append("\(entry): \(error.localizedDescription)")
            }
        }
        try? FileManager.default.removeItem(at: extractionDirectory)
    }
    print("Existing failed QSF members: \(rejected.count) still rejected, \(newlyReadable.count) newly readable")
    for entry in newlyReadable.prefix(20) { print("Previously failed but structurally readable QSF: \(entry)") }
    for entry in rejected.prefix(20) { print("Previously failed QSF still rejected: \(entry)") }
    #expect(rejected.count + newlyReadable.count == failedArchives.reduce(0) { $0 + $1.entries.count })
}

@Test(
    "Amiga fixture publishes UADE replayer tracks",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_AMIGA_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_AMIGA_INSPECT"] != nil,
        "Set SCANSONG_AMIGA_FIXTURE and SCANSONG_AMIGA_INSPECT to run the UADE scanner check."
    )
)
func amigaFixtureInspectsThroughUADE() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_AMIGA_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(inspection.tracks.count > 0)
    #expect(inspection.tracks.allSatisfy { $0.trackCount == inspection.tracks.count })
    #expect(inspection.tracks.map(\.trackIndex) == Array(0..<inspection.tracks.count))
    #expect(inspection.tracks.allSatisfy { $0.metadata?.system == "Commodore Amiga" })
}

@Test func apeDirectReaderPublishesHeaderTimingAndNativeTags() async throws {
    let fileURL = try writeSPCTestFile(makeAPEFixture(tags: [
        "Title": "  Direct Title  ",
        "Album": "Game Album",
        "Artist": "Composer",
        "Comment": "Authored comment"
    ]), name: "ape-direct.ape")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    let metadata = try #require(inspection.tracks.first?.metadata)
    #expect(inspection.tracks.count == 1)
    #expect(metadata.song == "Direct Title")
    #expect(metadata.game == "Game Album")
    #expect(metadata.author == "Composer")
    #expect(metadata.comment == "Authored comment")
    #expect(metadata.system == "Standard audio")
    #expect(metadata.playLengthMs == 1_000)
    #expect(metadata.introLengthMs == 0)
    #expect(metadata.loopLengthMs == 0)
    #expect(metadata.fadeLengthMs == 0)
}

@Test func apeDirectReaderReadsLeadingID3CommonTags() throws {
    var data = makeID3v24TextPrefix([
        ("TIT2", "ID3 song title"),
        ("TALB", "ID3 game album"),
        ("TPE1", "ID3 composer")
    ])
    data.append(makeAPEFixture(tags: [:]))
    let fileURL = try writeSPCTestFile(data, name: "id3-prefixed.ape")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try APEMetadataReader.read(fileURL: fileURL)
    #expect(metadata.song == "ID3 song title")
    #expect(metadata.game == "ID3 game album")
    #expect(metadata.author == "ID3 composer")
    #expect(metadata.playLengthMs == 1_000)
}

@Test func apeDirectReaderSupportsTheLegacyHeaderAndFilenameFallback() throws {
    let fileURL = try writeSPCTestFile(makeLegacyAPEFixture(), name: "legacy-track.ape")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let metadata = try APEMetadataReader.read(fileURL: fileURL)
    #expect(metadata.song == fileURL.deletingPathExtension().lastPathComponent)
    #expect(metadata.game.isEmpty)
    #expect(metadata.author.isEmpty)
    #expect(metadata.playLengthMs == 1_000)
}

@Test func apeDirectReaderRejectsTruncatedHeadersAndSeekTables() throws {
    let valid = makeAPEFixture(tags: [:])
    let truncatedHeader = try writeSPCTestFile(Data(valid.prefix(18)), name: "truncated-header.ape")
    defer { try? FileManager.default.removeItem(at: truncatedHeader) }
    #expect(throws: ScannerInspectionError.self) { try APEMetadataReader.read(fileURL: truncatedHeader) }

    var brokenSeekTable = valid
    brokenSeekTable.replaceSubrange(64..<68, with: littleEndianBytes(UInt32(2)))
    let truncatedTable = try writeSPCTestFile(brokenSeekTable, name: "bad-seek-table.ape")
    defer { try? FileManager.default.removeItem(at: truncatedTable) }
    #expect(throws: ScannerInspectionError.self) { try APEMetadataReader.read(fileURL: truncatedTable) }
}

@Test(
    "CocoaSpice APE rows match direct extraction from live archives",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_APE_LIVE_DB"] != nil,
        "Set SCANSONG_APE_LIVE_DB to run the read-only APE catalog parity check."
    )
)
func cocoaSpiceAPELiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_APE_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_APE_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveAPEArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    #expect(!archives.isEmpty)

    let extractionRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-live-ape-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: extractionRoot) }

    var exactFields = 0
    var mismatches: [String] = []
    for (archiveIndex, archive) in archives.enumerated() {
        let extractionDirectory = extractionRoot.appendingPathComponent("archive-\(archiveIndex)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try extractTarZstd(archiveURL: URL(fileURLWithPath: archive.path), into: extractionDirectory)
        for liveFile in archive.files {
            let source = "\(archive.path):\(liveFile.entryPath)"
            do {
                let memberURL = try findExtractedArchiveMember(named: liveFile.entryPath, under: extractionDirectory)
                let route = try #require(BuiltInScannerPlugins.registry.route(forPath: memberURL.path))
                let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
                let inspection = try await handler.inspect(fileURL: memberURL, route: route)
                guard inspection.tracks.count == 1, let track = inspection.tracks.first,
                      track.trackIndex == liveFile.trackIndex,
                      track.trackCount == liveFile.trackCount,
                      let metadata = track.metadata else {
                    mismatches.append("\(source): invalid direct track projection")
                    continue
                }
                let pairs: [(String, String, String)] = [
                    ("title", metadata.song, liveFile.title),
                    ("game", metadata.game, liveFile.game),
                    ("system", metadata.system, liveFile.system),
                    ("author", metadata.author, liveFile.author),
                    ("comment", metadata.comment, liveFile.comment)
                ]
                let times: [(String, Int, Int)] = [
                    ("intro", metadata.introLengthMs, liveFile.introLengthMs),
                    ("loop", metadata.loopLengthMs, liveFile.loopLengthMs),
                    ("play", metadata.playLengthMs, liveFile.playLengthMs),
                    ("fade", metadata.fadeLengthMs, liveFile.fadeLengthMs)
                ]
                for (field, direct, stored) in pairs {
                    if direct == stored { exactFields += 1 }
                    else { mismatches.append("\(source) \(field): direct=\(direct.debugDescription) live=\(stored.debugDescription)") }
                }
                for (field, direct, stored) in times {
                    if direct == stored { exactFields += 1 }
                    else { mismatches.append("\(source) \(field): direct=\(direct) live=\(stored)") }
                }
            } catch {
                mismatches.append("\(source): direct extraction failed: \(error.localizedDescription)")
            }
        }
        try? FileManager.default.removeItem(at: extractionDirectory)
    }

    print("APE live parity: archives=\(archives.count), tracks=\(archives.reduce(0) { $0 + $1.files.count }), exactFields=\(exactFields), mismatches=\(mismatches.count)")
    for mismatch in mismatches.prefix(20) { print("APE live parity mismatch: \(mismatch)") }
    #expect(mismatches.isEmpty)
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
    "MDX LZX fixture is decoded before scanner inspection",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_MDX_LZX_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_MDX_INSPECT"] != nil,
        "Set SCANSONG_MDX_LZX_FIXTURE and SCANSONG_MDX_INSPECT to run the real X68000 LZX check."
    )
)
func mdxLZXFixtureInspectsThroughVGMBoy() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_MDX_LZX_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: fileURL.pathExtension))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    #expect(inspection.tracks.count == 1)
    #expect((inspection.tracks.first?.metadata?.playLengthMs ?? 0) > 0)
    #expect(inspection.tracks.first?.metadata?.system == "Sharp X68000")
}

@Test(
    "MDX archive fixture materializes its PDX dependency before inspection",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_MDX_ARCHIVE_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_MDX_ROOT"] != nil
            && ProcessInfo.processInfo.environment["SCANSONG_MDX_INSPECT"] != nil,
        "Set SCANSONG_MDX_ARCHIVE_FIXTURE, SCANSONG_MDX_ROOT, and SCANSONG_MDX_INSPECT to run the archive-backed MDX check."
    )
)
func mdxArchiveFixtureMaterializesDependency() async throws {
    let archiveURL = URL(fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["SCANSONG_MDX_ARCHIVE_FIXTURE"]
    ))
    let rootURL = URL(fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["SCANSONG_MDX_ROOT"]
    ))
    let extracted = try await StandaloneArchiveExtractor().extractForScan(
        archiveURL: archiveURL,
        registry: BuiltInScannerPlugins.registry,
        dependencySearchRoot: rootURL
    )
    defer { StandaloneArchiveExtractor().discard(extracted) }

    let member = try #require(extracted.members.first)
    #expect(extracted.members.count == 1)
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: member.route))
    let inspection = try await handler.inspect(fileURL: member.fileURL, route: member.route)
    #expect(inspection.tracks.count == 1)
    #expect((inspection.tracks.first?.metadata?.playLengthMs ?? 0) > 0)
    #expect(inspection.tracks.first?.metadata?.system == "Sharp X68000")
}

@Test func mdxInspectorReportsMissingPDXBeforeInvokingAdapter() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-mdx-missing-pdx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var mdx = Data("[TITLE] Missing dependency\r\n".utf8)
    mdx.append(0x1A)
    mdx.append(contentsOf: Data("missing.pdx".utf8))
    mdx.append(0)
    let fileURL = root.appendingPathComponent("missing.MDX")
    try mdx.write(to: fileURL)

    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "mdx"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    do {
        _ = try await handler.inspect(fileURL: fileURL, route: route)
        Issue.record("MDX inspection unexpectedly proceeded without its required PDX dependency")
    } catch let error as ScannerInspectionError {
        #expect(error.errorDescription == "Required MDX dependency is missing: missing.pdx.")
    } catch {
        Issue.record("Unexpected MDX inspection error: \(error.localizedDescription)")
    }
}

@Test func mdxDependencyReaderInfersPDXOnlyForExtensionlessReferences() {
    func mdxData(for dependency: String) -> Data {
        var data = Data("[TITLE] Dependency test\r\n".utf8)
        data.append(contentsOf: [0x1A])
        data.append(contentsOf: Data(dependency.utf8))
        data.append(0)
        return data
    }

    #expect(MDXDependencyReader.dependencyName(in: mdxData(for: "nos")) == "nos.pdx")
    #expect(MDXDependencyReader.dependencyName(in: mdxData(for: "nos.smp")) == "nos.smp")
    #expect(MDXDependencyReader.dependencyName(in: mdxData(for: "thrice.pcm")) == "thrice.pcm")
    #expect(MDXDependencyReader.dependencyName(in: mdxData(for: "konami.mdx")) == "konami.mdx")
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
    let playlistURL = fileURL.deletingPathExtension().appendingPathExtension("m3u")
    let libGMEBaseline = try inspectHESWithLibGME(fileURL: fileURL, playlistURL: playlistURL)

    #expect(inspection.tracks.count == 17)
    #expect(inspection.tracks[0].metadata?.song == "Title")
    #expect(inspection.tracks[0].metadata?.playLengthMs == 20_000)
    #expect(inspection.tracks[12].metadata?.song == "Stage Clear")
    #expect(inspection.tracks[12].metadata?.playLengthMs == 4_000)
    #expect(inspection.tracks.compactMap(\.metadata) == libGMEBaseline)
}

@Test(
    "CocoaSpice HES rows match direct extraction from live archives",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_HES_LIVE_DB"] != nil,
        "Set SCANSONG_HES_LIVE_DB to run the read-only HES catalog parity check."
    )
)
func cocoaSpiceHESLiveRowsMatchDirectExtraction() async throws {
    let databasePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_HES_LIVE_DB"])
    let rootID = Int(ProcessInfo.processInfo.environment["SCANSONG_HES_LIVE_ROOT_ID"] ?? "1") ?? 1
    let archives = try readLiveHESArchives(databaseURL: URL(fileURLWithPath: databasePath), rootID: rootID)
    #expect(!archives.isEmpty)

    let extractor = StandaloneArchiveExtractor()
    var comparedArchives = 0
    var comparedSources = 0
    var comparedTracks = 0
    var exactFields = 0
    var mismatches: [String] = []

    for archive in archives {
        let extracted: ExtractedScanArchive
        do {
            extracted = try await extractor.extractForScan(archiveURL: URL(fileURLWithPath: archive.path))
        } catch {
            mismatches.append("\(archive.path): archive extraction failed: \(error.localizedDescription)")
            continue
        }
        do {
            defer { extractor.discard(extracted) }
            comparedArchives += 1
            let payloadURL = extracted.scratchURL.appendingPathComponent("payload", isDirectory: true)
            let groups = Dictionary(grouping: archive.tracks, by: \.entryPath)
            for entryPath in groups.keys.sorted() {
                guard let liveTracks = groups[entryPath]?.sorted(by: { $0.trackIndex < $1.trackIndex }) else { continue }
                let source = "\(archive.path)#\(entryPath)"
                do {
                    let fileURL = try findExtractedArchiveMember(named: entryPath, under: payloadURL)
                    guard let route = BuiltInScannerPlugins.registry.route(forPath: fileURL.path),
                          let handler = BuiltInFormatInspectors.registry.handler(for: route) else {
                        mismatches.append("\(source): no direct HES route")
                        continue
                    }
                    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
                    comparedSources += 1
                    comparedTracks += liveTracks.count
                    guard inspection.tracks.count == liveTracks.count else {
                        mismatches.append("\(source): direct tracks=\(inspection.tracks.count), live tracks=\(liveTracks.count)")
                        continue
                    }
                    for (direct, live) in zip(inspection.tracks, liveTracks) {
                        guard direct.trackIndex == live.trackIndex,
                              direct.trackCount == live.trackCount,
                              let metadata = direct.metadata else {
                            mismatches.append("\(source) row \(live.trackIndex): invalid track projection")
                            continue
                        }
                        let textFields: [(String, String, String)] = [
                            ("title", metadata.song, live.title),
                            ("game", metadata.game, live.game),
                            ("system", metadata.system, live.system),
                            ("author", metadata.author, live.author),
                            ("comment", metadata.comment, live.comment)
                        ]
                        for (field, directValue, liveValue) in textFields {
                            if directValue == liveValue { exactFields += 1 }
                            else { mismatches.append("\(source) #\(live.trackIndex) \(field): direct=\(directValue.debugDescription), live=\(liveValue.debugDescription)") }
                        }
                        let timeFields: [(String, Int, Int)] = [
                            ("intro", metadata.introLengthMs, live.introLengthMs),
                            ("loop", metadata.loopLengthMs, live.loopLengthMs),
                            ("play", metadata.playLengthMs, live.playLengthMs),
                            ("fade", metadata.fadeLengthMs, live.fadeLengthMs)
                        ]
                        for (field, directValue, liveValue) in timeFields {
                            if directValue == liveValue { exactFields += 1 }
                            else { mismatches.append("\(source) #\(live.trackIndex) \(field): direct=\(directValue), live=\(liveValue)") }
                        }
                    }
                } catch {
                    mismatches.append("\(source): direct extraction failed: \(error.localizedDescription)")
                }
            }
        }
    }

    print("HES live parity: archives=\(comparedArchives)/\(archives.count), sources=\(comparedSources), tracks=\(comparedTracks), exactFields=\(exactFields), mismatches=\(mismatches.count)")
    for mismatch in mismatches.prefix(20) { print("HES live parity mismatch: \(mismatch)") }
    #expect(mismatches.isEmpty)
}

@Test(
    "HES direct and libgme info-only paired performance",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_HES_PERF_FIXTURE"] != nil,
        "Set SCANSONG_HES_PERF_FIXTURE to run the paired HES inspection benchmark."
    )
)
func hesDirectAndLibGMEInfoOnlyPerformance() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SCANSONG_HES_PERF_FIXTURE"])
    let fileURL = URL(fileURLWithPath: path)
    let playlistURL = fileURL.deletingPathExtension().appendingPathExtension("m3u")
    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "hes"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    var directSamples: [UInt64] = []
    var libGMESamples: [UInt64] = []

    let iterations = 101
    for iteration in 0..<iterations {
        if iteration.isMultiple(of: 2) {
            let gmeStart = DispatchTime.now().uptimeNanoseconds
            _ = try inspectHESWithLibGME(fileURL: fileURL, playlistURL: playlistURL)
            libGMESamples.append(DispatchTime.now().uptimeNanoseconds - gmeStart)
            let directStart = DispatchTime.now().uptimeNanoseconds
            _ = try await handler.inspect(fileURL: fileURL, route: route)
            directSamples.append(DispatchTime.now().uptimeNanoseconds - directStart)
        } else {
            let directStart = DispatchTime.now().uptimeNanoseconds
            _ = try await handler.inspect(fileURL: fileURL, route: route)
            directSamples.append(DispatchTime.now().uptimeNanoseconds - directStart)
            let gmeStart = DispatchTime.now().uptimeNanoseconds
            _ = try inspectHESWithLibGME(fileURL: fileURL, playlistURL: playlistURL)
            libGMESamples.append(DispatchTime.now().uptimeNanoseconds - gmeStart)
        }
    }

    let directMedianMs = medianMilliseconds(directSamples)
    let libGMEMedianMs = medianMilliseconds(libGMESamples)
    print("HES paired inspect medians (same extracted file+M3U, \(iterations) alternating passes): direct=\(directMedianMs) ms, libgme-info-only=\(libGMEMedianMs) ms, direct/libgme=\(directMedianMs / libGMEMedianMs)x")
    #expect(directMedianMs > 0)
    #expect(libGMEMedianMs > 0)
}

@Test func hesDirectReaderPreservesNoPlaylistSlotsAndSuppressesUnknownTiming() async throws {
    var data = Data(repeating: 0, count: 0xD0)
    data.replaceSubrange(0..<4, with: Data("HESM".utf8))
    writeHESHeaderText(&data, at: 0x40, value: "Fixture Game")
    writeHESHeaderText(&data, at: 0x60, value: "Fixture Artist")
    let fileURL = try writeSPCTestFile(data, name: "no-playlist.hes")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let route = try #require(BuiltInScannerPlugins.registry.route(pathExtension: "hes"))
    let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
    let inspection = try await handler.inspect(fileURL: fileURL, route: route)
    let libGMEBaseline = try inspectHESWithLibGME(fileURL: fileURL, playlistURL: nil)

    #expect(inspection.tracks.count == 256)
    #expect(inspection.tracks.map(\.trackIndex) == Array(0..<256))
    #expect(inspection.tracks.allSatisfy { $0.trackCount == 256 })
    #expect(inspection.tracks.compactMap(\.metadata) == libGMEBaseline)
    #expect(inspection.tracks.allSatisfy { $0.metadata?.playLengthMs == 0 })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.introLengthMs == 0 })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.loopLengthMs == 0 })
    #expect(inspection.tracks.allSatisfy { $0.metadata?.fadeLengthMs == 0 })
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
    try Data([0]).write(to: root.appendingPathComponent("star.pdx"))
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

@Test func psfReaderHarvestsTagsAndTimingWithoutAPlaybackDecoder() throws {
    var data = Data([0x50, 0x53, 0x46, 0x41])
    data.append(Data(repeating: 0, count: 12))
    data.append(Data("[TAG]\ntitle=Cyberbot\ngame=Cyberbots\nartist=Capcom\nlength=1:23.500\nfade=4.250\n".utf8))

    let fileURL = try writeSPCTestFile(data, name: "cyberbot.psf")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let result = try #require(try PSFTagReader.readResult(fileURL: fileURL))

    #expect(result.tags["title"] == "Cyberbot")
    #expect(result.metadata.game == "Cyberbots")
    #expect(result.metadata.author == "Capcom")
    #expect(result.metadata.playLengthMs == 83_500)
    #expect(result.metadata.fadeLengthMs == 4_250)
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
    let metadata = try SPCMetadataReader.read(fileURL: fileURL)

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
    let metadata = try SPCMetadataReader.read(fileURL: fileURL)

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
    let metadata = try SPCMetadataReader.read(fileURL: fileURL)

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

@Test(
    "SPC archive fixtures preserve native metadata and libgme defaults",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SPC_PARITY_DIR"] != nil,
        "Set SCANSONG_SPC_PARITY_DIR to run archive-backed SPC parity."
    )
)
func spcFixtureDirectoryMatchesLibGMEInfoOnly() async throws {
    let rootPath = try #require(ProcessInfo.processInfo.environment["SCANSONG_SPC_PARITY_DIR"])
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    let files = enumerator.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "spc" }
        .sorted { $0.path < $1.path }
    #expect(!files.isEmpty)

    let taglessDefault = ScannerMetadata(
        game: "",
        song: "",
        system: "Super Nintendo",
        author: "",
        comment: "",
        introLengthMs: -1,
        loopLengthMs: -1,
        playLengthMs: 150_000,
        fadeLengthMs: 0
    )
    var exactGMEFiles = 0
    var taglessDefaultFiles = 0
    var enrichedTimingFiles = 0
    var directTimings: [UInt64] = []
    var gmeTimings: [UInt64] = []
    for (fileIndex, fileURL) in files.enumerated() {
        func measureGME() -> (ScannerMetadata?, UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = gmeInfoOnlyMetadata(fileURL: fileURL)?.first
            return (result, DispatchTime.now().uptimeNanoseconds &- started)
        }
        func measureDirect() throws -> (ScannerMetadata, UInt64) {
            let started = DispatchTime.now().uptimeNanoseconds
            let result = try SPCMetadataReader.read(fileURL: fileURL)
            return (result, DispatchTime.now().uptimeNanoseconds &- started)
        }

        let referenceResult: (ScannerMetadata?, UInt64)
        let directResult: (ScannerMetadata, UInt64)
        if fileIndex.isMultiple(of: 2) {
            referenceResult = measureGME()
            directResult = try measureDirect()
        } else {
            directResult = try measureDirect()
            referenceResult = measureGME()
        }
        let reference = try #require(referenceResult.0)
        let direct = directResult.0
        gmeTimings.append(referenceResult.1)
        directTimings.append(directResult.1)
        #expect(direct.game == reference.game, Comment(rawValue: fileURL.lastPathComponent))
        #expect(direct.song == reference.song, Comment(rawValue: fileURL.lastPathComponent))
        #expect(direct.system == reference.system, Comment(rawValue: fileURL.lastPathComponent))
        #expect(direct.author == reference.author, Comment(rawValue: fileURL.lastPathComponent))
        #expect(direct.comment == reference.comment, Comment(rawValue: fileURL.lastPathComponent))
        #expect(direct.playLengthMs == reference.playLengthMs, Comment(rawValue: fileURL.lastPathComponent))
        if direct == reference { exactGMEFiles += 1 }
        if direct == taglessDefault {
            taglessDefaultFiles += 1
            #expect(direct == reference, Comment(rawValue: fileURL.lastPathComponent))
        }
        if direct.introLengthMs != reference.introLengthMs
            || direct.loopLengthMs != reference.loopLengthMs
            || direct.fadeLengthMs != reference.fadeLengthMs {
            enrichedTimingFiles += 1
        }

        let route = try #require(BuiltInScannerPlugins.registry.route(forPath: fileURL.path))
        let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
        let inspection = try await handler.inspect(fileURL: fileURL, route: route)
        #expect(
            inspection.tracks.compactMap(\.metadata) == [direct],
            Comment(rawValue: fileURL.lastPathComponent)
        )
    }

    print(
        "SPC archive check: \(files.count) members; \(exactGMEFiles) exactly match libgme; "
            + "\(taglessDefaultFiles) use and match its tagless defaults; "
            + "\(enrichedTimingFiles) preserve additional native xID6 timing values; "
            + "median direct \(medianMilliseconds(directTimings)) ms, "
            + "libgme \(medianMilliseconds(gmeTimings)) ms."
    )
}

@Test(
    "Compressed SPC archive members scan through the direct route",
    .enabled(
        if: ProcessInfo.processInfo.environment["SCANSONG_SPC_ARCHIVE_FIXTURE"] != nil,
        "Set SCANSONG_SPC_ARCHIVE_FIXTURE to a compressed archive containing SPC files."
    )
)
func catalogScannerInspectsCompressedSPCArchiveMembers() async throws {
    let fixturePath = try #require(ProcessInfo.processInfo.environment["SCANSONG_SPC_ARCHIVE_FIXTURE"])
    let sourceArchive = URL(fileURLWithPath: fixturePath)
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-spc-archive-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let root = scratch.appendingPathComponent("Root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: sourceArchive, to: root.appendingPathComponent(sourceArchive.lastPathComponent))

    let databaseURL = scratch.appendingPathComponent("Library.sqlite")
    let result = try await CatalogScanner(databaseURL: databaseURL).scan(rootURL: root, mode: .newScan)
    #expect(result.trackCount > 0)
    #expect(result.failures.isEmpty)

    var database: OpaquePointer?
    #expect(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let row = try querySingleRow(
        database: try #require(database),
        sql: "SELECT COUNT(*), SUM(plugin_id = 'spc-direct') FROM scan_items WHERE format_extension = 'spc' AND archive_entry <> '';"
    )
    sqlite3_close(database)
    #expect(row == [String(result.trackCount), String(result.trackCount)])
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
    #expect(result.events.contains { $0.route?.pluginID == "spc-direct" })
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

@Test func standaloneMDXNormalizesLegacyLeadingBackslashDependency() async throws {
    let zstandardPath = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    guard let zstandardPath else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-mdx-legacy-pdx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var mdx = Data("[TITLE] Legacy dependency\r\n".utf8)
    mdx.append(contentsOf: [0x1A])
    mdx.append(contentsOf: Data("\\bos".utf8))
    mdx.append(0)
    mdx.append(contentsOf: [0, 0, 0, 0])
    let pdx = Data(repeating: 0x4B, count: 1_024)
    let rawMDX = root.appendingPathComponent("song.MDX")
    let rawPDX = root.appendingPathComponent("BOS.PDX")
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
    let pdxArchive = root.appendingPathComponent("BOS.PDX.zst")
    try compress(rawMDX, to: mdxArchive)
    try compress(rawPDX, to: pdxArchive)
    try FileManager.default.removeItem(at: rawMDX)
    try FileManager.default.removeItem(at: rawPDX)

    let extracted = try await StandaloneArchiveExtractor().extractForScan(
        archiveURL: mdxArchive,
        registry: BuiltInScannerPlugins.registry
    )
    defer { StandaloneArchiveExtractor().discard(extracted) }
    #expect(extracted.members.map(\.entryPath) == ["song.MDX"])
    let materializedPDX = extracted.scratchURL
        .appendingPathComponent("payload", isDirectory: true)
        .appendingPathComponent("bos.pdx")
    #expect(try Data(contentsOf: materializedPDX) == pdx)
}

@Test func standaloneMDXResolvesExplicitAlternateDependencyFromScanRoot() async throws {
    let zstandardPath = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    guard let zstandardPath else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanSong-mdx-root-smp-\(UUID().uuidString)", isDirectory: true)
    let bankDirectory = root.appendingPathComponent("Alternate Banks", isDirectory: true)
    try FileManager.default.createDirectory(at: bankDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var mdx = Data("[TITLE] Alternate dependency\r\n".utf8)
    mdx.append(contentsOf: [0x1A])
    mdx.append(contentsOf: Data("nos.smp".utf8))
    mdx.append(0)
    mdx.append(contentsOf: [0, 0, 0, 0])
    let smp = Data(repeating: 0x46, count: 1_024)
    let rawMDX = root.appendingPathComponent("song.MDX")
    let rawSMP = bankDirectory.appendingPathComponent("NOS.SMP")
    try mdx.write(to: rawMDX)
    try smp.write(to: rawSMP)

    func compress(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zstandardPath)
        process.arguments = ["-q", "-f", source.path, "-o", destination.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    let mdxArchive = root.appendingPathComponent("song.MDX.zst")
    let smpArchive = bankDirectory.appendingPathComponent("NOS.SMP.zst")
    try compress(rawMDX, to: mdxArchive)
    try compress(rawSMP, to: smpArchive)
    try FileManager.default.removeItem(at: rawMDX)
    try FileManager.default.removeItem(at: rawSMP)

    let extracted = try await StandaloneArchiveExtractor().extractForScan(
        archiveURL: mdxArchive,
        registry: BuiltInScannerPlugins.registry,
        dependencySearchRoot: root
    )
    defer { StandaloneArchiveExtractor().discard(extracted) }
    #expect(extracted.members.map(\.entryPath) == ["song.MDX"])
    #expect(extracted.skippedMembers.isEmpty)
    let materializedSMP = extracted.scratchURL
        .appendingPathComponent("payload", isDirectory: true)
        .appendingPathComponent("nos.smp")
    #expect(try Data(contentsOf: materializedSMP) == smp)
}

@Test func catalogBrowserSystemComesOnlyFromTheCollectionPath() {
    let source = "/Audio/Sony PlayStation 2/Castlevania/track.psf2"
    #expect(CatalogIdentity.browserSystem(sourcePath: source, rootPath: "/Audio") == "Sony PlayStation 2")
}

@Test func catalogBrowserSystemUsesTheParentConsoleFolderForGameArchives() {
    let source = "/Audio/JoshW/Nintendo DS/Castlevania.tar.zst"
    #expect(CatalogIdentity.browserSystem(sourcePath: source, rootPath: "/Audio/JoshW") == "Nintendo DS")
}

@Test func catalogBrowserGameStripsPlayableExtensionFromStandaloneCompressedSource() {
    #expect(CatalogIdentity.browserGame(
        metadataGame: "",
        sourcePath: "/Audio/ATARIST/sndh_lf/Proto/Doom.sndh.zst",
        archiveEntry: "Doom.sndh"
    ) == "Doom")
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

private struct GSFParitySummary: Sendable {
    var trackCount = 0
    var exactFieldMatches = 0
    var improvements = 0
    var mismatchCounts: [String: Int] = [:]
    var mismatchSamples: [String] = []
}

private struct LiveAPEFile {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let title: String
    let game: String
    let system: String
    let author: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
}

private struct LiveAPEArchive {
    let path: String
    var files: [LiveAPEFile]
}

private struct LiveHESTrack {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let title: String
    let game: String
    let system: String
    let author: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
}

private struct LiveHESArchive {
    let path: String
    var tracks: [LiveHESTrack]
}

private func readLiveAPEArchives(databaseURL: URL, rootID: Int) throws -> [LiveAPEArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 50, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.path, t.filename, t.track_index, t.track_count,
               m.title, m.game, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms,
               m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'ape'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 51, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 52)
    }

    var archives: [LiveAPEArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let file = LiveAPEFile(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            title: sqliteText(statement, 4),
            game: sqliteText(statement, 5),
            system: sqliteText(statement, 6),
            author: sqliteText(statement, 7),
            comment: sqliteText(statement, 8),
            introLengthMs: Int(sqlite3_column_int64(statement, 9)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 10)),
            playLengthMs: Int(sqlite3_column_int64(statement, 11)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 12))
        )
        if let index = indexes[path] {
            archives[index].files.append(file)
        } else {
            indexes[path] = archives.count
            archives.append(LiveAPEArchive(path: path, files: [file]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 53, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func readLiveHESArchives(databaseURL: URL, rootID: Int) throws -> [LiveHESArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 54, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.path, t.filename, t.track_index, t.track_count,
               m.title, m.game, m.system, m.author, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms,
               m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'hes'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 55, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 56)
    }

    var archives: [LiveHESArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let track = LiveHESTrack(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            title: sqliteText(statement, 4),
            game: sqliteText(statement, 5),
            system: sqliteText(statement, 6),
            author: sqliteText(statement, 7),
            comment: sqliteText(statement, 8),
            introLengthMs: Int(sqlite3_column_int64(statement, 9)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 10)),
            playLengthMs: Int(sqlite3_column_int64(statement, 11)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 12))
        )
        if let index = indexes[path] {
            archives[index].tracks.append(track)
        } else {
            indexes[path] = archives.count
            archives.append(LiveHESArchive(path: path, tracks: [track]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 57, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func inspectLiveGSFArchive(
    _ archive: LiveGSFArchive
) async throws -> GSFParitySummary {
    var summary = GSFParitySummary(trackCount: archive.files.count)
    func mismatch(_ field: String, _ message: String) {
        summary.mismatchCounts[field, default: 0] += 1
        if summary.mismatchSamples.count < 20 { summary.mismatchSamples.append(message) }
    }

    let extractor = StandaloneArchiveExtractor()
    let extracted: ExtractedScanArchive
    do {
        extracted = try await extractor.extractForScan(archiveURL: URL(fileURLWithPath: archive.path))
    } catch {
        mismatch("archiveExtract", "\(archive.path) extraction failed: \(error.localizedDescription)")
        return summary
    }
    defer { extractor.discard(extracted) }
    let payloadURL = extracted.scratchURL.appendingPathComponent("payload", isDirectory: true)

    func compare(_ field: String, _ directValue: Int, _ liveValue: Int, source: String) {
        if directValue == liveValue {
            summary.exactFieldMatches += 1
        } else if (field == "intro" || field == "play" || field == "fade")
                    && liveValue <= 0 && directValue > 0 {
            summary.improvements += 1
        } else {
            mismatch(field, "\(source) \(field): direct=\(directValue) live=\(liveValue)")
        }
    }
    func compare(_ field: String, _ directValue: String, _ liveValue: String, source: String) {
        if directValue == liveValue {
            summary.exactFieldMatches += 1
        } else if (field == "comment" || field == "author")
                    && !liveValue.isEmpty && directValue.contains(liveValue) {
            summary.improvements += 1
        } else if field == "comment" && liveValue.isEmpty && !directValue.isEmpty {
            summary.improvements += 1
        } else if field == "author" && isGenericLiveAuthor(liveValue) && !directValue.isEmpty {
            summary.improvements += 1
        } else {
            mismatch(field, "\(source) \(field): direct=\(directValue.debugDescription) live=\(liveValue.debugDescription)")
        }
    }

    for liveFile in archive.files {
        let source = "\(archive.path):\(liveFile.entryPath)"
        do {
            let memberURL = try findExtractedArchiveMember(named: liveFile.entryPath, under: payloadURL)
            let metadata = try GSFMetadataReader.read(fileURL: memberURL)
            compare("trackIndex", 0, liveFile.trackIndex, source: source)
            compare("trackCount", 1, liveFile.trackCount, source: source)
            compare("song", metadata.song, liveFile.song, source: source)
            compare("game", metadata.game, liveFile.game, source: source)
            compare("system", metadata.system, liveFile.system, source: source)
            compare("author", metadata.author, liveFile.author, source: source)
            compare("comment", metadata.comment, liveFile.comment, source: source)
            compare("intro", metadata.introLengthMs, liveFile.introLengthMs, source: source)
            compare("loop", metadata.loopLengthMs, liveFile.loopLengthMs, source: source)
            compare("play", metadata.playLengthMs, liveFile.playLengthMs, source: source)
            compare("fade", metadata.fadeLengthMs, liveFile.fadeLengthMs, source: source)
        } catch {
            mismatch("extract", "\(source) direct extraction failed: \(error.localizedDescription)")
        }
    }
    return summary
}

private func inspectLiveQSFArchive(
    _ archive: LiveQSFArchive,
    extractionDirectory: URL
) async throws -> QSFParitySummary {
    try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: extractionDirectory) }
    try extractTarZstd(archiveURL: URL(fileURLWithPath: archive.path), into: extractionDirectory)

    var summary = QSFParitySummary()
    func mismatch(_ message: String) {
        summary.mismatchCount += 1
        if summary.mismatchSamples.count < 20 { summary.mismatchSamples.append(message) }
    }
    func compare(_ field: String, _ direct: String, _ live: String, source: String) {
        if direct == live {
            summary.exactFieldMatches += 1
        } else {
            mismatch("\(source) \(field): direct=\(direct.debugDescription) live=\(live.debugDescription)")
        }
    }
    func compare(_ field: String, _ direct: Int, _ live: Int, source: String) {
        if direct == live {
            summary.exactFieldMatches += 1
        } else if (field == "play" || field == "fade") && live <= 0 && direct > 0 {
            summary.improvements += 1
        } else {
            mismatch("\(source) \(field): direct=\(direct) live=\(live)")
        }
    }

    for liveFile in archive.files {
        summary.trackCount += 1
        let source = "\(archive.path):\(liveFile.entryPath)"
        do {
            let memberURL = try findExtractedArchiveMember(named: liveFile.entryPath, under: extractionDirectory)
            let route = try #require(BuiltInScannerPlugins.registry.route(forPath: memberURL.path))
            let handler = try #require(BuiltInFormatInspectors.registry.handler(for: route))
            let inspection = try await handler.inspect(fileURL: memberURL, route: route)
            guard inspection.tracks.count == 1, let track = inspection.tracks.first else {
                mismatch("\(source) direct track count=\(inspection.tracks.count), expected 1")
                continue
            }
            guard let metadata = track.metadata else {
                mismatch("\(source) direct metadata is nil")
                continue
            }
            compare("trackIndex", track.trackIndex, liveFile.trackIndex, source: source)
            compare("trackCount", track.trackCount, liveFile.trackCount, source: source)
            compare("song", metadata.song, liveFile.song, source: source)
            compare("game", metadata.game, liveFile.game, source: source)
            compare("author", metadata.author, liveFile.author, source: source)
            compare("system", metadata.system, liveFile.system, source: source)
            compare("comment", metadata.comment, liveFile.comment, source: source)
            compare("intro", metadata.introLengthMs, liveFile.introLengthMs, source: source)
            compare("loop", metadata.loopLengthMs, liveFile.loopLengthMs, source: source)
            compare("play", metadata.playLengthMs, liveFile.playLengthMs, source: source)
            compare("fade", metadata.fadeLengthMs, liveFile.fadeLengthMs, source: source)
        } catch {
            mismatch("\(source) direct extraction failed: \(error.localizedDescription)")
        }
    }
    return summary
}

private struct LiveNSFETrack {
    let trackIndex: Int
    let trackCount: Int
    let song: String
    let game: String
    let author: String
    let system: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
}

private struct LiveNSFEFile {
    let archivePath: String
    let archiveEntry: String
    var tracks: [LiveNSFETrack]
}

private struct LiveGSFTrack: Sendable {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let song: String
    let game: String
    let author: String
    let system: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
}

private struct LiveGSFArchive: Sendable {
    let path: String
    var files: [LiveGSFTrack]
}

private struct LiveQSFTrack: Sendable {
    let entryPath: String
    let trackIndex: Int
    let trackCount: Int
    let song: String
    let game: String
    let author: String
    let system: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
}

private struct LiveQSFArchive: Sendable {
    let path: String
    var files: [LiveQSFTrack]
}

private struct QSFParitySummary: Sendable {
    var trackCount = 0
    var exactFieldMatches = 0
    var improvements = 0
    var mismatchCount = 0
    var mismatchSamples: [String] = []

    mutating func merge(_ other: QSFParitySummary) {
        trackCount += other.trackCount
        exactFieldMatches += other.exactFieldMatches
        improvements += other.improvements
        mismatchCount += other.mismatchCount
        mismatchSamples.append(contentsOf: other.mismatchSamples.prefix(max(0, 20 - mismatchSamples.count)))
    }
}

private struct FailedLiveGSFArchive {
    let path: String
    var entries: [String]
}

private func readFailedLiveGSFArchives(databaseURL: URL, rootID: Int) throws -> [FailedLiveGSFArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 35, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT path, archive_entry
          FROM scan_items
         WHERE root_id = ?1 AND state = 'failed'
           AND lower(format_extension) IN ('gsf', 'minigsf')
           AND archive_entry <> ''
         ORDER BY path, archive_entry
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 36, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 37)
    }

    var archives: [FailedLiveGSFArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let entry = sqliteText(statement, 1)
        if let index = indexes[path] {
            archives[index].entries.append(entry)
        } else {
            indexes[path] = archives.count
            archives.append(FailedLiveGSFArchive(path: path, entries: [entry]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 38, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func readFailedLiveQSFArchives(databaseURL: URL, rootID: Int) throws -> [FailedLiveGSFArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 45, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT path, archive_entry
          FROM scan_items
         WHERE root_id = ?1 AND state = 'failed'
           AND lower(format_extension) IN ('qsf', 'miniqsf')
           AND archive_entry <> ''
         ORDER BY path, archive_entry
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 46, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 47)
    }

    var archives: [FailedLiveGSFArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let entry = sqliteText(statement, 1)
        if let index = indexes[path] {
            archives[index].entries.append(entry)
        } else {
            indexes[path] = archives.count
            archives.append(FailedLiveGSFArchive(path: path, entries: [entry]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 48, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func readLiveGSFArchives(databaseURL: URL, rootID: Int) throws -> [LiveGSFArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 30, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.path, t.filename, t.track_index, t.track_count,
               m.title, m.game, m.author, m.system, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms,
               m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) IN ('gsf', 'minigsf')
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 31, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 32)
    }

    var archives: [LiveGSFArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let track = LiveGSFTrack(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            song: sqliteText(statement, 4),
            game: sqliteText(statement, 5),
            author: sqliteText(statement, 6),
            system: sqliteText(statement, 7),
            comment: sqliteText(statement, 8),
            introLengthMs: Int(sqlite3_column_int64(statement, 9)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 10)),
            playLengthMs: Int(sqlite3_column_int64(statement, 11)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 12))
        )
        if let index = indexes[path] {
            archives[index].files.append(track)
        } else {
            indexes[path] = archives.count
            archives.append(LiveGSFArchive(path: path, files: [track]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 33, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func readLiveQSFArchives(databaseURL: URL, rootID: Int) throws -> [LiveQSFArchive] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(domain: "ScanSongTests", code: 41, userInfo: [NSLocalizedDescriptionKey: message])
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.path, t.filename, t.track_index, t.track_count,
               m.title, m.game, m.author, m.system, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms,
               m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) IN ('qsf', 'miniqsf')
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "ScanSongTests", code: 42, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 43)
    }

    var archives: [LiveQSFArchive] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let path = sqliteText(statement, 0)
        let track = LiveQSFTrack(
            entryPath: sqliteText(statement, 1),
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            song: sqliteText(statement, 4),
            game: sqliteText(statement, 5),
            author: sqliteText(statement, 6),
            system: sqliteText(statement, 7),
            comment: sqliteText(statement, 8),
            introLengthMs: Int(sqlite3_column_int64(statement, 9)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 10)),
            playLengthMs: Int(sqlite3_column_int64(statement, 11)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 12))
        )
        if let index = indexes[path] {
            archives[index].files.append(track)
        } else {
            indexes[path] = archives.count
            archives.append(LiveQSFArchive(path: path, files: [track]))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(domain: "ScanSongTests", code: 44, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
    return archives
}

private func readLiveNSFEFiles(databaseURL: URL, rootID: Int) throws -> [LiveNSFEFile] {
    var database: OpaquePointer?
    let openStatus = sqlite3_open_v2(
        databaseURL.path,
        &database,
        SQLITE_OPEN_READONLY,
        nil
    )
    guard openStatus == SQLITE_OK, let database else {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the live catalog."
        sqlite3_close(database)
        throw NSError(
            domain: "ScanSongTests",
            code: 20,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)

    let sql = """
        SELECT t.path, t.filename, t.track_index, t.track_count,
               m.title, m.game, m.author, m.system, m.comment,
               m.intro_length_ms, m.loop_length_ms, m.play_length_ms,
               m.fade_length_ms
          FROM tracks t
          JOIN track_metadata m ON m.track_id = t.id
         WHERE t.root_id = ?1 AND lower(t.extension) = 'nsfe'
         ORDER BY t.path, t.filename, t.track_index
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(
            domain: "ScanSongTests",
            code: 21,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int(statement, 1, Int32(rootID)) == SQLITE_OK else {
        throw NSError(domain: "ScanSongTests", code: 22)
    }

    var files: [LiveNSFEFile] = []
    var indexes: [String: Int] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        let archivePath = sqliteText(statement, 0)
        let archiveEntry = sqliteText(statement, 1)
        let key = "\(archivePath)\u{1f}\(archiveEntry)"
        let track = LiveNSFETrack(
            trackIndex: Int(sqlite3_column_int64(statement, 2)),
            trackCount: Int(sqlite3_column_int64(statement, 3)),
            song: sqliteText(statement, 4),
            game: sqliteText(statement, 5),
            author: sqliteText(statement, 6),
            system: sqliteText(statement, 7),
            comment: sqliteText(statement, 8),
            introLengthMs: Int(sqlite3_column_int64(statement, 9)),
            loopLengthMs: Int(sqlite3_column_int64(statement, 10)),
            playLengthMs: Int(sqlite3_column_int64(statement, 11)),
            fadeLengthMs: Int(sqlite3_column_int64(statement, 12))
        )
        if let index = indexes[key] {
            files[index].tracks.append(track)
        } else {
            indexes[key] = files.count
            files.append(LiveNSFEFile(
                archivePath: archivePath,
                archiveEntry: archiveEntry,
                tracks: [track]
            ))
        }
    }
    guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
        throw NSError(
            domain: "ScanSongTests",
            code: 23,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
    return files
}

private func extractTarZstd(archiveURL: URL, into directoryURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["--zstd", "-xf", archiveURL.path, "-C", directoryURL.path]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "tar failed"
        throw NSError(
            domain: "ScanSongTests",
            code: 24,
            userInfo: [NSLocalizedDescriptionKey: "Could not extract \(archiveURL.lastPathComponent): \(error)"]
        )
    }
}

private func findExtractedArchiveMember(named entry: String, under directoryURL: URL) throws -> URL {
    let normalizedEntry = entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
    let directURL = directoryURL.appendingPathComponent(normalizedEntry)
    if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL
    }

    let targetName = URL(fileURLWithPath: normalizedEntry).lastPathComponent
    guard let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw NSError(
            domain: "ScanSongTests",
            code: 39,
            userInfo: [NSLocalizedDescriptionKey: "Could not enumerate extracted archive: \(directoryURL.path)"]
        )
    }
    for case let candidate as URL in enumerator where candidate.lastPathComponent == targetName {
        if try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            return candidate
        }
    }
    throw NSError(
        domain: "ScanSongTests",
        code: 25,
        userInfo: [NSLocalizedDescriptionKey: "Extracted archive member not found: \(entry)"]
    )
}

private func isGenericLiveAuthor(_ author: String) -> Bool {
    ["", "unknown", "n/a", "na", "none", "-"].contains(author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

private func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String {
    sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
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

private func writeHESHeaderText(_ data: inout Data, at offset: Int, value: String) {
    let bytes = Array(value.utf8)
    data.replaceSubrange(offset..<(offset + 0x20), with: Data(repeating: 0, count: 0x20))
    data.replaceSubrange(offset..<(offset + bytes.count), with: Data(bytes))
}

private func inspectHESWithLibGME(fileURL: URL, playlistURL: URL?) throws -> [ScannerMetadata] {
    var emulator: OpaquePointer?
    if let error = fileURL.path.withCString({ gme_open_file($0, &emulator, Int32(gme_info_only)) }) {
        throw NSError(domain: "ScanSongHESOracle", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: error)])
    }
    guard let emulator else {
        throw NSError(domain: "ScanSongHESOracle", code: 2, userInfo: [NSLocalizedDescriptionKey: "libgme returned no HES info reader."])
    }
    defer { gme_delete(emulator) }

    if let playlistURL,
       let error = playlistURL.path.withCString({ gme_load_m3u(emulator, $0) }) {
        throw NSError(domain: "ScanSongHESOracle", code: 3, userInfo: [NSLocalizedDescriptionKey: String(cString: error)])
    }

    let count = Int(gme_track_count(emulator))
    var tracks: [ScannerMetadata] = []
    tracks.reserveCapacity(count)
    for index in 0..<count {
        var infoPointer: UnsafeMutablePointer<gme_info_t>?
        if let error = gme_track_info(emulator, &infoPointer, Int32(index)) {
            throw NSError(domain: "ScanSongHESOracle", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: error)])
        }
        guard let infoPointer else {
            throw NSError(domain: "ScanSongHESOracle", code: 5, userInfo: [NSLocalizedDescriptionKey: "libgme returned no HES track info."])
        }
        defer { gme_free_info(infoPointer) }
        let info = infoPointer.pointee
        let suppressTiming = playlistURL == nil
        tracks.append(ScannerMetadata(
            game: gmeString(info.game),
            song: gmeString(info.song),
            system: gmeString(info.system),
            author: gmeString(info.author),
            comment: gmeString(info.comment),
            introLengthMs: suppressTiming ? 0 : Int(info.intro_length),
            loopLengthMs: suppressTiming ? 0 : Int(info.loop_length),
            playLengthMs: suppressTiming ? 0 : Int(info.play_length),
            fadeLengthMs: suppressTiming ? 0 : Int(info.fade_length)
        ))
    }
    return tracks
}


private func medianMilliseconds(_ samples: [UInt64]) -> Double {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return Double(sorted[middle - 1] + sorted[middle]) / 2_000_000
    }
    return Double(sorted[middle]) / 1_000_000
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

private func littleEndian16Bytes(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
}

private func makeAPEFixture(tags: [String: String]) -> Data {
    var data = Data("MAC ".utf8)
    data.append(contentsOf: littleEndian16Bytes(3_990))
    data.append(contentsOf: littleEndian16Bytes(0))
    data.append(contentsOf: littleEndianBytes(UInt32(52)))
    data.append(contentsOf: littleEndianBytes(UInt32(24)))
    data.append(contentsOf: littleEndianBytes(UInt32(4)))
    data.append(contentsOf: littleEndianBytes(UInt32(0)))
    data.append(contentsOf: littleEndianBytes(UInt32(4)))
    data.append(contentsOf: littleEndianBytes(UInt32(0)))
    data.append(contentsOf: littleEndianBytes(UInt32(0)))
    data.append(contentsOf: repeatElement(0, count: 16)) // source audio MD5
    data.append(contentsOf: littleEndian16Bytes(2_000))
    data.append(contentsOf: littleEndian16Bytes(0))
    data.append(contentsOf: littleEndianBytes(UInt32(294_912)))
    data.append(contentsOf: littleEndianBytes(UInt32(44_100)))
    data.append(contentsOf: littleEndianBytes(UInt32(1)))
    data.append(contentsOf: littleEndian16Bytes(16))
    data.append(contentsOf: littleEndian16Bytes(2))
    data.append(contentsOf: littleEndianBytes(UInt32(44_100)))
    data.append(contentsOf: littleEndianBytes(UInt32(0))) // first seek entry
    data.append(contentsOf: [0, 0, 0, 0]) // bounded opaque compressed-frame bytes

    var fields = Data()
    for (key, value) in tags {
        let valueBytes = Array(value.utf8)
        fields.append(contentsOf: littleEndianBytes(UInt32(valueBytes.count)))
        fields.append(contentsOf: littleEndianBytes(UInt32(0)))
        fields.append(contentsOf: key.utf8)
        fields.append(0)
        fields.append(contentsOf: valueBytes)
    }
    let tagSize = UInt32(fields.count + 32)
    data.append(Data("APETAGEX".utf8))
    data.append(contentsOf: littleEndianBytes(UInt32(2_000)))
    data.append(contentsOf: littleEndianBytes(tagSize))
    data.append(contentsOf: littleEndianBytes(UInt32(tags.count)))
    data.append(contentsOf: littleEndianBytes(UInt32(0xA000_0000))) // header, fields follow
    data.append(contentsOf: repeatElement(0, count: 8))
    data.append(fields)
    data.append(Data("APETAGEX".utf8))
    data.append(contentsOf: littleEndianBytes(UInt32(2_000)))
    data.append(contentsOf: littleEndianBytes(tagSize))
    data.append(contentsOf: littleEndianBytes(UInt32(tags.count)))
    data.append(contentsOf: littleEndianBytes(UInt32(0x8000_0000))) // footer with header
    data.append(contentsOf: repeatElement(0, count: 8))
    return data
}

private func makeLegacyAPEFixture() -> Data {
    var data = Data("MAC ".utf8)
    data.append(contentsOf: littleEndian16Bytes(3_970))
    data.append(contentsOf: littleEndian16Bytes(4_000)) // compression
    data.append(contentsOf: littleEndian16Bytes(0)) // format flags
    data.append(contentsOf: littleEndian16Bytes(2)) // channels
    data.append(contentsOf: littleEndianBytes(UInt32(44_100)))
    data.append(contentsOf: littleEndianBytes(UInt32(0))) // stored WAV header length
    data.append(contentsOf: littleEndianBytes(UInt32(0))) // WAV tail length
    data.append(contentsOf: littleEndianBytes(UInt32(1))) // total frames
    data.append(contentsOf: littleEndianBytes(UInt32(44_100))) // final-frame samples
    data.append(contentsOf: littleEndianBytes(UInt32(0))) // first seek entry
    data.append(contentsOf: [0, 0, 0, 0]) // bounded opaque compressed-frame bytes
    return data
}

private func makeID3v24TextPrefix(_ frames: [(String, String)]) -> Data {
    var body = Data()
    for (identifier, value) in frames {
        let payload = [UInt8(3)] + Array(value.utf8)
        body.append(Data(identifier.utf8))
        body.append(contentsOf: synchsafeBytes(payload.count))
        body.append(contentsOf: [0, 0])
        body.append(contentsOf: payload)
    }
    var tag = Data("ID3".utf8)
    tag.append(contentsOf: [4, 0, 0])
    tag.append(contentsOf: synchsafeBytes(body.count))
    tag.append(body)
    return tag
}

private func synchsafeBytes(_ value: Int) -> [UInt8] {
    [
        UInt8((value >> 21) & 0x7F),
        UInt8((value >> 14) & 0x7F),
        UInt8((value >> 7) & 0x7F),
        UInt8(value & 0x7F)
    ]
}

private func makeGSFExecutable(payload: [UInt8], offset: UInt32 = 0, gbaHeader: Bool = true) -> Data {
    var image = payload
    if gbaHeader {
        if image.count < 0xB3 {
            image.append(contentsOf: repeatElement(0, count: 0xB3 - image.count))
        }
        image[3] = 0xEA
        image[0xB2] = 0x96
    }
    var executable = Data(repeating: 0, count: 12)
    writeLittleEndian(&executable, at: 0, value: 0x0800_0000)
    writeLittleEndian(&executable, at: 4, value: offset)
    writeLittleEndian(&executable, at: 8, value: UInt32(image.count))
    executable.append(contentsOf: image)
    return executable
}

private func makeQSFBlock(_ kind: String, offset: UInt32, payload: [UInt8]) -> Data {
    var block = Data(kind.utf8)
    block.append(contentsOf: littleEndianBytes(offset))
    block.append(contentsOf: littleEndianBytes(UInt32(payload.count)))
    block.append(contentsOf: payload)
    return block
}

private func makeQSFContainer(tags: String, program: Data, version: UInt8 = 0x41) throws -> Data {
    var compressed = [UInt8](repeating: 0, count: Int(compressBound(uLong(program.count))))
    var compressedSize = uLongf(compressed.count)
    let compressionStatus = program.withUnsafeBytes { source in
        compressed.withUnsafeMutableBufferPointer { destination in
            compress2(
                destination.baseAddress,
                &compressedSize,
                source.bindMemory(to: Bytef.self).baseAddress,
                uLong(program.count),
                Z_BEST_COMPRESSION
            )
        }
    }
    guard compressionStatus == Z_OK else {
        throw NSError(domain: "ScanSongTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Could not create compressed QSF fixture."])
    }
    compressed.removeSubrange(Int(compressedSize)..<compressed.count)
    let checksum = compressed.withUnsafeBytes { bytes in
        crc32(crc32(0, nil, 0), bytes.bindMemory(to: Bytef.self).baseAddress, uInt(compressed.count))
    }
    var data = Data([0x50, 0x53, 0x46, version])
    data.append(contentsOf: littleEndianBytes(0))
    data.append(contentsOf: littleEndianBytes(UInt32(compressed.count)))
    data.append(contentsOf: littleEndianBytes(UInt32(checksum)))
    data.append(contentsOf: compressed)
    data.append(Data("[TAG]\n\(tags)".utf8))
    return data
}

private func makeGSFContainer(tags: String, executable: Data) throws -> Data {
    var compressed = [UInt8](repeating: 0, count: Int(compressBound(uLong(executable.count))))
    var compressedSize = uLongf(compressed.count)
    let compressionStatus = executable.withUnsafeBytes { source in
        compressed.withUnsafeMutableBufferPointer { destination in
            compress2(
                destination.baseAddress,
                &compressedSize,
                source.bindMemory(to: Bytef.self).baseAddress,
                uLong(executable.count),
                Z_BEST_COMPRESSION
            )
        }
    }
    guard compressionStatus == Z_OK else {
        throw NSError(domain: "ScanSongTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Could not create compressed GSF fixture."])
    }
    compressed.removeSubrange(Int(compressedSize)..<compressed.count)
    let checksum = compressed.withUnsafeBytes { bytes in
        crc32(crc32(0, nil, 0), bytes.bindMemory(to: Bytef.self).baseAddress, uInt(compressed.count))
    }
    var data = Data([0x50, 0x53, 0x46, 0x22])
    data.append(contentsOf: littleEndianBytes(0))
    data.append(contentsOf: littleEndianBytes(UInt32(compressed.count)))
    data.append(contentsOf: littleEndianBytes(UInt32(checksum)))
    data.append(contentsOf: compressed)
    data.append(Data("[TAG]\n\(tags)".utf8))
    return data
}

private func writeLittleEndian(_ data: inout Data, at offset: Int, value: UInt32) {
    data.replaceSubrange(offset..<(offset + 4), with: littleEndianBytes(value))
}

private func makeNSFEFixture() -> Data {
    var data = Data("NSFE".utf8)
    var info = [UInt8](repeating: 0, count: 10)
    info[0] = 0x00
    info[1] = 0x80
    info[2] = 0x03
    info[3] = 0x80
    info[4] = 0x06
    info[5] = 0x80
    info[6] = 0x01
    info[7] = 0x02
    info[8] = 0x03
    info[9] = 0x00
    appendNSFEChunk(&data, identifier: "INFO", payload: info)
    appendNSFEChunk(&data, identifier: "auth", payload: Array("NSFE Game\0Artist\0Copyright\0Ripper\0".utf8))
    appendNSFEChunk(&data, identifier: "tlbl", payload: Array("First\0Second\0Third\0".utf8))
    appendNSFEChunk(&data, identifier: "taut", payload: Array("First Author\0\0Third Author\0".utf8))
    appendNSFEChunk(&data, identifier: "time", payload: littleEndianBytes(1_000) + littleEndianBytes(UInt32(bitPattern: Int32(-1))) + littleEndianBytes(0))
    appendNSFEChunk(&data, identifier: "fade", payload: littleEndianBytes(100) + littleEndianBytes(200) + littleEndianBytes(UInt32(bitPattern: Int32(-1))))
    appendNSFEChunk(&data, identifier: "plst", payload: [2, 0, 2])
    appendNSFEChunk(&data, identifier: "text", payload: Array("fixture notes\0".utf8))
    appendNSFEChunk(&data, identifier: "DATA", payload: [0xEA, 0x60])
    appendNSFEChunk(&data, identifier: "NEND", payload: [])
    return data
}

private func appendNSFEChunk(_ data: inout Data, identifier: String, payload: [UInt8]) {
    data.append(contentsOf: littleEndianBytes(UInt32(payload.count)))
    data.append(contentsOf: identifier.utf8)
    data.append(contentsOf: payload)
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

private func makeAYData(author: String, comment: String, tracks: [(String, UInt16)]) -> Data {
    precondition((1...256).contains(tracks.count))
    var data = Data(repeating: 0, count: 0x14)
    data.replaceSubrange(0..<8, with: Data("ZXAYEMUL".utf8))
    data[8] = 1
    data[9] = 3
    data[16] = UInt8(tracks.count - 1)
    data[17] = 1

    let authorOffset = appendAYCString(author, to: &data)
    writeAYRelativePointer(&data, at: 12, target: authorOffset)
    let commentOffset = appendAYCString(comment, to: &data)
    writeAYRelativePointer(&data, at: 14, target: commentOffset)
    var titleOffsets: [Int] = []
    for (title, _) in tracks {
        titleOffsets.append(appendAYCString(title, to: &data))
    }

    let tableOffset = data.count
    data.append(contentsOf: repeatElement(0, count: tracks.count * 4))
    writeAYRelativePointer(&data, at: 18, target: tableOffset)
    for (index, track) in tracks.enumerated() {
        let rowOffset = tableOffset + index * 4
        writeAYRelativePointer(&data, at: rowOffset, target: titleOffsets[index])
        let infoOffset = data.count
        data.append(contentsOf: [0, 0, 0, 0, UInt8(track.1 >> 8), UInt8(track.1 & 0xFF)])
        writeAYRelativePointer(&data, at: rowOffset + 2, target: infoOffset)
    }
    return data
}

private func appendAYCString(_ value: String, to data: inout Data) -> Int {
    let offset = data.count
    data.append(contentsOf: value.utf8)
    data.append(0)
    return offset
}

private func writeAYRelativePointer(_ data: inout Data, at offset: Int, target: Int) {
    let encoded = UInt16(bitPattern: Int16(target - offset))
    data[offset] = UInt8(encoded >> 8)
    data[offset + 1] = UInt8(encoded & 0xFF)
}

private func gmeInfoOnlyMetadata(fileURL: URL) -> [ScannerMetadata]? {
    var emulator: OpaquePointer?
    if gme_open_file(fileURL.path, &emulator, Int32(gme_info_only)) != nil {
        if let emulator { gme_delete(emulator) }
        return nil
    }
    guard let emulator else { return nil }
    defer { gme_delete(emulator) }

    let count = Int(gme_track_count(emulator))
    guard count > 0, count <= 65_536 else { return nil }
    var tracks: [ScannerMetadata] = []
    tracks.reserveCapacity(count)
    for index in 0..<count {
        var infoPointer: UnsafeMutablePointer<gme_info_t>?
        guard gme_track_info(emulator, &infoPointer, Int32(index)) == nil,
              let infoPointer else {
            if let infoPointer { gme_free_info(infoPointer) }
            return nil
        }
        defer { gme_free_info(infoPointer) }
        let info = infoPointer.pointee
        tracks.append(ScannerMetadata(
            game: gmeString(info.game),
            song: gmeString(info.song),
            system: gmeString(info.system),
            author: gmeString(info.author),
            comment: gmeString(info.comment),
            introLengthMs: Int(info.intro_length),
            loopLengthMs: Int(info.loop_length),
            playLengthMs: Int(info.play_length),
            fadeLengthMs: Int(info.fade_length)
        ))
    }
    return tracks
}

private func gmeString(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    let value = String(cString: pointer)
    return value == "?" ? "" : value
}
