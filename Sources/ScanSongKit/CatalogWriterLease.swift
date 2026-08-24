import Darwin
import Foundation

/// An advisory, process-wide lease for the one component allowed to mutate a
/// catalog. The stable sidecar is intentionally not catalog data: it only
/// provides an OS lock that disappears when a crashed process exits.
final class CatalogWriterLease: @unchecked Sendable {
    let lockURL: URL
    private let fileDescriptor: Int32

    init(databaseURL: URL) throws {
        let catalogURL = databaseURL.standardizedFileURL
        lockURL = catalogURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(catalogURL.lastPathComponent).scansong-writer-lock", isDirectory: false)

        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw Self.systemError("Could not open the ScanSong writer lease.")
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let errorCode = errno
            close(descriptor)
            if errorCode == EWOULDBLOCK || errorCode == EAGAIN {
                throw CatalogWriterError.writerAlreadyActive(catalogURL.path)
            }
            throw Self.systemError("Could not acquire the ScanSong writer lease.", code: errorCode)
        }
        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }

    private static func systemError(_ message: String, code: Int32 = errno) -> NSError {
        NSError(
            domain: "ScanSong.CatalogWriterLease",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(message) \(String(cString: strerror(code)))"]
        )
    }
}

/// Expected contention boundaries for catalog mutations. These conditions do
/// not indicate a damaged catalog; the caller can leave player playback alone
/// and retry after the competing operation completes.
public enum CatalogWriterError: Error, LocalizedError, Equatable, Sendable {
    case writerAlreadyActive(String)
    case catalogBusy(String)

    public var errorDescription: String? {
        switch self {
        case .writerAlreadyActive:
            "Another ScanSong session is already writing this catalog. Wait for it to finish, then retry."
        case .catalogBusy:
            "The catalog is busy with another SQLite operation. Player playback may continue; retry shortly."
        }
    }

    public var isContention: Bool { true }

    public static func isContention(_ error: Error) -> Bool {
        (error as? CatalogWriterError)?.isContention == true
    }
}
