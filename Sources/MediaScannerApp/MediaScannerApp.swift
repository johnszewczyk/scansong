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
    case tested(CatalogLinkTestResult)
    case purged(Int)
    case failure(String)
}

@MainActor
final class ScannerAppModel: ObservableObject {
    private static let catalogPathKey = "MediaScanner.catalogPath"

    @Published var databaseURL: URL
    @Published var catalogStatus = "Choose or create a canonical catalog."
    @Published var roots: [CatalogRoot] = []
    @Published var checkedRootIDs: Set<Int64> = []
    @Published var scanStatus = "Add one or more scan folders."
    @Published var currentPath: String?
    @Published var progress: CatalogScanProgress?
    @Published var diagnostics: [String] = []
    @Published var isScanning = false
    @Published var isMaintaining = false
    @Published var rebuild = false
    @Published var foldersAsMetadata = true
    @Published var showsRemoveConfirmation = false
    @Published var showsClearDeadConfirmation = false

    private var scanTask: Task<Void, Never>?
    private var worker: Task<ScanOutcome, Never>?

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
    var canStart: Bool { !isBusy && !checkedRootIDs.isEmpty }

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

    func createCatalog() {
        let panel = NSSavePanel()
        panel.title = "Create Media Catalog"
        panel.prompt = "Create Catalog"
        panel.allowedContentTypes = [.database]
        panel.directoryURL = databaseURL.deletingLastPathComponent()
        panel.nameFieldStringValue = "Library.sqlite"
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        setCatalog(selected)
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add Media Files"
        panel.message = "Each selected file adds its containing folder as a complete scan root."
        panel.prompt = "Add Files"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls.map { $0.deletingLastPathComponent() })
    }

    func addFolders() {
        let panel = NSOpenPanel()
        panel.title = "Add Scan Folders"
        panel.prompt = "Add Folders"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func removeSelected() {
        guard !isBusy, !checkedRootIDs.isEmpty else { return }
        do {
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            for id in checkedRootIDs { try writer.removeRoot(id: id) }
            checkedRootIDs.removeAll()
            try loadRoots(using: writer)
            validateCatalog()
        } catch {
            diagnostics = ["ERROR • roots.remove • \(error.localizedDescription)"]
        }
    }

    func toggleAllRoots() {
        guard !isBusy else { return }
        checkedRootIDs = checkedRootIDs.count == roots.count ? [] : Set(roots.map(\.id))
    }

    func testFiles() { runMaintenance { .tested(try $0.testFiles()) } }

    func clearDeadLinks() { runMaintenance { .purged(try $0.clearDeadLinks()) } }

    func toggleRoot(_ id: Int64) {
        if checkedRootIDs.contains(id) { checkedRootIDs.remove(id) }
        else { checkedRootIDs.insert(id) }
    }

    func startScan() {
        guard canStart else { return }
        let roots = roots.filter { checkedRootIDs.contains($0.id) }.map { URL(fileURLWithPath: $0.path) }
        let databaseURL = databaseURL
        let mode: ScanMode = rebuild ? .newScan : .incremental
        let consoleSourcePolicy: CatalogConsoleSourcePolicy = foldersAsMetadata ? .foldersFirst : .metadataFirst
        let (updates, continuation) = AsyncStream.makeStream(of: CatalogScanProgress.self)
        isScanning = true
        progress = nil
        currentPath = nil
        diagnostics.removeAll()
        scanStatus = "Preparing catalog…"

        let worker = Task.detached(priority: .utility) {
            do {
                let scanner = try CatalogScanner(
                    databaseURL: databaseURL,
                    consoleSourcePolicy: consoleSourcePolicy
                )
                var results: [CatalogScanResult] = []
                for root in roots {
                    try Task.checkCancellation()
                    results.append(try await scanner.scan(rootURL: root, mode: mode) {
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

    func cancelScan() {
        guard isScanning else { return }
        scanStatus = "Cancelling and retaining completed checkpoints…"
        worker?.cancel()
    }

    private var readyText: String {
        "Ready • \(roots.count) scan root\(roots.count == 1 ? "" : "s") • \(checkedRootIDs.count) checked"
    }

    private func setCatalog(_ url: URL) {
        databaseURL = url.standardizedFileURL
        UserDefaults.standard.set(databaseURL.path, forKey: Self.catalogPathKey)
        validateCatalog()
    }

    private func validateCatalog() {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            catalogStatus = "New schema-23 catalog will be created when scanning starts."
            roots = []
            checkedRootIDs = []
            return
        }
        do {
            let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
            catalogStatus = "Schema \(summary.schemaVersion) • \(summary.rootCount) roots • \(summary.trackCount) tracks"
            let writer = try CanonicalCatalogWriter(databaseURL: databaseURL)
            try loadRoots(using: writer)
        } catch {
            catalogStatus = "Cannot use catalog: \(error.localizedDescription)"
            roots = []
            checkedRootIDs = []
        }
    }

    private func add(_ urls: [URL]) {
        guard !isBusy else { return }
        let canonical = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        do {
            let writer = try CanonicalCatalogWriter(
                databaseURL: databaseURL,
                consoleSourcePolicy: foldersAsMetadata ? .foldersFirst : .metadataFirst
            )
            for url in Set(canonical) {
                let root = try writer.addRoot(path: url.path)
                checkedRootIDs.insert(root.id)
            }
            try loadRoots(using: writer, preserveChecks: true)
            validateCatalog()
        } catch {
            diagnostics = ["ERROR • roots.add • \(error.localizedDescription)"]
        }
    }

    private func loadRoots(using writer: CanonicalCatalogWriter, preserveChecks: Bool = false) throws {
        let previous = checkedRootIDs
        roots = try writer.roots()
        checkedRootIDs = preserveChecks ? previous.intersection(Set(roots.map(\.id))) : Set(roots.map(\.id))
        scanStatus = roots.isEmpty ? "Add one or more scan folders." : readyText
    }

    private func runMaintenance(_ operation: @escaping @Sendable (CanonicalCatalogWriter) throws -> MaintenanceOutcome) {
        guard !isBusy else { return }
        isMaintaining = true
        diagnostics.removeAll()
        scanStatus = "Testing catalog links…"
        let databaseURL = databaseURL
        Task {
            let outcome = await Task.detached(priority: .utility) {
                do { return try operation(CanonicalCatalogWriter(databaseURL: databaseURL)) }
                catch { return MaintenanceOutcome.failure(error.localizedDescription) }
            }.value
            isMaintaining = false
            switch outcome {
            case .tested(let result):
                scanStatus = "Tested \(result.testedSourceCount) files • \(result.missingSourceCount) inactive • \(result.restoredSourceCount) restored"
            case .purged(let count):
                scanStatus = "Cleared \(count) dead link\(count == 1 ? "" : "s")."
            case .failure(let message):
                scanStatus = "Catalog maintenance failed."
                diagnostics = ["ERROR • catalog.maintenance • \(message)"]
            }
            validateCatalog()
        }
    }

    private func apply(_ update: CatalogScanProgress) {
        progress = update
        currentPath = update.currentPath
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
        isScanning = false
        worker = nil
        scanTask = nil
        currentPath = nil
        switch outcome {
        case .success(let results):
            let discovered = results.reduce(0) { $0 + $1.discoveredSourceCount }
            let tracks = results.reduce(0) { $0 + $1.trackCount }
            let reused = results.reduce(0) { $0 + $1.reusedSourceCount }
            let failures = results.flatMap(\.failures)
            diagnostics = failures.map {
                "ERROR • \($0.stage.rawValue) • \($0.identity.path) • \($0.message)"
            }
            scanStatus = "Complete • \(discovered) sources • \(tracks) tracks • \(reused) reused • \(failures.count) failed"
            validateCatalog()
        case .cancelled:
            scanStatus = "Cancelled. Completed source checkpoints were retained; Scan resumes them."
            validateCatalog()
        case .failure(let message):
            diagnostics = ["ERROR • session.fatal • \(message)"]
            scanStatus = "Scan stopped before publication. Completed checkpoints were retained."
            validateCatalog()
        }
    }

    private static func defaultCatalogURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CocoaSpice", isDirectory: true)
            .appendingPathComponent("Library.sqlite", isDirectory: false)
    }
}

struct ScannerWindow: View {
    @StateObject private var model = ScannerAppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Catalog") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.databaseURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("New") { model.createCatalog() }.disabled(model.isBusy)
                        Button("Browse") { model.chooseCatalog() }.disabled(model.isBusy)
                    }
                    Text(model.catalogStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Scan Roots") {
                VStack(spacing: 8) {
                    HStack {
                        Button { model.toggleAllRoots() } label: {
                            Image(systemName: model.checkedRootIDs.count == model.roots.count && !model.roots.isEmpty
                                  ? "checkmark.square.fill" : "square")
                        }
                        .help(model.checkedRootIDs.count == model.roots.count ? "Uncheck All" : "Check All")
                        Button("Add Files") { model.addFiles() }
                        Button("Add Folders") { model.addFolders() }
                        Button("Remove") { model.showsRemoveConfirmation = true }
                            .disabled(model.checkedRootIDs.isEmpty || model.isBusy)
                        Divider().frame(height: 18)
                        Button("Test Files") { model.testFiles() }
                            .disabled(model.roots.isEmpty || model.isBusy)
                        Button("Clear Dead Links") { model.showsClearDeadConfirmation = true }
                            .disabled(model.roots.allSatisfy { $0.deadSourceCount == 0 } || model.isBusy)
                        Spacer()
                    }
                    List(model.roots) { root in
                        HStack(spacing: 8) {
                            Button { model.toggleRoot(root.id) } label: {
                                Image(systemName: model.checkedRootIDs.contains(root.id) ? "checkmark.square.fill" : "square")
                            }
                            .buttonStyle(.plain)
                            rootStatusIcon(root)
                            Text(root.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(rootStatusText(root))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 130)
                }
                .padding(.top, 4)
            }

            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Folders as Metadata", isOn: $model.foldersAsMetadata)
                            .toggleStyle(.checkbox)
                            .disabled(model.isBusy)
                        Text("Use folder structure as metadata for console tags.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Rebuild", isOn: $model.rebuild)
                            .toggleStyle(.checkbox)
                            .disabled(model.isBusy)
                        Text("Full-scan all files and available metadata, overwriting previous records.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Scan Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.scanStatus).font(.system(size: 12, weight: .medium))
                    if let currentPath = model.currentPath {
                        Text(currentPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let fraction = model.progressFraction { ProgressView(value: fraction) }
                    else if model.isScanning { ProgressView().progressViewStyle(.linear) }
                    HStack {
                        Text("Only MediaScanner writes this catalog. Player apps open it read-only.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.isScanning {
                            Button("Cancel", role: .cancel) { model.cancelScan() }
                                .keyboardShortcut(.cancelAction)
                        } else {
                            Button("Scan") { model.startScan() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!model.canStart)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Diagnostics") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if model.diagnostics.isEmpty {
                            Text("No diagnostics.").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Text(diagnostic)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 90)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 650, idealHeight: 700)
        .confirmationDialog(
            "Remove checked scan roots?",
            isPresented: $model.showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { model.removeSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their indexed records are retained in the catalog, but the roots will no longer appear or scan.")
        }
        .confirmationDialog(
            "Clear all dead links?",
            isPresented: $model.showsClearDeadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Dead Links", role: .destructive) { model.clearDeadLinks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently purges records for files currently marked inactive. It does not delete media files.")
        }
    }

    @ViewBuilder
    private func rootStatusIcon(_ root: CatalogRoot) -> some View {
        if root.lastScanCompletedAt == nil {
            Image(systemName: "circle.fill").foregroundStyle(.gray)
        } else if root.lastScanError != nil || root.failedSourceCount > 0 || root.deadSourceCount > 0 {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func rootStatusText(_ root: CatalogRoot) -> String {
        if root.lastScanCompletedAt == nil { return "Unscanned" }
        let issues = root.failedSourceCount + root.deadSourceCount
        return issues == 0 ? "\(root.lastScanTrackCount) tracks" : "\(issues) issue\(issues == 1 ? "" : "s")"
    }
}

@main
struct MediaScannerApplication: App {
    var body: some Scene {
        WindowGroup("MediaScanner") { ScannerWindow() }
            .defaultSize(width: 840, height: 700)
    }
}
