import Foundation

/// Read the portable ledger one entry at a time. A legacy run may contain
/// millions of entries, but neither migration nor the UI retains that array.
enum StreamingHistoryReader {
    static func read(_ url: URL, entry: (SyncHistoryEntry) throws -> Void) throws -> SyncHistoryRecord {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var header = Data()
        var suffix = Data()
        var object = Data()
        var depth = 0
        var quoted = false
        var escaped = false
        var foundEntries = false
        var finishedEntries = false
        let decoder = JSONDecoder()
        let bound = 1024 * 1024

        func consume(_ bytes: Data) throws {
            for byte in bytes {
                if finishedEntries {
                    suffix.append(byte)
                    guard suffix.count <= bound else { throw invalid() }
                    continue
                }
                if object.isEmpty {
                    if byte == 93 {
                        finishedEntries = true; continue
                    }
                    if [9, 10, 13, 32, 44].contains(byte) {
                        continue
                    }
                    guard byte == 123 else { throw invalid() }
                }
                object.append(byte)
                guard object.count <= 64 * 1024 else { throw invalid() }
                if quoted {
                    if escaped {
                        escaped = false
                    } else if byte == 92 {
                        escaped = true
                    } else if byte == 34 {
                        quoted = false
                    }
                } else {
                    if byte == 34 {
                        quoted = true
                    } else if byte == 123 || byte == 91 {
                        depth += 1
                    } else if byte == 125 || byte == 93 {
                        depth -= 1
                    }
                }
                if depth == 0 {
                    try entry(decoder.decode(SyncHistoryEntry.self, from: object))
                    object.removeAll(keepingCapacity: true)
                }
            }
        }

        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return false }
            if foundEntries {
                try consume(chunk); return true
            }
            header.append(chunk)
            guard header.count <= bound else { throw invalid() }
            let text = String(decoding: header, as: UTF8.self)
            guard let range = text.range(of: #""entries"\s*:\s*\["#, options: .regularExpression) else { return true }
            let prefix = Data(header.prefix(text[..<range.lowerBound].utf8.count))
            let remainder = Data(header.dropFirst(text[..<range.upperBound].utf8.count))
            header = prefix + Data("\"entries\":[]".utf8)
            foundEntries = true
            try consume(remainder)
            return true
        }) {}
        guard foundEntries, finishedEntries, object.isEmpty else { throw invalid() }
        return try decoder.decode(SyncHistoryRecord.self, from: header + suffix)
    }

    private static func invalid() -> NSError {
        NSError(domain: "MacSyncHistory", code: 4)
    }
}
