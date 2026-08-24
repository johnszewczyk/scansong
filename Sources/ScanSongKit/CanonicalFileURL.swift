import Darwin
import Foundation

enum CanonicalFileURL {
    static func resolve(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard let resolved = realpath(standardized.path, nil) else { return standardized }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: standardized.hasDirectoryPath)
    }
}
