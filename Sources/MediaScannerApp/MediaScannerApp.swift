import AppKit
import Foundation
import MediaScannerKit
import SwiftUI
import UniformTypeIdentifiers

private enum ProbeOutcome: Sendable {
    case success(DryRunProbeResult)
    case cancelled
    case failure(String)
}

private final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func isCancelled() -> Bool {
        lock.withLock { cancelled }
    }
}

@MainActor
final class ScannerAppModel: ObservableObject {
    private static let catalogPathKey = "MediaScanner.catalogPath"
    @Published var databaseURL: URL
    @Published var catalogStatus = "Choose a canonical catalog."
    @Published var inputs: [URL] = []
    @Published var selection: Set<URL> = []
    @Published var scanStatus = "Add files or folders to run a scanner test."
    @Published var currentPath: String?
    @Published var progress: DryRunProbeProgress?
    @Published var diagnostics: [String] = []
    @Published var isScanning = false
    @Published var strictMode = false

    private var scanTask: Task<Void, Never>?
    private var cancellation: ProbeCancellation?

    init() {
        if let storedPath = UserDefaults.standard.string(forKey: Self.catalogPathKey),
           (storedPath as NSString).isAbsolutePath {
            databaseURL = URL(fileURLWithPath: storedPath).standardizedFileURL
        } else {
            databaseURL = Self.defaultCatalogURL()
        }
        validateCatalog()
    }

    var canStart: Bool {
        !isScanning && !inputs.isEmpty
    }

    var progressFraction: Double? {
        guard let progress, let total = progress.total, total > 0 else { return nil }
        return min(max(Double(progress.processed) / Double(total), 0), 1)
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
        panel.nameFieldStringValue = databaseURL.lastPathComponent
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        databaseURL = selected.standardizedFileURL
        UserDefaults.standard.set(databaseURL.path, forKey: Self.catalogPathKey)
        validateCatalog()
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add Media Files"
        panel.prompt = "Add Files"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Media Folder"
        panel.prompt = "Add Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func removeSelected() {
        guard !isScanning else { return }
        inputs.removeAll { selection.contains($0) }
        selection.removeAll()
        scanStatus = inputs.isEmpty
            ? "Add files or folders to run a scanner test."
            : "Ready to test \(inputs.count) input\(inputs.count == 1 ? "" : "s")."
    }

    func clearInputs() {
        guard !isScanning else { return }
        inputs.removeAll()
        selection.removeAll()
        diagnostics.removeAll()
        progress = nil
        currentPath = nil
        scanStatus = "Add files or folders to run a scanner test."
    }

    func startProbe() {
        guard canStart else { return }
        let paths = inputs.map(\.path)
        let strict = strictMode
        let cancellation = ProbeCancellation()
        let (updates, continuation) = AsyncStream.makeStream(of: DryRunProbeProgress.self)
        self.cancellation = cancellation
        isScanning = true
        progress = nil
        currentPath = nil
        diagnostics.removeAll()
        scanStatus = "Discovering files…"

        let worker = Task.detached(priority: .utility) {
            do {
                let result = try DryRunProbe().run(
                    paths: paths,
                    recursive: true,
                    strict: strict,
                    isCancelled: { cancellation.isCancelled() },
                    progress: { continuation.yield($0) }
                )
                continuation.finish()
                return ProbeOutcome.success(result)
            } catch is CancellationError {
                continuation.finish()
                return ProbeOutcome.cancelled
            } catch {
                continuation.finish()
                return ProbeOutcome.failure(error.localizedDescription)
            }
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            for await update in updates {
                self.apply(update)
            }
            self.finish(await worker.value)
        }
    }

    func cancelProbe() {
        guard isScanning else { return }
        scanStatus = "Cancelling…"
        cancellation?.cancel()
    }

    private func validateCatalog() {
        do {
            let summary = try CanonicalCatalog.inspect(databaseURL: databaseURL)
            catalogStatus = "Schema \(summary.schemaVersion) • \(summary.rootCount) roots • \(summary.trackCount) tracks • read-only validation passed"
        } catch {
            catalogStatus = "Catalog unavailable: \(error.localizedDescription)"
        }
    }

    private func add(_ urls: [URL]) {
        guard !isScanning else { return }
        let combined = Set(inputs + urls.map(\.standardizedFileURL))
        inputs = combined.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        scanStatus = "Ready to test \(inputs.count) input\(inputs.count == 1 ? "" : "s")."
    }

    private func apply(_ update: DryRunProbeProgress) {
        progress = update
        currentPath = update.path
        switch update.phase {
        case .discovering:
            scanStatus = "Discovering files • \(update.discovered) found"
        case .routing:
            scanStatus = "Testing routes • \(update.processed) of \(update.total ?? update.discovered)"
        case .finished:
            scanStatus = "Finishing scanner test…"
        }
    }

    private func finish(_ outcome: ProbeOutcome) {
        isScanning = false
        cancellation = nil
        scanTask = nil
        currentPath = nil
        switch outcome {
        case .success(let result):
            diagnostics = result.events.compactMap { event in
                guard let diagnostic = event.diagnostic else { return nil }
                let location = event.path.map { " • \($0)" } ?? ""
                return "\(diagnostic.severity.rawValue.uppercased()) • \(diagnostic.code)\(location) • \(diagnostic.message)"
            }
            let summary = result.events.last { $0.kind == .sessionFinished }
            let discovered = summary?.discovered ?? 0
            let accepted = summary?.accepted ?? 0
            let unsupported = summary?.unsupported ?? 0
            scanStatus = "Test complete • \(discovered) discovered • \(accepted) accepted • \(unsupported) unsupported • catalog unchanged"
        case .cancelled:
            scanStatus = "Scanner test cancelled. No catalog changes were made."
        case .failure(let message):
            diagnostics = ["ERROR • session.fatal • \(message)"]
            scanStatus = "Scanner test failed. No catalog changes were made."
        }
    }

    private static func defaultCatalogURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
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
                        Button("Browse…") { model.chooseCatalog() }
                            .disabled(model.isScanning)
                    }
                    Text(model.catalogStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            GroupBox("Files") {
                VStack(spacing: 8) {
                    HStack {
                        Button("Add Files…") { model.addFiles() }
                        Button("Add Folder…") { model.addFolder() }
                        Button("Remove") { model.removeSelected() }
                            .disabled(model.selection.isEmpty || model.isScanning)
                        Button("Clear") { model.clearInputs() }
                            .disabled(model.inputs.isEmpty || model.isScanning)
                        Spacer()
                        Toggle("Strict", isOn: $model.strictMode)
                            .toggleStyle(.checkbox)
                            .disabled(model.isScanning)
                    }
                    List(model.inputs, id: \.self, selection: $model.selection) { url in
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
                    Text(model.scanStatus)
                        .font(.system(size: 12, weight: .medium))
                    if let currentPath = model.currentPath {
                        Text(currentPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let fraction = model.progressFraction {
                        ProgressView(value: fraction)
                    } else if model.isScanning {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    HStack {
                        Text("This first GUI pass tests discovery and format routing; it does not yet publish rows to the catalog.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.isScanning {
                            Button("Cancel", role: .cancel) { model.cancelProbe() }
                                .keyboardShortcut(.cancelAction)
                        } else {
                            Button("Test Scan") { model.startProbe() }
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
                            Text("No diagnostics.")
                                .foregroundStyle(.secondary)
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
        WindowGroup("MediaScanner") {
            ScannerWindow()
        }
        .defaultSize(width: 780, height: 620)
    }
}
