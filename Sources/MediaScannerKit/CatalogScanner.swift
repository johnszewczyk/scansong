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
    public let telemetry: ScanPhaseTelemetry

    public init(
        root: CatalogRoot,
        discoveredSourceCount: Int,
        scannedSourceCount: Int,
        reusedSourceCount: Int,
        trackCount: Int,
        failures: [ScanFailure],
        telemetry: ScanPhaseTelemetry = .empty
    ) {
        self.root = root
        self.discoveredSourceCount = discoveredSourceCount
        self.scannedSourceCount = scannedSourceCount
        self.reusedSourceCount = reusedSourceCount
        self.trackCount = trackCount
        self.failures = failures
        self.telemetry = telemetry
    }
}

public final class CatalogScanner: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (CatalogScanProgress) -> Void

    private let writer: CanonicalCatalogWriter
    private let registry: ScannerPluginRegistry
    private let handlers: ScanPluginHandlerRegistry
    private let archiveExtractor: StandaloneArchiveExtractor
    private let inspectionScheduler: ScanResourceScheduler
    private let archivePipelineLimit: Int

    public init(
        databaseURL: URL,
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        handlers: ScanPluginHandlerRegistry = BuiltInFormatInspectors.registry,
        archiveExtractor: StandaloneArchiveExtractor = StandaloneArchiveExtractor(),
        inspectionPermits: Int = 8,
        archivePipelineLimit: Int = 4
    ) throws {
        writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
        self.registry = registry
        self.handlers = handlers
        self.archiveExtractor = archiveExtractor
        inspectionScheduler = ScanResourceScheduler(permits: inspectionPermits)
        self.archivePipelineLimit = max(1, archivePipelineLimit)
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
        let timeline = ScanPhaseTimeline()

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
            timeline.enter(.discovery)
            emit(.discovery)
            let candidates = try await ScanFilesystemDiscovery.discover(
                rootID: root.id,
                rootURL: rootURL,
                registry: registry,
                isArchive: StandaloneArchiveExtractor.isSupportedArchive
            )
            discovered = candidates.count
            try writer.synchronizeStage(stageID: stageID, discoveredPaths: Set(candidates.map(\.identity.path)))

            timeline.enter(.planning)
            emit(.planning)

            // Serial reuse pass. These are cheap fingerprint reads against the
            // writer and must not interleave with concurrent inspection commits.
            timeline.enter(.inspection)
            var pending: [ScanCandidate] = []
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
                pending.append(candidate)
            }

            // Concurrent inspection pipeline. Multiple sources extract and
            // inspect at once, but all member inspections share one permit pool
            // so the total subprocess count stays bounded. The writer is only
            // touched here (serial checkpoint commits), never by pipeline tasks.
            let outcomes = try await inspectPending(pending, pipelineLimit: archivePipelineLimit)
            for candidate in pending {
                try Task.checkCancellation()
                switch outcomes[candidate.identity.path] {
                case .success(let records):
                    try writer.checkpoint(
                        stageID: stageID,
                        rootPath: root.path,
                        sourcePath: candidate.identity.path,
                        fingerprint: candidate.fingerprint,
                        records: records
                    )
                    tracks += records.count
                    scanned += 1
                case .failure(let message):
                    let stage: ScanFailureStage = StandaloneArchiveExtractor.isSupportedArchive(candidate.sourceURL)
                        ? .archiveExtraction : .metadata
                    let failure = ScanFailure(
                        identity: candidate.identity,
                        fingerprint: candidate.fingerprint,
                        route: candidate.route,
                        stage: stage,
                        message: message
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
                case .cancelled, nil:
                    throw CancellationError()
                }
                processed += 1
                emit(.persistence, currentPath: candidate.identityDescription)
            }

            timeline.enter(.publication)
            emit(.publication)
            try writer.publish(stageID: stageID, targetRootID: root.id)
            let published = try writer.roots().first(where: { $0.id == root.id }) ?? root
            timeline.enter(.cleanup)
            emit(.cleanup)
            return CatalogScanResult(
                root: published,
                discoveredSourceCount: discovered,
                scannedSourceCount: scanned,
                reusedSourceCount: reused,
                trackCount: published.lastScanTrackCount,
                failures: failures,
                telemetry: timeline.snapshot()
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

    private enum CandidateInspectionOutcome {
        case success([CatalogTrackRecord])
        case failure(String)
        case cancelled
    }

    private func inspectPending(
        _ pending: [ScanCandidate],
        pipelineLimit: Int
    ) async throws -> [String: CandidateInspectionOutcome] {
        var outcomes: [String: CandidateInspectionOutcome] = [:]
        if pending.isEmpty { return outcomes }
        try await withThrowingTaskGroup(of: (String, CandidateInspectionOutcome).self) { group in
            var next = 0
            var inFlight = 0
            while next < pending.count || inFlight > 0 {
                while next < pending.count && inFlight < pipelineLimit {
                    let candidate = pending[next]
                    next += 1
                    inFlight += 1
                    group.addTask {
                        let outcome = await self.inspectCandidate(candidate)
                        return (candidate.identity.path, outcome)
                    }
                }
                if let (path, outcome) = try await group.next() {
                    inFlight -= 1
                    outcomes[path] = outcome
                }
            }
        }
        return outcomes
    }

    private func inspectCandidate(_ candidate: ScanCandidate) async -> CandidateInspectionOutcome {
        do {
            try Task.checkCancellation()
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
            return .success(records)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
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

        // Inspect members concurrently under a bounded permit pool. Subprocess
        // adapters (vgmstream, Highly Complete) dominate wall time; bounding
        // the pool keeps memory and process count predictable while preserving
        // deterministic record order via per-index collection.
        let members = archive.members
        var inspections: [ScanInspection?] = Array(repeating: nil, count: members.count)
        try await withThrowingTaskGroup(of: (Int, ScanInspection).self) { group in
            for (index, member) in members.enumerated() {
                try Task.checkCancellation()
                group.addTask {
                    let inspection = try await self.inspectionScheduler.withPermit {
                        try await self.inspect(fileURL: member.fileURL, route: member.route)
                    }
                    return (index, inspection)
                }
            }
            for try await (index, inspection) in group {
                inspections[index] = inspection
            }
        }

        var records: [CatalogTrackRecord] = []
        for (index, member) in members.enumerated() {
            guard let inspection = inspections[index] else { continue }
            try Task.checkCancellation()
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
