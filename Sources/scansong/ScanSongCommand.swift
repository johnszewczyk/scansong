import Darwin
import Dispatch
import Foundation
import ScanSongKit

private enum Exit: Error { case code(Int32) }

private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

private func write(_ event: ScannerEvent) throws {
    let data = try encoder.encode(event)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func writeFatal(_ message: String) throws {
    try write(ScannerEvent(
        kind: .diagnostic,
        sequence: 0,
        diagnostic: ScannerDiagnostic(code: "session.fatal", severity: .error, message: message)
    ))
}

private func usage() -> String {
    "Usage: scansong plugins | probe [--recursive] [--strict] PATH... | catalog create|validate|roots PATH | scan [--new] CATALOG ROOT..."
}

private final class SequencedEventWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSequence: Int

    init(startingAt sequence: Int) { nextSequence = sequence }

    func emit(_ event: (Int) -> ScannerEvent) {
        lock.withLock {
            try? write(event(nextSequence))
            nextSequence += 1
        }
    }
}

private final class ScanProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmissionAt = Date.distantPast
    private var lastPhase: ScanLifecyclePhase?

    func emit(_ update: CatalogScanProgress, to writer: SequencedEventWriter) {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        let phaseChanged = lastPhase != update.phase
        let phaseFinished = update.phaseCompleted != nil
            && update.phaseCompleted == update.phaseTotal
        guard phaseChanged || phaseFinished || now.timeIntervalSince(lastEmissionAt) >= 1 else { return }
        lastEmissionAt = now
        lastPhase = update.phase
        let phaseDetail = update.detail.map { " — \($0)" } ?? ""
        let detail = "\(update.phase.rawValue): \(update.processed)/\(update.discovered), \(update.failed) failed\(phaseDetail)"
        writer.emit { sequence in
            ScannerEvent(
                kind: .diagnostic,
                sequence: sequence,
                path: update.currentPath ?? update.rootPath,
                diagnostic: ScannerDiagnostic(code: "scan.progress", severity: .warning, message: detail)
            )
        }
    }
}

@main
private struct ScanSongCommand {
    static func main() async {
        do {
            try await run()
        } catch Exit.code(let code) {
            Foundation.exit(code)
        } catch is CancellationError {
            try? writeFatal("Scan cancelled; completed source checkpoints were retained for resume.")
            Foundation.exit(130)
        } catch {
            try? writeFatal(error.localizedDescription)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            try writeFatal(usage())
            throw Exit.code(64)
        }
        arguments.removeFirst()

        switch command {
        case "plugins":
            for (index, plugin) in BuiltInScannerPlugins.registry.descriptors.enumerated() {
                try write(ScannerEvent(kind: .plugin, sequence: index, plugin: plugin))
            }
        case "probe":
            try runProbe(arguments)
        case "catalog":
            try runCatalog(arguments)
        case "scan":
            try await runScan(arguments)
        default:
            try writeFatal("Unknown command: \(command). \(usage())")
            throw Exit.code(64)
        }
    }

    private static func runProbe(_ arguments: [String]) throws {
        let recursive = arguments.contains("--recursive")
        let strict = arguments.contains("--strict")
        let paths = arguments.filter { !$0.hasPrefix("--") }
        guard !paths.isEmpty else {
            try writeFatal("probe requires at least one path")
            throw Exit.code(64)
        }
        let result = try DryRunProbe().run(paths: paths, recursive: recursive, strict: strict)
        for event in result.events { try write(event) }
        if result.hasErrors { throw Exit.code(2) }
    }

    private static func runCatalog(_ arguments: [String]) throws {
        guard arguments.count == 2 else {
            try writeFatal("catalog requires: create|validate|roots PATH")
            throw Exit.code(64)
        }
        let action = arguments[0]
        let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        switch action {
        case "create":
            _ = try CanonicalCatalogWriter(databaseURL: url)
            let summary = try CanonicalCatalog.inspect(databaseURL: url)
            try write(ScannerEvent(kind: .catalogValidated, sequence: 0, path: summary.path, catalog: summary))
        case "validate":
            let summary = try CanonicalCatalog.inspect(databaseURL: url)
            try write(ScannerEvent(kind: .catalogValidated, sequence: 0, path: summary.path, catalog: summary))
        case "roots":
            let reader = try CanonicalCatalogReader(databaseURL: url)
            for (index, root) in try reader.roots().enumerated() {
                try write(ScannerEvent(kind: .sourceDiscovered, sequence: index, path: root.path))
            }
        default:
            try writeFatal("Unknown catalog action: \(action)")
            throw Exit.code(64)
        }
    }

    private static func runScan(_ arguments: [String]) async throws {
        let mode: ScanMode = arguments.contains("--new") ? .newScan : .incremental
        var inspectionPermits = 8
        if let index = arguments.firstIndex(of: "--permits"), index + 1 < arguments.count {
            inspectionPermits = Int(arguments[index + 1]).flatMap { $0 > 0 ? $0 : nil } ?? inspectionPermits
        }
        var archivePipelineLimit = 4
        if let index = arguments.firstIndex(of: "--archive-limit"), index + 1 < arguments.count {
            archivePipelineLimit = Int(arguments[index + 1]).flatMap { $0 > 0 ? $0 : nil } ?? archivePipelineLimit
        }
        var optionIndexes: Set<Int> = []
        for (index, argument) in arguments.enumerated() {
            if argument == "--permits" || argument == "--archive-limit" {
                optionIndexes.insert(index)
                if index + 1 < arguments.count { optionIndexes.insert(index + 1) }
            }
        }
        let paths = arguments.enumerated().compactMap { item -> String? in
            guard !optionIndexes.contains(item.offset), !item.element.hasPrefix("--") else { return nil }
            return item.element
        }
        guard paths.count >= 2 else {
            try writeFatal("scan requires a catalog path and at least one root folder")
            throw Exit.code(64)
        }
        let databaseURL = URL(fileURLWithPath: paths[0]).standardizedFileURL
        let roots = paths.dropFirst().map { URL(fileURLWithPath: $0).standardizedFileURL }
        let scanner = try CatalogScanner(
            databaseURL: databaseURL,
            inspectionPermits: inspectionPermits,
            archivePipelineLimit: archivePipelineLimit
        )
        try write(ScannerEvent(kind: .sessionStarted, sequence: 0, path: databaseURL.path))
        let events = SequencedEventWriter(startingAt: 1)
        let progressReporter = ScanProgressReporter()

        let operation = Task {
            var discovered = 0
            var accepted = 0
            var failed = 0
            var phaseMilliseconds: [ScanLifecyclePhase: Int] = [:]
            let results = try await scanner.scan(rootURLs: roots, mode: mode) { update in
                progressReporter.emit(update, to: events)
            }
            for result in results {
                discovered += result.discoveredSourceCount
                accepted += result.trackCount
                failed += result.failures.count
                for (phase, milliseconds) in result.telemetry.phaseMilliseconds {
                    phaseMilliseconds[phase, default: 0] += milliseconds
                }
                for failure in result.failures {
                    events.emit { sequence in
                        ScannerEvent(
                            kind: .diagnostic,
                            sequence: sequence,
                            path: failure.identity.archiveEntry.map { "\(failure.identity.path)#\($0)" } ?? failure.identity.path,
                            route: failure.route,
                            diagnostic: ScannerDiagnostic(
                                code: "scan.\(failure.stage.rawValue)",
                                severity: .error,
                                message: failure.message
                            )
                        )
                    }
                }
                if !result.skipped.isEmpty {
                    let counts = Dictionary(grouping: result.skipped, by: \.extensionName)
                        .mapValues(\.count)
                        .sorted { $0.key < $1.key }
                        .map { ".\($0.key): \($0.value)" }
                        .joined(separator: ", ")
                    events.emit { sequence in
                        ScannerEvent(
                            kind: .diagnostic,
                            sequence: sequence,
                            path: result.root.path,
                            diagnostic: ScannerDiagnostic(
                                code: "scan.skipped.summary",
                                severity: .warning,
                                message: "Explicitly ignored files were recorded in the scan log (\(counts))."
                            )
                        )
                    }
                }
            }
            events.emit { sequence in
                ScannerEvent(
                    kind: .sessionFinished,
                    sequence: sequence,
                    discovered: discovered,
                    accepted: accepted,
                    failed: failed,
                    unsupported: failed,
                    telemetry: ScanPhaseTelemetry(elapsedMilliseconds: phaseMilliseconds.values.reduce(0, +), phaseMilliseconds: phaseMilliseconds)
                )
            }
            return failed
        }

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global(qos: .utility))
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .utility))
        interrupt.setEventHandler { operation.cancel() }
        termination.setEventHandler { operation.cancel() }
        interrupt.resume()
        termination.resume()
        defer {
            interrupt.cancel()
            termination.cancel()
        }
        let failureCount = try await operation.value
        if failureCount > 0 { throw Exit.code(2) }
    }
}
