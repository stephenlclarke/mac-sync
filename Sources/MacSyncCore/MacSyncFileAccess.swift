import Foundation

struct MacSyncFileAccessBackend {
    let make: (URL) throws -> Data
    let resolve: (Data) throws -> URL
    let start: (URL) -> Bool
    let stop: (URL) -> Void

    static var live: Self {
        Self(make: { try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) },
             resolve: {
                 var stale = false
                 return try URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
             }, start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() })
    }
}

public struct MacSyncFileAccessRecord: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public let isDirectory: Bool
    public let bookmark: Data
    public var id: String {
        path
    }
}

/// UI and registered agent use the same signed executable and app container.
/// Each process resolves its own bookmarks and balances its own scope leases.
@MainActor
public final class MacSyncFileAccess {
    public private(set) var records: [MacSyncFileAccessRecord] = []
    public private(set) var unavailablePaths: [String] = []
    private let file: URL
    private let backend: MacSyncFileAccessBackend
    private var leases: [String: URL] = [:]

    public convenience init(file: URL) throws {
        try self.init(file: file, backend: .live)
    }

    init(file: URL, backend: MacSyncFileAccessBackend) throws {
        self.file = file
        self.backend = backend
        if FileManager.default.fileExists(atPath: file.path) {
            guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024 * 1024 else {
                throw BackupStorageError.unavailable("Saved folder permissions are too large. Review folder access in Settings.")
            }
            records = try JSONDecoder().decode([MacSyncFileAccessRecord].self, from: Data(contentsOf: file))
            guard records.count <= 4096 else { throw BackupStorageError.unavailable("Too many saved folder permissions. Grant access to containing folders instead.") }
        }
    }

    public func restore() {
        unavailablePaths = []
        for record in records where leases[record.path] == nil {
            do {
                let url = try backend.resolve(record.bookmark)
                guard backend.start(url) else {
                    unavailablePaths.append(record.path)
                    continue
                }
                leases[record.path] = url
            } catch { unavailablePaths.append(record.path) }
        }
    }

    public func remember(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let record = try MacSyncFileAccessRecord(path: url.standardizedFileURL.path, isDirectory: values.isDirectory == true,
                                                 bookmark: backend.make(url))
        var updated = records.filter { $0.path != record.path }
        updated.append(record)
        guard updated.count <= 4096 else { throw BackupStorageError.unavailable("Grant access to containing folders rather than thousands of individual files.") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(updated).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        records = updated
        if let lease = leases.removeValue(forKey: record.path) {
            backend.stop(lease)
        }
        restore()
    }

    public func covers(_ path: String) -> Bool {
        guard let canonical = MacSyncPaths.canonicalPath(path) else { return false }
        return records.contains { record in
            guard let lease = leases[record.path], let root = MacSyncPaths.canonicalPath(lease.path) else { return false }
            return canonical == root || (record.isDirectory && canonical.hasPrefix(root.hasSuffix("/") ? root : root + "/"))
        }
    }

    public var activeRoots: [MacSyncAccessRoot] {
        records.compactMap { record in
            leases[record.path].map { MacSyncAccessRoot(path: $0.path, isDirectory: record.isDirectory) }
        }
    }

    public func stop() {
        for url in leases.values {
            backend.stop(url)
        }
        leases.removeAll()
    }
}
