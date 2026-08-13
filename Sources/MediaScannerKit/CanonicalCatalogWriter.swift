import Foundation
import SQLite3

public struct CatalogRoot: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let path: String
    public let isEnabled: Bool
    public let lastScanStartedAt: Date?
    public let lastScanCompletedAt: Date?
    public let lastScanTrackCount: Int
    public let lastScanError: String?
    public let failedSourceCount: Int
    public let deadSourceCount: Int
}

public struct CatalogLinkTestResult: Equatable, Sendable {
    public let testedSourceCount: Int
    public let missingSourceCount: Int
    public let restoredSourceCount: Int
}

public struct CatalogTrackRecord: Sendable {
    public let sourcePath: String
    public let archiveEntry: String?
    public let route: ScannerRoute
    public let fingerprint: ScanFingerprint
    public let trackIndex: Int
    public let trackCount: Int
    public let metadata: ScannerMetadata?

    public init(
        sourcePath: String,
        archiveEntry: String?,
        route: ScannerRoute,
        fingerprint: ScanFingerprint,
        trackIndex: Int,
        trackCount: Int,
        metadata: ScannerMetadata?
    ) {
        self.sourcePath = sourcePath
        self.archiveEntry = archiveEntry
        self.route = route
        self.fingerprint = fingerprint
        self.trackIndex = trackIndex
        self.trackCount = trackCount
        self.metadata = metadata
    }
}

public enum CatalogConsoleSourcePolicy: String, CaseIterable, Codable, Sendable {
    case foldersFirst
    case metadataFirst
}

public final class CanonicalCatalogWriter: @unchecked Sendable {
    public static let policyVersion = 1

    private let database: OpaquePointer
    private let consoleSourcePolicy: CatalogConsoleSourcePolicy
    public let databaseURL: URL

    public init(
        databaseURL: URL,
        consoleSourcePolicy: CatalogConsoleSourcePolicy = .foldersFirst
    ) throws {
        self.databaseURL = databaseURL.standardizedFileURL
        self.consoleSourcePolicy = consoleSourcePolicy
        try FileManager.default.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            self.databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
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
        let journalMode = try scalarString("PRAGMA journal_mode=DELETE;").lowercased()
        guard journalMode == "delete" else {
            throw Self.error(
                "The catalog journal could not be changed from \(journalMode) to delete mode. Close CocoaSpice and SPCBoy, then scan again."
            )
        }
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try prepareSchema()
        try recoverInterruptedStages()
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
                path: Self.string(statement, 1),
                isEnabled: sqlite3_column_int(statement, 2) != 0,
                lastScanStartedAt: Self.date(statement, 3),
                lastScanCompletedAt: Self.date(statement, 4),
                lastScanTrackCount: Int(sqlite3_column_int64(statement, 5)),
                lastScanError: Self.nullableString(statement, 6),
                failedSourceCount: Int(sqlite3_column_int64(statement, 7)),
                deadSourceCount: Int(sqlite3_column_int64(statement, 8))
            )
        }
    }

    public func testFiles() throws -> CatalogLinkTestResult {
        let sources: [(rootID: Int64, path: String)] = try query(
            """
            SELECT DISTINCT i.root_id, i.path
            FROM scan_items i JOIN library_roots r ON r.id=i.root_id
            WHERE r.is_attached=1 AND i.archive_entry=''
            ORDER BY i.path;
            """
        ) { (sqlite3_column_int64($0, 0), Self.string($0, 1)) }
        var missing: [(Int64, String)] = []
        for source in sources {
            do {
                _ = try FileManager.default.attributesOfItem(atPath: source.path)
            } catch {
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain,
                   (cocoa.code == NSFileReadNoSuchFileError || cocoa.code == CocoaError.fileNoSuchFile.rawValue) {
                    missing.append(source)
                } else {
                    throw Self.error("Could not inspect \(source.path): \(error.localizedDescription)")
                }
            }
        }
        let missingKeys = Set(missing.map { "\($0.0)\u{1f}\($0.1)" })
        let previouslyDead: Set<String> = Set(try query(
            "SELECT root_id, path FROM dead_sources;"
        ) { "\(sqlite3_column_int64($0, 0))\u{1f}\(Self.string($0, 1))" })
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM dead_sources;")
            let now = Date().timeIntervalSince1970
            for source in missing {
                try execute(
                    "INSERT INTO dead_sources(root_id,path,marked_at) VALUES (?,?,?);",
                    [.integer(source.0), .text(source.1), .real(now)]
                )
            }
            for root in try roots() {
                try replaceBuckets(rootID: root.id)
                try updateActiveTrackCount(rootID: root.id)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
        return CatalogLinkTestResult(
            testedSourceCount: sources.count,
            missingSourceCount: missing.count,
            restoredSourceCount: previouslyDead.subtracting(missingKeys).count
        )
    }

    @discardableResult
    public func clearDeadLinks() throws -> Int {
        let count = try scalarInt("SELECT COUNT(*) FROM dead_sources;")
        guard count > 0 else { return 0 }
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM tracks WHERE EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id=tracks.root_id AND d.path=tracks.path);")
            try execute("DELETE FROM scan_items WHERE EXISTS (SELECT 1 FROM dead_sources d WHERE d.root_id=scan_items.root_id AND d.path=scan_items.path);")
            try execute("DELETE FROM dead_sources;")
            for root in try roots() {
                try replaceBuckets(rootID: root.id)
                try updateActiveTrackCount(rootID: root.id)
            }
            try execute("COMMIT;")
            return count
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    @discardableResult
    public func addRoot(path: String) throws -> CatalogRoot {
        let standardized = CanonicalFileURL.resolve(URL(fileURLWithPath: path))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw Self.error("Scan root does not exist or is not a directory: \(standardized.path)")
        }
        let displayOrder = try scalarInt("SELECT COUNT(*) FROM library_roots WHERE is_attached=1;")
        try execute(
            """
            INSERT INTO library_roots
                (path, is_enabled, display_order, created_at, is_attached,
                 game_sidebar_buckets_dirty, file_sidebar_buckets_dirty)
            VALUES (?, 1, ?, ?, 1, 0, 0)
            ON CONFLICT(path) DO UPDATE SET is_enabled=1, is_attached=1;
            """,
            [.text(standardized.path), .integer(Int64(displayOrder)), .real(Date().timeIntervalSince1970)]
        )
        guard let root = try roots().first(where: { $0.path == standardized.path }) else {
            throw Self.error("The scan root could not be read after insertion.")
        }
        return root
    }

    public func removeRoot(id: Int64) throws {
        try execute("UPDATE library_roots SET is_attached=0, is_enabled=0 WHERE id=?;", [.integer(id)])
    }

    public func setRootEnabled(id: Int64, enabled: Bool) throws {
        try execute("UPDATE library_roots SET is_enabled=? WHERE id=?;", [.integer(enabled ? 1 : 0), .integer(id)])
    }

    public func beginScan(root: CatalogRoot, mode: ScanMode) throws -> Int64 {
        try execute(
            "UPDATE library_roots SET last_scan_started_at=?, last_scan_error=NULL WHERE id=?;",
            [.real(Date().timeIntervalSince1970), .integer(root.id)]
        )
        if let stage = try existingStage(targetRootID: root.id, mode: mode) {
            try execute(
                "UPDATE scan_staging_roots SET state='active', updated_at=?, last_error=NULL WHERE staging_root_id=?;",
                [.real(Date().timeIntervalSince1970), .integer(stage)]
            )
            return stage
        }
        try discardStages(targetRootID: root.id)
        let stagePath = "\(root.path)#mediascanner-stage-\(UUID().uuidString)"
        try execute(
            """
            INSERT INTO library_roots
                (path, is_enabled, display_order, created_at, is_attached,
                 game_sidebar_buckets_dirty, file_sidebar_buckets_dirty)
            VALUES (?, 0, 0, ?, 0, 1, 1);
            """,
            [.text(stagePath), .real(Date().timeIntervalSince1970)]
        )
        let stageID = sqlite3_last_insert_rowid(database)
        try execute(
            """
            INSERT INTO scan_staging_roots
                (staging_root_id, target_root_id, created_at, state, mode,
                 policy_version, updated_at, last_error)
            VALUES (?, ?, ?, 'active', ?, ?, ?, NULL);
            """,
            [
                .integer(stageID), .integer(root.id), .real(Date().timeIntervalSince1970),
                .text(mode.rawValue), .integer(Int64(Self.policyVersion)), .real(Date().timeIntervalSince1970)
            ]
        )
        return stageID
    }

    public func completedFingerprint(stageID: Int64, sourcePath: String) throws -> ScanFingerprint? {
        try queryOne(
            """
            SELECT file_size, modified_at, content_signature
            FROM scan_source_checkpoints WHERE staging_root_id=? AND path=?;
            """,
            [.integer(stageID), .text(sourcePath)]
        ) { statement in
            ScanFingerprint(
                fileSize: sqlite3_column_int64(statement, 0),
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                contentSignature: Self.nullableString(statement, 2)
            )
        }
    }

    public func reusableLiveFingerprint(rootID: Int64, sourcePath: String) throws -> ScanFingerprint? {
        try queryOne(
            """
            SELECT file_size, modified_at, content_signature
            FROM scan_items
            WHERE root_id=? AND path=? AND archive_entry='' AND state='successful';
            """,
            [.integer(rootID), .text(sourcePath)]
        ) { statement in
            ScanFingerprint(
                fileSize: sqlite3_column_int64(statement, 0),
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                contentSignature: Self.nullableString(statement, 2)
            )
        }
    }

    public func reuseLiveSource(
        rootID: Int64,
        stageID: Int64,
        sourcePath: String,
        fingerprint: ScanFingerprint
    ) throws {
        try savepoint {
            try deleteSource(rootID: stageID, sourcePath: sourcePath)
            try execute(
                """
                INSERT INTO tracks
                    (root_id, folder_path, path, filename, extension, browser_game,
                     browser_system, track_index, track_count, file_size, modified_at,
                     discovered_at, archive_path, archive_entry)
                SELECT ?, folder_path, path, filename, extension, browser_game,
                       browser_system, track_index, track_count, file_size, modified_at,
                       discovered_at, archive_path, archive_entry
                FROM tracks WHERE root_id=? AND path=?;
                """,
                [.integer(stageID), .integer(rootID), .text(sourcePath)]
            )
            try execute(
                """
                INSERT INTO track_metadata
                    (track_id, title, game, author, system, comment, intro_length_ms,
                     loop_length_ms, play_length_ms, fade_length_ms, metadata_scanned_at)
                SELECT staged.id, metadata.title, metadata.game, metadata.author,
                       metadata.system, metadata.comment, metadata.intro_length_ms,
                       metadata.loop_length_ms, metadata.play_length_ms,
                       metadata.fade_length_ms, metadata.metadata_scanned_at
                FROM tracks staged
                JOIN tracks live ON live.root_id=? AND live.path=staged.path
                    AND COALESCE(live.archive_entry,'')=COALESCE(staged.archive_entry,'')
                    AND live.track_index=staged.track_index
                JOIN track_metadata metadata ON metadata.track_id=live.id
                WHERE staged.root_id=? AND staged.path=?;
                """,
                [.integer(rootID), .integer(stageID), .text(sourcePath)]
            )
            try execute(
                """
                INSERT INTO scan_items
                    (root_id, path, archive_entry, file_size, modified_at,
                     content_signature, state, plugin_id, format_extension,
                     supports_archive_members, supports_multi_track,
                     structure_policy, metadata_policy, failure_stage,
                     failure_message, updated_at)
                SELECT ?, path, archive_entry, file_size, modified_at,
                       content_signature, state, plugin_id, format_extension,
                       supports_archive_members, supports_multi_track,
                       structure_policy, metadata_policy, failure_stage,
                       failure_message, updated_at
                FROM scan_items WHERE root_id=? AND path=?;
                """,
                [.integer(stageID), .integer(rootID), .text(sourcePath)]
            )
            try writeCheckpoint(stageID: stageID, path: sourcePath, fingerprint: fingerprint)
        }
    }

    public func checkpoint(
        stageID: Int64,
        rootPath: String,
        sourcePath: String,
        fingerprint: ScanFingerprint,
        records: [CatalogTrackRecord],
        failures: [ScanFailure] = []
    ) throws {
        try savepoint {
            try deleteSource(rootID: stageID, sourcePath: sourcePath)
            for record in records {
                try insertTrack(stageID: stageID, rootPath: rootPath, record: record)
            }
            let parentRoute = records.first?.route
            try upsertInventory(
                rootID: stageID,
                path: sourcePath,
                archiveEntry: nil,
                fingerprint: fingerprint,
                route: parentRoute,
                state: records.isEmpty && !failures.isEmpty ? .failed : .successful,
                failure: failures.first
            )
            let members = Dictionary(grouping: records.compactMap { record in
                record.archiveEntry.map { ($0, record) }
            }, by: { $0.0 })
            for (entry, values) in members {
                guard let record = values.first?.1 else { continue }
                try upsertInventory(
                    rootID: stageID,
                    path: sourcePath,
                    archiveEntry: entry,
                    fingerprint: record.fingerprint,
                    route: record.route,
                    state: .successful,
                    failure: nil
                )
            }
            try writeCheckpoint(stageID: stageID, path: sourcePath, fingerprint: fingerprint)
        }
    }

    public func preserveLiveSourceAfterFailure(
        rootID: Int64,
        stageID: Int64,
        sourcePath: String,
        currentFingerprint: ScanFingerprint,
        route: ScannerRoute?,
        failure: ScanFailure
    ) throws {
        // A failed refresh must not make a previously playable source vanish
        // from the next atomic generation. Clone the last known-good rows, then
        // replace only the source-level inventory row with the current failure.
        try reuseLiveSource(
            rootID: rootID,
            stageID: stageID,
            sourcePath: sourcePath,
            fingerprint: currentFingerprint
        )
        try savepoint {
            try execute(
                "DELETE FROM scan_items WHERE root_id=? AND path=? AND archive_entry='';",
                [.integer(stageID), .text(sourcePath)]
            )
            try upsertInventory(
                rootID: stageID,
                path: sourcePath,
                archiveEntry: nil,
                fingerprint: currentFingerprint,
                route: route,
                state: .failed,
                failure: failure
            )
            try execute(
                "DELETE FROM scan_source_checkpoints WHERE staging_root_id=? AND path=?;",
                [.integer(stageID), .text(sourcePath)]
            )
        }
    }

    public func synchronizeStage(stageID: Int64, discoveredPaths: Set<String>) throws {
        let existing: [String] = try query(
            "SELECT DISTINCT path FROM scan_items WHERE root_id=?;",
            [.integer(stageID)]
        ) { Self.string($0, 0) }
        for vanished in existing where !discoveredPaths.contains(vanished) {
            try deleteSource(rootID: stageID, sourcePath: vanished)
            try execute(
                "DELETE FROM scan_source_checkpoints WHERE staging_root_id=? AND path=?;",
                [.integer(stageID), .text(vanished)]
            )
        }
    }

    public func pause(stageID: Int64, error message: String? = nil) {
        try? execute(
            "UPDATE scan_staging_roots SET state='paused', updated_at=?, last_error=? WHERE staging_root_id=?;",
            [.real(Date().timeIntervalSince1970), message.map(SQLiteValue.text) ?? .null, .integer(stageID)]
        )
    }

    public func publish(stageID: Int64, targetRootID: Int64) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM game_sidebar_buckets WHERE root_id=?;", [.integer(targetRootID)])
            try execute("DELETE FROM file_sidebar_buckets WHERE root_id=?;", [.integer(targetRootID)])
            try execute(
                "DELETE FROM dead_sources WHERE root_id=? AND EXISTS (SELECT 1 FROM scan_items staged WHERE staged.root_id=? AND staged.path=dead_sources.path);",
                [.integer(targetRootID), .integer(stageID)]
            )
            try execute("DELETE FROM tracks WHERE root_id=?;", [.integer(targetRootID)])
            try execute("DELETE FROM scan_items WHERE root_id=?;", [.integer(targetRootID)])
            try execute("UPDATE tracks SET root_id=? WHERE root_id=?;", [.integer(targetRootID), .integer(stageID)])
            try execute("UPDATE scan_items SET root_id=? WHERE root_id=?;", [.integer(targetRootID), .integer(stageID)])
            try rebuildBuckets(rootID: targetRootID)
            let now = Date().timeIntervalSince1970
            try execute(
                """
                UPDATE library_roots SET
                    last_scan_completed_at=?,
                    last_scan_track_count=(SELECT COUNT(*) FROM tracks WHERE root_id=?),
                    last_scan_error=NULL,
                    game_sidebar_buckets_dirty=0,
                    file_sidebar_buckets_dirty=0
                WHERE id=?;
                """,
                [.real(now), .integer(targetRootID), .integer(targetRootID)]
            )
            try execute("DELETE FROM library_roots WHERE id=?;", [.integer(stageID)])
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func markFailed(rootID: Int64, message: String) {
        try? execute(
            "UPDATE library_roots SET last_scan_error=? WHERE id=?;",
            [.text(message), .integer(rootID)]
        )
    }

    private func prepareSchema() throws {
        let version = try scalarInt("PRAGMA user_version;")
        if version == CanonicalCatalog.schemaVersion {
            _ = try CanonicalCatalog.inspect(databaseURL: databaseURL)
            return
        }
        guard version == 0 else {
            throw Self.error("MediaScanner does not migrate legacy catalog schema \(version). Choose a schema-23 catalog or a new database path.")
        }
        let statements = [
            "CREATE TABLE library_roots (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, is_enabled INTEGER NOT NULL DEFAULT 1, display_order INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL, last_scan_started_at REAL, last_scan_completed_at REAL, last_scan_track_count INTEGER NOT NULL DEFAULT 0, last_scan_error TEXT, is_attached INTEGER NOT NULL DEFAULT 1, game_sidebar_buckets_dirty INTEGER NOT NULL DEFAULT 1, file_sidebar_buckets_dirty INTEGER NOT NULL DEFAULT 1);",
            "CREATE TABLE tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, root_id INTEGER NOT NULL, folder_path TEXT NOT NULL, path TEXT NOT NULL, filename TEXT NOT NULL, extension TEXT NOT NULL, browser_game TEXT NOT NULL DEFAULT '', browser_system TEXT NOT NULL DEFAULT '', track_index INTEGER NOT NULL DEFAULT 0, track_count INTEGER NOT NULL DEFAULT 1, file_size INTEGER NOT NULL, modified_at REAL NOT NULL, discovered_at REAL NOT NULL, archive_path TEXT, archive_entry TEXT, UNIQUE(root_id, path, archive_entry, track_index), FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE track_metadata (track_id INTEGER PRIMARY KEY, title TEXT NOT NULL DEFAULT '', game TEXT NOT NULL DEFAULT '', author TEXT NOT NULL DEFAULT '', system TEXT NOT NULL DEFAULT '', comment TEXT NOT NULL DEFAULT '', intro_length_ms INTEGER NOT NULL DEFAULT 0, loop_length_ms INTEGER NOT NULL DEFAULT 0, play_length_ms INTEGER NOT NULL DEFAULT 0, fade_length_ms INTEGER NOT NULL DEFAULT 0, metadata_scanned_at REAL NOT NULL, FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE);",
            "CREATE TABLE scan_items (id INTEGER PRIMARY KEY AUTOINCREMENT, root_id INTEGER NOT NULL, path TEXT NOT NULL, archive_entry TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL, modified_at REAL NOT NULL, content_signature TEXT, state TEXT NOT NULL, plugin_id TEXT, format_extension TEXT, supports_archive_members INTEGER NOT NULL DEFAULT 0, supports_multi_track INTEGER NOT NULL DEFAULT 0, structure_policy TEXT NOT NULL DEFAULT 'knownSingle', metadata_policy TEXT NOT NULL DEFAULT 'decoder', failure_stage TEXT, failure_message TEXT, updated_at REAL NOT NULL, UNIQUE(root_id, path, archive_entry), FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE scan_staging_roots (staging_root_id INTEGER PRIMARY KEY, target_root_id INTEGER NOT NULL, created_at REAL NOT NULL, state TEXT NOT NULL DEFAULT 'paused', mode TEXT NOT NULL DEFAULT 'newScan', policy_version INTEGER NOT NULL DEFAULT 1, updated_at REAL NOT NULL DEFAULT 0, last_error TEXT, FOREIGN KEY(staging_root_id) REFERENCES library_roots(id) ON DELETE CASCADE, FOREIGN KEY(target_root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE scan_source_checkpoints (staging_root_id INTEGER NOT NULL, path TEXT NOT NULL, file_size INTEGER NOT NULL, modified_at REAL NOT NULL, content_signature TEXT, updated_at REAL NOT NULL, PRIMARY KEY(staging_root_id, path), FOREIGN KEY(staging_root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE dead_sources (root_id INTEGER NOT NULL, path TEXT NOT NULL, marked_at REAL NOT NULL, PRIMARY KEY(root_id, path), FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE game_sidebar_buckets (root_id INTEGER NOT NULL, browser_game TEXT NOT NULL, browser_system TEXT NOT NULL, track_count INTEGER NOT NULL, PRIMARY KEY(root_id, browser_game, browser_system), FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE TABLE file_sidebar_buckets (root_id INTEGER NOT NULL, folder_path TEXT NOT NULL, path TEXT NOT NULL, is_archive INTEGER NOT NULL, track_count INTEGER NOT NULL, PRIMARY KEY(root_id, path), FOREIGN KEY(root_id) REFERENCES library_roots(id) ON DELETE CASCADE);",
            "CREATE INDEX tracks_browser_bucket_index ON tracks(browser_game, browser_system, root_id);",
            "CREATE INDEX tracks_file_tree_index ON tracks(root_id, folder_path, path);",
            "CREATE INDEX tracks_source_lookup_index ON tracks(root_id, path);",
            "CREATE INDEX tracks_game_sidebar_index ON tracks(browser_game, browser_system, root_id, path);",
            "CREATE INDEX scan_items_state_index ON scan_items(root_id, state);",
            "CREATE INDEX scan_staging_target_index ON scan_staging_roots(target_root_id);",
            "CREATE INDEX scan_checkpoints_stage_index ON scan_source_checkpoints(staging_root_id, path);",
            "CREATE INDEX dead_sources_path_index ON dead_sources(path);",
            "CREATE INDEX file_sidebar_buckets_tree_index ON file_sidebar_buckets(root_id, folder_path, path);",
            "PRAGMA user_version=23;"
        ]
        try execute("BEGIN TRANSACTION;")
        do {
            for statement in statements { try execute(statement) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func recoverInterruptedStages() throws {
        try execute("UPDATE scan_staging_roots SET state='paused', updated_at=? WHERE state='active';", [.real(Date().timeIntervalSince1970)])
        try execute(
            """
            DELETE FROM library_roots WHERE id IN (
                SELECT s.staging_root_id FROM scan_staging_roots s
                WHERE NOT EXISTS (SELECT 1 FROM scan_source_checkpoints c WHERE c.staging_root_id=s.staging_root_id)
            );
            """
        )
    }

    private func existingStage(targetRootID: Int64, mode: ScanMode) throws -> Int64? {
        try queryOne(
            """
            SELECT staging_root_id FROM scan_staging_roots
            WHERE target_root_id=? AND mode=? AND policy_version=? AND state='paused'
            ORDER BY updated_at DESC LIMIT 1;
            """,
            [.integer(targetRootID), .text(mode.rawValue), .integer(Int64(Self.policyVersion))]
        ) { sqlite3_column_int64($0, 0) }
    }

    private func discardStages(targetRootID: Int64) throws {
        try execute(
            "DELETE FROM library_roots WHERE id IN (SELECT staging_root_id FROM scan_staging_roots WHERE target_root_id=?);",
            [.integer(targetRootID)]
        )
    }

    private func deleteSource(rootID: Int64, sourcePath: String) throws {
        try execute("DELETE FROM tracks WHERE root_id=? AND path=?;", [.integer(rootID), .text(sourcePath)])
        try execute("DELETE FROM scan_items WHERE root_id=? AND path=?;", [.integer(rootID), .text(sourcePath)])
    }

    private func insertTrack(stageID: Int64, rootPath: String, record: CatalogTrackRecord) throws {
        let entryName = record.archiveEntry.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sourceURL = URL(fileURLWithPath: record.sourcePath)
        let filename = entryName ?? sourceURL.lastPathComponent
        let extensionName = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let folderPath = record.archiveEntry == nil
            ? sourceURL.deletingLastPathComponent().path
            : sourceURL.deletingLastPathComponent().path
        let browserGame = CatalogIdentity.browserGame(
            metadataGame: record.metadata?.game ?? "",
            sourcePath: record.sourcePath,
            archiveEntry: record.archiveEntry
        )
        let browserSystem = CatalogIdentity.browserSystem(
            metadataSystem: record.metadata?.system ?? "",
            sourcePath: record.sourcePath,
            rootPath: rootPath,
            policy: consoleSourcePolicy
        )
        try execute(
            """
            INSERT INTO tracks
                (root_id, folder_path, path, filename, extension, browser_game,
                 browser_system, track_index, track_count, file_size, modified_at,
                 discovered_at, archive_path, archive_entry)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .integer(stageID), .text(folderPath), .text(record.sourcePath), .text(filename),
                .text(extensionName), .text(browserGame), .text(browserSystem),
                .integer(Int64(record.trackIndex)), .integer(Int64(record.trackCount)),
                .integer(record.fingerprint.fileSize), .real(record.fingerprint.modifiedAt.timeIntervalSince1970),
                .real(Date().timeIntervalSince1970),
                record.archiveEntry == nil ? .null : .text(record.sourcePath),
                record.archiveEntry.map(SQLiteValue.text) ?? .null
            ]
        )
        guard let metadata = record.metadata else { return }
        try execute(
            """
            INSERT INTO track_metadata
                (track_id, title, game, author, system, comment, intro_length_ms,
                 loop_length_ms, play_length_ms, fade_length_ms, metadata_scanned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .integer(sqlite3_last_insert_rowid(database)), .text(metadata.song), .text(metadata.game),
                .text(metadata.author), .text(metadata.system), .text(metadata.comment),
                .integer(Int64(metadata.introLengthMs)), .integer(Int64(metadata.loopLengthMs)),
                .integer(Int64(metadata.playLengthMs)), .integer(Int64(metadata.fadeLengthMs)),
                .real(Date().timeIntervalSince1970)
            ]
        )
    }

    private func upsertInventory(
        rootID: Int64,
        path: String,
        archiveEntry: String?,
        fingerprint: ScanFingerprint,
        route: ScannerRoute?,
        state: ScanItemState,
        failure: ScanFailure?
    ) throws {
        try execute(
            """
            INSERT INTO scan_items
                (root_id, path, archive_entry, file_size, modified_at,
                 content_signature, state, plugin_id, format_extension,
                 supports_archive_members, supports_multi_track,
                 structure_policy, metadata_policy, failure_stage,
                 failure_message, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .integer(rootID), .text(path), .text(archiveEntry ?? ""),
                .integer(fingerprint.fileSize), .real(fingerprint.modifiedAt.timeIntervalSince1970),
                fingerprint.contentSignature.map(SQLiteValue.text) ?? .null, .text(state.rawValue),
                route.map { .text($0.pluginID) } ?? .null,
                route.map { .text($0.formatExtension) } ?? .null,
                .integer(route?.supportsArchiveMembers == true ? 1 : 0),
                .integer(route?.supportsMultiTrack == true ? 1 : 0),
                .text(route?.structurePolicy.rawValue ?? ScanStructurePolicy.knownSingle.rawValue),
                .text(route?.metadataPolicy.rawValue ?? ScanMetadataPolicy.decoder.rawValue),
                failure.map { .text($0.stage.rawValue) } ?? .null,
                failure.map { .text($0.message) } ?? .null,
                .real(Date().timeIntervalSince1970)
            ]
        )
    }

    private func writeCheckpoint(stageID: Int64, path: String, fingerprint: ScanFingerprint) throws {
        try execute(
            """
            INSERT INTO scan_source_checkpoints
                (staging_root_id, path, file_size, modified_at, content_signature, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(staging_root_id, path) DO UPDATE SET
                file_size=excluded.file_size, modified_at=excluded.modified_at,
                content_signature=excluded.content_signature, updated_at=excluded.updated_at;
            """,
            [
                .integer(stageID), .text(path), .integer(fingerprint.fileSize),
                .real(fingerprint.modifiedAt.timeIntervalSince1970),
                fingerprint.contentSignature.map(SQLiteValue.text) ?? .null,
                .real(Date().timeIntervalSince1970)
            ]
        )
    }

    private func rebuildBuckets(rootID: Int64) throws {
        try execute(
            """
            INSERT INTO game_sidebar_buckets(root_id, browser_game, browser_system, track_count)
            SELECT root_id, browser_game, browser_system, COUNT(*) FROM tracks
            WHERE root_id=? AND NOT EXISTS (
                SELECT 1 FROM dead_sources d WHERE d.root_id=tracks.root_id AND d.path=tracks.path
            ) GROUP BY root_id, browser_game, browser_system;
            """,
            [.integer(rootID)]
        )
        try execute(
            """
            INSERT INTO file_sidebar_buckets(root_id, folder_path, path, is_archive, track_count)
            SELECT root_id, folder_path, path, MAX(archive_path IS NOT NULL), COUNT(*)
            FROM tracks WHERE root_id=? AND NOT EXISTS (
                SELECT 1 FROM dead_sources d WHERE d.root_id=tracks.root_id AND d.path=tracks.path
            ) GROUP BY root_id, folder_path, path;
            """,
            [.integer(rootID)]
        )
    }

    private func replaceBuckets(rootID: Int64) throws {
        try execute("DELETE FROM game_sidebar_buckets WHERE root_id=?;", [.integer(rootID)])
        try execute("DELETE FROM file_sidebar_buckets WHERE root_id=?;", [.integer(rootID)])
        try rebuildBuckets(rootID: rootID)
    }

    private func updateActiveTrackCount(rootID: Int64) throws {
        try execute(
            """
            UPDATE library_roots SET last_scan_track_count=(
                SELECT COUNT(*) FROM tracks t WHERE t.root_id=? AND NOT EXISTS (
                    SELECT 1 FROM dead_sources d WHERE d.root_id=t.root_id AND d.path=t.path
                )
            ) WHERE id=?;
            """,
            [.integer(rootID), .integer(rootID)]
        )
    }

    private func savepoint<T>(_ body: () throws -> T) throws -> T {
        let name = "scanner_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try execute("SAVEPOINT \(name);")
        do {
            let result = try body()
            try execute("RELEASE SAVEPOINT \(name);")
            return result
        } catch {
            try? execute("ROLLBACK TO SAVEPOINT \(name);")
            try? execute("RELEASE SAVEPOINT \(name);")
            throw error
        }
    }

    private enum SQLiteValue {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null
    }

    private func execute(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                // PRAGMA journal_mode returns its selected mode as a row.
                continue
            case SQLITE_DONE:
                return
            default:
                throw databaseError()
            }
        }
    }

    private func scalarInt(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int {
        try queryOne(sql, bindings) { Int(sqlite3_column_int64($0, 0)) } ?? 0
    }

    private func scalarString(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> String {
        try queryOne(sql, bindings) { Self.string($0, 0) } ?? ""
    }

    private func query<T>(_ sql: String, _ bindings: [SQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var values: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: values.append(try map(statement))
            case SQLITE_DONE: return values
            default: throw databaseError()
            }
        }
    }

    private func queryOne<T>(_ sql: String, _ bindings: [SQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> T? {
        try query(sql, bindings, map: map).first
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let value): status = sqlite3_bind_int64(statement, index, value)
            case .real(let value): status = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                status = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw databaseError() }
        }
    }

    private func databaseError() -> NSError { Self.error(String(cString: sqlite3_errmsg(database))) }

    private static func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private static func nullableString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index)
    }

    private static func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "MediaScanner.CanonicalCatalogWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum CatalogIdentity {
    private static let aliases: [String: String] = [
        "ps1": "Sony PlayStation", "psx": "Sony PlayStation", "playstation": "Sony PlayStation",
        "sony playstation": "Sony PlayStation",
        "ps2": "Sony PlayStation 2", "playstation 2": "Sony PlayStation 2",
        "sony playstation 2": "Sony PlayStation 2",
        "snes": "Super Nintendo", "super famicom": "Super Nintendo",
        "nes": "Nintendo Entertainment System", "n64": "Nintendo 64",
        "saturn": "Sega Saturn", "dreamcast": "Sega Dreamcast", "genesis": "Sega Genesis",
        "mega drive": "Sega Genesis", "game boy": "Nintendo Game Boy",
        "game boy advance": "Nintendo Game Boy Advance", "gba": "Nintendo Game Boy Advance"
    ]

    public static func browserGame(metadataGame: String, sourcePath: String, archiveEntry: String?) -> String {
        let tagged = metadataGame.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tagged.isEmpty && tagged != "?" { return tagged }
        if archiveEntry != nil {
            return stripArchiveExtension(URL(fileURLWithPath: sourcePath).lastPathComponent)
        }
        let parent = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent : parent
    }

    public static func browserSystem(
        metadataSystem: String,
        sourcePath: String,
        rootPath: String,
        policy: CatalogConsoleSourcePolicy = .foldersFirst
    ) -> String {
        let sourceComponents = URL(fileURLWithPath: sourcePath)
            .deletingLastPathComponent().standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).standardizedFileURL.pathComponents
        var folderSystem: String?
        if sourceComponents.count >= rootComponents.count,
           Array(sourceComponents.prefix(rootComponents.count)) == rootComponents {
            let firstCollectionComponent = max(0, rootComponents.count - 1)
            for component in sourceComponents[firstCollectionComponent...].reversed() {
                if let normalized = normalizeSystem(component) {
                    folderSystem = normalized
                    break
                }
            }
        }
        let trimmedMetadata = metadataSystem.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMetadata = normalizeSystem(trimmedMetadata) ?? (trimmedMetadata.isEmpty || trimmedMetadata == "?" ? nil : trimmedMetadata)
        switch policy {
        case .foldersFirst: return folderSystem ?? normalizedMetadata ?? ""
        case .metadataFirst: return normalizedMetadata ?? folderSystem ?? ""
        }
    }

    private static func normalizeSystem(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let alias = aliases[key] { return alias }
        let longestMatch = aliases.keys
            .filter(key.contains)
            .max { $0.count < $1.count }
        return longestMatch.flatMap { aliases[$0] }
    }

    private static func stripArchiveExtension(_ name: String) -> String {
        let lower = name.lowercased()
        for suffix in [".tar.zstd", ".tar.zst", ".tzst", ".zip", ".7z", ".rar", ".rsn"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }
}
