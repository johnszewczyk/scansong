import Foundation
import SQLite3

/// Query-only view of a validated schema-23 catalog.
///
/// Scanner presentation must remain able to display attached paths while a
/// player has the catalog open. Mutations remain exclusively in
/// `CanonicalCatalogWriter`.
public final class CanonicalCatalogReader: @unchecked Sendable {
    private let database: OpaquePointer
    public let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL.standardizedFileURL
        _ = try CanonicalCatalog.inspect(databaseURL: self.databaseURL)

        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            self.databaseURL.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the catalog."
            sqlite3_close(handle)
            throw Self.error(message)
        }
        database = handle
        sqlite3_extended_result_codes(handle, 1)
        sqlite3_busy_timeout(handle, 10_000)
    }

    deinit { sqlite3_close(database) }

    public func roots() throws -> [CatalogRoot] {
        try query(
            """
            SELECT r.id, r.path, r.is_enabled, r.last_scan_started_at, r.last_scan_completed_at,
                   r.last_scan_track_count, r.last_scan_error,
                   (SELECT COUNT(*) FROM scan_items i
                    WHERE i.root_id=r.id AND i.archive_entry='' AND i.state='failed'),
                   (SELECT COUNT(*) FROM dead_sources d WHERE d.root_id=r.id)
            FROM library_roots r WHERE r.is_attached=1
            ORDER BY lower(path), path;
            """
        ) { statement in
            CatalogRoot(
                id: sqlite3_column_int64(statement, 0),
                path: Self.string(statement, index: 1),
                isEnabled: sqlite3_column_int(statement, 2) != 0,
                lastScanStartedAt: Self.date(statement, index: 3),
                lastScanCompletedAt: Self.date(statement, index: 4),
                lastScanTrackCount: Int(sqlite3_column_int64(statement, 5)),
                lastScanError: Self.nullableString(statement, index: 6),
                failedSourceCount: Int(sqlite3_column_int64(statement, 7)),
                deadSourceCount: Int(sqlite3_column_int64(statement, 8))
            )
        }
    }

    public func scanTally(rootID: Int64) throws -> CatalogScanTally {
        var statement: OpaquePointer?
        let sql = """
        SELECT
            COUNT(*),
            SUM(CASE WHEN d.path IS NULL THEN 1 ELSE 0 END),
            SUM(CASE WHEN i.state='successful' THEN 1 ELSE 0 END),
            SUM(CASE WHEN i.state='failed' THEN 1 ELSE 0 END),
            COUNT(d.path)
        FROM scan_items i
        LEFT JOIN dead_sources d ON d.root_id=i.root_id AND d.path=i.path
        WHERE i.root_id=? AND i.archive_entry='';
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Self.error(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int64(statement, 1, rootID) == SQLITE_OK else {
            throw Self.error(String(cString: sqlite3_errmsg(database)))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.error(String(cString: sqlite3_errmsg(database)))
        }
        return CatalogScanTally(
            sourceCount: Int(sqlite3_column_int64(statement, 0)),
            activeSourceCount: Int(sqlite3_column_int64(statement, 1)),
            successfulSourceCount: Int(sqlite3_column_int64(statement, 2)),
            failedSourceCount: Int(sqlite3_column_int64(statement, 3)),
            inactiveSourceCount: Int(sqlite3_column_int64(statement, 4))
        )
    }

    private func query<T>(_ sql: String, map: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Self.error(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(try map(statement))
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw Self.error(String(cString: sqlite3_errmsg(database)))
        }
        return values
    }

    private static func string(_ statement: OpaquePointer, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private static func nullableString(_ statement: OpaquePointer, index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index: index)
    }

    private static func date(_ statement: OpaquePointer, index: Int32) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "ScanSong.CanonicalCatalogReader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
