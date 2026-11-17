import Foundation

public struct BackupRevision: Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
}

public struct RecoveryTestReport: Codable, Equatable, Sendable {
    public let machine: String
    public let revision: String
    public let testedAt: Date
    public let verifiedFiles: Int
    public let verifiedBytes: Int64
}

public struct UndoRestoreRecord: Codable, Equatable, Identifiable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let path: String
        public let copy: String
        public let existed: Bool
    }

    public let id: String
    public let createdAt: Date
    public let entries: [Entry]
}

/// Recovery works against immutable revisions. Neither listing versions nor
/// testing a recovery switches the working branch or writes into the HOME tree.
public struct BackupRecoveryService: Sendable {
    private let repository: String
    private let statusDirectory: String
    private let home: String
    private let environment: [String: String]
    private let destination: BackupDestinationSettings
    private var runner: ProcessRunner {
        ProcessRunner(environment: environment)
    }

    private var undoRoot: URL {
        URL(fileURLWithPath: statusDirectory).appendingPathComponent("restore-undo")
    }

    public init(repository: String, statusDirectory: String, home: String, environment: [String: String]) {
        self.repository = repository
        self.statusDirectory = statusDirectory
        self.home = home
        self.environment = environment
        destination = BackupDestinationSettings(environment: environment)
    }

    public func revisions(machine: String, limit: Int = 50, offset: Int = 0) throws -> [BackupRevision] {
        guard MacSyncPaths.safeMachineName(machine) else { throw BackupStorageError.invalidSnapshot }
        if destination.kind == .cloudFolder {
            guard let folder = destination.cloudFolder else { throw BackupStorageError.invalidDestination }
            return try FolderSnapshotStore(folder: folder, environment: environment).records(machine: machine, limit: limit, offset: offset)
                .map { BackupRevision(id: $0.id, createdAt: $0.createdAt) }
        }
        let result = runner.run("git", ["-C", repository, "log", "--format=%H%x09%ct", "-n", String(min(100, max(1, limit))),
                                        "--skip=\(max(0, offset))", "--", "machines/\(machine)"])
        guard result.status == 0 else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t")
            guard fields.count == 2, let time = TimeInterval(fields[1]) else { return nil }
            return BackupRevision(id: String(fields[0]), createdAt: Date(timeIntervalSince1970: time))
        }
    }

    public func workspace(machine: String, revision: String) throws -> SnapshotReadWorkspace {
        guard MacSyncPaths.safeMachineName(machine) else { throw BackupStorageError.invalidSnapshot }
        let commit: String
        if destination.kind == .cloudFolder {
            guard let folder = destination.cloudFolder else { throw BackupStorageError.invalidDestination }
            let store = FolderSnapshotStore(folder: folder, environment: environment)
            let record = try store.record(machine: machine, id: revision)
            commit = try store.fetch(record, into: repository)
        } else {
            commit = revision
        }
        let result = try SnapshotReadWorkspace(repository: repository, revision: commit, environment: environment)
        let machineRoot = result.root.appendingPathComponent("machines/\(machine)")
        guard FileManager.default.fileExists(atPath: machineRoot.path),
              BackupDestinationSettings.isInside(machineRoot.path, directory: result.root.path)
        else { throw BackupStorageError.invalidSnapshot }
        return result
    }

    public func testRecovery(machine: String, revision: String) throws -> RecoveryTestReport {
        let workspace = try workspace(machine: machine, revision: revision)
        defer { withExtendedLifetime(workspace) {} }
        let source = workspace.root.resolvingSymlinksInPath().appendingPathComponent("machines/\(machine)")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("mac-sync-recovery-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: copy) }
        try copyPath(source: source.path, destination: copy.appendingPathComponent("snapshot").path)
        var files = 0
        var bytes: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            throw BackupStorageError.invalidSnapshot
        }
        for case let url as URL in enumerator {
            try autoreleasepool {
                let itemPath = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
                guard itemPath.hasPrefix(source.path + "/") else { throw BackupStorageError.invalidSnapshot }
                let relative = String(itemPath.dropFirst(source.path.count + 1))
                let restored = copy.appendingPathComponent("snapshot").appendingPathComponent(relative)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true {
                    guard try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                        == FileManager.default.destinationOfSymbolicLink(atPath: restored.path) else { throw BackupStorageError.invalidSnapshot }
                    files += 1
                } else if values.isRegularFile == true {
                    guard try StreamingFileFingerprint.sha256(url.path) == StreamingFileFingerprint.sha256(restored.path) else {
                        throw BackupStorageError.invalidSnapshot
                    }
                    files += 1
                    bytes += Int64(values.fileSize ?? 0)
                }
            }
        }
        let report = RecoveryTestReport(machine: machine, revision: revision, testedAt: Date(), verifiedFiles: files, verifiedBytes: bytes)
        let reportURL = URL(fileURLWithPath: statusDirectory).appendingPathComponent("\(machine).recovery-test.json")
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
        return report
    }

    public func beginUndo(paths: [String]) throws -> UndoRestoreRecord {
        guard paths.count <= 1000, paths.allSatisfy(MacSyncPaths.safeSyncPath) else { throw BackupStorageError.invalidSnapshot }
        let id = UUID().uuidString
        let root = undoRoot.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var entries: [UndoRestoreRecord.Entry] = []
        do {
            for (index, path) in paths.enumerated() {
                let source = localPath(path)
                let existed = exists(source)
                let name = String(index)
                if existed {
                    try copyPath(source: source, destination: root.appendingPathComponent(name).path)
                }
                entries.append(.init(path: path, copy: name, existed: existed))
            }
            let record = UndoRestoreRecord(id: id, createdAt: Date(), entries: entries)
            try JSONEncoder().encode(record).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
            return record
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    public func undoRecords(limit: Int = 50, offset: Int = 0) -> [UndoRestoreRecord] {
        (try? NewestDiskPage.read(limit: limit, offset: offset, ordering: { ($0.createdAt, $0.id) }) { emit in
            guard let files = FileManager.default.enumerator(at: undoRoot, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else { return }
            for case let file as URL in files {
                autoreleasepool {
                    if let record = try? undoRecord(id: file.lastPathComponent) {
                        emit(record)
                    }
                }
            }
        }) ?? []
    }

    public func undo(id: String, preview: Bool) throws {
        let record = try undoRecord(id: id)
        for entry in record.entries {
            try validateTarget(localPath(entry.path), relative: !entry.path.hasPrefix("/"))
            if entry.existed, !exists(undoRoot.appendingPathComponent(id).appendingPathComponent(entry.copy).path) {
                throw BackupStorageError.invalidSnapshot
            }
        }
        for entry in record.entries {
            let target = localPath(entry.path)
            if preview {
                continue
            }
            try validateTarget(target, relative: !entry.path.hasPrefix("/"))
            let parent = URL(fileURLWithPath: target).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let staged = parent.appendingPathComponent(".mac-sync-undo-\(UUID().uuidString)")
            let previous = undoRoot.appendingPathComponent(".replaced-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staged) }
            if entry.existed {
                try copyPath(source: undoRoot.appendingPathComponent(id).appendingPathComponent(entry.copy).path, destination: staged.path)
            }
            let hadTarget = exists(target)
            if hadTarget {
                try FileManager.default.moveItem(atPath: target, toPath: previous.path)
            }
            do {
                if entry.existed {
                    try FileManager.default.moveItem(atPath: staged.path, toPath: target)
                }
            } catch {
                if hadTarget {
                    try? FileManager.default.moveItem(atPath: previous.path, toPath: target)
                }
                throw error
            }
            if hadTarget {
                try FileManager.default.removeItem(at: previous)
            }
        }
    }

    public func undoPreview(id: String) throws -> [UndoRestoreRecord.Entry] {
        try undoRecord(id: id).entries
    }

    public func validateTarget(_ target: String, relative: Bool) throws {
        let parent = URL(fileURLWithPath: target).deletingLastPathComponent().path
        if relative, !BackupDestinationSettings.isInside(parent, directory: home) {
            throw BackupStorageError.unavailable("A restore target has a linked parent outside your home folder. Export the version to a separate folder instead.")
        }
        for protected in [repository, statusDirectory, destination.cloudFolder].compactMap(\.self) {
            if BackupDestinationSettings.isInside(target, directory: protected) || BackupDestinationSettings.isInside(protected, directory: target) {
                throw BackupStorageError.invalidDestination
            }
        }
    }

    private func undoRecord(id: String) throws -> UndoRestoreRecord {
        guard UUID(uuidString: id) != nil else { throw BackupStorageError.invalidSnapshot }
        let manifest = undoRoot.appendingPathComponent(id).appendingPathComponent("manifest.json")
        guard BackupDestinationSettings.isInside(manifest.path, directory: undoRoot.path),
              let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1024 * 1024 else { throw BackupStorageError.invalidSnapshot }
        let record = try JSONDecoder().decode(UndoRestoreRecord.self, from: Data(contentsOf: manifest))
        guard record.id == id, record.entries.count <= 1000,
              record.entries.allSatisfy({ MacSyncPaths.safeSyncPath($0.path) && Int($0.copy).map { $0 >= 0 && $0 < 1000 } == true })
        else { throw BackupStorageError.invalidSnapshot }
        return record
    }

    private func localPath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "\(home)/\(path)"
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func copyPath(source: String, destination: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: source)
        let directory = attributes[.type] as? FileAttributeType == .typeDirectory
        if directory {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        }
        let result = runner.run("rsync", ["-a", directory ? source + "/" : source, directory ? destination + "/" : destination])
        guard result.status == 0 else { throw BackupStorageError.unavailable("A recovery safety copy failed (exit \(result.status)); recovery was stopped.") }
    }
}
