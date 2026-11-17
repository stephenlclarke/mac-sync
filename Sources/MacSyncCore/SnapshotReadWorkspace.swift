import Foundation

/// Materialise an immutable Git revision without switching the user's branch,
/// index or working files. All cleanup targets are generated scratch paths.
public final class SnapshotReadWorkspace {
    public let root: URL
    private let repository: String
    private let runner: ProcessRunner

    public init(repository: String, revision: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard revision.range(of: #"^[0-9a-f]{40,64}$"#, options: .regularExpression) != nil else { throw BackupStorageError.invalidSnapshot }
        self.repository = repository
        runner = ProcessRunner(environment: environment)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-sync-revision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = runner.run("git", ["-C", repository, "worktree", "add", "--detach", root.path, revision])
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: root)
            throw BackupStorageError.unavailable("The selected backup version could not be read. Current files were not changed.")
        }
    }

    deinit {
        _ = runner.run("git", ["-C", repository, "worktree", "remove", "--force", root.path])
        if FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
