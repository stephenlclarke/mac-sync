import Foundation

public struct MacSyncAccessRoot: Codable, Equatable, Sendable {
    public let path: String
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }

    public func covers(_ candidate: String) -> Bool {
        guard let candidate = MacSyncPaths.canonicalPath(candidate), let root = MacSyncPaths.canonicalPath(path) else { return false }
        return candidate == root || (isDirectory && candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/"))
    }
}

public enum MacSyncAccessPolicy {
    /// Metadata is not a grant. It records the scopes this particular parent
    /// held when spawning the worker; the kernel still enforces those scopes.
    public static func validate(paths: [String], environment: [String: String]) throws {
        guard MacSyncDistribution(environment: environment) == .appStore else { return }
        guard let manifest = environment["MAC_SYNC_ACCESS_MANIFEST"], let support = environment["MAC_SYNC_PRIVATE_SUPPORT"],
              BackupDestinationSettings.isInside(manifest, directory: support),
              let size = try URL(fileURLWithPath: manifest).resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2 * 1024 * 1024
        else {
            throw BackupStorageError.unavailable("Folder permissions need renewal in Mac Sync Settings. Existing snapshots were kept.")
        }
        let roots = try JSONDecoder().decode([MacSyncAccessRoot].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
        guard roots.count <= 4096 else { throw BackupStorageError.invalidSnapshot }
        for path in paths where !roots.contains(where: { $0.covers(path) }) {
            throw BackupStorageError.unavailable("Access to \(path) needs renewal in Mac Sync Settings. Existing snapshots were kept.")
        }
    }
}
