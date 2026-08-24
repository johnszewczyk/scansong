import Foundation
import SQLite3

public struct CanonicalCatalogSummary: Codable, Equatable, Sendable {
    public let path: String
    public let schemaVersion: Int
    public let rootCount: Int
    public let trackCount: Int

    public init(path: String, schemaVersion: Int, rootCount: Int, trackCount: Int) {
        self.path = path
        self.schemaVersion = schemaVersion
        self.rootCount = rootCount
        self.trackCount = trackCount
    }
}

public enum CanonicalCatalog {
    public static let schemaVersion = 23
    public static let requiredTables: Set<String> = [
        "library_roots",
        "tracks",
        "track_metadata",
        "scan_items",
        "scan_staging_roots",
        "scan_source_checkpoints",
        "dead_sources",
        "game_sidebar_buckets",
        "file_sidebar_buckets"
    ]

    public static func inspect(databaseURL: URL) throws -> CanonicalCatalogSummary {
        let standardizedURL = databaseURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw catalogError("The selected library database does not exist.")
        }

        var handle: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            standardizedURL.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard openStatus == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the file."
            sqlite3_close(handle)
            throw catalogError(message)
        }
        defer { sqlite3_close(handle) }

        let version = try scalarInt(handle, sql: "PRAGMA user_version;")
        guard version == schemaVersion else {
            throw catalogError("Unsupported library database schema \(version); expected \(schemaVersion).")
        }
        let presentTables = try stringSet(
            handle,
            sql: "SELECT name FROM sqlite_master WHERE type='table';"
        )
        let missingTables = requiredTables.subtracting(presentTables).sorted()
        guard missingTables.isEmpty else {
            throw catalogError("Library database is missing required tables: \(missingTables.joined(separator: ", ")).")
        }

        return CanonicalCatalogSummary(
            path: standardizedURL.path,
            schemaVersion: version,
            rootCount: try scalarInt(handle, sql: "SELECT COUNT(*) FROM library_roots WHERE is_attached=1;"),
            trackCount: try scalarInt(handle, sql: "SELECT COUNT(*) FROM tracks;")
        )
    }

    private static func scalarInt(_ handle: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw catalogError(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw catalogError(String(cString: sqlite3_errmsg(handle)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func stringSet(_ handle: OpaquePointer, sql: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw catalogError(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        var values = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            values.insert(String(cString: text))
        }
        return values
    }

    private static func catalogError(_ message: String) -> NSError {
        NSError(
            domain: "ScanSong.CanonicalCatalog",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
