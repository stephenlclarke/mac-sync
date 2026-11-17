import Foundation

public struct FolderSnapshotRecord: Codable, Equatable, Identifiable, Sendable {
    public let format: Int
    public let id: String
    public let machine: String
    public let createdAt: Date
    public let sourceCommit: String
    public let snapshotCommit: String
    public let reference: String
    public let sha256: String
}

/// The provider sees immutable, self-contained snapshot files, never a live
/// working tree or Git repository. A local write is NOT a confirmed upload.
public struct FolderSnapshotStore: Sendable {
    public let folder: String
    private let environment: [String: String]
    private var runner: ProcessRunner {
        ProcessRunner(environment: environment)
    }

    private var root: URL {
        URL(fileURLWithPath: folder).appendingPathComponent("MacSyncSnapshots")
    }

    public init(folder: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.folder = folder
        self.environment = environment
    }

    public func machines() throws -> [String] {
        try requireFolder()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: root.path).filter(MacSyncPaths.safeMachineName).sorted()
    }

    public func records(machine: String, limit: Int = 50, offset: Int = 0) throws -> [FolderSnapshotRecord] {
        guard MacSyncPaths.safeMachineName(machine) else { throw BackupStorageError.invalidSnapshot }
        try requireFolder()
        let directory = root.appendingPathComponent(machine)
        return try NewestDiskPage.read(limit: limit, offset: offset, ordering: { ($0.createdAt, $0.id) }) { emit in
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { return }
            for case let item as URL in files {
                autoreleasepool {
                    // Only complete manifests are candidates. Archive availability and
                    // integrity are checked again before fetching or restoring bytes.
                    let manifest = item.appendingPathComponent("manifest.json")
                    guard let size = try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024,
                          let data = try? Data(contentsOf: manifest),
                          let record = try? JSONDecoder().decode(FolderSnapshotRecord.self, from: data),
                          valid(record), record.machine == machine, record.id == item.lastPathComponent
                    else { return }
                    emit(record)
                }
            }
        }
    }

    public func record(machine: String, id: String) throws -> FolderSnapshotRecord {
        guard MacSyncPaths.safeMachineName(machine), UUID(uuidString: id) != nil else { throw BackupStorageError.invalidSnapshot }
        try requireFolder()
        let file = root.appendingPathComponent(machine).appendingPathComponent(id).appendingPathComponent("manifest.json")
        guard BackupDestinationSettings.isInside(file.path, directory: folder),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024 else { throw BackupStorageError.invalidSnapshot }
        let record = try JSONDecoder().decode(FolderSnapshotRecord.self, from: Data(contentsOf: file))
        guard valid(record), record.machine == machine, record.id == id else { throw BackupStorageError.invalidSnapshot }
        return record
    }

    @discardableResult
    public func publish(repository: String, machine: String) throws -> FolderSnapshotRecord {
        try requireFolder()
        guard MacSyncPaths.safeMachineName(machine),
              !BackupDestinationSettings.isInside(repository, directory: folder),
              !BackupDestinationSettings.isInside(folder, directory: repository)
        else { throw BackupStorageError.invalidDestination }
        let source = try git(repository, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let latest = try records(machine: machine, limit: 1).first, latest.sourceCommit == source {
            try verify(latest)
            return latest
        }
        let id = UUID().uuidString
        let reference = "refs/mac-sync-exports/\(id)"
        let directory = root.appendingPathComponent(machine)
        let staging = directory.appendingPathComponent(".staging-\(id)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("mac-sync-export-\(id)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: local) }
        let index = local.appendingPathComponent("index").path
        let extra = ["GIT_INDEX_FILE": index]
        _ = try git(repository, ["read-tree", "--empty"], extra: extra)
        _ = try git(repository, ["read-tree", "--prefix=machines/\(machine)/", "HEAD:machines/\(machine)"], extra: extra)
        for path in try MachineFileDeliveryStore(repository: repository, environment: environment).outboundPaths(sender: machine) {
            if path.hasPrefix("machines/\(machine)/") {
                continue
            }
            _ = try git(repository, ["read-tree", "--prefix=\(path)/", "HEAD:\(path)"], extra: extra)
        }
        if runner.run("git", ["-C", repository, "rev-parse", "--verify", "HEAD:machines/_shared"]).status == 0 {
            _ = try git(repository, ["read-tree", "--prefix=machines/_shared/", "HEAD:machines/_shared"], extra: extra)
        }
        let tree = try git(repository, ["write-tree"], extra: extra).trimmingCharacters(in: .whitespacesAndNewlines)
        // No parent: each portable bundle contains only this snapshot, not a
        // growing copy of every earlier backup's complete Git history.
        let commit = try git(repository, ["commit-tree", tree, "-m", "Mac Sync portable snapshot"], extra: [
            "GIT_AUTHOR_NAME": "Mac Sync", "GIT_AUTHOR_EMAIL": "mac-sync@localhost",
            "GIT_COMMITTER_NAME": "Mac Sync", "GIT_COMMITTER_EMAIL": "mac-sync@localhost",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git(repository, ["update-ref", reference, commit])
        defer { _ = runner.run("git", ["-C", repository, "update-ref", "-d", reference]) }
        let archive = staging.appendingPathComponent("snapshot.bundle")
        _ = try git(repository, ["bundle", "create", archive.path, reference])
        let digest = try StreamingFileFingerprint.sha256(archive.path)
        let record = FolderSnapshotRecord(format: 1, id: id, machine: machine, createdAt: Date(), sourceCommit: source,
                                          snapshotCommit: commit, reference: reference, sha256: digest)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        try JSONEncoder().encode(record).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory.appendingPathComponent(id))
        return record
    }

    public func fetch(_ record: FolderSnapshotRecord, into repository: String) throws -> String {
        try verify(record)
        _ = try git(repository, ["bundle", "verify", archiveURL(record).path])
        _ = try git(repository, ["fetch", "--no-tags", archiveURL(record).path, record.reference])
        let fetched = try git(repository, ["rev-parse", "FETCH_HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard fetched == record.snapshotCommit else { throw BackupStorageError.invalidSnapshot }
        return fetched
    }

    public func verify(_ record: FolderSnapshotRecord) throws {
        guard valid(record), BackupDestinationSettings.isInside(archiveURL(record).path, directory: folder),
              try StreamingFileFingerprint.sha256(archiveURL(record).path) == record.sha256
        else {
            throw BackupStorageError.invalidSnapshot
        }
    }

    private func archiveURL(_ record: FolderSnapshotRecord) -> URL {
        root.appendingPathComponent(record.machine).appendingPathComponent(record.id).appendingPathComponent("snapshot.bundle")
    }

    private func valid(_ record: FolderSnapshotRecord) -> Bool {
        record.format == 1 && UUID(uuidString: record.id) != nil && MacSyncPaths.safeMachineName(record.machine)
            && record.reference == "refs/mac-sync-exports/\(record.id)"
            && record.snapshotCommit.range(of: #"^[0-9a-f]{40,64}$"#, options: .regularExpression) != nil
            && record.sourceCommit.range(of: #"^[0-9a-f]{40,64}$"#, options: .regularExpression) != nil
            && record.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    private func requireFolder() throws {
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else {
            throw BackupStorageError.unavailable("The selected cloud folder is not available. Open its sync app or reconnect the volume, then retry. Existing backups were kept.")
        }
        guard BackupDestinationSettings.isInside(root.path, directory: folder) else { throw BackupStorageError.invalidDestination }
    }

    private func git(_ repository: String, _ args: [String], extra: [String: String] = [:]) throws -> String {
        let result = runner.run("git", ["-C", repository] + args, extraEnvironment: extra)
        guard result.status == 0 else {
            throw BackupStorageError.unavailable("Git could not prepare or read the portable snapshot (exit \(result.status)). Existing backups were kept.")
        }
        return result.stdout
    }
}
