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

@MainActor
final class ScannerAppModel: ObservableObject {
    private static let catalogPathKey = "MediaScanner.catalogPath"

    @Published var databaseURL: URL
    @Published var catalogStatus = "Choose or create a canonical catalog."
    @Published var roots: [URL] = []
    @Published var selection: Set<URL> = []
    @Published var scanStatus = "Add one or more scan folders."
    @Published var currentPath: String?
    @Published var progress: CatalogScanProgress?
    @Published var diagnostics: [String] = []
    @Published var isScanning = false
    @Published var rebuild = false
    @Published var consoleSourcePolicy: CatalogConsoleSourcePolicy = .foldersFirst

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

    var canStart: Bool { !isScanning && !roots.isEmpty }

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
        panel.prompt = "Add Files’ Folders"
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
        guard !isScanning else { return }
        roots.removeAll { selection.contains($0) }
        selection.removeAll()
        scanStatus = roots.isEmpty ? "Add one or more scan folders." : readyText
    }

    func clearRoots() {
        guard !isScanning else { return }
        roots.removeAll()
        selection.removeAll()
        diagnostics.removeAll()
        progress = nil
        currentPath = nil
        scanStatus = "Add one or more scan folders."
    }

    func startScan() {
        guard canStart else { return }
        let roots = roots
        let databaseURL = databaseURL
        let mode: ScanMode = rebuild ? .newScan : .incremental
        let consoleSourcePolicy = consoleSourcePolicy
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
        "Ready to scan \(roots.count) folder\(roots.count == 1 ? "" : "s")."
    }

    private func setCatalog(_ url: URL) {
        databaseURL = url.standardizedFileURL
        UserDefaults.standard.set(databaseURL.path, forKey: Self.catalogPathKey)
        validateCatalog()
    }

    private func validateCatalog() {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            catalogStatus = "New schema-23 catalog will be created when scanning starts."
            return
        }
        do {
            let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
            catalogStatus = "Schema \(summary.schemaVersion) • \(summary.rootCount) roots • \(summary.trackCount) tracks"
        } catch {
            catalogStatus = "Cannot use catalog: \(error.localizedDescription)"
        }
    }

    private func add(_ urls: [URL]) {
        guard !isScanning else { return }
        let canonical = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        roots = Array(Set(roots + canonical)).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        scanStatus = readyText
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
                        Button("New…") { model.createCatalog() }.disabled(model.isScanning)
                        Button("Browse…") { model.chooseCatalog() }.disabled(model.isScanning)
                    }
                    Text(model.catalogStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Scan Roots") {
                VStack(spacing: 8) {
                    HStack {
                        Button("Add Files…") { model.addFiles() }
                        Button("Add Folders…") { model.addFolders() }
                        Button("Remove") { model.removeSelected() }
                            .disabled(model.selection.isEmpty || model.isScanning)
                        Button("Clear") { model.clearRoots() }
                            .disabled(model.roots.isEmpty || model.isScanning)
                        Spacer()
                        Picker("Console Tags", selection: $model.consoleSourcePolicy) {
                            Text("Folders First").tag(CatalogConsoleSourcePolicy.foldersFirst)
                            Text("Metadata First").tag(CatalogConsoleSourcePolicy.metadataFirst)
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(model.isScanning)
                        Toggle("Rebuild", isOn: $model.rebuild)
                            .toggleStyle(.checkbox)
                            .disabled(model.isScanning)
                    }
                    List(model.roots, id: \.self, selection: $model.selection) { url in
                        Text(url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(url)
                    }
                    .frame(minHeight: 130)
                }
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
        .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 620)
    }
}

@main
struct MediaScannerApplication: App {
    var body: some Scene {
        WindowGroup("MediaScanner") { ScannerWindow() }
            .defaultSize(width: 780, height: 620)
    }
}
