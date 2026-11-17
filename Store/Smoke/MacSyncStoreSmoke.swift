import AppKit
import Foundation
import MacSyncCore

/// Test-only application. Never reads installed Mac Sync settings or user files.
@main
enum MacSyncStoreSmoke {
    @MainActor
    static func main() {
        guard Bundle.main.bundleIdentifier == "io.quux.mac-sync.smoke" else { Foundation.exit(2) }
        if CommandLine.arguments.contains("--grant-folder") {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            DispatchQueue.main.async { runTest() }
            app.run()
        } else {
            runTest()
        }
    }

    @MainActor
    private static func runTest() {
        do {
            try exercise()
            print("STORE_SANDBOX_SMOKE_PASSED")
            Foundation.exit(0)
        } catch {
            fputs("Store smoke failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func exercise() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/mac-sync-smoke/\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        var source = root.appendingPathComponent("source")
        let persistentGrant = root.deletingLastPathComponent().appendingPathComponent("relaunch-test-grant.json")
        let restoring = CommandLine.arguments.contains("--restore-grant")
        let grantFile = restoring ? persistentGrant : root.appendingPathComponent("grants.json")
        let grants = try MacSyncFileAccess(file: grantFile)
        if let flag = CommandLine.arguments.firstIndex(where: { ["--grant-folder", "--restore-grant"].contains($0) }) {
            guard flag + 1 < CommandLine.arguments.count,
                  CommandLine.arguments[flag + 1].hasPrefix("/")
            else {
                throw BackupStorageError.unavailable("Pass --grant-folder /absolute/path/to/the-approved-empty-test-folder.")
            }
            let approvedPath = CommandLine.arguments[flag + 1]
            guard approvedPath.range(of: #"^/private/tmp/mac-sync-store-access\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
                throw BackupStorageError.unavailable("Use an empty, explicitly approved mac-sync-store-access temporary folder.")
            }
            let approved = URL(fileURLWithPath: approvedPath).standardizedFileURL.resolvingSymlinksInPath()
            if restoring {
                guard grants.records.count == 1, grants.records.first?.path == approved.path else {
                    throw BackupStorageError.unavailable("The saved test grant does not match the approved folder.")
                }
                grants.restore()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.directoryURL = approved
                panel.message = "Choose the approved empty test folder. The test writes a uniquely named fixture, then removes it. It never reads existing files."
                guard panel.runModal() == .OK, let folder = panel.url else { throw BackupStorageError.unavailable("Test access cancelled.") }
                guard folder.standardizedFileURL.resolvingSymlinksInPath() == approved else {
                    throw BackupStorageError.unavailable("The chosen folder is not the approved test folder. No test files were written there.")
                }
                try grants.remember(folder)
                grants.stop()
                grants.restore()
            }
            guard grants.covers(approved.path) else { throw BackupStorageError.unavailable("Persistent grant did not restore.") }
            guard try fm.contentsOfDirectory(atPath: approved.path).isEmpty else {
                throw BackupStorageError.unavailable("The approved test folder is not empty. No test files were written there.")
            }
            source = approved.appendingPathComponent("mac-sync-smoke-\(UUID().uuidString)")
            if !restoring {
                try Data(contentsOf: grantFile).write(to: persistentGrant, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistentGrant.path)
            }
            print("EXTERNAL_FOLDER_APPROVED=\(approved.path)")
        }
        defer { try? fm.removeItem(at: source); grants.stop() }
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let workspace = root.appendingPathComponent("workspace")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        let item = source.appendingPathComponent("example.txt")
        try Data("first fixture\n".utf8).write(to: item)
        var env = MacSyncStoreRuntime.environment([:], bundle: Bundle.main.bundleURL, containerHome: NSHomeDirectory(), sourceHome: source.path)
        env["MAC_SYNC_MACHINES_REPO"] = workspace.path
        env["MAC_SYNC_STATUS_DIR"] = root.appendingPathComponent("status").path
        env["MAC_SYNC_PRIVATE_SUPPORT"] = root.path
        env["MAC_SYNC_MACHINE"] = "sandbox-fixture"
        env["MAC_SYNC_SECRETS"] = "0"
        env["MAC_SYNC_HOMEBREW"] = "0"
        env["MAC_SYNC_QUIET"] = "1"
        try fm.createDirectory(atPath: env["TMPDIR"]!, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let manifest = root.appendingPathComponent("lease.json")
        try JSONEncoder().encode([MacSyncAccessRoot(path: source.path, isDirectory: true)]).write(to: manifest)
        env["MAC_SYNC_ACCESS_MANIFEST"] = manifest.path
        let runner = ProcessRunner(environment: env)
        func require(_ program: String, _ arguments: [String], input: Data? = nil) throws -> String {
            let result = runner.run(program, arguments, workingDirectory: workspace.path, timeout: 90, input: input)
            guard result.status == 0 else { throw BackupStorageError.unavailable("\(program) failed (\(result.status)): \(result.combinedOutput)") }
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try require("git", ["init", "-b", "main"])
        _ = try require("git", ["config", "user.name", "Sandbox Fixture"])
        _ = try require("git", ["config", "user.email", "fixture@localhost"])
        let config = workspace.appendingPathComponent("machines/sandbox-fixture/config")
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        try Data("example.txt\n".utf8).write(to: config.appendingPathComponent("sync-paths.txt"))
        _ = try require(env["MAC_SYNC_EXECUTABLE"]!, ["sync"])
        let stored = workspace.appendingPathComponent("machines/sandbox-fixture/home/example.txt")
        guard try Data(contentsOf: stored) == Data(contentsOf: item) else { throw BackupStorageError.invalidSnapshot }
        try Data("second fixture\n".utf8).write(to: item)
        _ = try require(env["MAC_SYNC_EXECUTABLE"]!, ["sync"])
        guard try Data(contentsOf: stored) == Data(contentsOf: item) else { throw BackupStorageError.invalidSnapshot }
        let identity = root.appendingPathComponent("test-identity.txt")
        _ = try require("age-keygen", ["-o", identity.path])
        let recipient = try require("age-keygen", ["-y", identity.path])
        let encrypted = root.appendingPathComponent("test.age")
        _ = try require("age", ["-r", recipient, "-o", encrypted.path], input: Data("encryption fixture".utf8))
        guard try require("age", ["-d", "-i", identity.path, encrypted.path]) == "encryption fixture" else { throw BackupStorageError.invalidSnapshot }
        let archive = root.appendingPathComponent("test.tar")
        _ = try require("gtar", ["-cf", archive.path, "-C", source.path, "example.txt"])
        guard try require("gtar", ["-tf", archive.path]) == "example.txt" else { throw BackupStorageError.invalidSnapshot }
        // Denied metadata must not make a selected source look deleted.
        let before = try Data(contentsOf: stored)
        try JSONEncoder().encode([MacSyncAccessRoot]()).write(to: manifest)
        let denied = runner.run(env["MAC_SYNC_EXECUTABLE"]!, ["sync"], timeout: 90)
        guard denied.status != 0, try Data(contentsOf: stored) == before else { throw BackupStorageError.invalidSnapshot }
        try fm.removeItem(at: source)
        if CommandLine.arguments.contains("--grant-folder") || restoring {
            guard try fm.contentsOfDirectory(at: source.deletingLastPathComponent(), includingPropertiesForKeys: nil).isEmpty else {
                throw BackupStorageError.unavailable("The approved test folder was not left empty.")
            }
        }
        if CommandLine.arguments.contains("--grant-folder") || restoring {
            print("EXTERNAL_FOLDER_SYNC_UPDATE_ENCRYPTION_ARCHIVE_AND_DENIED_ACCESS_PASSED")
        }
        if restoring {
            try fm.removeItem(at: persistentGrant)
            print("BOOKMARK_RELAUNCH_PASSED_AND_SAVED_TEST_GRANT_REMOVED")
        }
    }
}
