import Foundation

/// Appends entries to disk and SQLite as they arrive. The JSON export remains
/// compatible with existing backups and never assembles all entries in RAM.
final class HistoryJournal {
    let id = UUID().uuidString
    private let directory: URL
    private let temporary: URL
    private let handle: FileHandle
    private let store: LocalHistoryStore
    private(set) var count = 0
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(directory: String) throws {
        self.directory = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        temporary = self.directory.appendingPathComponent(".entries-\(id).partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        handle = try FileHandle(forWritingTo: temporary)
        store = try LocalHistoryStore(directory: directory)
    }

    deinit { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }

    func append(_ entry: SyncHistoryEntry) throws {
        try autoreleasepool {
            let encoded = try encoder.encode(entry)
            if count > 0 {
                try handle.write(contentsOf: Data(",\n".utf8))
            }
            try handle.write(contentsOf: encoded)
            try store.append(entry, runID: id, ordinal: count)
            count += 1
        }
    }

    func finish(_ record: SyncHistoryRecord) throws {
        try handle.synchronize()
        let text = try String(decoding: encoder.encode(record.summary), as: UTF8.self)
        guard let range = text.range(of: #""entries"\s*:\s*\[\s*\]"#, options: .regularExpression) else {
            throw NSError(domain: "MacSyncHistory", code: 2)
        }
        let output = directory.appendingPathComponent(".run-\(id).partial")
        defer { try? FileManager.default.removeItem(at: output) }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let destination = try FileHandle(forWritingTo: output)
        defer { try? destination.close() }
        try destination.write(contentsOf: Data((text[..<range.lowerBound] + "\"entries\" : [\n").utf8))
        let source = try FileHandle(forReadingFrom: temporary)
        defer { try? source.close() }
        while try autoreleasepool(invoking: {
            guard let chunk = try source.read(upToCount: 64 * 1024), !chunk.isEmpty else { return false }
            try destination.write(contentsOf: chunk)
            return true
        }) {}
        try destination.write(contentsOf: Data(("\n]" + text[range.upperBound...]).utf8))
        try destination.synchronize()
        let name = String(format: "%013lld-%@.json", Int64(Date().timeIntervalSince1970 * 1000), id)
        let published = directory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: output, to: published)
        try store.finish(record.summary, entryCount: count)
        try store.markImported(published)
    }
}
