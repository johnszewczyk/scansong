import Foundation

/// Materializes paths authored by TXTP manifests inside a disposable archive
/// payload and identifies the underlying streams that must not be published a
/// second time as standalone tracks.
struct TXTPDependencyResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareDependencies(in rootURL: URL) throws -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var filesByLeafName: [String: [URL]] = [:]
        var txtpFiles: [URL] = []
        var dependencyPaths: Set<String> = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if fileURL.pathExtension.lowercased() == "txtp" {
                txtpFiles.append(fileURL)
            } else {
                filesByLeafName[fileURL.lastPathComponent, default: []].append(fileURL)
            }
        }

        for txtpURL in txtpFiles {
            guard let contents = try? String(contentsOf: txtpURL, encoding: .utf8) else { continue }
            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let rawReference = rawLine
                    .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let reference = rawReference.replacingOccurrences(of: "\\", with: "/")
                guard !reference.isEmpty,
                      !reference.hasPrefix("/"),
                      !reference.contains("..") else { continue }

                let aliasURL = txtpURL.deletingLastPathComponent()
                    .appendingPathComponent(reference, isDirectory: false)
                if fileManager.fileExists(atPath: aliasURL.path) {
                    dependencyPaths.insert(aliasURL.standardizedFileURL.path)
                    continue
                }
                guard let leafName = reference.split(separator: "/").last.map(String.init),
                      let candidates = filesByLeafName[leafName],
                      candidates.count == 1 else { continue }
                try fileManager.createDirectory(
                    at: aliasURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.linkItem(at: candidates[0], to: aliasURL)
                dependencyPaths.insert(candidates[0].standardizedFileURL.path)
                dependencyPaths.insert(aliasURL.standardizedFileURL.path)
            }
        }
        return dependencyPaths
    }
}
