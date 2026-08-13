import Foundation
import SQLite3
import Testing
@testable import MediaScannerKit

@Test func builtInPoliciesPreserveRequiredStructureWork() throws {
    let registry = BuiltInScannerPlugins.registry
    #expect(registry.route(pathExtension: "spc")?.metadataPolicy == .direct)
    #expect(registry.route(pathExtension: ".NSF")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "gbs")?.structurePolicy == .enumerate)
    #expect(registry.route(pathExtension: "flac")?.metadataPolicy == .optionalDeferred)
    #expect(registry.route(pathExtension: "txtp")?.structurePolicy == .dependencyEnumerate)
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

@Test func catalogConsoleSourcePolicyIsDeterministicForPlayStationFamilies() {
    let source = "/Audio/Sony PlayStation 2/Castlevania/track.psf2"
    #expect(CatalogIdentity.browserSystem(
        metadataSystem: "PlayStation",
        sourcePath: source,
        rootPath: "/Audio",
        policy: .foldersFirst
    ) == "Sony PlayStation 2")
    #expect(CatalogIdentity.browserSystem(
        metadataSystem: "PlayStation",
        sourcePath: source,
        rootPath: "/Audio",
        policy: .metadataFirst
    ) == "Sony PlayStation")
}

@Test func sharedPlannerSkipsOnlyACompletedMatchingIncrementalItem() throws {
    let sourceURL = URL(fileURLWithPath: "/library/game.nsf")
    let identity = ScanItemIdentity(rootID: 7, path: sourceURL.path, archiveEntry: nil)
    let fingerprint = ScanFingerprint(fileSize: 42, modifiedAt: Date(timeIntervalSince1970: 100), contentSignature: "same")
    let item = ScanInventoryItem(
        identity: identity,
        fingerprint: fingerprint,
        state: .successful,
        route: BuiltInScannerPlugins.registry.route(pathExtension: "nsf")
    )
    let skipped = ScanPlanner.makePlan(
        mode: .incremental,
        items: [item],
        sourceURLs: [identity: sourceURL],
        currentFingerprints: [identity: fingerprint]
    )
    let full = ScanPlanner.makePlan(
        mode: .newScan,
        items: [item],
        sourceURLs: [identity: sourceURL],
        currentFingerprints: [identity: fingerprint]
    )
    #expect(skipped.count == 0)
    #expect(full.count == 1)
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
        throw NSError(domain: "MediaScannerTests", code: 3)
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
