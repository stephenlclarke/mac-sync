import Darwin
import Foundation

public struct MachineFileDelivery: Codable, Identifiable, Sendable {
    public let format: Int
    public let id: String
    public let sender: String
    public let target: String
    public let path: String
    public let createdAt: Date
    public let digest: String
    public let expectedDigest: String?
}

public struct MachineDeliveryReceipt: Codable, Sendable {
    public let id: String
    public let state: String
    public let detail: String
    public let recordedAt: Date
}

/// Each sender owns only its namespace in a target Mac's Inbox. The receiving
/// Mac remains the sole writer of its canonical snapshot and live files.
public struct MachineFileDeliveryStore: Sendable {
    public let repository: String
    private let environment: [String: String]
    private var runner: ProcessRunner {
        ProcessRunner(environment: environment)
    }

    public init(repository: String, environment: [String: String]) {
        self.repository = repository
        self.environment = environment
    }

    public func outboundPaths(sender: String) throws -> [String] {
        guard MacSyncPaths.safeMachineName(sender) else { throw BackupStorageError.invalidSnapshot }
        let root = URL(fileURLWithPath: repository).appendingPathComponent("machines")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: root.path).filter(MacSyncPaths.safeMachineName).compactMap { target in
            let path = "machines/\(target)/inbox/\(sender)"
            return FileManager.default.fileExists(atPath: repository + "/" + path) ? path : nil
        }
    }

    @discardableResult
    public func send(file: String, sender: String, target: String, path: String) throws -> MachineFileDelivery {
        guard MacSyncPaths.safeMachineName(sender), MacSyncPaths.safeMachineName(target), sender != target,
              safeRelative(path), try regular(file),
              FileManager.default.fileExists(atPath: repository + "/machines/" + target) else { throw BackupStorageError.invalidSnapshot }
        let base = repository + "/machines/\(target)/inbox/\(sender)"
        try contained(base)
        let id = UUID().uuidString
        let staging = base + "/.staging-" + id
        try FileManager.default.createDirectory(atPath: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            if FileManager.default.fileExists(atPath: staging) {
                try? FileManager.default.removeItem(atPath: staging)
            }
        }
        let archived = repository + "/machines/\(target)/home/" + path
        try contained(archived)
        let expected = try regular(archived) ? StreamingFileFingerprint.sha256(archived) : nil
        let result = runner.run("rsync", ["-a", "--", file, staging + "/file"])
        guard result.status == 0, try regular(staging + "/file") else { throw BackupStorageError.invalidSnapshot }
        let delivery = try MachineFileDelivery(format: 1, id: id, sender: sender, target: target, path: path, createdAt: Date(),
                                               digest: StreamingFileFingerprint.sha256(staging + "/file"), expectedDigest: expected)
        try JSONEncoder().encode(delivery).write(to: URL(fileURLWithPath: staging + "/manifest.json"), options: .atomic)
        try FileManager.default.moveItem(atPath: staging, toPath: base + "/" + id)
        return delivery
    }

    public func deliveries(target: String, sender selectedSender: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [MachineFileDelivery] {
        guard MacSyncPaths.safeMachineName(target) else { throw BackupStorageError.invalidSnapshot }
        let base = repository + "/machines/\(target)/inbox"
        try contained(base)
        guard let senders = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }
        return try NewestDiskPage.read(limit: limit, offset: offset, ordering: { ($0.createdAt, $0.id) }) { emit in
            for sender in senders where MacSyncPaths.safeMachineName(sender) && (selectedSender == nil || selectedSender == sender) {
                let directory = URL(fileURLWithPath: base + "/" + sender)
                guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { continue }
                for case let item as URL in files {
                    try autoreleasepool {
                        guard UUID(uuidString: item.lastPathComponent) != nil else { return }
                        let manifest = item.appendingPathComponent("manifest.json")
                        try contained(manifest.path)
                        guard let size = try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024,
                              let data = try? Data(contentsOf: manifest), let record = try? JSONDecoder().decode(MachineFileDelivery.self, from: data),
                              valid(record), record.sender == sender, record.target == target, record.id == item.lastPathComponent else { return }
                        emit(record)
                    }
                }
            }
        }
    }

    public func delivery(target: String, id: String) throws -> MachineFileDelivery {
        guard UUID(uuidString: id) != nil else { throw BackupStorageError.invalidSnapshot }
        var offset = 0
        while true {
            let page = try deliveries(target: target, offset: offset)
            if let record = page.first(where: { $0.id == id }) {
                return record
            }
            if page.count < 100 {
                throw BackupStorageError.invalidSnapshot
            }
            offset += 100
        }
    }

    public func receipt(_ delivery: MachineFileDelivery) -> MachineDeliveryReceipt? {
        let file = repository + "/machines/\(delivery.target)/delivery-receipts/\(delivery.id).json"
        guard valid(delivery), (try? contained(file)) != nil,
              let size = try? URL(fileURLWithPath: file).resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024,
              let data = try? Data(contentsOf: URL(fileURLWithPath: file)), data.count < 16 * 1024 else { return nil }
        return try? JSONDecoder().decode(MachineDeliveryReceipt.self, from: data)
    }

    /// Called before backing up local paths, so a queued replacement is not
    /// overwritten by the receiving Mac's previous source copy.
    public func applyPending(target: String, home: String, status: String, selection: [String], automatic: Bool) throws {
        let exclusions = try SyncPathExclusions(file: environment["MAC_SYNC_EXCLUDES_FILE"] ?? repository + "/machines/\(target)/config/excludes.txt")
        var offset = 0
        while true {
            let page = try deliveries(target: target, offset: offset)
            if page.isEmpty {
                return
            }
            for record in page where receipt(record)?.state != "applied" && receipt(record)?.state != "keptLocal" {
                let selected = selection.contains { record.path == $0 || record.path.hasPrefix($0 + "/") } && !exclusions.excludes(record.path, selection: selection)
                if automatic, selected {
                    do { try apply(record, home: home, status: status, force: false) }
                    catch { try saveReceipt(record, state: "needsReview", detail: "The local file changed or is not safe to replace automatically. Both versions were kept.") }
                } else {
                    try saveReceipt(record, state: "needsReview", detail: selected ? "Incoming files are set to review first." : "This path is not selected on the receiving Mac. Choose where to copy it or explicitly apply it.")
                }
            }
            if page.count < 100 {
                return
            }
            offset += 100
        }
    }

    public func apply(_ record: MachineFileDelivery, home: String, status: String, force: Bool) throws {
        try verify(record)
        let target = home + "/" + record.path
        let recovery = BackupRecoveryService(repository: repository, statusDirectory: status, home: home, environment: environment)
        try recovery.validateTarget(target, relative: true)
        let parent = URL(fileURLWithPath: target).deletingLastPathComponent()
        guard BackupDestinationSettings.isInside(parent.path, directory: home) else { throw BackupStorageError.invalidSnapshot }
        var directory = ObjCBool(false)
        guard !FileManager.default.fileExists(atPath: target, isDirectory: &directory) || !directory.boolValue else { throw BackupStorageError.invalidSnapshot }
        let isRegular = try regular(target)
        if !force, FileManager.default.fileExists(atPath: target) && !isRegular {
            throw BackupStorageError.invalidSnapshot
        }
        let current = try isRegular ? StreamingFileFingerprint.sha256(target) : nil
        guard force || current == record.expectedDigest else { throw BackupStorageError.invalidSnapshot }
        // A linked parent would direct the write to a different path even if
        // its current target happens to be somewhere inside HOME.
        var component = parent
        let root = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        while component.resolvingSymlinksInPath().path != root {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: component.path)) != nil {
                throw BackupStorageError.invalidSnapshot
            }
            if component.path == "/" {
                throw BackupStorageError.invalidSnapshot
            }
            component.deleteLastPathComponent()
        }
        _ = try recovery.beginUndo(paths: [record.path])
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appendingPathComponent(".mac-sync-delivery-\(UUID().uuidString)")
        defer {
            if FileManager.default.fileExists(atPath: staged.path) {
                try? FileManager.default.removeItem(at: staged)
            }
        }
        let result = runner.run("rsync", ["-a", "--", payload(record), staged.path])
        guard result.status == 0, try StreamingFileFingerprint.sha256(staged.path) == record.digest,
              try (regular(target) ? StreamingFileFingerprint.sha256(target) : nil) == current,
              rename(staged.path, target) == 0 else { throw BackupStorageError.invalidSnapshot }
        try saveReceipt(record, state: "applied", detail: "Copied to this Mac. The next publish shares the updated snapshot.")
    }

    public func keepLocal(_ record: MachineFileDelivery) throws {
        try saveReceipt(record, state: "keptLocal", detail: "The receiving user kept their local file.")
    }

    /// Merge only immutable deliveries owned by this sender. Existing IDs can
    /// never be overwritten by a later cloud download.
    public func importDeliveries(from sourceRepository: String, sender: String) throws {
        let source = MachineFileDeliveryStore(repository: sourceRepository, environment: environment)
        for path in try source.outboundPaths(sender: sender) {
            let target = path.split(separator: "/")[1]
            var offset = 0
            while true {
                let page = try source.deliveries(target: String(target), sender: sender, offset: offset)
                for record in page {
                    try source.verify(record)
                    let destination = repository + "/machines/\(record.target)/inbox/\(sender)/\(record.id)"
                    try contained(destination)
                    if FileManager.default.fileExists(atPath: destination) {
                        try verify(record); continue
                    }
                    try FileManager.default.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    let staged = destination + ".staging-" + UUID().uuidString
                    defer {
                        if FileManager.default.fileExists(atPath: staged) {
                            try? FileManager.default.removeItem(atPath: staged)
                        }
                    }
                    try FileManager.default.createDirectory(atPath: staged, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(atPath: source.payload(record), toPath: staged + "/file")
                    try JSONEncoder().encode(record).write(to: URL(fileURLWithPath: staged + "/manifest.json"), options: .atomic)
                    try FileManager.default.moveItem(atPath: staged, toPath: destination)
                }
                if page.count < 100 {
                    break
                }
                offset += 100
            }
        }
    }

    private func saveReceipt(_ record: MachineFileDelivery, state: String, detail: String) throws {
        guard valid(record) else { throw BackupStorageError.invalidSnapshot }
        if let previous = receipt(record), previous.state == state, previous.detail == detail {
            return
        }
        let file = URL(fileURLWithPath: repository + "/machines/\(record.target)/delivery-receipts/\(record.id).json")
        try contained(file.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(MachineDeliveryReceipt(id: record.id, state: state, detail: detail, recordedAt: Date())).write(to: file, options: .atomic)
    }

    private func verify(_ record: MachineFileDelivery) throws {
        guard valid(record) else { throw BackupStorageError.invalidSnapshot }
        try contained(payload(record))
        guard try regular(payload(record)), try StreamingFileFingerprint.sha256(payload(record)) == record.digest else { throw BackupStorageError.invalidSnapshot }
    }

    private func payload(_ record: MachineFileDelivery) -> String {
        repository + "/machines/\(record.target)/inbox/\(record.sender)/\(record.id)/file"
    }

    private func contained(_ path: String) throws {
        guard BackupDestinationSettings.isInside(path, directory: repository) else { throw BackupStorageError.invalidSnapshot }
    }

    private func regular(_ path: String) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func valid(_ value: MachineFileDelivery) -> Bool {
        value.format == 1 && UUID(uuidString: value.id) != nil && MacSyncPaths.safeMachineName(value.sender) && MacSyncPaths.safeMachineName(value.target)
            && value.sender != value.target && safeRelative(value.path)
            && value.digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
            && (value.expectedDigest == nil || value.expectedDigest?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
    }

    private func safeRelative(_ path: String) -> Bool {
        !path.hasPrefix("/") && MacSyncPaths.safeSyncPath(path) && !path.split(separator: "/").contains(".git")
    }
}
