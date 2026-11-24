import Darwin
import Foundation
import MacSyncCore

/// Narrow, bounded local reads. No Git, migrations, history store, credential helpers or network.
enum LocalRepairInspectionReader {
    static func read(_ path: String, limit: Int = 1_048_576) throws -> Data? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw LocalRepairError.unreadableStatus
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= limit else { throw LocalRepairError.unreadableStatus }
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        var count = 0
        while count < bytes.count {
            let amount = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!.advanced(by: count), buffer.count - count)
            }
            if amount < 0, errno == EINTR {
                continue
            }
            guard amount >= 0 else { throw LocalRepairError.unreadableStatus }
            if amount == 0 {
                break
            }
            count += amount
        }
        guard count <= limit else { throw LocalRepairError.unreadableStatus }
        return Data(bytes.prefix(count))
    }

    static func worker(configuration: SyncConfiguration, temporaryDirectory: String) throws -> LocalWorkerState {
        let runningPath = "\(configuration.statusDirectory)/\(configuration.machineName).running"
        if let data = try read(runningPath, limit: 64) {
            guard let text = String(data: data, encoding: .utf8), let pid = Int32(text
                .trimmingCharacters(in: .whitespacesAndNewlines)),
                pid > 1 else { return .unknown }
            // An unrelated reused PID remains conservative for this legacy marker.
            if kill(pid, 0) == 0 {
                return .active
            }
            if errno != ESRCH {
                return .unknown
            }
        }
        return operationLockState("\(temporaryDirectory)/mac-sync-\(configuration.machineName).lock/pid")
    }

    /// UI-only inspection. The worker deliberately retains an empty file after
    /// release. F_GETLK queries the kernel; it never takes a lock or writes bytes.
    private static func operationLockState(_ path: String) -> LocalWorkerState {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return errno == ENOENT ? .idle : .unknown }
        defer { close(descriptor) }
        var opened = stat()
        var current = stat()
        var query = flock()
        query.l_type = Int16(F_WRLCK)
        query.l_whence = Int16(SEEK_SET)
        guard fstat(descriptor, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG,
              fcntl(descriptor, F_GETLK, &query) == 0,
              stat(path, &current) == 0,
              opened.st_dev == current.st_dev, opened.st_ino == current.st_ino else { return .unknown }
        return query.l_type == F_UNLCK ? .idle : .active
    }

    static func status(
        configuration: SyncConfiguration, cached: SyncStatus, expectedRemote: String?
    ) throws -> SyncStatus? {
        let prefix = "\(configuration.statusDirectory)/\(configuration.machineName)"
        guard let first = try read("\(prefix).env") else { return nil }
        guard let text = String(data: first, encoding: .utf8) else { throw LocalRepairError.unreadableStatus }
        let values = text.components(separatedBy: "\n")
            .reduce(into: [String: String]()) { values, line in
                guard let split = line.firstIndex(of: "=") else { return }
                values[String(line[..<split])] = String(line[line.index(after: split)...])
            }
        guard let result = values["result"].flatMap(SyncResult.init(rawValue:)), values["finished_at"] != nil else {
            throw LocalRepairError.unreadableStatus
        }
        if let remote = values["remote_repo"], !remote.isEmpty, !(remote == "none" && expectedRemote == nil) {
            guard let expectedRemote,
                  remote == expectedRemote || sameGitHubRemote(remote, expectedRemote)
            else {
                throw LocalRepairError.unreadableStatus
            }
        }
        func lines(_ suffix: String, preserveSpaces: Bool = false) throws -> [String] {
            let data = try read(prefix + suffix) ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { throw LocalRepairError.unreadableStatus }
            let trim = preserveSpaces ? CharacterSet(charactersIn: "\r") : .whitespacesAndNewlines
            return text.split(separator: "\n").map { String($0).trimmingCharacters(in: trim) }
        }
        func json<T: Decodable>(_ suffix: String) throws -> [T] {
            guard let data = try read(prefix + suffix) else { return [] }
            return try JSONDecoder().decode([T].self, from: data)
        }
        let status = try SyncStatus(
            result: result, startedAt: values["started_at"], finishedAt: values["finished_at"],
            durationSeconds: Int(values["duration_seconds"] ?? ""),
            updatedFileCount: Int(values["updated_file_count"] ?? ""),
            updatedByteCount: Int(values["updated_byte_count"] ?? ""),
            storageFileCount: Int(values["storage_file_count"] ?? ""),
            storageByteCount: Int(values["storage_byte_count"] ?? ""),
            warningCount: Int(values["warning_count"] ?? "") ?? 0,
            errorCount: Int(values["error_count"] ?? "") ?? 0, lastCommit: values["last_commit"],
            remoteRepository: values["remote_repo"],
            warnings: lines(".warnings.log"), errors: lines(".errors.log"), conditions: json(".conditions.json"),
            commandDiagnostics: json(".commands.json"),
            recordedLocalChanges: lines(".local-changes.log", preserveSpaces: true),
            currentLocalChanges: values["finished_at"] == cached.finishedAt ? cached.currentLocalChanges : nil
        )
        guard try read("\(prefix).env") == first else { throw LocalRepairError.unreadableStatus }
        return status
    }

    private static func sameGitHubRemote(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = MacSyncPaths.normalizeGitHubRemoteURL(lhs),
              let right = MacSyncPaths.normalizeGitHubRemoteURL(rhs) else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
