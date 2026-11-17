import CryptoKit
import Darwin
import Foundation

public enum IncomingSyncPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, review
    public var id: String {
        rawValue
    }

    public var title: String {
        self == .automatic ? "Apply non-conflicting changes" : "Review every incoming change"
    }
}

struct SyncFileVersion: Codable, Equatable {
    enum Kind: String, Codable { case file, link, deleted }
    let path: String
    let kind: Kind
    let digest: String
    var clock: [String: Int64]
    var generation: String = ""
    var executable = false

    func sameContent(_ other: Self) -> Bool {
        kind == other.kind && digest == other.digest && executable == other.executable
    }

    func dominates(_ other: Self) -> Bool {
        other.clock.allSatisfy { clock[$0.key, default: 0] >= $0.value }
            && clock.contains { $0.value > other.clock[$0.key, default: 0] }
    }

    mutating func merge(_ other: Self) throws {
        guard Set(clock.keys).union(other.clock.keys).count <= 64 else { throw BackupStorageError.invalidSnapshot }
        for (device, count) in other.clock {
            clock[device] = max(clock[device, default: 0], count)
        }
    }

    mutating func increment(_ device: String) throws {
        guard clock.count < 64 || clock[device] != nil, clock[device, default: 0] < Int64.max else { throw BackupStorageError.invalidSnapshot }
        clock[device, default: 0] += 1
    }

    func validate() throws {
        guard MacSyncPaths.safeSyncPath(path), path.utf8.count <= 4096, !path.split(separator: "/").contains(".git"),
              clock.count <= 64, !clock.isEmpty, clock.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value > 0 }),
              kind == .deleted ? digest.isEmpty : digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
        else { throw BackupStorageError.invalidSnapshot }
    }
}

public struct IncomingSyncChange: Codable, Identifiable, Sendable {
    public let id: String
    public let machine: String
    public let revision: String
    public let path: String
    public let reason: String
    public let deletion: Bool
    fileprivate let encodedVersion: Data
}

private struct SyncIndexHeader: Codable {
    let format: Int
    let device: String
    let machine: String
}

/// Per-file causal versions prevent a stale/offline Mac from replacing newer
/// work. Timestamps do not decide a winner. All indexes are streamed on disk.
public final class IncomingSyncEngine {
    private let repository: String
    private let status: String
    private let home: String
    private let machine: String
    private let environment: [String: String]
    private let database: SyncStateDatabase
    private let device: String
    private let recovery: BackupRecoveryService
    private let exclusions: SyncPathExclusions
    private var runner: ProcessRunner {
        ProcessRunner(environment: environment)
    }

    private var root: String {
        "\(repository)/machines/\(machine)"
    }

    public init(repository: String, status: String, home: String, machine: String, environment: [String: String]) throws {
        guard MacSyncPaths.safeMachineName(machine) else { throw BackupStorageError.invalidSnapshot }
        self.repository = repository
        self.status = status
        self.home = home
        self.machine = machine
        self.environment = environment
        recovery = BackupRecoveryService(repository: repository, statusDirectory: status, home: home, environment: environment)
        exclusions = try SyncPathExclusions(file: environment["MAC_SYNC_EXCLUDES_FILE"] ?? repository + "/machines/\(machine)/config/excludes.txt")
        let key = Self.hash(repository + "\0" + machine)
        database = try SyncStateDatabase(path: "\(status)/sync-\(key).sqlite")
        let identity = URL(fileURLWithPath: status).appendingPathComponent("device-id")
        if FileManager.default.fileExists(atPath: identity.path) {
            guard let size = try identity.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 128 else { throw BackupStorageError.invalidSnapshot }
            let data = try Data(contentsOf: identity, options: .mappedIfSafe)
            guard data.count < 128, let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil else { throw BackupStorageError.invalidSnapshot }
            device = value
        } else if let saved = try database.get("device", as: String.self) {
            device = saved
            try Data(saved.utf8).write(to: identity, options: .atomic)
        } else {
            device = UUID().uuidString
            try Data(device.utf8).write(to: identity, options: .withoutOverwriting)
        }
        if let saved = try database.get("device", as: String.self), saved != device {
            throw BackupStorageError.invalidSnapshot
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identity.path)
        try database.put("device", device)
        let index = root + "/sync-index.ndjson"
        if FileManager.default.fileExists(atPath: index) {
            var header: SyncIndexHeader?
            try Self.lines(index) { data in
                if header == nil {
                    header = try JSONDecoder().decode(SyncIndexHeader.self, from: data)
                } else {
                    let value = try JSONDecoder().decode(SyncFileVersion.self, from: data)
                    try value.validate()
                    if try database.get("file:" + value.path, as: SyncFileVersion.self) == nil {
                        try database.put("file:" + value.path, value)
                    }
                }
            }
            guard header?.device == device else {
                throw BackupStorageError.unavailable("Another Mac owns the snapshot named \(machine). Choose a unique This Mac identifier in Settings before syncing. No incoming files were applied.")
            }
        }
    }

    /// Called after rsync. Versions describe exactly the bytes copied into the
    /// snapshot, and only paths that are still selected may become tombstones.
    public func capture(selection: [String]) throws {
        let generation = UUID().uuidString
        try database.execute("BEGIN IMMEDIATE")
        do {
            for selected in selection where !selected.hasPrefix("/") {
                let snapshot = URL(fileURLWithPath: root + "/home/" + selected).standardizedFileURL.resolvingSymlinksInPath()
                guard BackupDestinationSettings.isInside(snapshot.path, directory: root + "/home") else { continue }
                var directory = ObjCBool(false)
                guard FileManager.default.fileExists(atPath: snapshot.path, isDirectory: &directory) || (try? FileManager.default.destinationOfSymbolicLink(atPath: snapshot.path)) != nil else { continue }
                if directory.boolValue {
                    guard let files = FileManager.default.enumerator(at: snapshot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { throw BackupStorageError.invalidSnapshot }
                    for case let file as URL in files {
                        if file.lastPathComponent == ".git" {
                            files.skipDescendants(); continue
                        }
                        try autoreleasepool {
                            let itemPath = file.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(file.lastPathComponent).path
                            guard itemPath.hasPrefix(snapshot.path + "/") else { throw BackupStorageError.invalidSnapshot }
                            let path = selected + "/" + itemPath.dropFirst(snapshot.path.count + 1)
                            if !exclusions.excludes(String(path), selection: selection) {
                                try captureOne(String(path), snapshot: file.path, generation: generation)
                            }
                        }
                    }
                } else if !exclusions.excludes(selected, selection: selection) {
                    try captureOne(selected, snapshot: snapshot.path, generation: generation)
                }
            }
            try database.each(prefix: "file:", as: SyncFileVersion.self) { key, old in
                guard old.generation != generation, selected(old.path, selection: selection), old.kind != .deleted else { return }
                if old.generation == "excluded" || exclusions.excludes(old.path, selection: selection) || FileManager.default.fileExists(atPath: home + "/" + old.path) {
                    var excluded = old
                    excluded.generation = "excluded"
                    try database.put(key, excluded)
                    return
                }
                var deleted = SyncFileVersion(path: old.path, kind: .deleted, digest: "", clock: old.clock, generation: generation)
                try deleted.increment(device)
                try database.put(key, deleted)
            }
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
    }

    private func captureOne(_ path: String, snapshot: String, generation: String) throws {
        guard let fingerprint = try Self.fingerprint(snapshot, path: path) else { return }
        let current = try Self.fingerprint(home + "/" + path, path: path)
        // A save raced rsync. Never advertise bytes that were not captured.
        guard current?.sameContent(fingerprint) == true else { throw BackupStorageError.unavailable("The file \(path) changed while it was being copied. Its incoming changes were not applied; the next sync will retry.") }
        var value = fingerprint
        if let previous = try database.get("file:" + path, as: SyncFileVersion.self) {
            value.clock = previous.clock
            if !value.sameContent(previous) {
                try value.increment(device)
            }
        } else {
            try value.increment(device)
        }
        value.generation = generation
        try database.put("file:" + path, value)
    }

    @discardableResult
    public func receive(selection: [String], policy: IncomingSyncPolicy, boundary: () throws -> Void = {}) throws -> Int {
        try database.execute("BEGIN IMMEDIATE")
        var committed = false
        defer {
            if !committed {
                try? database.execute("ROLLBACK")
            }
        }
        try database.each(prefix: "change:", as: IncomingSyncChange.self) { key, _ in try database.remove(key) }
        var applied = 0
        let names = try FileManager.default.contentsOfDirectory(atPath: repository + "/machines").filter { MacSyncPaths.safeMachineName($0) && $0 != machine && $0 != "_shared" }.sorted()
        for peer in names {
            try boundary()
            let sourceRoot = repository + "/machines/" + peer
            let index = sourceRoot + "/sync-index.ndjson"
            guard FileManager.default.fileExists(atPath: index) else { continue }
            let revision: String = if environment["MAC_SYNC_STORAGE_KIND"] == BackupStorageKind.cloudFolder.rawValue {
                (try? String(contentsOfFile: status + "/cloud-imports/" + peer + ".id", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else {
                runner.run("git", ["-C", repository, "rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Validate a whole ledger before applying any of its entries.
            try database.each(prefix: "incoming:", as: Bool.self) { key, _ in try database.remove(key) }
            var header: SyncIndexHeader?
            try Self.lines(index) { data in
                if header == nil {
                    let decoded = try JSONDecoder().decode(SyncIndexHeader.self, from: data)
                    guard decoded.format == 1, decoded.machine == peer, UUID(uuidString: decoded.device) != nil, decoded.device != device else { throw BackupStorageError.invalidSnapshot }
                    header = decoded
                } else {
                    let value = try JSONDecoder().decode(SyncFileVersion.self, from: data)
                    try value.validate()
                    guard try database.get("incoming:" + value.path, as: Bool.self) == nil else { throw BackupStorageError.invalidSnapshot }
                    try database.put("incoming:" + value.path, true)
                }
            }
            guard header != nil else { throw BackupStorageError.invalidSnapshot }
            var first = true
            try Self.lines(index) { data in
                if first {
                    first = false; return
                }
                try boundary()
                let remote = try JSONDecoder().decode(SyncFileVersion.self, from: data)
                try remote.validate()
                guard selected(remote.path, selection: selection), !exclusions.excludes(remote.path, selection: selection) else { return }
                let stored = try database.get("file:" + remote.path, as: SyncFileVersion.self)
                let local = stored?.generation == "excluded" ? nil : stored
                if let local, local.dominates(remote) {
                    return
                }
                if let local, local.sameContent(remote) {
                    var merged = local
                    try merged.merge(remote)
                    try database.put("file:" + remote.path, merged)
                    return
                }
                let concurrent = local.map { !remote.dominates($0) } ?? false
                let reason: String? = if remote.kind == .deleted {
                    "Deletion requires confirmation"
                } else if concurrent {
                    "Both Macs changed this file"
                } else if policy == .review {
                    "Incoming changes are set to review first"
                } else {
                    nil
                }
                if let reason {
                    try recordChange(remote, peer: peer, revision: revision, reason: reason); return
                }
                do {
                    try apply(remote, from: sourceRoot, expected: local)
                    try database.put("file:" + remote.path, remote)
                    applied += 1
                } catch {
                    try recordChange(remote, peer: peer, revision: revision, reason: "The local path changed, is linked, or needs a file/folder replacement. Review it before applying.")
                }
            }
        }
        try database.execute("COMMIT")
        committed = true
        return applied
    }

    public func exportIndex(selection: [String]) throws {
        let file = URL(fileURLWithPath: root + "/sync-index.ndjson")
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".sync-index-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer {
            if FileManager.default.fileExists(atPath: temporary.path) {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try handle.write(contentsOf: encoder.encode(SyncIndexHeader(format: 1, device: device, machine: machine)) + Data([10]))
        try database.each(prefix: "file:", as: SyncFileVersion.self) { _, value in
            var exported = value
            exported.generation = ""
            if selected(value.path, selection: selection), value.generation != "excluded" {
                try handle.write(contentsOf: encoder.encode(exported) + Data([10]))
            }
        }
        try handle.synchronize()
        if FileManager.default.fileExists(atPath: file.path), StreamingFileComparison.equal(file.path, temporary.path) {
            return
        }
        guard rename(temporary.path, file.path) == 0 else { throw BackupStorageError.invalidSnapshot }
    }

    public func changes(limit: Int = 100, offset: Int = 0) throws -> [IncomingSyncChange] {
        try Self.changes(database: database, limit: limit, offset: offset)
    }

    public static func pendingChanges(repository: String, status: String, machine: String, limit: Int = 100, offset: Int = 0) throws -> [IncomingSyncChange] {
        let path = "\(status)/sync-\(hash(repository + "\0" + machine)).sqlite"
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        return try changes(database: SyncStateDatabase(path: path), limit: limit, offset: offset)
    }

    private static func changes(database: SyncStateDatabase, limit: Int, offset: Int) throws -> [IncomingSyncChange] {
        try database.page(prefix: "change:", as: IncomingSyncChange.self, limit: limit, offset: offset)
    }

    public func resolve(id: String, keepLocal: Bool, keepBoth: Bool = false, selection: [String]) throws {
        guard let change = try database.get("change:" + id, as: IncomingSyncChange.self) else { throw BackupStorageError.invalidSnapshot }
        guard selected(change.path, selection: selection), !exclusions.excludes(change.path, selection: selection) else { throw BackupStorageError.unavailable("This file is no longer selected for sync, or is excluded. No incoming changes were applied.") }
        let remote = try JSONDecoder().decode(SyncFileVersion.self, from: change.encodedVersion)
        try remote.validate()
        var local = try Self.fingerprint(home + "/" + remote.path, path: remote.path)
            ?? SyncFileVersion(path: remote.path, kind: .deleted, digest: "", clock: [:])
        if let previous = try database.get("file:" + remote.path, as: SyncFileVersion.self) {
            try local.merge(previous)
        }
        try local.merge(remote)
        try local.increment(device)
        if !keepLocal {
            let workspace = try recovery.workspace(machine: change.machine, revision: change.revision)
            defer { withExtendedLifetime(workspace) {} }
            let source = workspace.root.appendingPathComponent("machines/\(change.machine)").path
            if keepBoth, remote.kind != .deleted {
                let copyPath = remote.path + ".from-" + change.machine + "-" + UUID().uuidString.prefix(8)
                let copy = SyncFileVersion(path: String(copyPath), kind: remote.kind, digest: remote.digest, clock: remote.clock, executable: remote.executable)
                try apply(copy, from: source, expected: nil, sourcePath: remote.path, reviewed: true)
            } else {
                try apply(remote, from: source, expected: local, reviewed: true)
                local = SyncFileVersion(path: remote.path, kind: remote.kind, digest: remote.digest, clock: local.clock, executable: remote.executable)
            }
        }
        try database.put("file:" + remote.path, local)
        try database.remove("change:" + id)
    }

    private func recordChange(_ value: SyncFileVersion, peer: String, revision: String, reason: String) throws {
        let id = Self.hash(peer + "\0" + value.path)
        try database.put("change:" + id, IncomingSyncChange(id: id, machine: peer, revision: revision, path: value.path, reason: reason,
                                                            deletion: value.kind == .deleted, encodedVersion: JSONEncoder().encode(value)))
    }

    private func apply(_ value: SyncFileVersion, from sourceRoot: String, expected: SyncFileVersion?, sourcePath: String? = nil, reviewed: Bool = false) throws {
        let target = home + "/" + value.path
        try recovery.validateTarget(target, relative: true)
        let parent = (target as NSString).deletingLastPathComponent
        guard !Self.hasLinkedParent(target, root: home), !Self.hasLinkedParent(sourceRoot + "/home/" + (sourcePath ?? value.path), root: sourceRoot) else { throw BackupStorageError.invalidSnapshot }
        let current = try Self.fingerprint(target, path: value.path)
        if !reviewed {
            guard current?.sameContent(expected ?? SyncFileVersion(path: value.path, kind: .deleted, digest: "", clock: [:])) == true || (current == nil && (expected == nil || expected?.kind == .deleted)) else { throw BackupStorageError.invalidSnapshot }
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue {
                throw BackupStorageError.invalidSnapshot
            }
        }
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let staged = parent + "/.mac-sync-incoming-" + UUID().uuidString
        defer {
            if FileManager.default.fileExists(atPath: staged) {
                try? FileManager.default.removeItem(atPath: staged)
            }
        }
        if value.kind != .deleted {
            let source = sourceRoot + "/home/" + (sourcePath ?? value.path)
            guard BackupDestinationSettings.isInside(source, directory: sourceRoot), let bytes = try Self.fingerprint(source, path: value.path), bytes.sameContent(value) else { throw BackupStorageError.invalidSnapshot }
            let result = runner.run("rsync", ["-a", "--", source, staged])
            guard result.status == 0, try Self.fingerprint(staged, path: value.path)?.sameContent(value) == true else { throw BackupStorageError.invalidSnapshot }
        }
        // Retain an undo copy for automatic changes too. Recheck after copying
        // it, so an editor save during staging cannot be silently overwritten.
        _ = try recovery.beginUndo(paths: [value.path])
        let rechecked = try Self.fingerprint(target, path: value.path)
        guard rechecked?.sameContent(current ?? SyncFileVersion(path: value.path, kind: .deleted, digest: "", clock: [:])) == true || (rechecked == nil && current == nil) else { throw BackupStorageError.invalidSnapshot }
        if value.kind == .deleted {
            var directory = ObjCBool(false)
            guard !FileManager.default.fileExists(atPath: target, isDirectory: &directory) || !directory.boolValue else {
                throw BackupStorageError.unavailable("This path is now a folder. Remove or recover it explicitly; a file-deletion decision cannot delete a folder.")
            }
            if current != nil {
                try FileManager.default.removeItem(atPath: target)
            }
        } else {
            var directory = ObjCBool(false)
            if reviewed, FileManager.default.fileExists(atPath: target, isDirectory: &directory), directory.boolValue {
                let previous = parent + "/.mac-sync-replaced-" + UUID().uuidString
                try FileManager.default.moveItem(atPath: target, toPath: previous)
                if rename(staged, target) != 0 {
                    do { try FileManager.default.moveItem(atPath: previous, toPath: target) }
                    catch { throw BackupStorageError.unavailable("The previous copy was preserved at \(previous). Recovery was stopped.") }
                    throw BackupStorageError.invalidSnapshot
                }
                try FileManager.default.removeItem(atPath: previous)
            } else {
                guard rename(staged, target) == 0 else { throw BackupStorageError.invalidSnapshot }
            }
        }
    }

    private func selected(_ path: String, selection: [String]) -> Bool {
        !path.hasPrefix("/") && selection.contains { !$0.hasPrefix("/") && (path == $0 || path.hasPrefix($0 + "/")) }
    }

    private static func hasLinkedParent(_ path: String, root: String) -> Bool {
        var url = URL(fileURLWithPath: path).deletingLastPathComponent()
        let canonicalRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        while url.resolvingSymlinksInPath().path != canonicalRoot {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                return true
            }
            if url.path == "/" {
                return true
            }
            url.deleteLastPathComponent()
        }
        return false
    }

    private static func fingerprint(_ file: String, path: String) throws -> SyncFileVersion? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file), let type = attributes[.type] as? FileAttributeType else { return nil }
        if type == .typeSymbolicLink {
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: file)
            return SyncFileVersion(path: path, kind: .link, digest: hash(link), clock: [:])
        }
        guard type == .typeRegular else { return nil }
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return try SyncFileVersion(path: path, kind: .file, digest: StreamingFileFingerprint.sha256(file), clock: [:], executable: mode & 0o111 != 0)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func lines(_ path: String, body: (Data) throws -> Void) throws {
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? file.close() }
        var pending = Data()
        while let chunk = try file.read(upToCount: 32 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            while let end = pending.firstIndex(of: 10) {
                let line = Data(pending[..<end])
                guard !line.isEmpty, line.count <= 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
                try autoreleasepool { try body(line) }
                pending.removeSubrange(...end)
            }
            guard pending.count <= 64 * 1024 else { throw BackupStorageError.invalidSnapshot }
        }
        guard pending.isEmpty else { throw BackupStorageError.invalidSnapshot }
    }
}
