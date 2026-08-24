import Foundation

struct ArchiveMemberEnumerator {
    private let fileManager: FileManager

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

        let canonicalRoot = payloadURL.standardizedFileURL.path + "/"
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
            let standardizedPath = fileURL.standardizedFileURL.path
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
        return (
            members.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending },
            skipped.sorted { $0.entryPath.localizedStandardCompare($1.entryPath) == .orderedAscending }
        )
    }
}
