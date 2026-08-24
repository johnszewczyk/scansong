import Foundation

struct CatalogSourceLink: Hashable, Sendable {
    let rootID: Int64
    let path: String
}

/// Filesystem-facing half of catalog link maintenance. Database mutation stays
/// in the writer transaction; this type only determines which attached source
/// paths have actually disappeared.
struct CatalogLinkAuditor {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func missingSources(
        among sources: [CatalogSourceLink],
        progress: (@Sendable (CatalogMaintenanceProgress) -> Void)?
    ) throws -> [CatalogSourceLink] {
        var missing: [CatalogSourceLink] = []
        progress?(CatalogMaintenanceProgress(
            operation: .checkLinks,
            processed: 0,
            total: sources.count,
            detail: "Checking \(sources.count) catalog links…"
        ))
        for (index, source) in sources.enumerated() {
            progress?(CatalogMaintenanceProgress(
                operation: .checkLinks,
                processed: index,
                total: sources.count,
                currentPath: source.path,
                detail: "Checking link \(index + 1) of \(sources.count)…"
            ))
            do {
                _ = try fileManager.attributesOfItem(atPath: source.path)
            } catch {
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain,
                   (cocoa.code == NSFileReadNoSuchFileError
                       || cocoa.code == CocoaError.fileNoSuchFile.rawValue) {
                    missing.append(source)
                } else {
                    throw NSError(
                        domain: "ScanSong.CatalogLinkAuditor",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not inspect \(source.path): \(error.localizedDescription)"
                        ]
                    )
                }
            }
        }
        return missing
    }
}
