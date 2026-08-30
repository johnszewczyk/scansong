import Foundation

public struct ScannerMetadata: Codable, Equatable, Sendable {
    public let game: String
    public let song: String
    public let system: String
    public let author: String
    public let comment: String
    public let introLengthMs: Int
    public let loopLengthMs: Int
    public let playLengthMs: Int
    public let fadeLengthMs: Int

    public init(
        game: String,
        song: String,
        system: String,
        author: String,
        comment: String,
        introLengthMs: Int,
        loopLengthMs: Int,
        playLengthMs: Int,
        fadeLengthMs: Int
    ) {
        self.game = game
        self.song = song
        self.system = system
        self.author = author
        self.comment = comment
        self.introLengthMs = introLengthMs
        self.loopLengthMs = loopLengthMs
        self.playLengthMs = playLengthMs
        self.fadeLengthMs = fadeLengthMs
    }
}

public struct ScanCandidate: Hashable, Sendable {
    public let identity: ScanItemIdentity
    public let fingerprint: ScanFingerprint
    public let sourceURL: URL
    public let route: ScannerRoute?

    public init(
        identity: ScanItemIdentity,
        fingerprint: ScanFingerprint,
        sourceURL: URL,
        route: ScannerRoute?
    ) {
        self.identity = identity
        self.fingerprint = fingerprint
        self.sourceURL = sourceURL
        self.route = route
    }

    public var isArchiveMember: Bool { identity.archiveEntry != nil }

    public var identityDescription: String {
        identity.archiveEntry.map { "\(identity.path)#\($0)" } ?? identity.path
    }
}

public enum ScanSkipReason: String, Codable, Sendable, Hashable {
    case explicitlyIgnored = "explicitIgnore"
    case unsupportedFormat = "unsupportedFormat"
}

public struct ScanSkippedFile: Sendable, Equatable {
    public let identity: ScanItemIdentity
    public let extensionName: String
    public let reason: ScanSkipReason

    public init(identity: ScanItemIdentity, extensionName: String, reason: ScanSkipReason) {
        self.identity = identity
        self.extensionName = extensionName
        self.reason = reason
    }

    public var identityDescription: String {
        identity.archiveEntry.map { "\(identity.path)#\($0)" } ?? identity.path
    }
}

public struct ScanDiscoveryReport: Sendable {
    public let candidates: [ScanCandidate]
    public let skipped: [ScanSkippedFile]

    public init(candidates: [ScanCandidate], skipped: [ScanSkippedFile]) {
        self.candidates = candidates
        self.skipped = skipped
    }
}

public struct ScanArchiveMember: Hashable, Sendable {
    public let archiveURL: URL
    public let entryPath: String
    public let fingerprint: ScanFingerprint
    public let route: ScannerRoute?

    public init(
        archiveURL: URL,
        entryPath: String,
        fingerprint: ScanFingerprint,
        route: ScannerRoute?
    ) {
        self.archiveURL = archiveURL
        self.entryPath = entryPath
        self.fingerprint = fingerprint
        self.route = route
    }

    public var identityDescription: String { "\(archiveURL.path)#\(entryPath)" }
}

public struct ScanArchiveListing: Sendable {
    public let members: [ScanArchiveMember]
    public let scanSignature: String?

    public init(members: [ScanArchiveMember], scanSignature: String?) {
        self.members = members
        self.scanSignature = scanSignature
    }
}

public struct ScanTrackMetadata: Sendable {
    public let trackIndex: Int
    public let trackCount: Int
    public let metadata: ScannerMetadata?

    public init(trackIndex: Int, trackCount: Int, metadata: ScannerMetadata?) {
        self.trackIndex = trackIndex
        self.trackCount = trackCount
        self.metadata = metadata
    }
}

public struct ScanInspection: Sendable {
    public let route: ScannerRoute
    public let tracks: [ScanTrackMetadata]

    public init(route: ScannerRoute, tracks: [ScanTrackMetadata]) {
        self.route = route
        self.tracks = tracks
    }
}

public enum ScanFailureStage: String, Codable, Sendable {
    case discovery
    case archiveListing
    case archiveExtraction
    case routing
    case metadata
    case persistence
}

public struct ScanFailure: Sendable {
    public let identity: ScanItemIdentity
    public let fingerprint: ScanFingerprint
    public let route: ScannerRoute?
    public let stage: ScanFailureStage
    public let message: String

    public init(
        identity: ScanItemIdentity,
        fingerprint: ScanFingerprint,
        route: ScannerRoute?,
        stage: ScanFailureStage,
        message: String
    ) {
        self.identity = identity
        self.fingerprint = fingerprint
        self.route = route
        self.stage = stage
        self.message = ScanDiagnosticSanitizer.sanitize(message)
    }
}

public enum ScanPipelineResult: Sendable {
    case success(ScanCandidate, ScanInspection)
    case archiveCompleted(ScanCandidate)
    case unsupported(ScanCandidate)
    case failure(ScanFailure)

    public func persistenceFailure(message: String) -> ScanPipelineResult {
        let failure: ScanFailure
        switch self {
        case .success(let candidate, _), .unsupported(let candidate), .archiveCompleted(let candidate):
            failure = ScanFailure(
                identity: candidate.identity,
                fingerprint: candidate.fingerprint,
                route: candidate.route,
                stage: .persistence,
                message: message
            )
        case .failure(let existing):
            failure = ScanFailure(
                identity: existing.identity,
                fingerprint: existing.fingerprint,
                route: existing.route,
                stage: .persistence,
                message: message
            )
        }
        return .failure(failure)
    }
}

public protocol ScanArchiveProvider: Sendable {
    func listMembers(in archiveURL: URL, supportedExtensions: Set<String>) async throws -> ScanArchiveListing
    func materialize(archiveURL: URL, entryPath: String) async throws -> URL
    func materializeEntries(archiveURL: URL, entryPaths: [String]) async throws -> URL
    func materializeArchive(at archiveURL: URL) async throws -> URL
    func materializeEntriesForScan(archiveURL: URL, entryPaths: [String]) async throws -> URL
    func materializeArchiveForScan(at archiveURL: URL) async throws -> URL
    func discardScanMaterialization(at rootURL: URL) async
}

public extension ScanArchiveProvider {
    func materializeEntriesForScan(archiveURL: URL, entryPaths: [String]) async throws -> URL {
        try await materializeEntries(archiveURL: archiveURL, entryPaths: entryPaths)
    }

    func materializeArchiveForScan(at archiveURL: URL) async throws -> URL {
        try await materializeArchive(at: archiveURL)
    }

    func discardScanMaterialization(at rootURL: URL) async {}
}

public protocol ScanFormatHandler: Sendable {
    var descriptor: ScannerPluginDescriptor { get }
    func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection
}

public struct ScanPluginHandlerRegistry: Sendable {
    private let handlers: [String: any ScanFormatHandler]

    public init(handlers: [any ScanFormatHandler]) {
        self.handlers = Dictionary(
            handlers.map { ($0.descriptor.pluginID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func handler(for route: ScannerRoute) -> (any ScanFormatHandler)? {
        handlers[route.pluginID]
    }
}

public protocol ScanResultSink: Sendable {
    func accept(_ result: ScanPipelineResult) async throws
}

public enum ScanLifecyclePhase: String, CaseIterable, Codable, Sendable {
    case preparing
    case discovery
    case planning
    case archiveListing
    case materialization
    case inspection
    case persistence
    case publication
    case cleanup

    public static func infer(from status: String) -> ScanLifecyclePhase? {
        if status.hasPrefix("Starting") || status.hasPrefix("Preparing") { return .preparing }
        if status.hasPrefix("Discovering") { return .discovery }
        if status.hasPrefix("Discovered") || status.hasPrefix("Planned") { return .planning }
        if status.hasPrefix("Scanning") { return .inspection }
        if status.hasPrefix("Publishing") { return .publication }
        return nil
    }
}

public struct ScanActivity: Sendable {
    public let phase: ScanLifecyclePhase
    public let sourcePath: String
    public let filename: String
    public let detail: String

    public init(
        candidate: ScanCandidate,
        phase: ScanLifecyclePhase = .inspection,
        detail: String
    ) {
        self.phase = phase
        if let entryPath = candidate.identity.archiveEntry {
            sourcePath = "\(candidate.sourceURL.path)#\(entryPath)"
            filename = URL(fileURLWithPath: entryPath).lastPathComponent
        } else {
            sourcePath = candidate.sourceURL.path
            filename = candidate.sourceURL.lastPathComponent
        }
        self.detail = detail
    }
}

public enum ScanPipelineError: LocalizedError {
    case operationTimedOut(String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .operationTimedOut(let description, let seconds):
            return "Timed out after \(seconds) seconds: \(description)"
        }
    }
}

public enum ScanOperationTimeout {
    public enum Kind: Sendable {
        case archiveListing
        case archiveExtraction
        case metadataInspection

        public var seconds: Int {
            switch self {
            case .archiveListing: return 30
            case .archiveExtraction: return 600
            case .metadataInspection: return 60
            }
        }
    }

    public static func run<T: Sendable>(
        kind: Kind = .metadataInspection,
        description: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(kind.seconds))
                throw ScanPipelineError.operationTimedOut(description, seconds: kind.seconds)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

public struct ScanPhaseTelemetry: Codable, Sendable {
    public let elapsedMilliseconds: Int
    public let phaseMilliseconds: [ScanLifecyclePhase: Int]

    public init(elapsedMilliseconds: Int, phaseMilliseconds: [ScanLifecyclePhase: Int]) {
        self.elapsedMilliseconds = elapsedMilliseconds
        self.phaseMilliseconds = phaseMilliseconds
    }

    public static let empty = ScanPhaseTelemetry(elapsedMilliseconds: 0, phaseMilliseconds: [:])
}

public final class ScanPhaseTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private let startedAt = Date()
    private var currentPhase: ScanLifecyclePhase?
    private var phaseStartedAt = Date()
    private var durations: [ScanLifecyclePhase: TimeInterval] = [:]

    public init() {}

    public func enter(_ phase: ScanLifecyclePhase) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let currentPhase, currentPhase != phase {
            durations[currentPhase, default: 0] += now.timeIntervalSince(phaseStartedAt)
            phaseStartedAt = now
        } else if currentPhase == nil {
            phaseStartedAt = now
        }
        currentPhase = phase
    }

    public func snapshot() -> ScanPhaseTelemetry {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        var completedDurations = durations
        if let currentPhase {
            completedDurations[currentPhase, default: 0] += now.timeIntervalSince(phaseStartedAt)
        }
        return ScanPhaseTelemetry(
            elapsedMilliseconds: Int((now.timeIntervalSince(startedAt) * 1_000).rounded()),
            phaseMilliseconds: completedDurations.mapValues { Int(($0 * 1_000).rounded()) }
        )
    }
}

public struct ScanSummary: Sendable {
    public let discovered: Int
    public let completed: Int
    public let successful: Int
    public let failed: Int
    public let unsupported: Int
    public let cancelled: Int
    public let failures: [ScanFailure]
    public let telemetry: ScanPhaseTelemetry

    public init(
        discovered: Int,
        completed: Int,
        successful: Int,
        failed: Int,
        unsupported: Int,
        cancelled: Int,
        failures: [ScanFailure],
        telemetry: ScanPhaseTelemetry = .empty
    ) {
        self.discovered = discovered
        self.completed = completed
        self.successful = successful
        self.failed = failed
        self.unsupported = unsupported
        self.cancelled = cancelled
        self.failures = failures
        self.telemetry = telemetry
    }
}

public actor ScanResultAccumulator: ScanResultSink {
    private var discoveredCount = 0
    private var completedCount = 0
    private var successfulCount = 0
    private var failedCount = 0
    private var unsupportedCount = 0
    private var cancelledCount = 0
    private var failureValues: [ScanFailure] = []
    private var resultValues: [ScanPipelineResult] = []

    public init(discovered: Int = 0) { discoveredCount = discovered }

    public func accept(_ result: ScanPipelineResult) async throws {
        resultValues.append(result)
        switch result {
        case .success:
            completedCount += 1
            successfulCount += 1
        case .archiveCompleted:
            break
        case .unsupported:
            completedCount += 1
            unsupportedCount += 1
        case .failure(let failure):
            completedCount += 1
            if failure.message == "Cancelled" {
                cancelledCount += 1
            } else {
                failedCount += 1
                failureValues.append(failure)
            }
        }
    }

    public var summary: ScanSummary {
        ScanSummary(
            discovered: discoveredCount,
            completed: completedCount,
            successful: successfulCount,
            failed: failedCount,
            unsupported: unsupportedCount,
            cancelled: cancelledCount,
            failures: failureValues
        )
    }

    public var results: [ScanPipelineResult] { resultValues }
}

public enum ScanFilesystemDiscovery {
    public static func discover(
        rootID: Int64,
        rootURL: URL,
        registry: ScannerPluginRegistry,
        isArchive: @escaping @Sendable (URL) -> Bool,
        ignoredFileExtensions: Set<String> = []
    ) async throws -> [ScanCandidate] {
        try await discoverReport(
            rootID: rootID,
            rootURL: rootURL,
            registry: registry,
            isArchive: isArchive,
            ignoredFileExtensions: ignoredFileExtensions
        ).candidates
    }

    public static func discoverReport(
        rootID: Int64,
        rootURL: URL,
        registry: ScannerPluginRegistry,
        isArchive: @escaping @Sendable (URL) -> Bool,
        ignoredFileExtensions: Set<String> = []
    ) async throws -> ScanDiscoveryReport {
        let task = Task.detached(priority: .utility) {
            var candidates: [ScanCandidate] = []
            var skipped: [ScanSkippedFile] = []
            try walk(
                rootID: rootID,
                folderURL: rootURL.standardizedFileURL,
                registry: registry,
                isArchive: isArchive,
                ignoredFileExtensions: ignoredFileExtensions,
                candidates: &candidates,
                skipped: &skipped
            )
            try Task.checkCancellation()
            candidates.sort { $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending }
            skipped.sort { $0.identityDescription.localizedStandardCompare($1.identityDescription) == .orderedAscending }
            return ScanDiscoveryReport(candidates: candidates, skipped: skipped)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func walk(
        rootID: Int64,
        folderURL: URL,
        registry: ScannerPluginRegistry,
        isArchive: @Sendable (URL) -> Bool,
        ignoredFileExtensions: Set<String>,
        candidates: inout [ScanCandidate],
        skipped: inout [ScanSkippedFile]
    ) throws {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let extensionName = ScannerFormatPolicy.normalize(child.pathExtension)
            let identity = ScanItemIdentity(rootID: rootID, path: child.path, archiveEntry: nil)
            if ignoredFileExtensions.contains(extensionName) {
                skipped.append(ScanSkippedFile(identity: identity, extensionName: extensionName, reason: .explicitlyIgnored))
                continue
            }
            // A standalone compressed PDX is a companion bank for a nearby
            // MDX, not an archive or playable source in its own right. It is
            // decompressed on demand when the owning MDX is inspected.
            if StandaloneArchiveExtractor.isStandaloneSupportFile(child) {
                continue
            }
            let route = registry.route(forPath: child.path)
            guard isArchive(child) || route != nil else { continue }
            candidates.append(ScanCandidate(
                identity: identity,
                fingerprint: ScanFingerprint(
                    fileSize: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                ),
                sourceURL: child,
                route: route
            ))
        }
    }
}
