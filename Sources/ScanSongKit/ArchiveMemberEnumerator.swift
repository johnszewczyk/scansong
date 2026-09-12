import Foundation

struct ArchiveMemberEnumerator {
    private let fileManager: FileManager

    // These files describe or feed a playable member but are not playable
    // sources themselves. They must stay out of the unrecognized inventory so
    // archives do not produce one diagnostic per decoder sidecar.
    private static let supportFileExtensions: Set<String> = [
        "2sflib", "bd", "gsflib", "pdx", "psflib", "qsflib", "ssflib",
        "pcm", "sbb", "smp", "txth", "txt", "usflib"
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enumerate(
        payloadURL: URL,
        registry: ScannerPluginRegistry,
        ignoredFileExtensions: Set<String>,
        dependencyPaths: Set<String>
    ) throws -> (members: [ExtractedScanArchive.Member], skipped: [ExtractedScanArchive.SkippedMember]) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: payloadURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        let canonicalRoot = payloadURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var totalBytes: Int64 = 0
        var fileCount = 0
        var members: [ExtractedScanArchive.Member] = []
        var skipped: [ExtractedScanArchive.SkippedMember] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw StandaloneArchiveError.unsafeEntry(fileURL.path)
            }
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            guard fileCount <= StandaloneArchiveExtractor.maximumMemberCount else {
                throw StandaloneArchiveError.resourceLimit(
                    "Archive exceeds the \(StandaloneArchiveExtractor.maximumMemberCount)-member safety limit."
                )
            }
            let standardizedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard standardizedPath.hasPrefix(canonicalRoot) else {
                throw StandaloneArchiveError.unsafeEntry(standardizedPath)
            }
            let size = Int64(values.fileSize ?? 0)
            let (expandedBytes, overflow) = totalBytes.addingReportingOverflow(size)
            guard !overflow, expandedBytes <= StandaloneArchiveExtractor.maximumExpandedBytes else {
                throw StandaloneArchiveError.resourceLimit("Archive expands beyond the 8 GiB scan safety limit.")
            }
            totalBytes = expandedBytes
            let entry = String(standardizedPath.dropFirst(canonicalRoot.count))
            guard StandaloneArchiveExtractor.isSafeRelativePath(entry) else {
                throw StandaloneArchiveError.unsafeEntry(entry)
            }
            if dependencyPaths.contains(standardizedPath) { continue }
            let extensionName = ScannerFormatPolicy.normalize(fileURL.pathExtension)
            if ignoredFileExtensions.contains(extensionName) {
                skipped.append(.init(entryPath: entry, extensionName: extensionName, reason: .explicitlyIgnored))
                continue
            }
            // PDX is native MDX sample-bank data, not an independent playable
            // source. Apply the support-file rule before the path-aware Amiga
            // prefix router, because names such as `star.pdx` can otherwise
            // be mistaken for Amiga modules.
            if !extensionName.isEmpty && Self.supportFileExtensions.contains(extensionName) {
                continue
            }
            guard let route = registry.route(forPath: fileURL.path, archiveMember: true) else {
                if !extensionName.isEmpty {
                    skipped.append(.init(entryPath: entry, extensionName: extensionName, reason: .unsupportedFormat))
                }
                continue
            }
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
        return (
            members.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending },
            skipped.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending }
        )
    }
}
