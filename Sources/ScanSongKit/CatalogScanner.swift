import Foundation

private final class MonotonicScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0

    init(completed: Int) {
        self.completed = completed
    }

    func advance(to value: Int) -> Int {
        lock.withLock {
            completed = max(completed, value)
            return completed
        }
    }
}

public struct CatalogScanProgress: Sendable {
    public let phase: ScanLifecyclePhase
    public let rootPath: String
    public let currentPath: String?
    public let discovered: Int
    public let processed: Int
    public let successful: Int
    public let failed: Int
    public let detail: String?
    public let phaseCompleted: Int?
    public let phaseTotal: Int?

    public init(
        phase: ScanLifecyclePhase,
        rootPath: String,
        currentPath: String?,
        discovered: Int,
        processed: Int,
        successful: Int,
        failed: Int,
        detail: String? = nil,
        phaseCompleted: Int? = nil,
        phaseTotal: Int? = nil
    ) {
        self.phase = phase
        self.rootPath = rootPath
        self.currentPath = currentPath
        self.discovered = discovered
        self.processed = processed
        self.successful = successful
        self.failed = failed
        self.detail = detail
        self.phaseCompleted = phaseCompleted
        self.phaseTotal = phaseTotal
    }
}

public struct CatalogScanResult: Sendable {
    public let root: CatalogRoot
    public let discoveredSourceCount: Int
    public let scannedSourceCount: Int
    public let reusedSourceCount: Int
    public let trackCount: Int
    public let failures: [ScanFailure]
    public let skipped: [ScanSkippedFile]
    public let telemetry: ScanPhaseTelemetry

    public init(
        root: CatalogRoot,
        discoveredSourceCount: Int,
        scannedSourceCount: Int,
        reusedSourceCount: Int,
        trackCount: Int,
        failures: [ScanFailure],
        skipped: [ScanSkippedFile] = [],
        telemetry: ScanPhaseTelemetry = .empty
    ) {
        self.root = root
        self.discoveredSourceCount = discoveredSourceCount
        self.scannedSourceCount = scannedSourceCount
        self.reusedSourceCount = reusedSourceCount
        self.trackCount = trackCount
        self.failures = failures
        self.skipped = skipped
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
    private let archiveExtractionScheduler: ScanResourceScheduler
    private let archivePipelineLimit: Int
    private let ignoredFileExtensions: Set<String>

    public init(
        databaseURL: URL,
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        handlers: ScanPluginHandlerRegistry = BuiltInFormatInspectors.registry,
        archiveExtractor: StandaloneArchiveExtractor = StandaloneArchiveExtractor(),
        inspectionPermits: Int = 8,
        archivePipelineLimit: Int = 4,
        ignoredFileExtensions: Set<String> = ScannerFormatPolicy.defaultIgnoredExtensions
    ) throws {
        writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
        self.registry = registry
        self.handlers = handlers
        self.archiveExtractor = archiveExtractor
        inspectionScheduler = ScanResourceScheduler(permits: inspectionPermits)
        // Extraction holds a payload on disk for the duration of member
        // inspection. Keep this at one archive at a time so the per-archive
        // expansion ceiling cannot multiply across the pipeline.
        archiveExtractionScheduler = ScanResourceScheduler(permits: 1)
        self.archivePipelineLimit = max(1, archivePipelineLimit)
        self.ignoredFileExtensions = Set(ignoredFileExtensions.map(ScannerFormatPolicy.normalize))
    }

    public func scan(
        rootURL: URL,
        mode: ScanMode = .incremental,
        discoveryReport: ScanDiscoveryReport? = nil,
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
        var skipped: [ScanSkippedFile] = []
        var discovered = 0
        let timeline = ScanPhaseTimeline()
        let monotonicProgress = MonotonicScanProgress(completed: 0)

        func emit(_ phase: ScanLifecyclePhase, currentPath: String? = nil) {
            let visibleProcessed = monotonicProgress.advance(to: processed)
            progress?(CatalogScanProgress(
                phase: phase,
                rootPath: root.path,
                currentPath: currentPath,
                discovered: discovered,
                processed: visibleProcessed,
                successful: max(0, visibleProcessed - failures.count),
                failed: failures.count,
                phaseCompleted: visibleProcessed,
                phaseTotal: discovered
            ))
        }

        do {
            timeline.enter(.discovery)
            emit(.discovery)
            let discovery: ScanDiscoveryReport
            if let discoveryReport {
                discovery = discoveryReport
            } else {
                discovery = try await ScanFilesystemDiscovery.discoverReport(
                    rootID: root.id,
                    rootURL: rootURL,
                    registry: registry,
                    isArchive: StandaloneArchiveExtractor.isSupportedArchive,
                    ignoredFileExtensions: ignoredFileExtensions
                )
            }
            let candidates = discovery.candidates
            skipped.append(contentsOf: discovery.skipped)
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
            let inspectionProcessed = processed
            let inspectionFailed = failures.count
            let outcomes = try await inspectPending(
                pending,
                pipelineLimit: archivePipelineLimit,
                dependencySearchRoot: rootURL,
                progress: { [progress, rootPath = root.path, discovered, inspectionProcessed, inspectionFailed] phase, currentPath, detail, phaseCompleted, _ in
                    let globalPhaseCompleted = phaseCompleted.map {
                        min(discovered, inspectionProcessed + $0)
                    }
                    let visibleProcessed = monotonicProgress.advance(
                        to: globalPhaseCompleted ?? inspectionProcessed
                    )
                    progress?(CatalogScanProgress(
                        phase: phase,
                        rootPath: rootPath,
                        currentPath: currentPath,
                        discovered: discovered,
                        processed: visibleProcessed,
                        successful: max(0, visibleProcessed - inspectionFailed),
                        failed: inspectionFailed,
                        detail: detail,
                        phaseCompleted: globalPhaseCompleted,
                        phaseTotal: phaseCompleted == nil ? nil : discovered
                    ))
                }
            )
            for candidate in pending {
                try Task.checkCancellation()
                switch outcomes[candidate.identity.path] {
                case .success(let inspection):
                    try writer.checkpoint(
                        stageID: stageID,
                        rootPath: root.path,
                        sourcePath: candidate.identity.path,
                        fingerprint: candidate.fingerprint,
                        records: inspection.records,
                        failures: inspection.failures
                    )
                    tracks += inspection.records.count
                    failures.append(contentsOf: inspection.failures)
                    skipped.append(contentsOf: inspection.skipped)
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
                case .cancelled:
                    throw CancellationError()
                case nil:
                    throw CancellationError()
                }
                processed += 1
                emit(.persistence, currentPath: candidate.identityDescription)
            }

            timeline.enter(.publication)
            emit(.publication)
            let publicationDiscovered = discovered
            let publicationProcessed = processed
            let publicationFailed = failures.count
            try writer.publish(stageID: stageID, targetRootID: root.id) { completed, total, detail in
                progress?(CatalogScanProgress(
                    phase: .publication,
                    rootPath: root.path,
                    currentPath: nil,
                    discovered: publicationDiscovered,
                    processed: monotonicProgress.advance(to: publicationProcessed),
                    successful: max(0, publicationProcessed - publicationFailed),
                    failed: publicationFailed,
                    detail: detail,
                    phaseCompleted: completed,
                    phaseTotal: total
                ))
            }
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
                skipped: skipped,
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

    /// Scans several roots as one operation. Discovery is completed once for
    /// every root before source inspection begins, which gives callers one
    /// stable source/archive total instead of a denominator that changes as
    /// sequential roots are introduced.
    public func scan(
        rootURLs: [URL],
        mode: ScanMode = .incremental,
        progress: ProgressHandler? = nil
    ) async throws -> [CatalogScanResult] {
        guard !rootURLs.isEmpty else { return [] }

        struct PreparedRoot: Sendable {
            let url: URL
            let discovery: ScanDiscoveryReport
        }

        var prepared: [PreparedRoot] = []
        var discoveredSoFar = 0
        for rootURL in rootURLs {
            try Task.checkCancellation()
            let canonicalURL = CanonicalFileURL.resolve(rootURL)
            let root = try writer.addRoot(path: canonicalURL.path)
            let discovery = try await ScanFilesystemDiscovery.discoverReport(
                rootID: root.id,
                rootURL: canonicalURL,
                registry: registry,
                isArchive: StandaloneArchiveExtractor.isSupportedArchive,
                ignoredFileExtensions: ignoredFileExtensions
            )
            prepared.append(PreparedRoot(url: canonicalURL, discovery: discovery))
            discoveredSoFar += discovery.candidates.count
            progress?(CatalogScanProgress(
                phase: .discovery,
                rootPath: canonicalURL.path,
                currentPath: nil,
                discovered: discoveredSoFar,
                processed: 0,
                successful: 0,
                failed: 0,
                detail: "Counted \(discoveredSoFar) sources…"
            ))
        }

        let total = prepared.reduce(0) { $0 + $1.discovery.candidates.count }
        progress?(CatalogScanProgress(
            phase: .planning,
            rootPath: prepared.first?.url.path ?? "",
            currentPath: nil,
            discovered: total,
            processed: 0,
            successful: 0,
            failed: 0,
            detail: "Discovered \(total) sources across \(prepared.count) roots",
            phaseCompleted: 0,
            phaseTotal: total
        ))

        var results: [CatalogScanResult] = []
        var processedOffset = 0
        var failureOffset = 0
        for item in prepared {
            try Task.checkCancellation()
            let currentProcessedOffset = processedOffset
            let currentFailureOffset = failureOffset
            let result = try await scan(
                rootURL: item.url,
                mode: mode,
                discoveryReport: item.discovery
            ) { update in
                let globalProcessed = min(total, currentProcessedOffset + update.processed)
                let globalSuccessful = currentProcessedOffset + update.successful
                let globalFailed = currentFailureOffset + update.failed
                let sourcePhaseProgress = update.phase == .publication
                    ? (update.phaseCompleted, update.phaseTotal)
                    : (update.phaseCompleted.map { currentProcessedOffset + $0 }, update.phaseCompleted == nil ? nil : total)
                progress?(CatalogScanProgress(
                    phase: update.phase,
                    rootPath: update.rootPath,
                    currentPath: update.currentPath,
                    discovered: total,
                    processed: globalProcessed,
                    successful: globalSuccessful,
                    failed: globalFailed,
                    detail: update.detail,
                    phaseCompleted: sourcePhaseProgress.0,
                    phaseTotal: sourcePhaseProgress.1
                ))
            }
            results.append(result)
            processedOffset += result.discoveredSourceCount
            failureOffset += result.failures.count
        }
        return results
    }

    private struct CandidateInspection: Sendable {
        let records: [CatalogTrackRecord]
        let failures: [ScanFailure]
        let skipped: [ScanSkippedFile]
    }

    private enum CandidateInspectionOutcome: Sendable {
        case success(CandidateInspection)
        case failure(String)
        case cancelled
    }

    private func inspectPending(
        _ pending: [ScanCandidate],
        pipelineLimit: Int,
        dependencySearchRoot: URL,
        progress: @escaping @Sendable (ScanLifecyclePhase, String?, String?, Int?, Int?) -> Void
    ) async throws -> [String: CandidateInspectionOutcome] {
        var outcomes: [String: CandidateInspectionOutcome] = [:]
        if pending.isEmpty { return outcomes }
        try await withThrowingTaskGroup(of: (String, CandidateInspectionOutcome).self) { group in
            var next = 0
            var inFlight = 0
            var completed = 0
            while next < pending.count || inFlight > 0 {
                while next < pending.count && inFlight < pipelineLimit {
                    let candidate = pending[next]
                    next += 1
                    inFlight += 1
                    group.addTask {
                        let outcome = await self.inspectCandidate(
                            candidate,
                            dependencySearchRoot: dependencySearchRoot,
                            progress: progress
                        )
                        return (candidate.identity.path, outcome)
                    }
                }
                if let (path, outcome) = try await group.next() {
                    inFlight -= 1
                    outcomes[path] = outcome
                    completed += 1
                    progress(.inspection, path, "Inspected source \(completed) of \(pending.count)…", completed, pending.count)
                }
            }
        }
        return outcomes
    }

    private func inspectCandidate(
        _ candidate: ScanCandidate,
        dependencySearchRoot: URL,
        progress: @escaping @Sendable (ScanLifecyclePhase, String?, String?, Int?, Int?) -> Void
    ) async -> CandidateInspectionOutcome {
        do {
            try Task.checkCancellation()
            let inspection: CandidateInspection
            if StandaloneArchiveExtractor.isSupportedArchive(candidate.sourceURL) {
                inspection = try await archiveExtractionScheduler.withPermit {
                    progress(.archiveListing, candidate.identityDescription, "Extracting \(candidate.sourceURL.lastPathComponent)…", nil, nil)
                    return try await self.inspectArchive(
                        candidate,
                        dependencySearchRoot: dependencySearchRoot,
                        progress: progress
                    )
                }
            } else {
                let records = try await inspectLoose(candidate)
                guard !records.isEmpty else {
                    throw ScannerInspectionError.malformedFile(
                        "No supported playable tracks were found in \(candidate.sourceURL.lastPathComponent)."
                    )
                }
                inspection = CandidateInspection(records: records, failures: [], skipped: [])
            }
            // An archive containing only explicitly ignored members is a
            // successful no-op. Routed corrupt members are returned as
            // failures below and are never silently discarded.
            return .success(inspection)
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

    private func inspectArchive(
        _ candidate: ScanCandidate,
        dependencySearchRoot: URL,
        progress: @escaping @Sendable (ScanLifecyclePhase, String?, String?, Int?, Int?) -> Void
    ) async throws -> CandidateInspection {
        let archive = try await archiveExtractor.extractForScan(
            archiveURL: candidate.sourceURL,
            registry: registry,
            ignoredFileExtensions: ignoredFileExtensions,
            dependencySearchRoot: dependencySearchRoot
        )
        defer { archiveExtractor.discard(archive) }
        progress(.materialization, candidate.identityDescription, "Materialized \(archive.members.count) playable members", nil, nil)

        // Inspect members concurrently under a bounded permit pool. Subprocess
        // adapters (vgmstream, Highly Complete) dominate wall time; bounding
        // the pool keeps memory and process count predictable while preserving
        // deterministic record order via per-index collection.
        let members = archive.members
        var inspections: [ScanInspection?] = Array(repeating: nil, count: members.count)
        var memberFailures: [String?] = Array(repeating: nil, count: members.count)
        try await withThrowingTaskGroup(of: (Int, ScanInspection?, String?).self) { group in
            for (index, member) in members.enumerated() {
                try Task.checkCancellation()
                group.addTask {
                    progress(
                        .inspection,
                        "\(candidate.identity.path)#\(member.entryPath)",
                        "Inspecting member \(index + 1)/\(members.count)…",
                        nil,
                        nil
                    )
                    do {
                        let inspection = try await self.inspectionScheduler.withPermit {
                            try await self.inspect(fileURL: member.fileURL, route: member.route)
                        }
                        return (index, inspection, nil)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (index, nil, error.localizedDescription)
                    }
                }
            }
            for try await (index, inspection, failure) in group {
                inspections[index] = inspection
                memberFailures[index] = failure
            }
        }

        var records: [CatalogTrackRecord] = []
        var failures: [ScanFailure] = []
        let skipped = archive.skippedMembers.map {
            ScanSkippedFile(
                identity: ScanItemIdentity(
                    rootID: candidate.identity.rootID,
                    path: candidate.identity.path,
                    archiveEntry: $0.entryPath
                ),
                extensionName: $0.extensionName,
                reason: $0.reason
            )
        }
        for (index, member) in members.enumerated() {
            try Task.checkCancellation()
            if let inspection = inspections[index] {
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
            } else if let message = memberFailures[index] {
                failures.append(ScanFailure(
                    identity: ScanItemIdentity(
                        rootID: candidate.identity.rootID,
                        path: candidate.identity.path,
                        archiveEntry: member.entryPath
                    ),
                    fingerprint: member.fingerprint,
                    route: member.route,
                    stage: .metadata,
                    message: message
                ))
            }
        }
        return CandidateInspection(records: records, failures: failures, skipped: skipped)
    }

    private func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        guard let handler = handlers.handler(for: route) else {
            throw ScannerInspectionError.unsupportedRoute(route.pluginID)
        }
        return try await handler.inspect(fileURL: fileURL, route: route)
    }
}
