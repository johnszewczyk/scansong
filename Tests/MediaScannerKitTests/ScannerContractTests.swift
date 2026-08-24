import Foundation
import SQLite3
import Testing
@testable import MediaScannerKit

@Test func builtInPoliciesPreserveRequiredStructureWork() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "spc")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: ".NSF")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "gbs")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "flac")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "txtp")?.structurePolicy == .dependencyEnumerate)
    #expect(registry.route(pathExtension: "sid")?.structurePolicy == .knownSingle)
    #expect(registry.route(pathExtension: "sid")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "ogg")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: "ogg")?.pluginID == "standard-audio")
    #expect(registry.route(pathExtension: "ogg")?.pluginID != "vgmstream")
    #expect(registry.route(pathExtension: "qsf")?.pluginID == "qsf")
    #expect(registry.route(pathExtension: "miniqsf")?.pluginID == "qsf-mini")
    #expect(registry.route(pathExtension: "miniqsf")?.structurePolicy == .dependencyEnumerate)
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
    "Core Audio inspection publishes FLAC metadata and duration",
    .enabled(
        if: ProcessInfo.processInfo.environment["MEDIASCANNER_FLAC_FIXTURE"] != nil,
        "Set MEDIASCANNER_FLAC_FIXTURE to run the archive-backed FLAC metadata check."
    )
)
func flacFixturePublishesStandardMetadata() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["MEDIASCANNER_FLAC_FIXTURE"])
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
        if: ProcessInfo.processInfo.environment["MEDIASCANNER_GAMECUBE_FIXTURES"] != nil,
        "Set MEDIASCANNER_GAMECUBE_FIXTURES to run the archive-backed GameCube scanner checks."
    )
)
func gameCubeFixturesInspectThroughVGMStream() async throws {
    let rootPath = try #require(ProcessInfo.processInfo.environment["MEDIASCANNER_GAMECUBE_FIXTURES"])
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
        .appendingPathComponent("MediaScanner-txtp-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-ignore-policy-\(UUID().uuidString)", isDirectory: true)
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

@Test func sidHeaderReaderPublishesCommodore64Metadata() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MediaScanner-sid-\(UUID().uuidString)", isDirectory: true)
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

@Test func dryRunReportsTypedRoutesWithoutWritingADataStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MediaScanner-probe-\(UUID().uuidString)", isDirectory: true)
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
    #expect(json["contract"] as? String == MediaScannerContract.name)
    #expect(json["version"] as? Int == MediaScannerContract.version)
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
        .appendingPathComponent("MediaScanner-catalog-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-invalid-catalog-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-writer-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-writer-lease-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-wal-writer-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-links-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-reset-catalog-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-reuse-\(UUID().uuidString)", isDirectory: true)
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
        .appendingPathComponent("MediaScanner-discovery-\(UUID().uuidString)", isDirectory: true)
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

private func createCanonicalCatalog(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw NSError(domain: "MediaScannerTests", code: 1)
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
                domain: "MediaScannerTests",
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
            domain: "MediaScannerTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw NSError(domain: "MediaScannerTests", code: 4)
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
