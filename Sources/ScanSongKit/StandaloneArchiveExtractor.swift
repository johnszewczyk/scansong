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

    // Companion files are inputs to another playable member, not standalone
    // scan sources. This list mirrors ArchiveMemberEnumerator's archive-side
    // dependency policy and also applies to standalone .zst wrappers.
    private static let supportFileExtensions: Set<String> = [
        "2sflib", "bd", "gsflib", "pdx", "psflib", "qsflib", "ssflib",
        "pcm", "sbb", "smp", "txth", "txt", "usflib"
    ]

    private var fileManager: FileManager { .default }
    private let dependencyIndex: MDXDependencyIndex

    public init() {
        dependencyIndex = MDXDependencyIndex()
    }

    public static func isSupportedArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".7z", ".lha", ".rar", ".rsn", ".tar.zst", ".tar.zstd", ".tzst", ".zip", ".zst", ".zstd"]
            .contains { name.hasSuffix($0) }
    }

    /// A standalone Zstandard file has one implicit member. The outer name
    /// carries that member's playable extension: `track.vgm.zst` becomes
    /// `track.vgm`. Unknown or extensionless payloads are rejected instead of
    /// being admitted as an opaque archive.
    static func standaloneEntryPath(
        for archiveURL: URL,
        registry: ScannerPluginRegistry
    ) -> String? {
        guard isStandaloneZstandard(archiveURL) else { return nil }
        let entryPath = archiveURL.deletingPathExtension().lastPathComponent
        guard isSafeRelativePath(entryPath),
              !entryPath.isEmpty,
              registry.route(
                  pathExtension: URL(fileURLWithPath: entryPath).pathExtension,
                  archiveMember: true
              ) != nil else {
            return nil
        }
        return entryPath
    }

    public func extractForScan(
        archiveURL: URL,
        registry: ScannerPluginRegistry = BuiltInScannerPlugins.registry,
        ignoredFileExtensions: Set<String> = [],
        dependencySearchRoot: URL? = nil
    ) async throws -> ExtractedScanArchive {
        try Task.checkCancellation()
        let root = try makeScratchDirectory()
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: payload, withIntermediateDirectories: true)
        do {
            if Self.isTarZstandard(archiveURL) {
                try await extractTarZstandard(archiveURL: archiveURL, payloadURL: payload, scratchURL: root)
            } else if Self.isStandaloneZstandard(archiveURL) {
                guard let entryPath = Self.standaloneEntryPath(for: archiveURL, registry: registry) else {
                    throw StandaloneArchiveError.unsupported(archiveURL.lastPathComponent)
                }
                try await extractStandaloneZstandard(
                    archiveURL: archiveURL,
                    entryPath: entryPath,
                    payloadURL: payload,
                    scratchURL: root
                )
                if URL(fileURLWithPath: entryPath).pathExtension.lowercased() == "mdx" {
                    try await materializeStandaloneMDXDependency(
                        archiveURL: archiveURL,
                        entryPath: entryPath,
                        payloadURL: payload,
                        scratchURL: root,
                        dependencySearchRoot: dependencySearchRoot
                    )
                }
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

    private func extractStandaloneZstandard(
        archiveURL: URL,
        entryPath: String,
        payloadURL: URL,
        scratchURL: URL
    ) async throws {
        let zstandard = try requiredTool([
            "/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"
        ])
        let outputURL = payloadURL.appendingPathComponent(entryPath, isDirectory: false)
        // `entryPath` is admitted only after this relative-path check. Do not
        // compare standardized absolute strings here: macOS can spell the same
        // temporary directory as both /tmp and /private/tmp depending on whether
        // the final member exists yet.
        guard Self.isSafeRelativePath(entryPath) else {
            throw StandaloneArchiveError.unsafeEntry(entryPath)
        }
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try await ScannerCommand.runWritingOutput(
                executable: zstandard,
                arguments: ["-d", "-q", "-c", "--", archiveURL.path],
                outputURL: outputURL,
                logURL: scratchURL.appendingPathComponent("zstd.log")
            )
            let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount > 0 else {
                throw StandaloneArchiveError.resourceLimit("Standalone Zstandard payload is empty.")
            }
            guard byteCount <= Self.maximumExpandedBytes else {
                throw StandaloneArchiveError.resourceLimit(
                    "Standalone Zstandard payload expands beyond the 8 GiB scan safety limit."
                )
            }
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    private func materializeStandaloneMDXDependency(
        archiveURL: URL,
        entryPath: String,
        payloadURL: URL,
        scratchURL: URL,
        dependencySearchRoot: URL?
    ) async throws {
        let mdxURL = payloadURL.appendingPathComponent(entryPath)
        let data = try Data(contentsOf: mdxURL)
        guard let dependencyName = MDXDependencyReader.dependencyName(in: data) else { return }
        guard Self.isSafeRelativePath(dependencyName) else {
            throw StandaloneArchiveError.unsafeEntry(dependencyName)
        }

        let requestedName = (dependencyName as NSString).lastPathComponent
        let requestedDirectory = (dependencyName as NSString).deletingLastPathComponent
        let sourceDirectory = requestedDirectory == "."
            ? archiveURL.deletingLastPathComponent()
            : archiveURL.deletingLastPathComponent()
                .appendingPathComponent(requestedDirectory)
                .standardizedFileURL
        let outputURL = payloadURL.appendingPathComponent(dependencyName)
        guard Self.isSafeRelativePath(dependencyName) else {
            throw StandaloneArchiveError.unsafeEntry(dependencyName)
        }
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let directoryContents = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let regularFiles = directoryContents.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { left, right in
            left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
        let localSource = regularFiles.first { candidate in
            let candidateName = candidate.lastPathComponent
            return candidateName.caseInsensitiveCompare(requestedName) == .orderedSame
        } ?? regularFiles.first { candidate in
            let candidateName = candidate.lastPathComponent
            return candidateName.caseInsensitiveCompare(requestedName + ".zst") == .orderedSame
                || candidateName.caseInsensitiveCompare(requestedName + ".zstd") == .orderedSame
        }
        let source = localSource ?? dependencySearchRoot.flatMap {
            dependencyIndex.bestMatch(
                named: requestedName,
                for: archiveURL,
                under: $0
            )
        }
        guard let source else { return }

        try? fileManager.removeItem(at: outputURL)
        let sourceName = source.lastPathComponent.lowercased()
        if sourceName.hasSuffix(".zst") || sourceName.hasSuffix(".zstd") {
            let zstandard = try requiredTool([
                "/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"
            ])
            try await ScannerCommand.runWritingOutput(
                executable: zstandard,
                arguments: ["-d", "-q", "-c", "--", source.path],
                outputURL: outputURL,
                logURL: scratchURL.appendingPathComponent("mdx-dependency-zstd.log")
            )
        } else {
            try fileManager.copyItem(at: source, to: outputURL)
        }

        let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 else {
            throw StandaloneArchiveError.resourceLimit("MDX dependency is empty: \(dependencyName)")
        }
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

    static func isStandaloneSupportFile(_ url: URL) -> Bool {
        guard isStandaloneZstandard(url) else { return false }
        return supportFileExtensions.contains(url.deletingPathExtension().pathExtension.lowercased())
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

    private static func isTarZstandard(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.zst") || name.hasSuffix(".tar.zstd") || name.hasSuffix(".tzst")
    }

    private static func isStandaloneZstandard(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return (name.hasSuffix(".zst") || name.hasSuffix(".zstd")) && !isTarZstandard(url)
    }

}

enum MDXDependencyReader {
    /// Returns the dependency name as declared by the MDX header.
    ///
    /// X68000 files commonly omit the `.PDX` suffix, so that suffix remains
    /// the inference for an extensionless reference. An explicit alternate
    /// extension is authoritative: `NOS.SMP` must stay `NOS.SMP`, not become
    /// the impossible `NOS.SMP.PDX`.
    static func dependencyName(in data: Data) -> String? {
        let marker = Data([0x0D, 0x0A, 0x1A])
        guard let markerRange = data.range(of: marker) else { return nil }
        let dependencyStart = markerRange.upperBound
        guard dependencyStart < data.endIndex else { return nil }
        let remainder = data[dependencyStart...]
        guard let terminator = remainder.firstIndex(of: 0x00) else { return nil }
        let rawName = remainder[..<terminator]
        guard !rawName.isEmpty else { return nil }
        // MDX files traditionally store the companion dependency in the X68000
        // locale encoding. Decoding those bytes as UTF-8 turns a valid
        // Japanese filename into replacement characters (and can introduce
        // apparent path separators), which then looks like an unsafe member.
        // Prefer Shift-JIS, with UTF-8 as a compatibility fallback for newer
        // hand-authored modules.
        var name = String(data: Data(rawName), encoding: .shiftJIS)
            ?? String(data: Data(rawName), encoding: .utf8)
            ?? String(decoding: rawName, as: UTF8.self)
        // A legacy X68000 writer used `\name` for a same-directory dependency
        // basename. Strip only those leading backslashes; traversal and any
        // remaining backslash syntax stay rejected by isSafeRelativePath.
        while name.hasPrefix("\\") {
            name.removeFirst()
        }
        guard !name.isEmpty else { return nil }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            name += ".pdx"
        }
        return name
    }

    static func siblingURL(named name: String, beside fileURL: URL) -> URL? {
        let requestedURL = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        if (try? requestedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return requestedURL
        }

        let directory = requestedURL.deletingLastPathComponent()
        let requestedBasename = requestedURL.lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .first { $0.lastPathComponent.caseInsensitiveCompare(requestedBasename) == .orderedSame }
    }
}

/// Indexes MDX dependency sidecars within one explicitly supplied scan root. The source
/// library may flatten MDX modules and their banks into different subfolders,
/// so sibling lookup alone is insufficient. The index is built at most once
/// per root and a match is selected deterministically: nearest shared path,
/// uncompressed before compressed, then lexical path order.
private final class MDXDependencyIndex: @unchecked Sendable {
    private static let dependencyExtensions: Set<String> = ["mdx", "pdx", "pcm", "smp"]
    private let lock = NSLock()
    private var indexes: [String: [String: [URL]]] = [:]

    func bestMatch(named: String, for archiveURL: URL, under rootURL: URL) -> URL? {
        let root = rootURL.standardizedFileURL
        let rootPath = root.path
        let candidates = lock.withLock {
            if indexes[rootPath] == nil {
                indexes[rootPath] = buildIndex(root: root)
            }
            return indexes[rootPath]?[named.lowercased()] ?? []
        }
        guard !candidates.isEmpty else { return nil }

        let sourceDirectory = archiveURL.deletingLastPathComponent().standardizedFileURL
        return candidates.sorted { left, right in
            let leftShared = sharedPathLength(sourceDirectory, left.deletingLastPathComponent())
            let rightShared = sharedPathLength(sourceDirectory, right.deletingLastPathComponent())
            if leftShared != rightShared { return leftShared > rightShared }

            let leftCompressed = left.lastPathComponent.lowercased().hasSuffix(".zst")
                || left.lastPathComponent.lowercased().hasSuffix(".zstd")
            let rightCompressed = right.lastPathComponent.lowercased().hasSuffix(".zst")
                || right.lastPathComponent.lowercased().hasSuffix(".zstd")
            if leftCompressed != rightCompressed { return !leftCompressed }
            return left.path.localizedStandardCompare(right.path) == .orderedAscending
        }.first
    }

    private func buildIndex(root: URL) -> [String: [URL]] {
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [:] }

        var result: [String: [URL]] = [:]
        for case let candidate as URL in enumerator {
            guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let lowerName = candidate.lastPathComponent.lowercased()
            let logicalName: String
            if lowerName.hasSuffix(".zstd") {
                logicalName = String(lowerName.dropLast(5))
            } else if lowerName.hasSuffix(".zst") {
                logicalName = String(lowerName.dropLast(4))
            } else {
                logicalName = lowerName
            }
            guard Self.dependencyExtensions.contains(URL(fileURLWithPath: logicalName).pathExtension) else {
                continue
            }
            result[logicalName, default: []].append(candidate.standardizedFileURL)
        }
        return result
    }

    private func sharedPathLength(_ left: URL, _ right: URL) -> Int {
        zip(left.pathComponents, right.pathComponents)
            .prefix { $0.0 == $0.1 }
            .count
    }
}

private final class ScannerPipelineStatus: @unchecked Sendable {
    enum ProcessKind {
        case zstandard
        case tar
    }

    private enum State {
        case notStarted
        case running
        case finished
    }

    private let lock = NSLock()
    private var zstandardStatus: Int32?
    private var tarStatus: Int32?
    private var continuation: CheckedContinuation<(Int32, Int32), Error>?
    private var failure: Error?
    private var zstandardState: State = .notStarted
    private var tarState: State = .notStarted
    private var didResume = false

    func install(_ continuation: CheckedContinuation<(Int32, Int32), Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func begin(_ process: ProcessKind) {
        lock.withLock {
            switch process {
            case .zstandard: zstandardState = .running
            case .tar: tarState = .running
            }
        }
    }

    func finishWithoutLaunch(_ process: ProcessKind) {
        lock.withLock {
            switch process {
            case .zstandard: zstandardState = .finished
            case .tar: tarState = .finished
            }
            finishIfReadyLocked()
        }
    }

    func recordZstandard(_ status: Int32) {
        lock.withLock {
            zstandardStatus = status
            zstandardState = .finished
            finishIfReadyLocked()
        }
    }

    func recordTar(_ status: Int32) {
        lock.withLock {
            tarStatus = status
            tarState = .finished
            finishIfReadyLocked()
        }
    }

    func fail(_ error: Error) {
        lock.withLock {
            guard !didResume else { return }
            failure = error
            finishIfReadyLocked()
        }
    }

    private func finishIfReadyLocked() {
        guard !didResume,
              zstandardState == .finished,
              tarState == .finished,
              let continuation else { return }
        didResume = true
        if let failure {
            continuation.resume(throwing: failure)
        } else if let zstandardStatus, let tarStatus {
            continuation.resume(returning: (zstandardStatus, tarStatus))
        } else {
            continuation.resume(throwing: CancellationError())
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
        let box = ScannerManagedProcess()
        box.install(process)

        defer { box.clear(); try? log.close() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    guard try box.launch(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                } catch {
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

    static func runWritingOutput(
        executable: URL,
        arguments: [String],
        outputURL: URL,
        logURL: URL
    ) async throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let log = try FileHandle(forWritingTo: logURL)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = log
        let box = ScannerManagedProcess()
        box.install(process)

        defer { box.clear(); try? output.close(); try? log.close() }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    guard try box.launch(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
        try output.close()
        try log.close()
        if status != 0 {
            let detail = String(
                decoding: (try? Data(contentsOf: logURL))?.suffix(8_192) ?? Data(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if Task.isCancelled { throw CancellationError() }
            throw StandaloneArchiveError.commandFailed(
                tool: executable.lastPathComponent,
                status: status,
                detail: detail
            )
        }
        try Task.checkCancellation()
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

        let zstandardBox = ScannerManagedProcess()
        let tarBox = ScannerManagedProcess()
        zstandardBox.install(zstandardProcess)
        tarBox.install(tarProcess)
        defer {
            zstandardBox.clear()
            tarBox.clear()
            try? output.close()
            try? bridge.fileHandleForReading.close()
            try? bridge.fileHandleForWriting.close()
            try? zstandardError.fileHandleForReading.close()
            try? tarError.fileHandleForReading.close()
        }
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
                var tarLaunched = false
                var zstandardLaunched = false
                do {
                    completion.begin(.tar)
                    guard try tarBox.launch(tarProcess) else {
                        completion.finishWithoutLaunch(.tar)
                        throw CancellationError()
                    }
                    tarLaunched = true
                    completion.begin(.zstandard)
                    guard try zstandardBox.launch(zstandardProcess) else {
                        completion.finishWithoutLaunch(.zstandard)
                        throw CancellationError()
                    }
                    zstandardLaunched = true
                } catch {
                    if !tarLaunched { completion.finishWithoutLaunch(.tar) }
                    if !zstandardLaunched { completion.finishWithoutLaunch(.zstandard) }
                    tarBox.terminate()
                    zstandardBox.terminate()
                    completion.fail(error)
                }
            }
        } onCancel: {
            tarBox.terminate()
            zstandardBox.terminate()
        }
        try output.close()
        outputClosed = true

        let standardOutput = (try? Data(contentsOf: logURL)) ?? Data()
        let errorOutput = zstandardError.fileHandleForReading.readDataToEndOfFile()
            + tarError.fileHandleForReading.readDataToEndOfFile()
        let combinedOutput = standardOutput + errorOutput
        try combinedOutput.write(to: logURL, options: .atomic)
        if Task.isCancelled { throw CancellationError() }
        if status.0 != 0, status.1 == 0 {
            // Some tar readers stop at the standard end-of-archive blocks
            // without draining trailing bytes from the compressed frame. In
            // that case zstd can receive SIGPIPE even though tar accepted the
            // archive. Accept that pipeline result only after a complete
            // standalone pass verifies the entire compressed source.
            let verificationLogURL = logURL.appendingPathExtension("zstd-verification")
            defer { try? FileManager.default.removeItem(at: verificationLogURL) }
            do {
                _ = try await run(
                    executable: zstandard,
                    arguments: ["-t", "--", archiveURL.path],
                    logURL: verificationLogURL
                )
                return combinedOutput
            } catch {
                let detail = String(decoding: errorOutput.suffix(8_192), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw StandaloneArchiveError.commandFailed(
                    tool: zstandard.lastPathComponent,
                    status: status.0,
                    detail: "TAR accepted the archive, but the complete Zstandard frame did not verify: \(error.localizedDescription). \(detail)"
                )
            }
        }
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
