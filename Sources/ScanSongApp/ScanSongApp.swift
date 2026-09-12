import AppKit
import Darwin
import Foundation
import ScanSongKit
import SwiftUI
import UniformTypeIdentifiers

private enum ScanOutcome: Sendable {
    case success([CatalogScanResult])
    case cancelled
    case failure(String)
}

private enum MaintenanceOutcome: Sendable {
    case checked(CatalogLinkTestResult)
    case cleaned(Int)
    case failure(String)
}

private enum PathAdditionOutcome: Sendable {
    case success
    case failure(String)
}

@MainActor
final class ScannerAppModel: ObservableObject {
    private static let catalogPathKey = "ScanSong.catalogPath"
    private static let ignoredFileTypesKey = "ScanSong.ignoredFileTypes"
    private static let cocoaSpiceDefaultsSuite = "com.local.cocoaspice"
    private static let cocoaSpiceCatalogPathKey = "CocoaSpice.libraryDatabasePath"

    @Published var databaseURL: URL
    @Published var catalogStatus = "Choose or create a canonical catalog."
    @Published var roots: [CatalogRoot] = []
    @Published var rootTallies: [Int64: CatalogScanTally] = [:]
    @Published var scanStatus = "Add one or more scan paths."
    @Published var currentPath: String?
    @Published var currentFile: String?
    @Published var operationProgress: ScannerOperationProgress?
    @Published private(set) var completedOperation: ScannerOperationTelemetry?
    @Published var isScanning = false
    @Published var isMaintaining = false
    @Published var deepScan = false
    @Published var showsResetPathsConfirmation = false
    @Published var showsResetCatalogConfirmation = false
    @Published var showsDeleteCatalogConfirmation = false
    @Published var showsCleanLinksConfirmation = false
    @Published private(set) var ignoredFileExtensions: Set<String>

    private var scanTask: Task<Void, Never>?
    private var worker: Task<ScanOutcome, Never>?
    private var pathTask: Task<PathAdditionOutcome, Never>?
    private var pathObserverTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var maintenanceWorker: Task<MaintenanceOutcome, Never>?
    private var activeRootID: Int64?
    private var operationStartedAt: Date?
    private var logWindows: [Int64: ScannerScanLogWindow] = [:]
    private var closeWhenIdle: (() -> Void)?

    init() {
        if let storedPath = UserDefaults.standard.string(forKey: Self.catalogPathKey),
           (storedPath as NSString).isAbsolutePath {
            databaseURL = URL(fileURLWithPath: storedPath).standardizedFileURL
        } else {
            databaseURL = Self.defaultCatalogURL()
        }
        let knownExtensions = Set(ScannerFormatPolicy.knownUnsupportedFileTypes.map(\.id))
        let storedExtensions = UserDefaults.standard.stringArray(forKey: Self.ignoredFileTypesKey) ?? []
        ignoredFileExtensions = Set(storedExtensions.map(ScannerFormatPolicy.normalize)).intersection(knownExtensions)
        if storedExtensions.isEmpty {
            ignoredFileExtensions = ScannerFormatPolicy.defaultIgnoredExtensions
        }
        validateCatalog()
    }

    deinit {
        scanTask?.cancel()
        worker?.cancel()
        pathObserverTask?.cancel()
        pathTask?.cancel()
        maintenanceTask?.cancel()
        maintenanceWorker?.cancel()
    }

    var isBusy: Bool { isScanning || isMaintaining }
    var canScanAll: Bool { !isBusy && roots.contains(where: \.isEnabled) }
    var hasInactiveLinks: Bool { roots.contains(where: { $0.deadSourceCount > 0 }) }
    var hasDatabaseFile: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }
    var fileTypePolicies: [ScannerFileTypePolicy] { ScannerFormatPolicy.knownUnsupportedFileTypes }

    var databaseFileDisplayPath: String {
        hasDatabaseFile ? databaseURL.path : "(None)"
    }

    func isFileTypeIgnored(_ policy: ScannerFileTypePolicy) -> Bool {
        ignoredFileExtensions.contains(policy.id)
    }

    func setFileTypeIgnored(_ extensionName: String, ignored: Bool) {
        guard !isBusy else { return }
        let normalized = ScannerFormatPolicy.normalize(extensionName)
        guard fileTypePolicies.contains(where: { $0.id == normalized }) else { return }
        if ignored {
            ignoredFileExtensions.insert(normalized)
        } else {
            ignoredFileExtensions.remove(normalized)
        }
        UserDefaults.standard.set(Array(ignoredFileExtensions).sorted(), forKey: Self.ignoredFileTypesKey)
    }

    var progressFraction: Double? {
        operationProgress?.fraction
    }

    func chooseCatalog() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Media Catalog"
        panel.prompt = "Choose Catalog"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.database]
        panel.directoryURL = databaseURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        setCatalog(selected)
    }

    func addNewCatalog() {
        guard !isBusy else { return }
        let panel = NSSavePanel()
        panel.title = "Add New Media Catalog"
        panel.prompt = "Add New"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.database]
        panel.nameFieldStringValue = "Library.sqlite"
        panel.directoryURL = databaseURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let selected = panel.url else { return }

        let candidate = selected.standardizedFileURL
        guard !FileManager.default.fileExists(atPath: candidate.path) else {
            catalogStatus = "A database already exists at that path. Choose a new file name."
            return
        }

        do {
            // CanonicalCatalogWriter creates the schema-23 file immediately;
            // ScanSong becomes responsible for it only after that succeeds.
            _ = try CanonicalCatalogWriter(databaseURL: candidate)
            setCatalog(candidate)
            scanStatus = "Add one or more scan paths."
        } catch {
            record(error, stage: "database.create")
        }
    }

    func useDefaultCatalog() {
        guard !isBusy else { return }
        setCatalog(Self.defaultCatalogURL())
    }

    func resetCatalog() {
        guard !isBusy, hasDatabaseFile else { return }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            try writer.resetCatalog()
            ScannerScanLogStore.discardAll(databaseURL: databaseURL)
            logWindows.values.forEach { $0.close() }
            logWindows.removeAll()
            validateCatalog()
            scanStatus = "Database reset. Add one or more scan paths."
        } catch {
            record(error, stage: "database.reset")
        }
    }

    func deleteCatalogFile() {
        guard !isBusy, hasDatabaseFile else { return }
        do {
            let fileManager = FileManager.default
            try fileManager.removeItem(at: databaseURL)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if fileManager.fileExists(atPath: sidecar.path) {
                    try fileManager.removeItem(at: sidecar)
                }
            }
            ScannerScanLogStore.discardAll(databaseURL: databaseURL)
            logWindows.values.forEach { $0.close() }
            logWindows.removeAll()
            validateCatalog()
            scanStatus = "No database file selected. Use Default, Open, or Add New."
        } catch {
            record(error, stage: "database.delete")
        }
    }

    func addPaths() {
        let panel = NSOpenPanel()
        panel.title = "Add Scan Paths"
        panel.prompt = "Add Path"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func removePath(_ id: Int64) {
        guard !isBusy else { return }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            try writer.removeRoot(id: id)
            logWindows[id]?.close()
            logWindows[id] = nil
            try refreshRoots()
            scanStatus = roots.isEmpty ? "Add one or more scan paths." : readyText
            validateCatalog()
        } catch {
            record(error, stage: "paths.remove")
        }
    }

    func resetPaths() {
        guard !isBusy else { return }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            for root in roots { try writer.removeRoot(id: root.id) }
            logWindows.values.forEach { $0.close() }
            logWindows.removeAll()
            try refreshRoots()
            scanStatus = "Add one or more scan paths."
            validateCatalog()
        } catch {
            record(error, stage: "paths.reset")
        }
    }

    func setPathEnabled(_ id: Int64, enabled: Bool) {
        guard !isBusy else { return }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            try writer.setRootEnabled(id: id, enabled: enabled)
            try refreshRoots()
            scanStatus = readyText
        } catch {
            record(error, stage: "paths.enable")
        }
    }

    func toggleAllPathsEnabled() {
        guard !isBusy, !roots.isEmpty else { return }
        let enable = roots.contains(where: { !$0.isEnabled })
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            for root in roots { try writer.setRootEnabled(id: root.id, enabled: enable) }
            try refreshRoots()
            scanStatus = readyText
        } catch {
            record(error, stage: "paths.toggle-all")
        }
    }

    func scanPath(_ id: Int64) {
        startScan(roots: roots.filter { $0.id == id })
    }

    func scanAllPaths() {
        startScan(roots: roots.filter(\.isEnabled))
    }

    func checkLinks() {
        runMaintenance(kind: .checkLinks, starting: "Checking catalog links…") { writer, progress in
            .checked(try writer.testFiles(progress: progress))
        }
    }

    func cleanLinks() {
        runMaintenance(kind: .removeLinks, starting: "Removing inactive catalog links…") { writer, progress in
            .cleaned(try writer.clearDeadLinks(progress: progress))
        }
    }

    func showScanLog(_ id: Int64) {
        if let window = logWindows[id] {
            window.show()
            return
        }
        guard let root = roots.first(where: { $0.id == id }) else { return }
        let tally = rootTallies[id] ?? emptyTally
        let window = ScannerScanLogWindow(
            root: root,
            summary: ScannerScanLogStore.summary(root: root, tally: tally),
            lines: ScannerScanLogStore.read(databaseURL: databaseURL, rootID: id)
        )
        logWindows[id] = window
        window.show()
    }

    func hasScanLog(_ id: Int64) -> Bool {
        ScannerScanLogStore.exists(databaseURL: databaseURL, rootID: id)
            || roots.first(where: { $0.id == id })?.lastScanStartedAt != nil
    }

    func cancelScan() {
        guard isScanning else { return }
        scanStatus = "Cancelling and retaining completed checkpoints…"
        worker?.cancel()
    }

    /// A window close must never tear down a scan halfway through an archive or
    /// publication transaction. Scans cancel cooperatively; maintenance is
    /// allowed to finish its current SQLite operation before the window closes.
    func closeWhenWorkIsSafe(_ close: @escaping () -> Void) {
        guard isBusy else {
            close()
            return
        }
        closeWhenIdle = close
        if isScanning { cancelScan() }
    }

    func rootStatusText(_ root: CatalogRoot) -> String {
        let tally = rootTallies[root.id] ?? emptyTally
        if let error = root.lastScanError, !error.isEmpty {
            return "Last scan failed • \(error)"
        }
        guard let completedAt = root.lastScanCompletedAt else {
            return "Not scanned • \(tally.sourceCount) files"
        }
        let completed = DateFormatter.localizedString(from: completedAt, dateStyle: .medium, timeStyle: .short)
        let issues = tally.failedSourceCount + tally.inactiveSourceCount
        return "Last scan \(completed) • \(tally.sourceCount) files • \(root.lastScanTrackCount) tracks • \(issues) issue\(issues == 1 ? "" : "s")"
    }

    func rootStatusIsEmpty(_ root: CatalogRoot) -> Bool {
        root.lastScanCompletedAt != nil && root.lastScanTrackCount == 0
    }

    func rootStatusHasIssues(_ root: CatalogRoot) -> Bool {
        let tally = rootTallies[root.id] ?? emptyTally
        return root.lastScanError?.isEmpty == false || tally.failedSourceCount > 0 || tally.inactiveSourceCount > 0
    }

    func rootStatusIsClean(_ root: CatalogRoot) -> Bool {
        root.lastScanCompletedAt != nil && !rootStatusIsEmpty(root) && !rootStatusHasIssues(root)
    }

    func abbreviatedPath(for root: CatalogRoot) -> String {
        let paths = roots.map { URL(fileURLWithPath: $0.path).pathComponents }
        guard let first = paths.first else { return root.path }
        let sharedCount = paths.dropFirst().reduce(first.count) { count, path in
            zip(first.prefix(count), path.prefix(count)).prefix { $0 == $1 }.count
        }
        let components = URL(fileURLWithPath: root.path).pathComponents
        let suffix = Array(components.dropFirst(min(sharedCount, components.count)))
        let visible = suffix.isEmpty ? Array(components.suffix(2)) : suffix
        return visible.joined(separator: "/")
    }

    private var emptyTally: CatalogScanTally {
        CatalogScanTally(
            sourceCount: 0,
            activeSourceCount: 0,
            successfulSourceCount: 0,
            failedSourceCount: 0,
            inactiveSourceCount: 0
        )
    }

    private var readyText: String {
        let enabled = roots.filter(\.isEnabled).count
        return "Ready • \(roots.count) scan path\(roots.count == 1 ? "" : "s") • \(enabled) enabled"
    }

    private func setCatalog(_ url: URL) {
        databaseURL = url.standardizedFileURL
        UserDefaults.standard.set(databaseURL.path, forKey: Self.catalogPathKey)
        logWindows.values.forEach { $0.close() }
        logWindows.removeAll()
        validateCatalog()
    }

    private func validateCatalog() {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            catalogStatus = "New schema-23 catalog will be created when scanning starts."
            roots = []
            rootTallies = [:]
            scanStatus = "Add one or more scan paths."
            return
        }
        do {
            let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
            catalogStatus = "Schema \(summary.schemaVersion) • \(summary.rootCount) paths • \(summary.trackCount) tracks"
            try refreshRoots()
            if !isBusy && scanStatus.hasPrefix("Add one or more") && !roots.isEmpty {
                scanStatus = readyText
            }
        } catch {
            catalogStatus = "Cannot use catalog: \(error.localizedDescription)"
            roots = []
            rootTallies = [:]
        }
    }

    private func add(_ urls: [URL]) {
        guard !isBusy else { return }
        let canonical = Array(Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !canonical.isEmpty else { return }

        isMaintaining = true
        completedOperation = nil
        operationProgress = ScannerOperationProgress(
            operation: .addPath,
            phase: "adding",
            processed: 0,
            total: nil,
            failures: 0,
            detail: "Adding \(canonical.count) scan path\(canonical.count == 1 ? "" : "s")…"
        )
        scanStatus = "Adding \(canonical.count) scan path\(canonical.count == 1 ? "" : "s") to the catalog…"

        let databaseURL = databaseURL
        let worker = Task.detached(priority: .utility) {
            do {
                let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
                for url in canonical { _ = try writer.addRoot(path: url.path) }
                return PathAdditionOutcome.success
            } catch {
                return PathAdditionOutcome.failure(error.localizedDescription)
            }
        }
        pathTask = worker
        pathObserverTask = Task { [weak self] in
            let outcome = await worker.value
            guard let self else { return }
            pathTask = nil
            pathObserverTask = nil
            isMaintaining = false
            switch outcome {
            case .success:
                do {
                    try refreshRoots()
                    scanStatus = readyText
                    validateCatalog()
                } catch {
                    record(error, stage: "paths.add.refresh")
                }
            case .failure(let message):
                recordMaintenanceFailure(message)
            }
            operationProgress = nil
            completeRequestedCloseIfIdle()
        }
    }

    private func startScan(roots requestedRoots: [CatalogRoot]) {
        guard !isBusy, !requestedRoots.isEmpty else { return }
        let databaseURL = databaseURL
        let ignoredFileExtensions = ignoredFileExtensions
        let mode: ScanMode = deepScan ? .newScan : .incremental
        let progressBuffer = LatestValueBuffer<CatalogScanProgress>()
        isScanning = true
        operationProgress = nil
        completedOperation = nil
        operationStartedAt = Date()
        activeRootID = requestedRoots.first?.id
        currentPath = nil
        currentFile = nil
        scanStatus = "Preparing catalog…"

        let worker = Task.detached(priority: .utility) {
            defer { progressBuffer.finish() }
            do {
                let scanner = try CatalogScanner(
                    databaseURL: databaseURL,
                    ignoredFileExtensions: ignoredFileExtensions
                )
                let results = try await scanner.scan(
                    rootURLs: requestedRoots.map { URL(fileURLWithPath: $0.path) },
                    mode: mode
                ) {
                    progressBuffer.publish($0)
                }
                return ScanOutcome.success(results)
            } catch is CancellationError {
                return ScanOutcome.cancelled
            } catch {
                return ScanOutcome.failure(error.localizedDescription)
            }
        }
        self.worker = worker
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.sampleProgress(from: progressBuffer, apply: self.applyVisibleProgress)
            self.finish(await worker.value)
        }
    }

    private func refreshRoots() throws {
        let reader = try CanonicalCatalogReader(databaseURL: databaseURL)
        roots = try reader.roots()
        rootTallies = try Dictionary(
            uniqueKeysWithValues: roots.map { root in
                (root.id, try reader.scanTally(rootID: root.id))
            }
        )
    }

    private func runMaintenance(
        kind: ScannerOperationKind,
        starting activity: String,
        _ operation: @escaping @Sendable (CanonicalCatalogWriter, @escaping @Sendable (CatalogMaintenanceProgress) -> Void) throws -> MaintenanceOutcome
    ) {
        guard !isBusy else { return }
        isMaintaining = true
        operationStartedAt = Date()
        completedOperation = nil
        operationProgress = ScannerOperationProgress(
            operation: kind,
            phase: "preparing",
            processed: 0,
            total: nil,
            failures: 0,
            detail: activity
        )
        scanStatus = activity
        let databaseURL = databaseURL
        let progressBuffer = LatestValueBuffer<CatalogMaintenanceProgress>()
        let worker = Task.detached(priority: .utility) {
            defer { progressBuffer.finish() }
            do {
                let result = try operation(
                    CanonicalCatalogWriter(databaseURL: databaseURL),
                    { progressBuffer.publish($0) }
                )
                return result
            } catch {
                return MaintenanceOutcome.failure(error.localizedDescription)
            }
        }
        self.maintenanceWorker = worker
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await self.sampleProgress(from: progressBuffer, apply: self.applyMaintenanceProgress)
            let outcome = await worker.value
            maintenanceWorker = nil
            maintenanceTask = nil
            isMaintaining = false
            switch outcome {
            case .checked(let result):
                let missingDescription = result.missingSourceCount == 0
                    ? "No missing files found"
                    : "\(result.missingSourceCount) missing file\(result.missingSourceCount == 1 ? "" : "s") found and marked inactive"
                completeMaintenance(
                    kind: kind,
                    processed: result.testedSourceCount,
                    failures: result.missingSourceCount,
                    result: "Checked \(result.testedSourceCount) files • \(missingDescription) • \(result.restoredSourceCount) restored"
                )
            case .cleaned(let count):
                completeMaintenance(
                    kind: kind,
                    processed: count,
                    failures: 0,
                    result: "Removed \(count) inactive link\(count == 1 ? "" : "s")"
                )
            case .failure(let message):
                recordMaintenanceFailure(message)
            }
            validateCatalog()
            completeRequestedCloseIfIdle()
        }
    }

    private func applyMaintenanceProgress(_ update: CatalogMaintenanceProgress) {
        let kind: ScannerOperationKind = update.operation == .checkLinks ? .checkLinks : .removeLinks
        operationProgress = ScannerOperationProgress(
            operation: kind,
            phase: "maintenance",
            processed: update.processed,
            total: update.total,
            failures: update.failures,
            detail: update.detail
        )
        scanStatus = update.detail
        if let currentPath = update.currentPath {
            self.currentPath = (currentPath as NSString).deletingLastPathComponent
            self.currentFile = (currentPath as NSString).lastPathComponent
        }
    }

    private func completeMaintenance(
        kind: ScannerOperationKind,
        processed: Int,
        failures: Int,
        result: String
    ) {
        let completedAt = Date()
        let telemetry = ScannerOperationTelemetry(
            operation: kind,
            startedAt: operationStartedAt ?? completedAt,
            completedAt: completedAt,
            processed: processed,
            total: processed,
            failures: failures,
            result: result
        )
        completedOperation = telemetry
        scanStatus = telemetry.statusText
        operationProgress = nil
    }

    private func sampleProgress<Value: Sendable>(
        from buffer: LatestValueBuffer<Value>,
        apply: (Value) -> Void
    ) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: ScannerProgressDelivery.sampleIntervalNanoseconds)
            guard !Task.isCancelled else { break }
            if let update = buffer.take() {
                apply(update)
            }
            if buffer.isFinished { break }
        }
        if let update = buffer.take() {
            apply(update)
        }
    }

    private func applyVisibleProgress(_ update: CatalogScanProgress) {
        operationProgress = ScannerOperationProgress(
            operation: .scan,
            phase: update.phase.rawValue,
            processed: update.processed,
            total: update.discovered,
            failures: update.failed,
            detail: update.detail
        )
        activeRootID = roots.first(where: { $0.path == update.rootPath })?.id
        if let candidate = update.currentPath {
            if let separator = candidate.firstIndex(of: "#") {
                let sourcePath = String(candidate[..<separator])
                let archiveEntry = String(candidate[candidate.index(after: separator)...])
                currentPath = (sourcePath as NSString).deletingLastPathComponent
                currentFile = "\((sourcePath as NSString).lastPathComponent)#\(archiveEntry)"
            } else {
                currentPath = (candidate as NSString).deletingLastPathComponent
                currentFile = (candidate as NSString).lastPathComponent
            }
        }
        switch update.phase {
        case .preparing: scanStatus = "Preparing catalog…"
        case .discovery: scanStatus = "Discovering supported sources…"
        case .planning: scanStatus = "Discovered \(update.discovered) sources"
        case .archiveListing: scanStatus = "Extracting archives…"
        case .materialization: scanStatus = "Materializing archive members…"
        case .inspection: scanStatus = "Inspecting sources…"
        case .persistence:
            scanStatus = "Saved \(update.processed) of \(update.discovered) • \(update.failed) failed"
        case .publication:
            currentPath = nil
            currentFile = nil
            scanStatus = update.detail ?? "Publishing catalog atomically…"
        case .cleanup: scanStatus = "Cleaning temporary scan files…"
        }
    }

    private func finish(_ outcome: ScanOutcome) {
        isScanning = false
        worker = nil
        scanTask = nil
        currentPath = nil
        currentFile = nil
        switch outcome {
        case .success(let results):
            for result in results { writeLastScanLog(rootID: result.root.id, result: result, terminalMessage: nil) }
            let completedAt = results.compactMap(\.root.lastScanCompletedAt).max() ?? Date()
            let startedAt = results.compactMap(\.root.lastScanStartedAt).min() ?? completedAt
            let totalDiscovered = results.reduce(0) { $0 + $1.discoveredSourceCount }
            let totalFailures = results.reduce(0) { $0 + $1.failures.count }
            let totalSkipped = results.reduce(0) { $0 + $1.skipped.count }
            let totalTracks = results.reduce(0) { $0 + $1.trackCount }
            let telemetry = ScannerOperationTelemetry(
                operation: .scan,
                startedAt: operationStartedAt ?? startedAt,
                completedAt: completedAt,
                processed: totalDiscovered,
                total: totalDiscovered,
                failures: totalFailures,
                result: "\(totalDiscovered) items • \(totalTracks) tracks • \(totalFailures) failed • \(totalSkipped) skipped"
            )
            completedOperation = telemetry
            scanStatus = telemetry.statusText
        case .cancelled:
            writeLastScanLog(rootID: activeRootID, result: nil, terminalMessage: "Cancelled. Completed checkpoints were retained.")
            scanStatus = "Cancelled. Completed source checkpoints were retained; Scan resumes them."
        case .failure(let message):
            writeLastScanLog(rootID: activeRootID, result: nil, terminalMessage: "Stopped before publication — \(message)")
            if isCatalogContention(message) {
                scanStatus = "Catalog busy. Existing records remain consistent; retry the scan shortly."
            } else {
                scanStatus = "Scan stopped before publication: \(message)"
            }
        }
        operationProgress = nil
        activeRootID = nil
        validateCatalog()
        completeRequestedCloseIfIdle()
    }

    private func completeRequestedCloseIfIdle() {
        guard !isBusy, let close = closeWhenIdle else { return }
        closeWhenIdle = nil
        close()
    }

    private func writeLastScanLog(rootID: Int64?, result: CatalogScanResult?, terminalMessage: String?) {
        guard let rootID else { return }
        do {
            let reader = try CanonicalCatalogReader(databaseURL: databaseURL)
            guard let root = try reader.roots().first(where: { $0.id == rootID }) else { return }
            let tally = try reader.scanTally(rootID: rootID)
            logWindows[rootID]?.close()
            logWindows[rootID] = nil
            ScannerScanLogStore.writeLastResult(
                databaseURL: databaseURL,
                root: root,
                tally: tally,
                result: result,
                terminalMessage: terminalMessage
            )
        } catch {
            scanStatus = "Scan completed, but its log could not be saved: \(error.localizedDescription)"
        }
    }

    private func record(_ error: Error, stage: String) {
        if CatalogWriterError.isContention(error) {
            scanStatus = "Catalog busy. Player playback may continue; retry the operation shortly."
            return
        }
        scanStatus = "Catalog operation failed at \(stage): \(error.localizedDescription)"
    }

    private func recordMaintenanceFailure(_ message: String) {
        if isCatalogContention(message) {
            scanStatus = "Catalog busy. Player playback may continue; retry the operation shortly."
        } else {
            scanStatus = "Catalog maintenance failed: \(message)"
        }
    }

    private func isCatalogContention(_ message: String) -> Bool {
        message.contains("Another ScanSong session is already writing this catalog.")
            || message.contains("The catalog is busy with another SQLite operation.")
    }

    private static func defaultCatalogURL() -> URL {
        if let configuredPath = UserDefaults(suiteName: cocoaSpiceDefaultsSuite)?
            .string(forKey: cocoaSpiceCatalogPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty,
           (configuredPath as NSString).isAbsolutePath {
            return URL(fileURLWithPath: configuredPath).standardizedFileURL
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CocoaSpice", isDirectory: true)
            .appendingPathComponent("Library.sqlite", isDirectory: false)
    }
}

struct ScannerWindow: View {
    @ObservedObject var model: ScannerAppModel
    @Environment(\.openWindow) private var openWindow

    private let windowBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let panelBackground = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                catalogCard
                scanPathsCard
                scannerOptionsCard
                scanStatusCard
            }
            .padding(20)
        }
        .background(windowBackground)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 700)
        .background(WindowCloseGuard(model: model))
        .onAppear { ScanSongApplicationDelegate.shared?.scannerModel = model }
        .confirmationDialog(
            "Reset all scan paths?",
            isPresented: $model.showsResetPathsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Paths", role: .destructive) { model.resetPaths() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every configured scan path from the catalog. Indexed records stay intact and can be reused when a path is added again.")
        }
        .confirmationDialog(
            "Remove Links?",
            isPresented: $model.showsCleanLinksConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Links", role: .destructive) { model.cleanLinks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moved files' records are retained for fast recognition. Permanently remove dead links from database?")
        }
        .confirmationDialog(
            "Reset Database?",
            isPresented: $model.showsResetCatalogConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Database", role: .destructive) { model.resetCatalog() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This empties the selected catalog, including scan paths, indexed tracks, metadata, and scan history. Media files on disk are not changed.")
        }
        .confirmationDialog(
            "Delete Database File?",
            isPresented: $model.showsDeleteCatalogConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Database File", role: .destructive) { model.deleteCatalogFile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the selected database file from disk. Media files on disk are not changed.")
        }
    }

    private var catalogCard: some View {
        sectionCard(title: "Database File") {
            databaseFileRow
            HStack(spacing: 8) {
                actionButton("Use Default") { model.useDefaultCatalog() }
                    .disabled(model.isBusy)
                actionButton("Add New") { model.addNewCatalog() }
                    .disabled(model.isBusy)
            }
        }
    }

    private var scanPathsCard: some View {
        sectionCard(title: "Scan Paths") {
            if model.roots.isEmpty {
                Text("No scan paths configured.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.roots) { root in
                        scanPathRow(root)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.toggleAllPathsEnabled()
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .help("Enable All / Disable All")
                .accessibilityLabel("Enable All / Disable All Paths")
                .disabled(model.isBusy || model.roots.isEmpty)

                actionButton(model.operationProgress?.operation == .addPath ? "Adding…" : "Add Path") { model.addPaths() }
                    .disabled(model.isBusy)
                actionButton("Reset Paths") { model.showsResetPathsConfirmation = true }
                    .disabled(model.isBusy || model.roots.isEmpty)
                actionButton("Scan All") { model.scanAllPaths() }
                    .disabled(!model.canScanAll)
                actionButton("Check Links") { model.checkLinks() }
                    .disabled(model.isBusy || model.roots.isEmpty)
                actionButton("Remove Links") { model.showsCleanLinksConfirmation = true }
                    .disabled(model.isBusy || !model.hasInactiveLinks)
            }
        }
    }

    private var scannerOptionsCard: some View {
        sectionCard(title: "Scanner Options") {
            HStack(alignment: .center, spacing: 16) {
                Toggle(isOn: $model.deepScan) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deep Scan")
                            .foregroundStyle(.white)
                        Text("Unzip, read metadata for all files.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(model.isBusy)

                Spacer(minLength: 16)

                Button { openWindow(id: "options") } label: {
                    Image(systemName: "gearshape")
                }
                .help("Scanner Options")
                .accessibilityLabel("Scanner Options")
                .disabled(model.isBusy)
            }
        }
    }

    private var scanStatusCard: some View {
        sectionCard(title: "Scan Status") {
            if !model.isBusy, let completedOperation = model.completedOperation {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(completedOperation.statusText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(completedOperation.statusText)
            } else {
                scanReadout
            }
            if model.isBusy {
                Group {
                    if let fraction = model.progressFraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Scan progress")
                .transition(.move(edge: .top).combined(with: .opacity))
                // A short ease-out gives the bar the requested simple
                // exponential-style decay without animating the data area.
                .animation(.easeOut(duration: 0.2), value: model.isBusy)
            }
            if model.isScanning {
                Button(role: .cancel) { model.cancelScan() } label: {
                    Text("Cancel Scan")
                        .frame(maxWidth: .infinity)
                }
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var scanReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Scan")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(model.scanStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            VStack(alignment: .leading, spacing: 2) {
                monoStatusField(
                    title: " Items:",
                    value: model.operationProgress.map { progress in
                        if let total = progress.total { return "\(progress.processed) / \(total)" }
                        return String(progress.processed)
                    } ?? "0 / 0"
                )
                monoStatusField(
                    title: " Fails:",
                    value: model.operationProgress.map { String($0.failures) } ?? "0"
                )
            }
            if model.isBusy {
                Text("Current File")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                monoStatusField(title: " Path:", value: model.currentPath ?? "—")
                monoStatusField(title: " File:", value: model.currentFile ?? "—")
            }

        }
    }

    private var databaseFileRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cylinder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.databaseFileDisplayPath)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.catalogStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button { model.chooseCatalog() } label: {
                    Image(systemName: "folder")
                }
                .help("Open Database File")
                .accessibilityLabel("Open Database File")
                .disabled(model.isBusy)

                Button(role: .destructive) {
                    model.showsResetCatalogConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Empty Database")
                .accessibilityLabel("Reset Database")
                .disabled(model.isBusy || !model.hasDatabaseFile)

                Button(role: .destructive) { model.showsDeleteCatalogConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Database File")
                .accessibilityLabel("Delete Database File")
                .disabled(model.isBusy || !model.hasDatabaseFile)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func scanPathRow(_ root: CatalogRoot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { root.isEnabled },
                    set: { model.setPathEnabled(root.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(model.isBusy)

            scanPathStatusIcon(root)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.abbreviatedPath(for: root))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .help(root.path)
                Text(model.rootStatusText(root))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button { model.scanPath(root.id) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help(root.isEnabled ? "Scan Path" : "Scan Path Without Enabling It")
                .disabled(model.isBusy)

                Button { model.showScanLog(root.id) } label: {
                    Image(systemName: "doc.text")
                }
                .help("Show Last Scan Log")
                .disabled(!model.hasScanLog(root.id))

                Button(role: .destructive) { model.removePath(root.id) } label: {
                    Image(systemName: "trash")
                }
                .help("Remove Path")
                .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func scanPathStatusIcon(_ root: CatalogRoot) -> some View {
        if model.rootStatusIsEmpty(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Scan completed with no playable files")
        } else if model.rootStatusHasIssues(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Scan completed with issues; see Log for details")
        } else if model.rootStatusIsClean(root) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Scan completed without issues")
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not yet scanned")
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monoStatusField(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Divider()
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(panelBackground))
    }
}

@MainActor
private final class ScanSongApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: ScanSongApplicationDelegate?
    weak var scannerModel: ScannerAppModel?
    private var terminationSignal: DispatchSourceSignal?
    private var terminationWasSignalled = false

    override init() {
        super.init()
        Self.shared = self

        // launch.sh uses SIGTERM to retire the previous development build.
        // Ignore the default abrupt signal action and route it through the same
        // cooperative close path used by the native UI.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.terminationWasSignalled else { return }
                self.terminationWasSignalled = true
                NSApplication.shared.terminate(nil)
            }
        }
        source.resume()
        terminationSignal = source
    }

    deinit {
        terminationSignal?.cancel()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = scannerModel, model.isBusy else { return .terminateNow }

        if terminationWasSignalled {
            model.closeWhenWorkIsSafe { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }

        let alert = NSAlert()
        if model.isScanning {
            alert.messageText = "Scan in Progress"
            alert.informativeText = "Cancel the scan and quit after completed checkpoints are safely retained?"
            alert.addButton(withTitle: "Keep Scanning")
            alert.addButton(withTitle: "Cancel Scan and Quit")
        } else {
            alert.messageText = "Catalog Operation in Progress"
            alert.informativeText = "Quit after the current database operation has finished?"
            alert.addButton(withTitle: "Keep Working")
            alert.addButton(withTitle: "Quit When Finished")
        }
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.closeWhenWorkIsSafe { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    @ObservedObject var model: ScannerAppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        attach(context.coordinator, to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.model = model
        attach(context.coordinator, to: view)
    }

    private func attach(_ coordinator: Coordinator, to view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window, window.delegate !== coordinator else { return }
            window.delegate = coordinator
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var model: ScannerAppModel

        init(model: ScannerAppModel) {
            self.model = model
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard model.isBusy else { return true }

            let alert = NSAlert()
            if model.isScanning {
                alert.messageText = "Scan in Progress"
                alert.informativeText = "Cancel the scan and close after completed checkpoints are safely retained?"
                alert.addButton(withTitle: "Keep Scanning")
                alert.addButton(withTitle: "Cancel Scan and Close")
            } else {
                alert.messageText = "Catalog Operation in Progress"
                alert.informativeText = "Close after the current database operation has finished?"
                alert.addButton(withTitle: "Keep Working")
                alert.addButton(withTitle: "Close When Finished")
            }
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
            model.closeWhenWorkIsSafe { [weak sender] in sender?.performClose(nil) }
            return false
        }
    }
}

@main
struct ScanSongApplication: App {
    @NSApplicationDelegateAdaptor(ScanSongApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = ScannerAppModel()

    init() {
        if let iconURL = Bundle.main.url(forResource: "app-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("ScanSong") { ScannerWindow(model: model) }
            .defaultSize(width: 840, height: 700)
            .commands {
                ScannerCommands()
            }

        Window("Options", id: "options") {
            ScannerOptionsView(model: model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)
    }
}

private struct ScannerCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Options…") {
                openWindow(id: "options")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
