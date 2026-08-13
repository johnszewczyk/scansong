import Foundation

public struct CatalogScanProgress: Sendable {
    public let phase: ScanLifecyclePhase
    public let rootPath: String
    public let currentPath: String?
    public let discovered: Int
    public let processed: Int
    public let successful: Int
    public let failed: Int

    public init(
        phase: ScanLifecyclePhase,
        rootPath: String,
        currentPath: String?,
        discovered: Int,
        processed: Int,
        successful: Int,
        failed: Int
    ) {
        self.phase = phase
        self.rootPath = rootPath
        self.currentPath = currentPath
        self.discovered = discovered
        self.processed = processed
        self.successful = successful
        self.failed = failed
    }
}

public struct CatalogScanResult: Sendable {
    public let root: CatalogRoot
    public let discoveredSourceCount: Int
    public let scannedSourceCount: Int
    public let reusedSourceCount: Int
    public let trackCount: Int
    public let failures: [ScanFailure]

    public init(
        root: CatalogRoot,
        discoveredSourceCount: Int,
        scannedSourceCount: Int,
        reusedSourceCount: Int,
        trackCount: Int,
        failures: [ScanFailure]
    ) {
        self.root = root
        self.discoveredSourceCount = discoveredSourceCount
        self.scannedSourceCount = scannedSourceCount
        self.reusedSourceCount = reusedSourceCount
        self.trackCount = trackCount
        self.failures = failures
    }
}

public final class CatalogScanner: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (CatalogScanProgress) -> Void

    private let writer: CanonicalCatalogWriter
    private let registry: ScannerPluginRegistry
    private let handlers: ScanPluginHandlerRegistry
    private let archiveExtractor: StandaloneArchiveExtractor

    public init(
        databaseURL: URL,
        consoleSourcePolicy: CatalogConsoleSourcePolicy = .foldersFirst,
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        handlers: ScanPluginHandlerRegistry = BuiltInFormatInspectors.registry,
        archiveExtractor: StandaloneArchiveExtractor = StandaloneArchiveExtractor()
    ) throws {
        writer = try CanonicalCatalogWriter(
            databaseURL: databaseURL,
            consoleSourcePolicy: consoleSourcePolicy
        )
        self.registry = registry
        self.handlers = handlers
        self.archiveExtractor = archiveExtractor
    }

    public func scan(
        rootURL: URL,
        mode: ScanMode = .incremental,
        progress: ProgressHandler? = nil
    ) async throws -> CatalogScanResult {
        let rootURL = CanonicalFileURL.resolve(rootURL)
        let root = try writer.addRoot(path: rootURL.path)
        let stageID = try writer.beginScan(root: root, mode: mode)
        var processed = 0
        var scanned = 0
        var reused = 0
        var tracks = 0
        var failures: [ScanFailure] = []
        var discovered = 0

        func emit(_ phase: ScanLifecyclePhase, currentPath: String? = nil) {
            progress?(CatalogScanProgress(
                phase: phase,
                rootPath: root.path,
                currentPath: currentPath,
                discovered: discovered,
                processed: processed,
                successful: processed - failures.count,
                failed: failures.count
            ))
        }

        do {
            emit(.discovery)
            let candidates = try await ScanFilesystemDiscovery.discover(
                rootID: root.id,
                rootURL: rootURL,
                registry: registry,
                isArchive: StandaloneArchiveExtractor.isSupportedArchive
            )
            discovered = candidates.count
            try writer.synchronizeStage(stageID: stageID, discoveredPaths: Set(candidates.map(\.identity.path)))
            emit(.planning)

            for candidate in candidates {
                try Task.checkCancellation()
                emit(.inspection, currentPath: candidate.identityDescription)

                if let completed = try writer.completedFingerprint(
                    stageID: stageID,
                    sourcePath: candidate.identity.path
                ), completed.matches(candidate.fingerprint) {
                    processed += 1
                    reused += 1
                    continue
                }
                if mode == .incremental,
                   let live = try writer.reusableLiveFingerprint(
                    rootID: root.id,
                    sourcePath: candidate.identity.path
                   ), live.matches(candidate.fingerprint) {
                    try writer.reuseLiveSource(
                        rootID: root.id,
                        stageID: stageID,
                        sourcePath: candidate.identity.path,
                        fingerprint: candidate.fingerprint
                    )
                    processed += 1
                    reused += 1
                    continue
                }

                do {
                    let records: [CatalogTrackRecord]
                    if StandaloneArchiveExtractor.isSupportedArchive(candidate.sourceURL) {
                        records = try await inspectArchive(candidate)
                    } else {
                        records = try await inspectLoose(candidate)
                    }
                    guard !records.isEmpty else {
                        throw ScannerInspectionError.malformedFile(
                            "No supported playable tracks were found in \(candidate.sourceURL.lastPathComponent)."
                        )
                    }
                    try writer.checkpoint(
                        stageID: stageID,
                        rootPath: root.path,
                        sourcePath: candidate.identity.path,
                        fingerprint: candidate.fingerprint,
                        records: records
                    )
                    tracks += records.count
                    scanned += 1
                    processed += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let stage: ScanFailureStage = StandaloneArchiveExtractor.isSupportedArchive(candidate.sourceURL)
                        ? .archiveExtraction : .metadata
                    let failure = ScanFailure(
                        identity: candidate.identity,
                        fingerprint: candidate.fingerprint,
                        route: candidate.route,
                        stage: stage,
                        message: error.localizedDescription
                    )
                    try writer.preserveLiveSourceAfterFailure(
                        rootID: root.id,
                        stageID: stageID,
                        sourcePath: candidate.identity.path,
                        currentFingerprint: candidate.fingerprint,
                        route: candidate.route,
                        failure: failure
                    )
                    failures.append(failure)
                    processed += 1
                }
                emit(.persistence, currentPath: candidate.identityDescription)
            }

            try Task.checkCancellation()
            emit(.publication)
            try writer.publish(stageID: stageID, targetRootID: root.id)
            let published = try writer.roots().first(where: { $0.id == root.id }) ?? root
            emit(.cleanup)
            return CatalogScanResult(
                root: published,
                discoveredSourceCount: discovered,
                scannedSourceCount: scanned,
                reusedSourceCount: reused,
                trackCount: published.lastScanTrackCount,
                failures: failures
            )
        } catch is CancellationError {
            writer.pause(stageID: stageID, error: "Cancelled")
            throw CancellationError()
        } catch {
            writer.pause(stageID: stageID, error: error.localizedDescription)
            writer.markFailed(rootID: root.id, message: error.localizedDescription)
            throw error
        }
    }

    private func inspectLoose(_ candidate: ScanCandidate) async throws -> [CatalogTrackRecord] {
        guard let route = candidate.route else {
            throw ScannerInspectionError.unsupportedRoute(candidate.sourceURL.pathExtension)
        }
        let inspection = try await inspect(fileURL: candidate.sourceURL, route: route)
        return inspection.tracks.map {
            CatalogTrackRecord(
                sourcePath: candidate.identity.path,
                archiveEntry: nil,
                route: route,
                fingerprint: candidate.fingerprint,
                trackIndex: $0.trackIndex,
                trackCount: $0.trackCount,
                metadata: $0.metadata
            )
        }
    }

    private func inspectArchive(_ candidate: ScanCandidate) async throws -> [CatalogTrackRecord] {
        let archive = try await archiveExtractor.extractForScan(
            archiveURL: candidate.sourceURL,
            registry: registry
        )
        defer { archiveExtractor.discard(archive) }
        var records: [CatalogTrackRecord] = []
        for member in archive.members {
            try Task.checkCancellation()
            let inspection = try await inspect(fileURL: member.fileURL, route: member.route)
            records.append(contentsOf: inspection.tracks.map {
                CatalogTrackRecord(
                    sourcePath: candidate.identity.path,
                    archiveEntry: member.entryPath,
                    route: member.route,
                    fingerprint: member.fingerprint,
                    trackIndex: $0.trackIndex,
                    trackCount: $0.trackCount,
                    metadata: $0.metadata
                )
            })
        }
        return records
    }

    private func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        guard let handler = handlers.handler(for: route) else {
            throw ScannerInspectionError.unsupportedRoute(route.pluginID)
        }
        return try await handler.inspect(fileURL: fileURL, route: route)
    }
}
