import Foundation
import SQLite3

/// A bounded-cache local index. Snapshot data and the portable JSON ledger stay
/// on disk; only a page of summaries or transfer details is returned at a time.
public final class LocalHistoryStore {
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var pendingWrites = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("history.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            throw NSError(domain: "MacSyncHistory", code: 1)
        }
        sqlite3_busy_timeout(database, 5000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA cache_size=-1024; PRAGMA temp_store=FILE;")
        try execute("CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, ordering REAL NOT NULL, summary BLOB NOT NULL, entry_count INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS run_order ON runs(ordering DESC); CREATE TABLE IF NOT EXISTS entries(run_id TEXT NOT NULL, ordinal INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(run_id,ordinal)); CREATE TABLE IF NOT EXISTS imports(path TEXT PRIMARY KEY, modified REAL NOT NULL);")
    }

    deinit {
        if pendingWrites > 0 {
            try? execute("COMMIT")
        }
        sqlite3_close(database)
    }

    public func append(_ entry: SyncHistoryEntry, runID: String, ordinal: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        if pendingWrites == 0 {
            try execute("BEGIN IMMEDIATE")
        }
        do {
            try statement("INSERT OR REPLACE INTO entries VALUES(?,?,?)", values: [runID, ordinal, encoder.encode(entry)]) { _ in }
            pendingWrites += 1
            if pendingWrites >= 256 {
                try flush()
            }
        } catch {
            try? execute("ROLLBACK")
            pendingWrites = 0
            throw error
        }
    }

    public func finish(_ summary: SyncHistoryRecord, entryCount: Int, ordering: Double = Date().timeIntervalSince1970) throws {
        lock.lock()
        defer { lock.unlock() }
        try flush()
        try statement("INSERT OR REPLACE INTO runs VALUES(?,?,?,?)", values: [summary.id, ordering, encoder.encode(summary.summary), entryCount]) { _ in }
    }

    public func page(limit: Int = 50, offset: Int = 0) throws -> [SyncHistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        var records: [SyncHistoryRecord] = []
        try statement("SELECT summary FROM runs ORDER BY ordering DESC,id DESC LIMIT ? OFFSET ?", values: [min(100, max(1, limit)), max(0, offset)]) { row in
            try records.append(decoder.decode(SyncHistoryRecord.self, from: blob(row, column: 0)))
        }
        return records
    }

    public func entries(runID: String, limit: Int = 200, offset: Int = 0) throws -> [SyncHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        var result: [SyncHistoryEntry] = []
        try statement("SELECT payload FROM entries WHERE run_id=? ORDER BY ordinal LIMIT ? OFFSET ?", values: [runID, min(500, max(1, limit)), max(0, offset)]) { row in
            try result.append(decoder.decode(SyncHistoryEntry.self, from: blob(row, column: 0)))
        }
        return result
    }

    public func entryCount(runID: String) throws -> Int {
        try integer("SELECT entry_count FROM runs WHERE id=?", values: [runID])
    }

    public func count() throws -> Int {
        try integer("SELECT COUNT(*) FROM runs")
    }

    public func markImported(_ url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
        try statement("INSERT OR REPLACE INTO imports VALUES(?,?)", values: [url.lastPathComponent, modified]) { _ in }
    }

    /// Old ledgers are preserved and streamed once. Invalid records remain
    /// on disk for diagnosis; one corrupt record does not hide other runs.
    public func importLegacy(directory: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let root = URL(fileURLWithPath: directory)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { return }
        for case let url as URL in files where url.pathExtension == "json" {
            let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = attributes.contentModificationDate?.timeIntervalSince1970 ?? 0
            var imported = false
            try statement("SELECT modified FROM imports WHERE path=?", values: [url.lastPathComponent]) { row in
                imported = sqlite3_column_double(row, 0) == modified
            }
            if imported {
                continue
            }
            let stagingID = "import-\(UUID().uuidString)"
            var entryCount = 0
            let record: SyncHistoryRecord
            do {
                record = try StreamingHistoryReader.read(url) { entry in
                    try self.append(entry, runID: stagingID, ordinal: entryCount)
                    entryCount += 1
                }
                try flush()
            } catch {
                try flush()
                try statement("DELETE FROM entries WHERE run_id=?", values: [stagingID]) { _ in }
                try markImported(url)
                continue
            }
            let exists = try integer("SELECT COUNT(*) FROM runs WHERE id=?", values: [record.id]) > 0
            if !exists {
                try statement("UPDATE entries SET run_id=? WHERE run_id=?", values: [record.id, stagingID]) { _ in }
                try finish(record.summary, entryCount: entryCount, ordering: Double(url.deletingPathExtension().lastPathComponent.prefix(13)).map { $0 / 1000 } ?? modified)
            } else {
                try statement("DELETE FROM entries WHERE run_id=?", values: [stagingID]) { _ in }
            }
            try statement("INSERT OR REPLACE INTO imports VALUES(?,?)", values: [url.lastPathComponent, modified]) { _ in }
        }
    }

    private func flush() throws {
        if pendingWrites > 0 {
            try execute("COMMIT"); pendingWrites = 0
        }
    }

    private func integer(_ sql: String, values: [Any] = []) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var result = 0
        try statement(sql, values: values) { result = Int(sqlite3_column_int64($0, 0)) }
        return result
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func statement(_ sql: String, values: [Any], row: (OpaquePointer) throws -> Void) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else { throw failure() }
        defer { sqlite3_finalize(prepared) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            if let value = value as? String {
                sqlite3_bind_text(prepared, position, value, -1, transient)
            } else if let value = value as? Int {
                sqlite3_bind_int64(prepared, position, Int64(value))
            } else if let value = value as? Double {
                sqlite3_bind_double(prepared, position, value)
            } else if let value = value as? Data {
                _ = value.withUnsafeBytes { sqlite3_bind_blob(prepared, position, $0.baseAddress, Int32($0.count), transient) }
            }
        }
        while true {
            let status = sqlite3_step(prepared)
            if status == SQLITE_DONE {
                return
            }
            guard status == SQLITE_ROW else { throw failure() }
            try row(prepared)
        }
    }

    private func blob(_ row: OpaquePointer, column: Int32) -> Data {
        Data(bytes: sqlite3_column_blob(row, column), count: Int(sqlite3_column_bytes(row, column)))
    }

    private func failure() -> NSError {
        NSError(domain: "MacSyncHistory", code: Int(sqlite3_errcode(database)))
    }
}

public extension SyncHistoryRecord {
    var summary: SyncHistoryRecord {
        let boundedConditions = (conditions ?? []).prefix(32).map { condition in
            SyncHealthCondition(id: condition.id, code: condition.code, component: condition.component,
                                severity: condition.severity, title: String(condition.title.prefix(512)),
                                detail: String(condition.detail.prefix(2000)), recovery: String(condition.recovery.prefix(2000)))
        }
        let boundedCommands = (commands ?? []).suffix(32).map { command in
            SyncCommandDiagnostic(id: command.id, step: String(command.step.prefix(512)),
                                  command: String(command.command.prefix(512)), attempt: command.attempt,
                                  exitStatus: command.exitStatus, output: String(command.output.prefix(2000)))
        }
        return SyncHistoryRecord(id: id, action: action, sourceMachine: sourceMachine, result: result,
                                 timing: SyncHistoryTiming(startedAt: startedAt, finishedAt: finishedAt, durationSeconds: durationSeconds), entries: [],
                                 diagnostics: SyncHistoryDiagnostics(warningCount: warningCount, errorCount: errorCount,
                                                                     warnings: warnings.prefix(100).map { String($0.prefix(2000)) },
                                                                     errors: errors.prefix(100).map { String($0.prefix(2000)) },
                                                                     conditions: boundedConditions, commands: boundedCommands))
    }
}
