import Foundation
import SQLite3

/// A disk-backed key/value ledger. Tree size never determines the Swift heap.
final class SyncStateDatabase {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, readOnly: Bool = false) throws {
        if !readOnly {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &database, access | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            throw BackupStorageError.invalidSnapshot
        }
        sqlite3_busy_timeout(database, 5000)
        if !readOnly {
            do {
                try execute("PRAGMA journal_mode=WAL; PRAGMA cache_size=-1024; PRAGMA temp_store=FILE; CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value BLOB NOT NULL);")
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            } catch {
                sqlite3_close(database)
                database = nil
                throw error
            }
        }
    }

    deinit { sqlite3_close(database) }

    func get<T: Decodable>(_ key: String, as _: T.Type) throws -> T? {
        var value: T?
        try query("SELECT key,value FROM state WHERE key=?", key: key) { _, data in value = try JSONDecoder().decode(T.self, from: data) }
        return value
    }

    func put(_ key: String, _ value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO state VALUES(?,?)", -1, &statement, nil) == SQLITE_OK, let statement else { throw BackupStorageError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw BackupStorageError.invalidSnapshot }
    }

    func remove(_ key: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM state WHERE key=?", -1, &statement, nil) == SQLITE_OK, let statement else { throw BackupStorageError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw BackupStorageError.invalidSnapshot }
    }

    func each<T: Decodable>(prefix: String, as _: T.Type, _ body: (String, T) throws -> Void) throws {
        // Page keys before callbacks, so callers can safely update the ledger.
        var cursor = prefix
        while true {
            var page: [(String, Data)] = []
            try query("SELECT key,value FROM state WHERE key>? ORDER BY key LIMIT 100", key: cursor) { key, data in page.append((key, data)) }
            guard !page.isEmpty else { return }
            for (key, data) in page {
                guard key.hasPrefix(prefix) else { return }
                try autoreleasepool { try body(key, JSONDecoder().decode(T.self, from: data)) }
                cursor = key
            }
        }
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw BackupStorageError.invalidSnapshot }
    }

    func page<T: Decodable>(prefix: String, as _: T.Type, limit: Int, offset: Int) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM state WHERE key>=? AND key<? ORDER BY key LIMIT ? OFFSET ?", -1, &statement, nil) == SQLITE_OK, let statement else { throw BackupStorageError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, prefix, -1, transient)
        sqlite3_bind_text(statement, 2, prefix + "\u{10FFFF}", -1, transient)
        sqlite3_bind_int64(statement, 3, Int64(min(200, max(1, limit))))
        sqlite3_bind_int64(statement, 4, Int64(max(0, offset)))
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return result
            }
            guard status == SQLITE_ROW, sqlite3_column_bytes(statement, 0) <= 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
            let data = Data(bytes: sqlite3_column_blob(statement, 0), count: Int(sqlite3_column_bytes(statement, 0)))
            try autoreleasepool { try result.append(JSONDecoder().decode(T.self, from: data)) }
        }
    }

    private func query(_ sql: String, key: String, body: (String, Data) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw BackupStorageError.invalidSnapshot }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return
            }
            guard result == SQLITE_ROW, let name = sqlite3_column_text(statement, 0), sqlite3_column_bytes(statement, 1) <= 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
            try body(String(cString: name), Data(bytes: sqlite3_column_blob(statement, 1), count: Int(sqlite3_column_bytes(statement, 1))))
        }
    }
}
