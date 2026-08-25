import Foundation

public struct ExtractedScanArchive: Sendable {
    public struct Member: Sendable {
        public let entryPath: String
        public let fileURL: URL
        public let fingerprint: ScanFingerprint
        public let route: ScannerRoute
    }

    public struct SkippedMember: Sendable {
        public let entryPath: String
        public let extensionName: String
        public let reason: ScanSkipReason
    }

    public let archiveURL: URL
    public let scratchURL: URL
    public let members: [Member]
    public let skippedMembers: [SkippedMember]
}

public enum StandaloneArchiveError: LocalizedError {
    case unsupported(String)
    case missingTool(String)
    case commandFailed(tool: String, status: Int32, detail: String)
    case unsafeEntry(String)
    case resourceLimit(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): return "Unsupported archive container: \(name)"
        case .missingTool(let path): return "Required archive tool is unavailable: \(path)"
        case .commandFailed(let tool, let status, let detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "\(tool) failed with exit code \(status)\(suffix)"
        case .unsafeEntry(let entry): return "Archive contains an unsafe member path: \(entry)"
        case .resourceLimit(let message): return message
        }
    }
}

public struct StandaloneArchiveExtractor: Sendable {
    public static let maximumMemberCount = 100_000
    public static let maximumExpandedBytes: Int64 = 8 * 1_024 * 1_024 * 1_024

    private var fileManager: FileManager { .default }

    public init() {}

    public static func isSupportedArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".7z", ".rar", ".rsn", ".tar.zst", ".tar.zstd", ".tzst", ".zip"]
            .contains { name.hasSuffix($0) }
    }

    public func extractForScan(
        archiveURL: URL,
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        ignoredFileExtensions: Set<String> = []
    ) async throws -> ExtractedScanArchive {
        try Task.checkCancellation()
        let root = try makeScratchDirectory()
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        do {
            if isTarZstandard(archiveURL) {
                try await extractTarZstandard(archiveURL: archiveURL, payloadURL: payload, scratchURL: root)
            } else {
                try await extractWith7Zip(archiveURL: archiveURL, payloadURL: payload, scratchURL: root)
            }
            try normalizeExtractedDirectories(at: payload)
            try normalizeExtractedTXTHAliases(at: payload)
            let txtpDependencyPaths = try TXTPDependencyResolver().prepareDependencies(in: payload)
            let listing = try ArchiveMemberEnumerator().enumerate(
                payloadURL: payload,
                registry: registry,
                ignoredFileExtensions: ignoredFileExtensions,
                dependencyPaths: txtpDependencyPaths
            )
            return ExtractedScanArchive(
                archiveURL: archiveURL,
                scratchURL: root,
                members: listing.members,
                skippedMembers: listing.skipped
            )
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    public func discard(_ extracted: ExtractedScanArchive) {
        try? fileManager.removeItem(at: extracted.scratchURL)
    }

    private func extractTarZstandard(archiveURL: URL, payloadURL: URL, scratchURL: URL) async throws {
        let listing = try await ScannerCommand.runTarZstandard(
            archiveURL: archiveURL,
            tarArguments: ["-tf", "-"],
            logURL: scratchURL.appendingPathComponent("tar-list.log")
        )
        try validateTarListing(listing)
        let verboseListing = try await ScannerCommand.runTarZstandard(
            archiveURL: archiveURL,
            tarArguments: ["-tvf", "-"],
            logURL: scratchURL.appendingPathComponent("tar-verbose-list.log")
        )
        try validateTarExpandedSize(verboseListing)
        _ = try await ScannerCommand.runTarZstandard(
            archiveURL: archiveURL,
            tarArguments: ["-xf", "-", "-C", payloadURL.path],
            logURL: scratchURL.appendingPathComponent("tar-extract.log")
        )
    }

    private func extractWith7Zip(archiveURL: URL, payloadURL: URL, scratchURL: URL) async throws {
        guard Self.isSupportedArchive(archiveURL) else {
            throw StandaloneArchiveError.unsupported(archiveURL.lastPathComponent)
        }
        let sevenZip = try requiredTool([
            "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z"
        ])
        _ = try await ScannerCommand.run(
            executable: sevenZip,
            arguments: ["x", "-mmt=1", "-y", "-o\(payloadURL.path)", archiveURL.path],
            logURL: scratchURL.appendingPathComponent("7zip.log")
        )
    }

    private func normalizeExtractedDirectories(at rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private func normalizeExtractedTXTHAliases(at rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = url.lastPathComponent
            guard name.hasPrefix("_."), name.lowercased().hasSuffix(".txth") else { continue }

            let canonicalName = "." + String(name.dropFirst(2))
            let canonicalURL = url.deletingLastPathComponent().appendingPathComponent(canonicalName)
            guard !fileManager.fileExists(atPath: canonicalURL.path) else { continue }
            try fileManager.copyItem(at: url, to: canonicalURL)
        }
    }

    private func validateTarListing(_ data: Data) throws {
        let entries = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard entries.count <= Self.maximumMemberCount else {
            throw StandaloneArchiveError.resourceLimit("Archive exceeds the \(Self.maximumMemberCount)-member safety limit.")
        }
        for entry in entries {
            let path = String(entry)
            guard Self.isSafeRelativePath(path) else { throw StandaloneArchiveError.unsafeEntry(path) }
        }
    }

    private func validateTarExpandedSize(_ data: Data) throws {
        var parsedEntries = 0
        var totalBytes: Int64 = 0
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count > 4, let size = Int64(fields[4]) else { continue }
            parsedEntries += 1
            let (sum, overflow) = totalBytes.addingReportingOverflow(size)
            guard !overflow else {
                throw StandaloneArchiveError.resourceLimit("Archive expanded size exceeds the scanner safety limit.")
            }
            totalBytes = sum
            guard totalBytes <= Self.maximumExpandedBytes else {
                throw StandaloneArchiveError.resourceLimit("Archive expands beyond the 8 GiB scan safety limit.")
            }
        }
        // macOS tar emits a size field for regular files. If a future tar
        // format changes that output, the post-extraction member accounting
        // remains the fallback safety check.
        _ = parsedEntries
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private func makeScratchDirectory() throws -> URL {
        let cache = fileManager.temporaryDirectory
            .appendingPathComponent("ScanSong-ScanScratch", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        reapStaleScratchDirectories(in: cache)
        let root = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func reapStaleScratchDirectories(in cache: URL) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cache,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func requiredTool(_ candidates: [String]) throws -> URL {
        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw StandaloneArchiveError.missingTool(candidates.joined(separator: " or "))
        }
        return URL(fileURLWithPath: path)
    }

    private func isTarZstandard(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.zst") || name.hasSuffix(".tar.zstd") || name.hasSuffix(".tzst")
    }

}

private final class ScannerProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func install(_ process: Process) { lock.withLock { self.process = process } }
    func clear() { lock.withLock { process = nil } }
    func terminate() {
        lock.withLock {
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }
}

private final class ScannerPipelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []

    func install(_ processes: [Process]) {
        lock.withLock { self.processes = processes }
    }

    func terminate() {
        lock.withLock {
            for process in processes where process.isRunning {
                process.terminate()
            }
        }
    }
}

private final class ScannerPipelineStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var zstandardStatus: Int32?
    private var tarStatus: Int32?
    private var continuation: CheckedContinuation<(Int32, Int32), Error>?
    private var didResume = false

    func install(_ continuation: CheckedContinuation<(Int32, Int32), Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func recordZstandard(_ status: Int32) {
        finishIfReady(zstandard: status, tar: nil)
    }

    func recordTar(_ status: Int32) {
        finishIfReady(zstandard: nil, tar: status)
    }

    func fail(_ error: Error) {
        lock.withLock {
            guard !didResume, let continuation else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }

    private func finishIfReady(zstandard: Int32?, tar: Int32?) {
        lock.withLock {
            if let zstandard { zstandardStatus = zstandard }
            if let tar { tarStatus = tar }
            guard !didResume,
                  let zstandardStatus,
                  let tarStatus,
                  let continuation else { return }
            didResume = true
            continuation.resume(returning: (zstandardStatus, tarStatus))
        }
    }
}

private enum ScannerCommand {
    private static func requiredTool(_ candidates: [String]) throws -> URL {
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw StandaloneArchiveError.missingTool(candidates.joined(separator: " or "))
        }
        return URL(fileURLWithPath: path)
    }

    static func run(executable: URL, arguments: [String], logURL: URL) async throws -> Data {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log
        let box = ScannerProcessBox()
        box.install(process)

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    box.clear()
                    continuation.resume(returning: finished.terminationStatus)
                }
                do { try process.run() }
                catch {
                    box.clear()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
        try log.close()
        let output = (try? Data(contentsOf: logURL)) ?? Data()
        if status != 0 {
            let detail = String(decoding: output.suffix(8_192), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if Task.isCancelled { throw CancellationError() }
            throw StandaloneArchiveError.commandFailed(
                tool: executable.lastPathComponent,
                status: status,
                detail: detail
            )
        }
        try Task.checkCancellation()
        return output
    }

    static func runTarZstandard(
        archiveURL: URL,
        tarArguments: [String],
        logURL: URL
    ) async throws -> Data {
        let zstandard = try requiredTool([
            "/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"
        ])
        let tar = try requiredTool(["/usr/bin/tar"])
        let bridge = Pipe()
        let zstandardError = Pipe()
        let tarError = Pipe()
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: logURL)
        var outputClosed = false
        defer {
            if !outputClosed { try? output.close() }
        }

        let zstandardProcess = Process()
        zstandardProcess.executableURL = zstandard
        zstandardProcess.arguments = ["-dc", "--", archiveURL.path]
        zstandardProcess.standardOutput = bridge
        zstandardProcess.standardError = zstandardError

        let tarProcess = Process()
        tarProcess.executableURL = tar
        tarProcess.arguments = tarArguments
        tarProcess.standardInput = bridge
        tarProcess.standardOutput = output
        tarProcess.standardError = tarError

        let pipeline = ScannerPipelineBox()
        pipeline.install([zstandardProcess, tarProcess])
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completion = ScannerPipelineStatus()
                completion.install(continuation)
                zstandardProcess.terminationHandler = { process in
                    completion.recordZstandard(process.terminationStatus)
                }
                tarProcess.terminationHandler = { process in
                    completion.recordTar(process.terminationStatus)
                }
                do {
                    try tarProcess.run()
                    try zstandardProcess.run()
                } catch {
                    pipeline.terminate()
                    completion.fail(error)
                }
            }
        } onCancel: {
            pipeline.terminate()
        }
        try output.close()
        outputClosed = true

        let standardOutput = (try? Data(contentsOf: logURL)) ?? Data()
        let errorOutput = zstandardError.fileHandleForReading.readDataToEndOfFile()
            + tarError.fileHandleForReading.readDataToEndOfFile()
        let combinedOutput = standardOutput + errorOutput
        try combinedOutput.write(to: logURL, options: .atomic)
        if Task.isCancelled { throw CancellationError() }
        guard status.0 == 0, status.1 == 0 else {
            let failedTool = status.0 == 0 ? tar.lastPathComponent : zstandard.lastPathComponent
            let detail = String(decoding: errorOutput.suffix(8_192), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw StandaloneArchiveError.commandFailed(
                tool: failedTool,
                status: status.0 == 0 ? status.1 : status.0,
                detail: detail.isEmpty ? "No diagnostic output." : detail
            )
        }
        return combinedOutput
    }
}
