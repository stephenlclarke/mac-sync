import CryptoKit
import Foundation

public enum BackupStorageKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case git
    case cloudFolder
    public var id: String {
        rawValue
    }

    public var title: String {
        self == .git ? "Git repository" : "Cloud-synced folder"
    }
}

public enum BackupStorageError: LocalizedError {
    case invalidDestination
    case invalidSnapshot
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination: "Choose an existing destination folder outside the source selection and local backup workspace."
        case .invalidSnapshot: "This backup is incomplete, changed, or not a supported Mac Sync snapshot. The existing local snapshot was kept."
        case let .unavailable(detail): detail
        }
    }
}

public struct BackupDestinationSettings: Equatable, Sendable {
    public let workspace: String
    public let kind: BackupStorageKind
    public let cloudFolder: String?

    public init(workspace: String, kind: BackupStorageKind = .git, cloudFolder: String? = nil) {
        self.workspace = workspace
        self.kind = kind
        self.cloudFolder = cloudFolder
    }

    public init(environment: [String: String]) {
        let values = MacSyncUserConfiguration.resolvedEnvironment(environment)
        workspace = values["MAC_SYNC_MACHINES_REPO"] ?? "\(values["HOME"] ?? NSHomeDirectory())/github/mac-sync-data"
        kind = BackupStorageKind(rawValue: values["MAC_SYNC_STORAGE_KIND"] ?? "") ?? .git
        cloudFolder = values["MAC_SYNC_CLOUD_FOLDER"]
    }

    public static func isInside(_ path: String, directory: String) -> Bool {
        guard let path = MacSyncPaths.canonicalPath(path), let directory = MacSyncPaths.canonicalPath(directory) else { return false }
        return path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }

    public static func cloudWorkspace(folder: String, home: String) -> String {
        let canonical = MacSyncPaths.canonicalPath(folder) ?? folder
        let hash = SHA256.hash(data: Data(canonical.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(home)/Library/Application Support/mac-sync/workspaces/\(hash)"
    }
}
