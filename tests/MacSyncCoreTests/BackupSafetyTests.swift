import Foundation
@testable import MacSyncCore
import XCTest

final class BackupSafetyTests: XCTestCase {
    func testNewStorageChildrenResolveConsistentlyAcrossTmpAliases() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("mac-sync-canonical-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("new/nested/file").path
        XCTAssertTrue(BackupDestinationSettings.isInside(missing, directory: root.path))
        XCTAssertEqual(MacSyncPaths.canonicalPath(missing), MacSyncPaths.canonicalPath(missing.replacingOccurrences(of: "/private/tmp/", with: "/tmp/")))
        XCTAssertFalse(BackupDestinationSettings.isInside(root.path + "-other/file", directory: root.path))
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/private/tmp")
        XCTAssertFalse(BackupDestinationSettings.isInside(link.appendingPathComponent("outside-file").path, directory: root.path))
        XCTAssertNil(MacSyncPaths.canonicalPath("invalid\0path"))
    }

    func testRapidSameSizeEditsAreCapturedDespiteMatchingModificationTime() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("first", to: fixture.source)
        let stamp = Date(timeIntervalSince1970: 100_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: fixture.source.path)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        try fixture.write("other", to: fixture.source)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: fixture.source.path)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.snapshot, encoding: .utf8), "other")
    }

    func testUnrelatedStagedChangesAreNotCommittedAndSelectedIgnoredFilesAreIncluded() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("user work", to: fixture.repository.appendingPathComponent("unrelated"))
        try fixture.write("home/\n", to: fixture.repository.appendingPathComponent(".gitignore"))
        let runner = ProcessRunner(environment: fixture.environment)
        XCTAssertEqual(runner.run("git", ["-C", fixture.repository.path, "add", "unrelated"]).status, 0)
        try fixture.write("selected", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        XCTAssertEqual(runner.run("git", ["-C", fixture.repository.path, "show", "HEAD:machines/target/home/.tool"]).stdout, "selected")
        XCTAssertNotEqual(runner.run("git", ["-C", fixture.repository.path, "cat-file", "-e", "HEAD:unrelated"]).status, 0)
        XCTAssertTrue(runner.run("git", ["-C", fixture.repository.path, "diff", "--cached", "--name-only"]).stdout.contains("unrelated"))
    }

    func testDirectoryCanBecomeFileAndBackWithoutNestedOrStaleCopies() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("before", to: fixture.source.appendingPathComponent("old"))
        XCTAssertEqual(fixture.run(["sync"]), 0)
        try FileManager.default.removeItem(at: fixture.source)
        try fixture.write("file", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.snapshot, encoding: .utf8), "file")
        try FileManager.default.removeItem(at: fixture.source)
        try fixture.write("directory", to: fixture.source.appendingPathComponent("new"))
        XCTAssertEqual(fixture.run(["sync"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.snapshot.appendingPathComponent("new"), encoding: .utf8), "directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.snapshot.appendingPathComponent("old").path))
    }

    func testFailedTypeReplacementPreservesOldSnapshot() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("old backup", to: fixture.snapshot.appendingPathComponent("old"))
        try fixture.write("new file", to: fixture.source)
        let bin = fixture.root.appendingPathComponent("bin")
        let rsync = bin.appendingPathComponent("rsync")
        try fixture.write("#!/bin/sh\nexit 23\n", to: rsync)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rsync.path)
        XCTAssertEqual(fixture.run(["sync"], extra: ["PATH": "\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin"]), 23)
        XCTAssertEqual(try String(contentsOf: fixture.snapshot.appendingPathComponent("old"), encoding: .utf8), "old backup")
    }

    func testPreviewPreservesStatusCheckpointAndSnapshot() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("source", to: fixture.source)
        let status = fixture.status.appendingPathComponent("target.env")
        try fixture.write("last successful backup", to: status)
        let checkpoint = fixture.status.appendingPathComponent("target.background.json")
        var state = BackgroundCheckpoint.load(from: checkpoint.path, repository: fixture.repository.path)
        state.failed(authentication: false)
        state.lastInventory = Date(timeIntervalSince1970: 100)
        try state.save(to: checkpoint.path)
        let before = try Data(contentsOf: checkpoint)
        XCTAssertEqual(fixture.run(["sync"], extra: ["MAC_SYNC_DRY_RUN": "1"]), 0)
        XCTAssertEqual(try Data(contentsOf: checkpoint), before)
        XCTAssertEqual(try String(contentsOf: status, encoding: .utf8), "last successful backup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.snapshot.path))
    }

    func testRestoreDoesNotWriteWhileOperationLockIsHeld() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("snapshot", to: fixture.snapshot)
        let lock = try XCTUnwrap(MacSyncProcessLock.acquire(at: fixture.temporary.appendingPathComponent("mac-sync-target.lock/pid")))
        defer { lock.release() }
        XCTAssertEqual(fixture.run(["restore", "--from", "target", "--path", ".tool"]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    }
}

/// Every command and all writes are confined to a generated temporary HOME.
struct BackupFixture {
    let root: URL
    var home: URL {
        root.appendingPathComponent("home")
    }

    var repository: URL {
        root.appendingPathComponent("data")
    }

    var status: URL {
        root.appendingPathComponent("status")
    }

    var temporary: URL {
        root.appendingPathComponent("tmp")
    }

    var source: URL {
        home.appendingPathComponent(".tool")
    }

    var snapshot: URL {
        repository.appendingPathComponent("machines/target/home/.tool")
    }

    var environment: [String: String] {
        ["HOME": home.path, "TMPDIR": temporary.path, "USER": "review", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
         "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0", "MAC_SYNC_MACHINE": "target",
         "MAC_SYNC_MACHINES_REPO": repository.path, "MAC_SYNC_STATUS_DIR": status.path,
         "MAC_SYNC_DYNAMIC_REFS": "0", "MAC_SYNC_HOMEBREW": "0", "MAC_SYNC_VSCODE_EXTENSIONS": "0",
         "MAC_SYNC_GITHUB_REPOS": "0", "MAC_SYNC_SECRETS": "0", "MAC_SYNC_QUIET": "1"]
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for directory in [home, repository, status, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let runner = ProcessRunner(environment: environment)
        for args in [["init", "-b", "main"], ["config", "user.name", "Synthetic test"], ["config", "user.email", "test@example.invalid"]] {
            let result = runner.run("git", ["-C", repository.path] + args)
            guard result.status == 0 else { throw NSError(domain: "BackupFixture", code: Int(result.status)) }
        }
        try write(".tool\n", to: repository.appendingPathComponent("machines/target/config/sync-paths.txt"))
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func run(_ args: [String], extra: [String: String] = [:]) -> Int {
        MacSyncApp(arguments: ["mac-sync"] + args, environment: environment.merging(extra) { _, value in value }).run()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
