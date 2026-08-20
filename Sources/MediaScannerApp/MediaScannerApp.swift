import AppKit
import Foundation
import MediaScannerKit
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

@MainActor
final class ScannerAppModel: ObservableObject {
    private static let catalogPathKey = "MediaScanner.catalogPath"
    private static let cocoaSpiceDefaultsSuite = "com.local.cocoaspice"
    private static let cocoaSpiceCatalogPathKey = "CocoaSpice.libraryDatabasePath"

    @Published var databaseURL: URL
    @Published var catalogStatus = "Choose or create a canonical catalog."
    @Published var roots: [CatalogRoot] = []
    @Published var rootTallies: [Int64: CatalogScanTally] = [:]
    @Published var scanStatus = "Add one or more scan paths."
    @Published var currentPath: String?
    @Published var currentFile: String?
    @Published var progress: CatalogScanProgress?
    @Published var isScanning = false
    @Published var isMaintaining = false
    @Published var deepScan = false
    @Published var showsResetPathsConfirmation = false
    @Published var showsResetCatalogConfirmation = false
    @Published var showsDeleteCatalogConfirmation = false
    @Published var showsCleanLinksConfirmation = false

    private var scanTask: Task<Void, Never>?
    private var worker: Task<ScanOutcome, Never>?
    private var pendingProgress: CatalogScanProgress?
    private var progressUpdateTask: Task<Void, Never>?
    private var activeRootID: Int64?
    private var logWindows: [Int64: ScannerScanLogWindow] = [:]
    private var closeWhenIdle: (() -> Void)?

    init() {
        if let storedPath = UserDefaults.standard.string(forKey: Self.catalogPathKey),
           (storedPath as NSString).isAbsolutePath {
            databaseURL = URL(fileURLWithPath: storedPath).standardizedFileURL
        } else {
            databaseURL = Self.defaultCatalogURL()
        }
        validateCatalog()
    }

    var isBusy: Bool { isScanning || isMaintaining }
    var canScanAll: Bool { !isBusy && roots.contains(where: \.isEnabled) }
    var hasInactiveLinks: Bool { roots.contains(where: { $0.deadSourceCount > 0 }) }
    var hasDatabaseFile: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    var databaseFileDisplayPath: String {
        hasDatabaseFile ? databaseURL.path : "(None)"
    }

    var progressFraction: Double? {
        guard let progress, progress.discovered > 0 else { return nil }
        return min(max(Double(progress.processed) / Double(progress.discovered), 0), 1)
    }

    func chooseCatalog() {
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
            scanStatus = "No database file selected. Use Default or Open a database file."
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
        runMaintenance(starting: "Checking catalog links…") { .checked(try $0.testFiles()) }
    }

    func cleanLinks() {
        runMaintenance(starting: "Cleaning inactive catalog links…") { .cleaned(try $0.clearDeadLinks()) }
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
        let canonical = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            for url in Set(canonical) { _ = try writer.addRoot(path: url.path) }
            try refreshRoots()
            scanStatus = readyText
            validateCatalog()
        } catch {
            record(error, stage: "paths.add")
        }
    }

    private func startScan(roots requestedRoots: [CatalogRoot]) {
        guard !isBusy, !requestedRoots.isEmpty else { return }
        let databaseURL = databaseURL
        let mode: ScanMode = deepScan ? .newScan : .incremental
        let (updates, continuation) = AsyncStream.makeStream(of: CatalogScanProgress.self)
        isScanning = true
        progressUpdateTask?.cancel()
        progressUpdateTask = nil
        pendingProgress = nil
        progress = nil
        currentPath = nil
        currentFile = nil
        activeRootID = requestedRoots.first?.id
        scanStatus = "Preparing catalog…"

        let worker = Task.detached(priority: .utility) {
            do {
                let scanner = try CatalogScanner(databaseURL: databaseURL)
                var results: [CatalogScanResult] = []
                for root in requestedRoots {
                    try Task.checkCancellation()
                    results.append(try await scanner.scan(rootURL: URL(fileURLWithPath: root.path), mode: mode) {
                        continuation.yield($0)
                    })
                }
                continuation.finish()
                return ScanOutcome.success(results)
            } catch is CancellationError {
                continuation.finish()
                return ScanOutcome.cancelled
            } catch {
                continuation.finish()
                return ScanOutcome.failure(error.localizedDescription)
            }
        }
        self.worker = worker
        scanTask = Task { [weak self] in
            guard let self else { return }
            for await update in updates { self.apply(update) }
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
        starting activity: String,
        _ operation: @escaping @Sendable (CanonicalCatalogWriter) throws -> MaintenanceOutcome
    ) {
        guard !isBusy else { return }
        isMaintaining = true
        scanStatus = activity
        let databaseURL = databaseURL
        Task {
            let outcome = await Task.detached(priority: .utility) {
                do { return try operation(CanonicalCatalogWriter(databaseURL: databaseURL)) }
                catch { return MaintenanceOutcome.failure(error.localizedDescription) }
            }.value
            isMaintaining = false
            switch outcome {
            case .checked(let result):
                scanStatus = "Checked \(result.testedSourceCount) files • \(result.missingSourceCount) marked inactive • \(result.restoredSourceCount) restored"
            case .cleaned(let count):
                scanStatus = "Cleaned \(count) inactive link\(count == 1 ? "" : "s")."
            case .failure(let message):
                recordMaintenanceFailure(message)
            }
            validateCatalog()
            completeRequestedCloseIfIdle()
        }
    }

    private func apply(_ update: CatalogScanProgress) {
        pendingProgress = update
        guard progressUpdateTask == nil else { return }
        progressUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingProgress()
        }
    }

    private func flushPendingProgress() {
        progressUpdateTask = nil
        guard let update = pendingProgress else { return }
        pendingProgress = nil
        applyVisibleProgress(update)
    }

    private func flushQueuedProgress() {
        progressUpdateTask?.cancel()
        progressUpdateTask = nil
        guard let update = pendingProgress else { return }
        pendingProgress = nil
        applyVisibleProgress(update)
    }

    private func applyVisibleProgress(_ update: CatalogScanProgress) {
        progress = update
        activeRootID = roots.first(where: { $0.path == update.rootPath })?.id
        if let candidate = update.currentPath {
            currentPath = (candidate as NSString).deletingLastPathComponent
            currentFile = (candidate as NSString).lastPathComponent
        }
        switch update.phase {
        case .preparing: scanStatus = "Preparing catalog…"
        case .discovery: scanStatus = "Discovering supported sources…"
        case .planning: scanStatus = "Discovered \(update.discovered) sources"
        case .archiveListing, .materialization, .inspection:
            scanStatus = "Scanning \(update.processed) of \(update.discovered) • \(update.failed) failed"
        case .persistence:
            scanStatus = "Saved \(update.processed) of \(update.discovered) • \(update.failed) failed"
        case .publication: scanStatus = "Publishing catalog atomically…"
        case .cleanup: scanStatus = "Cleaning temporary scan files…"
        }
    }

    private func finish(_ outcome: ScanOutcome) {
        flushQueuedProgress()
        isScanning = false
        worker = nil
        scanTask = nil
        currentPath = nil
        currentFile = nil
        switch outcome {
        case .success(let results):
            for result in results { writeLastScanLog(rootID: result.root.id, result: result, terminalMessage: nil) }
            let discovered = results.reduce(0) { $0 + $1.discoveredSourceCount }
            let tracks = results.reduce(0) { $0 + $1.trackCount }
            let reused = results.reduce(0) { $0 + $1.reusedSourceCount }
            let failures = results.flatMap(\.failures)
            scanStatus = "Complete • \(discovered) sources • \(tracks) tracks • \(reused) reused • \(failures.count) failed"
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
    @StateObject private var model = ScannerAppModel()

    private let windowBackground = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let panelBackground = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                catalogCard
                scanPathsCard
                scannerOptionsCard
                if model.isBusy || model.progress != nil {
                    scanStatusCard
                }
            }
            .padding(20)
        }
        .background(windowBackground)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 560, idealHeight: 700)
        .background(WindowCloseGuard(model: model))
        .onAppear { MediaScannerApplicationDelegate.shared?.scannerModel = model }
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
            "Clean Links?",
            isPresented: $model.showsCleanLinksConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Links", role: .destructive) { model.cleanLinks() }
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
            actionButton("Use Default") { model.useDefaultCatalog() }
                .disabled(model.isBusy)
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

                actionButton("Add Path") { model.addPaths() }
                    .disabled(model.isBusy)
                actionButton("Reset Paths") { model.showsResetPathsConfirmation = true }
                    .disabled(model.isBusy || model.roots.isEmpty)
                actionButton("Scan All") { model.scanAllPaths() }
                    .disabled(!model.canScanAll)
                actionButton("Check Links") { model.checkLinks() }
                    .disabled(model.isBusy || model.roots.isEmpty)
                actionButton("Clean Links") { model.showsCleanLinksConfirmation = true }
                    .disabled(model.isBusy || !model.hasInactiveLinks)
            }
        }
    }

    private var scannerOptionsCard: some View {
        sectionCard(title: "Scanner Options") {
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

        }
    }

    private var scanStatusCard: some View {
        sectionCard(title: "Scan Status") {
            statusField(title: "Current Activity", value: model.scanStatus)
            statusField(title: "File Path", value: model.currentPath ?? "Preparing scan path…")
            statusField(title: "File Name", value: model.currentFile ?? model.scanStatus)
            if let fraction = model.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Scan progress")
            } else if model.isBusy {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Scan progress")
            }
            if model.isScanning {
                Button("Cancel Scan", role: .cancel) { model.cancelScan() }
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
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
private final class MediaScannerApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: MediaScannerApplicationDelegate?
    weak var scannerModel: ScannerAppModel?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = scannerModel, model.isBusy else { return .terminateNow }

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
struct MediaScannerApplication: App {
    @NSApplicationDelegateAdaptor(MediaScannerApplicationDelegate.self) private var applicationDelegate

    init() {
        if let iconURL = Bundle.main.url(forResource: "app-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("ScanSong") { ScannerWindow() }
            .defaultSize(width: 840, height: 700)
    }
}
