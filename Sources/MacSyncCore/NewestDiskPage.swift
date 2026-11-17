import Foundation

/// Pages arbitrarily old records with a constant 100-record memory bound.
/// Re-scanning a directory is deliberately preferable to retaining its tree.
enum NewestDiskPage {
    static func read<T>(limit: Int, offset: Int, ordering: @escaping (T) -> (Date, String), enumerate: (_ emit: (T) -> Void) throws -> Void) throws -> [T] {
        var cursor: (Date, String)?
        var skip = max(0, offset)
        let limit = min(100, max(1, limit))
        var result: [T] = []
        while result.count < limit {
            var page: [T] = []
            try enumerate { record in
                if let cursor, ordering(record) >= cursor {
                    return
                }
                page.append(record)
                page.sort { ordering($0) > ordering($1) }
                if page.count > 100 {
                    page.removeLast()
                }
            }
            guard let last = page.last else { return result }
            cursor = ordering(last)
            for record in page {
                if skip > 0 {
                    skip -= 1
                } else {
                    result.append(record); if result.count == limit {
                        return result
                    }
                }
            }
        }
        return result
    }
}
