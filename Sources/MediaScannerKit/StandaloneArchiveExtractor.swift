import Foundation

public struct ExtractedScanArchive: Sendable {
    public struct Member: Sendable {
        public let entryPath: String
        public let fileURL: URL
        public let fingerprint: ScanFingerprint
        public let route: ScannerRoute
    }

    public let archiveURL: URL
    public let scratchURL: URL
    public let members: [Member]
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
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry
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
            let members = try enumerateMembers(payloadURL: payload, registry: registry)
            return ExtractedScanArchive(archiveURL: archiveURL, scratchURL: root, members: members)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    public func discard(_ extracted: ExtractedScanArchive) {
        try? fileManager.removeItem(at: extracted.scratchURL)
    }

    private func extractTarZstandard(archiveURL: URL, payloadURL: URL, scratchURL: URL) async throws {
        let zstd = try requiredTool(["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"])
        let tar = try requiredTool(["/usr/bin/tar"])
        let tarURL = scratchURL.appendingPathComponent("expanded.tar", isDirectory: false)

        _ = try await ScannerCommand.run(
            executable: zstd,
            arguments: ["-d", "-q", "-f", archiveURL.path, "-o", tarURL.path],
            logURL: scratchURL.appendingPathComponent("zstd.log")
        )
        try Task.checkCancellation()
        let listing = try await ScannerCommand.run(
            executable: tar,
            arguments: ["-tf", tarURL.path],
            logURL: scratchURL.appendingPathComponent("tar-list.log")
        )
        try validateTarListing(listing)
        _ = try await ScannerCommand.run(
            executable: tar,
            arguments: ["-xf", tarURL.path, "-C", payloadURL.path],
            logURL: scratchURL.appendingPathComponent("tar-extract.log")
        )
        try? fileManager.removeItem(at: tarURL)
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

    private func enumerateMembers(
        payloadURL: URL,
        registry: ScannerPluginRegistry
    ) throws -> [ExtractedScanArchive.Member] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: payloadURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let canonicalRoot = payloadURL.standardizedFileURL.path + "/"
        var totalBytes: Int64 = 0
        var fileCount = 0
        var members: [ExtractedScanArchive.Member] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                throw StandaloneArchiveError.unsafeEntry(fileURL.path)
            }
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            guard fileCount <= Self.maximumMemberCount else {
                throw StandaloneArchiveError.resourceLimit("Archive exceeds the \(Self.maximumMemberCount)-member safety limit.")
            }
            let standardizedPath = fileURL.standardizedFileURL.path
            guard standardizedPath.hasPrefix(canonicalRoot) else {
                throw StandaloneArchiveError.unsafeEntry(standardizedPath)
            }
            let size = Int64(values.fileSize ?? 0)
            totalBytes += size
            guard totalBytes <= Self.maximumExpandedBytes else {
                throw StandaloneArchiveError.resourceLimit("Archive expands beyond the 8 GiB scan safety limit.")
            }
            let entry = String(standardizedPath.dropFirst(canonicalRoot.count))
            guard Self.isSafeRelativePath(entry) else { throw StandaloneArchiveError.unsafeEntry(entry) }
            guard let route = registry.route(for: fileURL.pathExtension, archiveMember: true) else { continue }
            members.append(.init(
                entryPath: entry,
                fileURL: fileURL,
                fingerprint: ScanFingerprint(
                    fileSize: size,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ),
                route: route
            ))
        }
        return members.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending }
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

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private func makeScratchDirectory() throws -> URL {
        let cache = fileManager.temporaryDirectory
            .appendingPathComponent("MediaScanner-ScanScratch", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        let root = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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

private enum ScannerCommand {
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
}
