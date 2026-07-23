import Foundation
import MacSyncCore

enum NavigationItem: Hashable {
    case dashboard
    case thisMac
    case selection
    case history
    case triage
    case machine(String)
}

enum SyncResult: String, Equatable {
    case unknown
    case success
    case failed

    var title: String {
        switch self {
        case .unknown:
            "Not yet run"
        case .success:
            "Synced"
        case .failed:
            "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown:
            "circle.dashed"
        case .success:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

struct SyncStatus: Equatable {
    let result: SyncResult
    let startedAt: String?
    let finishedAt: String?
    let durationSeconds: Int?
    let updatedFileCount: Int?
    let updatedByteCount: Int?
    let storageFileCount: Int?
    let storageByteCount: Int?
    let warningCount: Int
    let errorCount: Int
    let lastCommit: String?
    let remoteRepository: String?
    let warnings: [String]
    let errors: [String]
    let recordedLocalChanges: [String]
    /// `nil` means the live working tree could not be inspected. An empty
    /// array means this Mac's snapshot is currently clean.
    let currentLocalChanges: [String]?

    static let empty = SyncStatus(
        result: .unknown,
        startedAt: nil,
        finishedAt: nil,
        durationSeconds: nil,
        updatedFileCount: nil,
        updatedByteCount: nil,
        storageFileCount: nil,
        storageByteCount: nil,
        warningCount: 0,
        errorCount: 0,
        lastCommit: nil,
        remoteRepository: nil,
        warnings: [],
        errors: [],
        recordedLocalChanges: [],
        currentLocalChanges: nil
    )
}

struct SnapshotFile: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case file
        case folder

        var systemImage: String {
            switch self {
            case .file:
                "doc"
            case .folder:
                "folder"
            }
        }
    }

    let displayPath: String
    let kind: Kind
    let byteCount: Int
    let modifiedAt: Date?

    var id: String {
        displayPath
    }
}

struct SnapshotContentNode: Identifiable, Hashable {
    let file: SnapshotFile
    let title: String
    let contents: SnapshotFolderContents?
    let children: [SnapshotContentNode]?

    var id: String {
        file.id
    }
}

struct SnapshotFolderContents: Hashable {
    let fileCount: Int
    let folderCount: Int
}

enum SnapshotContentsTree {
    static func nodes(for files: [SnapshotFile]) -> [SnapshotContentNode] {
        var nodesByPath = [String: MutableNode]()
        var rootPaths = [String]()

        for file in files {
            var parent: MutableNode?
            let paths = ancestorPaths(for: file.displayPath)

            for (index, path) in paths.enumerated() {
                let node: MutableNode
                if let existing = nodesByPath[path] {
                    node = existing
                } else {
                    node = MutableNode(file: SnapshotFile(
                        displayPath: path,
                        kind: .folder,
                        byteCount: 0,
                        modifiedAt: nil
                    ))
                    nodesByPath[path] = node
                    if let parent {
                        parent.children[path] = node
                    } else {
                        rootPaths.append(path)
                    }
                }

                if index == paths.count - 1 {
                    node.file = file
                }
                parent = node
            }
        }

        return ordered(rootPaths.compactMap { nodesByPath[$0] }).map {
            makeNode($0, isRoot: true)
        }
    }

    /// Returns every display path that must be expanded to reveal a snapshot
    /// item, including the item itself when it is a folder.
    static func ancestorPaths(for path: String) -> [String] {
        let isHomePath = path.hasPrefix("~/")
        let isAbsolutePath = path.hasPrefix("/")
        let pathWithoutRoot: Substring = if isHomePath {
            path.dropFirst(2)
        } else if isAbsolutePath {
            path.dropFirst()
        } else {
            Substring(path)
        }
        let components = pathWithoutRoot.split(separator: "/").map(String.init)

        var currentPath = isHomePath ? "~" : ""
        return components.map { component in
            if currentPath == "~" {
                currentPath = "~/\(component)"
            } else if currentPath.isEmpty, isAbsolutePath {
                currentPath = "/\(component)"
            } else if currentPath.isEmpty {
                currentPath = component
            } else {
                currentPath += "/\(component)"
            }
            return currentPath
        }
    }

    /// Converts visible archive paths back to the syntax accepted by
    /// `mac-sync restore --path`. Home-relative archive paths are intentionally
    /// kept portable, while absolute paths remain absolute.
    static func restorePaths(for snapshotPaths: some Sequence<String>) -> [String] {
        let paths = snapshotPaths
            .map { path in
                path.hasPrefix("~/") ? String(path.dropFirst(2)) : path
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        var result: [String] = []
        for path in paths where !result.contains(path) {
            guard !result.contains(where: { selectedPath in
                path.hasPrefix(selectedPath.hasSuffix("/") ? selectedPath : "\(selectedPath)/")
            }) else {
                continue
            }
            result.append(path)
        }
        return result
    }

    private static func ordered(_ nodes: [MutableNode]) -> [MutableNode] {
        nodes.sorted {
            if $0.file.kind != $1.file.kind {
                return $0.file.kind == .folder
            }
            return $0.file.displayPath.localizedStandardCompare($1.file.displayPath) == .orderedAscending
        }
    }

    private static func makeNode(_ node: MutableNode, isRoot: Bool = false) -> SnapshotContentNode {
        let children = ordered(Array(node.children.values)).map { makeNode($0) }
        let contents: SnapshotFolderContents? = if node.file.kind == .folder {
            SnapshotFolderContents(
                fileCount: children.reduce(0) { count, child in
                    count + (child.file.kind == .file ? 1 : child.contents?.fileCount ?? 0)
                },
                folderCount: children.reduce(0) { count, child in
                    guard child.file.kind == .folder else { return count }
                    return count + 1 + (child.contents?.folderCount ?? 0)
                }
            )
        } else {
            nil
        }
        return SnapshotContentNode(
            file: node.file,
            title: isRoot ? node.file.displayPath : pathComponent(in: node.file.displayPath),
            contents: contents,
            children: children.isEmpty ? nil : children
        )
    }

    private static func pathComponent(in path: String) -> String {
        String(path.split(separator: "/").last ?? Substring(path))
    }

    private final class MutableNode {
        var file: SnapshotFile
        var children = [String: MutableNode]()

        init(file: SnapshotFile) {
            self.file = file
        }
    }
}

struct ConfiguredPath: Identifiable, Hashable {
    enum SnapshotState: Hashable {
        case present(SnapshotFile.Kind, Int, Int)
        case missing
    }

    let path: String
    let isDynamic: Bool
    let snapshotState: SnapshotState

    var id: String {
        path
    }
}

struct MachineSnapshot: Identifiable, Hashable {
    let name: String
    let computerName: String?
    let operatingSystem: String?
    let architecture: String?
    let modifiedAt: Date?
    let files: [SnapshotFile]
    let configuredPaths: [ConfiguredPath]
    let hasEncryptedSecrets: Bool
    let packageCount: Int
    let editorExtensionCount: Int
    let repositoryCount: Int

    var id: String {
        name
    }

    var fileCount: Int {
        files.filter { $0.kind == .file }.count
    }

    var totalByteCount: Int {
        files.reduce(0) { $0 + $1.byteCount }
    }
}

struct SyncConfiguration: Equatable {
    let homeDirectory: String
    let dataRepository: String
    let statusDirectory: String
    let machineName: String
    let pathsFile: String
}

struct RepositoryLocations: Equatable, Sendable {
    let dataRepository: String

    static func defaults(homeDirectory: String) -> RepositoryLocations {
        RepositoryLocations(
            dataRepository: "\(homeDirectory)/github/mac-sync-data"
        )
    }
}

enum LocalRepositoryKind: String, CaseIterable, Identifiable, Sendable {
    case syncData

    var id: String {
        rawValue
    }

    var title: String {
        "mac-sync data"
    }

    var shortTitle: String {
        "mac-sync data"
    }

    var cloneURL: String {
        "https://github.com/stephenlclarke/mac-sync-data.git"
    }
}

enum LocalRepositoryState: Equatable, Sendable {
    case ready
    case missing
    case notGitRepository
}

struct LocalRepositoryInspection: Identifiable, Equatable, Sendable {
    let kind: LocalRepositoryKind
    let path: String
    let state: LocalRepositoryState
    let hasOrigin: Bool
    let remoteURL: String?
    let branch: String?

    var id: LocalRepositoryKind {
        kind
    }

    var isReady: Bool {
        state == .ready
    }
}

struct RepositoryRecoveryPlan: Equatable, Sendable {
    let kind: LocalRepositoryKind
    let originalPath: String
    let backupPath: String
}

enum GitHubAccessState: Equatable, Sendable {
    case notChecked
    case checking
    case readAccessReady
    case syncAccessReady
    case noOrigin
    case notGitHubRemote
    case authenticationRequired
    case writeAccessDenied
    case unavailable
    case failed
}

struct GitHubConnectionReport: Identifiable, Equatable, Sendable {
    let repository: LocalRepositoryInspection
    let state: GitHubAccessState
    let detail: String

    var id: LocalRepositoryKind {
        repository.kind
    }
}

struct SyncOverview {
    let configuration: SyncConfiguration
    let status: SyncStatus
    let history: [SyncHistoryRecord]
    let currentMachine: MachineSnapshot?
    let peerMachines: [MachineSnapshot]
    let localSyncProcessID: Int32?
    let isLocalSyncActive: Bool

    var machines: [MachineSnapshot] {
        ([currentMachine].compactMap(\.self) + peerMachines).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

enum SyncAction: Equatable {
    case syncing
    case previewingRestore(String)
    case restoring(String)
    case preparingEncryptedSecretsAccess

    var title: String {
        switch self {
        case .syncing:
            "Syncing this Mac"
        case let .previewingRestore(machine):
            "Previewing copy from \(machine)"
        case let .restoring(machine):
            "Copying from \(machine)"
        case .preparingEncryptedSecretsAccess:
            "Preparing encrypted secrets access"
        }
    }
}

enum SyncConfigurationError: LocalizedError {
    case invalidPath(String)
    case missingExecutable
    case setupRequired

    var errorDescription: String? {
        switch self {
        case let .invalidPath(path):
            "This path is not safe to add to the sync selection: \(path)"
        case .missingExecutable:
            "The mac-sync command is unavailable. Reinstall the app or set MAC_SYNC_EXECUTABLE."
        case .setupRequired:
            "Set up the mac-sync-data repository before running sync or restore."
        }
    }
}
