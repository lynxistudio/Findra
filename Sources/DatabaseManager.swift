import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String
    private let dbQueue = DispatchQueue(label: "com.lynxistudio.findra.db", qos: .userInitiated)

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("Findra")
        let legacyDbDir = appSupport.appendingPathComponent("FastFinder")

        if !FileManager.default.fileExists(atPath: dbDir.path),
           FileManager.default.fileExists(atPath: legacyDbDir.path) {
            try? FileManager.default.moveItem(at: legacyDbDir, to: dbDir)
        }

        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let newDbURL = dbDir.appendingPathComponent("findra.db")
        let legacyDbURL = dbDir.appendingPathComponent("fastfinder.db")
        if !FileManager.default.fileExists(atPath: newDbURL.path),
           FileManager.default.fileExists(atPath: legacyDbURL.path) {
            try? FileManager.default.moveItem(at: legacyDbURL, to: newDbURL)
        }

        dbPath = newDbURL.path
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    func setupDatabase() {
        dbQueue.sync {
            if sqlite3_open(dbPath, &db) != SQLITE_OK {
                print("无法打开数据库: \(dbPath)")
                return
            }
            sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA cache_size=-8000", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA mmap_size=268435456", nil, nil, nil)

            let createDirs = """
            CREATE TABLE IF NOT EXISTS directories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL UNIQUE,
                type TEXT NOT NULL DEFAULT 'local',
                last_scan_time REAL DEFAULT 0,
                enabled INTEGER DEFAULT 1
            );
            """
            sqlite3_exec(db, createDirs, nil, nil, nil)

            let createFiles = """
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name TEXT NOT NULL,
                full_path TEXT NOT NULL UNIQUE,
                size INTEGER DEFAULT 0,
                mod_date REAL DEFAULT 0,
                dir_id INTEGER NOT NULL,
                is_directory INTEGER DEFAULT 0,
                FOREIGN KEY (dir_id) REFERENCES directories(id) ON DELETE CASCADE
            );
            """
            sqlite3_exec(db, createFiles, nil, nil, nil)

            // Migration: add is_directory column for existing databases
            sqlite3_exec(db, "ALTER TABLE files ADD COLUMN is_directory INTEGER DEFAULT 0", nil, nil, nil)

            let idxName = "CREATE INDEX IF NOT EXISTS idx_files_name ON files(file_name);"
            sqlite3_exec(db, idxName, nil, nil, nil)
            let idxPath = "CREATE INDEX IF NOT EXISTS idx_files_path ON files(full_path);"
            sqlite3_exec(db, idxPath, nil, nil, nil)
            let idxDirId = "CREATE INDEX IF NOT EXISTS idx_files_dirid ON files(dir_id);"
            sqlite3_exec(db, idxDirId, nil, nil, nil)
            let idxModDate = "CREATE INDEX IF NOT EXISTS idx_files_mod_date ON files(mod_date);"
            sqlite3_exec(db, idxModDate, nil, nil, nil)

            let createScanStaging = """
            CREATE TABLE IF NOT EXISTS scan_staging (
                scan_id TEXT NOT NULL,
                file_name TEXT NOT NULL,
                full_path TEXT NOT NULL,
                size INTEGER DEFAULT 0,
                mod_date REAL DEFAULT 0,
                is_directory INTEGER DEFAULT 0,
                PRIMARY KEY (scan_id, full_path)
            );
            """
            sqlite3_exec(db, createScanStaging, nil, nil, nil)

            // Excluded directories table
            let createExcluded = """
            CREATE TABLE IF NOT EXISTS excluded_dirs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pattern TEXT NOT NULL UNIQUE
            );
            """
            sqlite3_exec(db, createExcluded, nil, nil, nil)

            var schemaVersion = 0
            var versionStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK,
               sqlite3_step(versionStatement) == SQLITE_ROW {
                schemaVersion = Int(sqlite3_column_int(versionStatement, 0))
            }
            sqlite3_finalize(versionStatement)

            // Older releases silently added these exclusions. Remove them once so a root is
            // exhaustive by default, while preserving exclusions the user adds from now on.
            if schemaVersion < 2 {
                let legacyDefaultExclusions = [
                    ".git", "node_modules", ".cache", "tmp", "temp",
                    "Trash", "Recycle Bin", "@eaDir", "#recycle", ".recycle",
                    "System Volume Information", ".DS_Store", "Thumbs.db"
                ]
                var removeLegacyExclusion: OpaquePointer?
                if sqlite3_prepare_v2(db, "DELETE FROM excluded_dirs WHERE pattern = ?", -1, &removeLegacyExclusion, nil) == SQLITE_OK {
                    for pattern in legacyDefaultExclusions {
                        sqlite3_reset(removeLegacyExclusion)
                        sqlite3_clear_bindings(removeLegacyExclusion)
                        sqlite3_bind_text(removeLegacyExclusion, 1, pattern, -1, SQLITE_TRANSIENT)
                        sqlite3_step(removeLegacyExclusion)
                    }
                }
                sqlite3_finalize(removeLegacyExclusion)
                sqlite3_exec(db, "PRAGMA user_version = 2", nil, nil, nil)
            }

            // Trigram FTS keeps multi-word partial filename searches index-only and fast.
            sqlite3_exec(db, "DROP TABLE IF EXISTS files_fts", nil, nil, nil)
            let createFts = """
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                file_name,
                full_path,
                content='files',
                content_rowid='id',
                tokenize='trigram'
            );
            """
            sqlite3_exec(db, createFts, nil, nil, nil)

            // Triggers to keep FTS in sync
            let t1 = """
            CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
                INSERT INTO files_fts(rowid, file_name, full_path) VALUES (new.id, new.file_name, new.full_path);
            END;
            """
            sqlite3_exec(db, t1, nil, nil, nil)

            let t2 = """
            CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, file_name, full_path) VALUES('delete', old.id, old.file_name, old.full_path);
            END;
            """
            sqlite3_exec(db, t2, nil, nil, nil)

            let t3 = """
            CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, file_name, full_path) VALUES('delete', old.id, old.file_name, old.full_path);
                INSERT INTO files_fts(rowid, file_name, full_path) VALUES (new.id, new.file_name, new.full_path);
            END;
            """
            sqlite3_exec(db, t3, nil, nil, nil)

            // Rebuild FTS index from existing data
            let rebuild = "INSERT INTO files_fts(files_fts) VALUES('rebuild');"
            sqlite3_exec(db, rebuild, nil, nil, nil)

            sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        }
    }

    // MARK: - Directory Operations

    func getAllDirectories() -> [IndexDirectory] {
        return dbQueue.sync {
            var dirs: [IndexDirectory] = []
            let sql = "SELECT id, path, type, last_scan_time, enabled FROM directories ORDER BY id"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return dirs }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let path = String(cString: sqlite3_column_text(stmt, 1))
                let typeStr = String(cString: sqlite3_column_text(stmt, 2))
                let lst = sqlite3_column_double(stmt, 3)
                let ena = sqlite3_column_int(stmt, 4)
                let dt = DirectoryType(rawValue: typeStr) ?? .local
                dirs.append(IndexDirectory(id: id, path: path, type: dt, lastScanTime: lst, enabled: ena != 0))
            }
            sqlite3_finalize(stmt)
            return dirs
        }
    }

    func addDirectory(_ dir: IndexDirectory) {
        dbQueue.sync {
            let sql = "INSERT OR IGNORE INTO directories (path, type, enabled) VALUES (?, ?, 1)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, dir.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dir.type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func removeDirectory(_ dir: IndexDirectory) {
        dbQueue.sync {
            // Delete files in this directory
            var delStmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE dir_id = ?", -1, &delStmt, nil)
            sqlite3_bind_int64(delStmt, 1, dir.id)
            sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)

            // Delete directory
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM directories WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, dir.id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// A parent index root already covers its descendants, so nested roots would duplicate paths.
    func removeDirectoriesNestedWithin(_ parentPath: String) {
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        dbQueue.sync {
            let sql = "SELECT id FROM directories WHERE path LIKE ?"
            var selectStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &selectStmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(selectStmt, 1, "\(prefix)%", -1, SQLITE_TRANSIENT)

            var nestedIds: [Int64] = []
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                nestedIds.append(sqlite3_column_int64(selectStmt, 0))
            }
            sqlite3_finalize(selectStmt)

            guard !nestedIds.isEmpty else { return }
            for id in nestedIds {
                var deleteFiles: OpaquePointer?
                if sqlite3_prepare_v2(db, "DELETE FROM files WHERE dir_id = ?", -1, &deleteFiles, nil) == SQLITE_OK {
                    sqlite3_bind_int64(deleteFiles, 1, id)
                    sqlite3_step(deleteFiles)
                }
                sqlite3_finalize(deleteFiles)

                var deleteDirectory: OpaquePointer?
                if sqlite3_prepare_v2(db, "DELETE FROM directories WHERE id = ?", -1, &deleteDirectory, nil) == SQLITE_OK {
                    sqlite3_bind_int64(deleteDirectory, 1, id)
                    sqlite3_step(deleteDirectory)
                }
                sqlite3_finalize(deleteDirectory)
            }
        }
    }

    func updateLastScanTime(_ dir: IndexDirectory) {
        dbQueue.sync {
            let sql = "UPDATE directories SET last_scan_time = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 2, dir.id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - File Operations

    func insertFilesBatch(_ files: [(fileName: String, fullPath: String, size: Int64, modDate: Double, dirId: Int64, isDirectory: Bool)]) {
        dbQueue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            let sql = """
            INSERT OR REPLACE INTO files (file_name, full_path, size, mod_date, dir_id, is_directory)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            for file in files {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, file.fileName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, file.fullPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, file.size)
                sqlite3_bind_double(stmt, 4, file.modDate)
                sqlite3_bind_int64(stmt, 5, file.dirId)
                sqlite3_bind_int(stmt, 6, file.isDirectory ? 1 : 0)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    /// Atomically replace all entries for a directory: delete old + insert new in one transaction
    func replaceDirectoryEntries(dirId: Int64, entries: [(fileName: String, fullPath: String, size: Int64, modDate: Double, isDirectory: Bool)]) {
        dbQueue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

            // Delete old entries for this directory
            var delStmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE dir_id = ?", -1, &delStmt, nil)
            sqlite3_bind_int64(delStmt, 1, dirId)
            sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)

            // Insert new entries
            let sql = """
            INSERT OR REPLACE INTO files (file_name, full_path, size, mod_date, dir_id, is_directory)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            for entry in entries {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, entry.fileName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, entry.fullPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, entry.size)
                sqlite3_bind_double(stmt, 4, entry.modDate)
                sqlite3_bind_int64(stmt, 5, dirId)
                sqlite3_bind_int(stmt, 6, entry.isDirectory ? 1 : 0)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    // MARK: - Transactional Directory Scans

    /// Scan results are staged first, so a failed or incomplete scan never replaces a valid index.
    func beginDirectoryScan(_ scanId: String) -> Bool {
        dbQueue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM scan_staging WHERE scan_id = ?", -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_text(stmt, 1, scanId, -1, SQLITE_TRANSIENT)
            let success = sqlite3_step(stmt) == SQLITE_DONE
            sqlite3_finalize(stmt)
            return success
        }
    }

    func appendDirectoryScanEntries(_ scanId: String, entries: [(fileName: String, fullPath: String, size: Int64, modDate: Double, isDirectory: Bool)]) -> Bool {
        guard !entries.isEmpty else { return true }

        return dbQueue.sync {
            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return false }
            let sql = """
            INSERT OR REPLACE INTO scan_staging (scan_id, file_name, full_path, size, mod_date, is_directory)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }

            var success = true
            for entry in entries {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, scanId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, entry.fileName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, entry.fullPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, entry.size)
                sqlite3_bind_double(stmt, 5, entry.modDate)
                sqlite3_bind_int(stmt, 6, entry.isDirectory ? 1 : 0)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    success = false
                    break
                }
            }
            sqlite3_finalize(stmt)

            guard success else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
        }
    }

    func commitDirectoryScan(_ scanId: String, dirId: Int64) -> Bool {
        dbQueue.sync {
            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return false }

            var deleteFiles: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM files WHERE dir_id = ?", -1, &deleteFiles, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_bind_int64(deleteFiles, 1, dirId)
            guard sqlite3_step(deleteFiles) == SQLITE_DONE else {
                sqlite3_finalize(deleteFiles)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_finalize(deleteFiles)

            let insertSQL = """
            INSERT OR REPLACE INTO files (file_name, full_path, size, mod_date, dir_id, is_directory)
            SELECT file_name, full_path, size, mod_date, ?, is_directory
            FROM scan_staging WHERE scan_id = ?
            """
            var insertFiles: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertSQL, -1, &insertFiles, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_bind_int64(insertFiles, 1, dirId)
            sqlite3_bind_text(insertFiles, 2, scanId, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(insertFiles) == SQLITE_DONE else {
                sqlite3_finalize(insertFiles)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_finalize(insertFiles)

            var deleteStaging: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM scan_staging WHERE scan_id = ?", -1, &deleteStaging, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_bind_text(deleteStaging, 1, scanId, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(deleteStaging) == SQLITE_DONE else {
                sqlite3_finalize(deleteStaging)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_finalize(deleteStaging)

            return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
        }
    }

    func discardDirectoryScan(_ scanId: String) {
        dbQueue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM scan_staging WHERE scan_id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, scanId, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func clearDirectoryFiles(_ dir: IndexDirectory) {
        dbQueue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE dir_id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, dir.id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func removeFileById(_ id: Int64) {
        dbQueue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func getTotalFileCount() -> Int {
        return dbQueue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM files", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            var count: Int = 0
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
            return count
        }
    }

    func getDirectoryIndexStats() -> [Int64: DirectoryIndexStats] {
        dbQueue.sync {
            var stats: [Int64: DirectoryIndexStats] = [:]
            let sql = """
            SELECT dir_id,
                   SUM(CASE WHEN is_directory = 0 THEN 1 ELSE 0 END),
                   SUM(CASE WHEN is_directory = 1 THEN 1 ELSE 0 END)
            FROM files
            GROUP BY dir_id
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return stats }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dirId = sqlite3_column_int64(stmt, 0)
                stats[dirId] = DirectoryIndexStats(
                    fileCount: Int(sqlite3_column_int64(stmt, 1)),
                    folderCount: Int(sqlite3_column_int64(stmt, 2))
                )
            }
            sqlite3_finalize(stmt)
            return stats
        }
    }

    func getFilesByIds(_ ids: Set<Int64>) -> [IndexedFile] {
        return dbQueue.sync {
            var files: [IndexedFile] = []
            guard !ids.isEmpty else { return files }
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT id, file_name, full_path, size, mod_date, dir_id, is_directory FROM files WHERE id IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return files }
            for (i, id) in ids.enumerated() {
                sqlite3_bind_int64(stmt, Int32(i + 1), id)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                files.append(readFile(stmt))
            }
            sqlite3_finalize(stmt)
            return files
        }
    }

    // MARK: - Search using LIKE (fast for filename search on indexed column)

    func searchFiles(query: String, limit: Int) -> [IndexedFile] {
        return dbQueue.sync {
            var files: [IndexedFile] = []
            // Split into tokens, search each with AND logic using LIKE
            let tokens = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return files }

            // A single partial term is inexpensive with LIKE. Multiple substantial terms use
            // the trigram index, preserving substring semantics without scanning the disk.
            if tokens.count == 1 {
                let likePattern = "%\(tokens[0])%"
                let sql = "SELECT id, file_name, full_path, size, mod_date, dir_id, is_directory FROM files WHERE file_name LIKE ? LIMIT ?"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return files }
                sqlite3_bind_text(stmt, 1, likePattern, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    files.append(readFile(stmt))
                }
                sqlite3_finalize(stmt)
            } else if tokens.allSatisfy({ $0.count >= 3 }) {
                let ftsQuery = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")
                let sql = """
                SELECT f.id, f.file_name, f.full_path, f.size, f.mod_date, f.dir_id, f.is_directory
                FROM files_fts ft
                JOIN files f ON f.id = ft.rowid
                WHERE files_fts MATCH ?
                LIMIT ?
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return files }
                sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    files.append(readFile(stmt))
                }
                sqlite3_finalize(stmt)
            } else {
                let conditions = tokens.map { _ in "file_name LIKE ?" }.joined(separator: " AND ")
                let sql = "SELECT id, file_name, full_path, size, mod_date, dir_id, is_directory FROM files WHERE \(conditions) LIMIT ?"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return files }
                for (index, token) in tokens.enumerated() {
                    sqlite3_bind_text(stmt, Int32(index + 1), "%\(token)%", -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int(stmt, Int32(tokens.count + 1), Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    files.append(readFile(stmt))
                }
                sqlite3_finalize(stmt)
            }
            return files
        }
    }

    // MARK: - Excluded Directories

    func getAllExcludedPatterns() -> [String] {
        return dbQueue.sync {
            var patterns: [String] = []
            let sql = "SELECT pattern FROM excluded_dirs ORDER BY id"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return patterns }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    patterns.append(String(cString: cstr))
                }
            }
            sqlite3_finalize(stmt)
            return patterns
        }
    }

    func addExcludedPattern(_ pattern: String) {
        dbQueue.sync {
            let sql = "INSERT OR IGNORE INTO excluded_dirs (pattern) VALUES (?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func removeExcludedPattern(_ pattern: String) {
        dbQueue.sync {
            let sql = "DELETE FROM excluded_dirs WHERE pattern = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Rename

    func renameFile(fileId: Int64, newName: String, newPath: String) -> Bool {
        return dbQueue.sync {
            let sql = "UPDATE files SET file_name = ?, full_path = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, newPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, fileId)
            let result = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            return result == SQLITE_DONE
        }
    }

    func getFileByPath(_ path: String) -> IndexedFile? {
        return dbQueue.sync {
            let sql = "SELECT id, file_name, full_path, size, mod_date, dir_id, is_directory FROM files WHERE full_path = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            var file: IndexedFile?
            if sqlite3_step(stmt) == SQLITE_ROW {
                file = readFile(stmt)
            }
            sqlite3_finalize(stmt)
            return file
        }
    }

    func deleteByPath(_ path: String) {
        dbQueue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM files WHERE full_path = ?", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func getLastScanTime(for dirId: Int64) -> Double {
        return dbQueue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT last_scan_time FROM directories WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            sqlite3_bind_int64(stmt, 1, dirId)
            var result: Double = 0
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = sqlite3_column_double(stmt, 0)
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    private func readFile(_ stmt: OpaquePointer!) -> IndexedFile {
        return IndexedFile(
            id: sqlite3_column_int64(stmt, 0),
            fileName: String(cString: sqlite3_column_text(stmt, 1)),
            fullPath: String(cString: sqlite3_column_text(stmt, 2)),
            size: sqlite3_column_int64(stmt, 3),
            modDate: sqlite3_column_double(stmt, 4),
            dirId: sqlite3_column_int64(stmt, 5),
            isDirectory: sqlite3_column_int(stmt, 6) != 0
        )
    }
}
