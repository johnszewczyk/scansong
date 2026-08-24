import Foundation

public struct DryRunProbeResult: Sendable {
    public let events: [ScannerEvent]
    public let hasErrors: Bool
}

public enum DryRunProbePhase: String, Sendable {
    case discovering
    case routing
    case finished
}

public struct DryRunProbeProgress: Sendable {
    public let phase: DryRunProbePhase
    public let path: String?
    public let discovered: Int
    public let processed: Int
    public let total: Int?

    public init(
        phase: DryRunProbePhase,
        path: String?,
        discovered: Int,
        processed: Int,
        total: Int?
    ) {
        self.phase = phase
        self.path = path
        self.discovered = discovered
        self.processed = processed
        self.total = total
    }
}

public enum DryRunProbeError: LocalizedError {
    case missingPath(String)
    case directoryRequiresRecursive(String)
    case unreadablePath(String)

    public var errorDescription: String? {
        switch self {
        case .missingPath(let path): "Input does not exist: \(path)"
        case .directoryRequiresRecursive(let path): "Directory input requires --recursive: \(path)"
        case .unreadablePath(let path): "Input is not readable: \(path)"
        }
    }
}

public struct DryRunProbe: Sendable {
    public let registry: ScannerPluginRegistry
    public let ignoredFileExtensions: Set<String>

    public init(
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        ignoredFileExtensions: Set<String> = ScannerFormatPolicy.defaultIgnoredExtensions
    ) {
        self.registry = registry
        self.ignoredFileExtensions = Set(ignoredFileExtensions.map(ScannerFormatPolicy.normalize))
    }

    public func run(
        paths: [String],
        recursive: Bool,
        strict: Bool,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (DryRunProbeProgress) -> Void = { _ in }
    ) throws -> DryRunProbeResult {
        var sequence = 0
        var events: [ScannerEvent] = [ScannerEvent(kind: .sessionStarted, sequence: sequence)]
        sequence += 1
        let inputs = try collectInputs(
            paths: paths,
            recursive: recursive,
            isCancelled: isCancelled,
            progress: progress
        )
        var accepted = 0
        var unsupported = 0

        for (index, url) in inputs.enumerated() {
            try checkCancellation(isCancelled)
            progress(DryRunProbeProgress(
                phase: .routing,
                path: url.path,
                discovered: inputs.count,
                processed: index,
                total: inputs.count
            ))
            events.append(ScannerEvent(kind: .sourceDiscovered, sequence: sequence, path: url.path))
            sequence += 1
            if ignoredFileExtensions.contains(ScannerFormatPolicy.normalize(url.pathExtension)) {
                events.append(ScannerEvent(
                    kind: .diagnostic,
                    sequence: sequence,
                    path: url.path,
                    diagnostic: ScannerDiagnostic(
                        code: "source.ignored",
                        severity: .warning,
                        message: "Ignored by the configured file-type policy."
                    )
                ))
            } else if let route = registry.route(pathExtension: url.pathExtension) {
                accepted += 1
                events.append(ScannerEvent(kind: .sourceRouted, sequence: sequence, path: url.path, route: route))
            } else if isArchive(url) {
                accepted += 1
                let route = ScannerRoute(pluginID: "archive", formatExtension: archiveExtension(url), structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder)
                events.append(ScannerEvent(kind: .sourceRouted, sequence: sequence, path: url.path, route: route))
            } else {
                unsupported += 1
                events.append(ScannerEvent(
                    kind: .diagnostic,
                    sequence: sequence,
                    path: url.path,
                    diagnostic: ScannerDiagnostic(
                        code: "source.unrecognized",
                        severity: strict ? .error : .warning,
                        message: "No scanner plugin recognizes this input."
                    )
                ))
            }
            sequence += 1
        }

        try checkCancellation(isCancelled)
        progress(DryRunProbeProgress(
            phase: .finished,
            path: nil,
            discovered: inputs.count,
            processed: inputs.count,
            total: inputs.count
        ))

        events.append(ScannerEvent(
            kind: .sessionFinished,
            sequence: sequence,
            discovered: inputs.count,
            accepted: accepted,
            unsupported: unsupported
        ))
        return DryRunProbeResult(events: events, hasErrors: strict && unsupported > 0)
    }

    private func collectInputs(
        paths: [String],
        recursive: Bool,
        isCancelled: @Sendable () -> Bool,
        progress: @Sendable (DryRunProbeProgress) -> Void
    ) throws -> [URL] {
        var results: [URL] = []
        for path in paths {
            try checkCancellation(isCancelled)
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw DryRunProbeError.missingPath(url.path)
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw DryRunProbeError.unreadablePath(url.path)
            }
            if !isDirectory.boolValue {
                results.append(url)
                progress(DryRunProbeProgress(
                    phase: .discovering,
                    path: url.path,
                    discovered: results.count,
                    processed: 0,
                    total: nil
                ))
                continue
            }
            guard recursive else { throw DryRunProbeError.directoryRequiresRecursive(url.path) }
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw DryRunProbeError.unreadablePath(url.path)
            }
            for case let child as URL in enumerator {
                try checkCancellation(isCancelled)
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
                if values.isRegularFile == true && values.isHidden != true {
                    let standardizedChild = child.standardizedFileURL
                    results.append(standardizedChild)
                    progress(DryRunProbeProgress(
                        phase: .discovering,
                        path: standardizedChild.path,
                        discovered: results.count,
                        processed: 0,
                        total: nil
                    ))
                }
            }
        }
        return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
    }

    private func isArchive(_ url: URL) -> Bool {
        BuiltInScannerPlugins.archiveExtensions.contains(archiveExtension(url))
    }

    private func archiveExtension(_ url: URL) -> String {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.zstd") { return "tar.zstd" }
        if lower.hasSuffix(".tar.zst") { return "tar.zst" }
        return url.pathExtension.lowercased()
    }
}
