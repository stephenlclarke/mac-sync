import Foundation
@testable import MacSyncCore
import XCTest

final class IncomingSyncTests: XCTestCase {
    func testExcludingAFileDoesNotAskOtherMacsToDeleteIt() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        defer { a.remove(); b.remove() }
        try a.write("keep this"); try a.sync(); try b.importPeer(a); try b.sync()
        try Data("file\n".utf8).write(to: a.snapshot.appendingPathComponent("config/excludes.txt"))
        try a.sync(); try b.importPeer(a); try b.sync()
        XCTAssertEqual(try b.read(), "keep this")
        XCTAssertTrue(try b.engine().changes().isEmpty)
        XCTAssertEqual(try a.read(), "keep this")
        try b.write("remote update"); try b.sync(); try a.importPeer(b); try a.sync()
        XCTAssertEqual(try a.read(), "keep this")
        try FileManager.default.removeItem(at: a.file)
        try a.sync(); try b.importPeer(a); try b.sync()
        XCTAssertEqual(try b.read(), "remote update")
        XCTAssertTrue(try b.engine().changes().isEmpty)
        let index = try String(contentsOf: a.snapshot.appendingPathComponent("sync-index.ndjson"), encoding: .utf8)
        XCTAssertFalse(index.contains(".settings/file"))
    }

    func testFailedPeerReadPreservesExistingConflictReview() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        let c = try SyncPeer(name: "charlie")
        defer { a.remove(); b.remove(); c.remove() }
        try a.write("base"); try a.sync(); try b.importPeer(a); try b.sync()
        try a.write("local"); try a.sync(); try b.write("other"); try b.sync(); try a.importPeer(b); try a.sync()
        let before = try XCTUnwrap(a.engine().changes().first)
        try c.write("third"); try c.sync(); try a.importPeer(c)
        try Data("broken\n".utf8).write(to: a.repository.appendingPathComponent("machines/charlie/sync-index.ndjson"))
        XCTAssertNotEqual(a.run(), 0)
        XCTAssertEqual(try a.engine().changes().first?.id, before.id)
        XCTAssertEqual(try a.read(), "local")
    }

    func testTwoMacsApplySafeEditsAndDoNotRevertFromStalePeer() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        defer { a.remove(); b.remove() }
        try a.write("first")
        try a.sync()
        try b.importPeer(a)
        try b.sync()
        XCTAssertEqual(try b.read(), "first")
        try b.write("second")
        try b.sync()
        try a.importPeer(b)
        try a.sync()
        XCTAssertEqual(try a.read(), "second")
        // B still holds A's old first version. It must not win by being read
        // later, or because its snapshot has a newer filesystem timestamp.
        try b.sync()
        XCTAssertEqual(try b.read(), "second")
        let index = a.snapshot.appendingPathComponent("sync-index.ndjson")
        let unchanged = try Data(contentsOf: index)
        try a.sync()
        XCTAssertEqual(try Data(contentsOf: index), unchanged)
    }

    func testConcurrentEditsRequireReviewAndKeepLocalResolvesCausally() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        defer { a.remove(); b.remove() }
        try a.write("base"); try a.sync(); try b.importPeer(a); try b.sync()
        try a.write("alpha edit"); try a.sync()
        try b.write("bravo edit"); try b.sync()
        try a.importPeer(b); try a.sync()
        XCTAssertEqual(try a.read(), "alpha edit")
        let changes = try a.engine().changes()
        XCTAssertEqual(changes.count, 1)
        let change = try XCTUnwrap(changes.first)
        XCTAssertTrue(change.reason.contains("Both Macs"))
        try a.engine().resolve(id: change.id, keepLocal: true, selection: [".settings"])
        try a.sync(); try b.importPeer(a); try b.sync()
        XCTAssertEqual(try b.read(), "alpha edit")
        XCTAssertTrue(try b.engine().changes().isEmpty)
    }

    func testDeletionsAreNeverAutomaticallyApplied() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        defer { a.remove(); b.remove() }
        try a.write("base"); try a.sync(); try b.importPeer(a); try b.sync()
        try FileManager.default.removeItem(at: a.file)
        try a.sync(); try b.importPeer(a); try b.sync()
        XCTAssertEqual(try b.read(), "base")
        let change = try XCTUnwrap(b.engine().changes().first)
        XCTAssertTrue(change.deletion)
        try b.engine().resolve(id: change.id, keepLocal: false, selection: [".settings"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.file.path))
        XCTAssertFalse(BackupRecoveryService(repository: b.repository.path, statusDirectory: b.status.path, home: b.home.path, environment: b.environment).undoRecords().isEmpty)
    }

    func testReviewPolicyAndKeepBothPreserveBothCopies() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        defer { a.remove(); b.remove() }
        var preferences = BackupPreferences()
        preferences.incomingPolicy = .review
        try preferences.save(directory: b.status.path, machine: "bravo")
        try a.write("remote"); try a.sync(); try b.importPeer(a); try b.sync()
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.file.path))
        let change = try XCTUnwrap(b.engine().changes().first)
        XCTAssertThrowsError(try b.engine().resolve(id: change.id, keepLocal: false, selection: []))
        try b.engine().resolve(id: change.id, keepLocal: false, keepBoth: true, selection: [".settings"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.file.path))
        let copies = try FileManager.default.contentsOfDirectory(atPath: b.file.deletingLastPathComponent().path)
        let copy = try XCTUnwrap(copies.first(where: { $0.hasPrefix("file.from-alpha-") }))
        XCTAssertEqual(try String(contentsOf: b.file.deletingLastPathComponent().appendingPathComponent(copy), encoding: .utf8), "remote")
    }

    func testSnapshotNameCollisionAndMalformedMetadataFailClosed() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "alpha")
        defer { a.remove(); b.remove() }
        try a.write("other Mac"); try a.sync()
        try b.importPeer(a)
        try b.write("keep local")
        XCTAssertNotEqual(b.run(), 0)
        XCTAssertEqual(try b.read(), "keep local")
        let c = try SyncPeer(name: "charlie")
        defer { c.remove() }
        try c.importPeer(a)
        try Data("bad metadata\n".utf8).write(to: c.repository.appendingPathComponent("machines/alpha/sync-index.ndjson"))
        XCTAssertNotEqual(c.run(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.file.path))
    }
}

final class SyncPathExclusionsTests: XCTestCase {
    func testCommonRsyncExclusionsAndAdvancedFiltersFailClosed() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent("exclude-patterns")
        try fixture.write("# comment\n*.pem\n.git/\n*/History/\nconfig/private.key\n", to: file)
        let rules = try SyncPathExclusions(file: file.path)
        XCTAssertFalse(rules.requiresManualCopy)
        for path in [".settings/key.pem", ".settings/.git/config", ".settings/editor/History/item", ".settings/config/private.key"] {
            XCTAssertTrue(rules.excludes(path, selection: [".settings"]))
        }
        XCTAssertFalse(rules.excludes(".settings/normal.txt", selection: [".settings"]))
        XCTAssertFalse(rules.excludes(".settings/History", selection: [".settings"]))
        try fixture.write("+ keep\n*\n", to: file)
        XCTAssertTrue(try SyncPathExclusions(file: file.path).excludes(".settings/normal.txt", selection: [".settings"]))
    }
}

struct SyncPeer {
    let root: URL
    let name: String
    let cloudFolder: URL?
    var home: URL {
        root.appendingPathComponent("home")
    }

    var repository: URL {
        root.appendingPathComponent("data")
    }

    var status: URL {
        root.appendingPathComponent("status")
    }

    var file: URL {
        home.appendingPathComponent(".settings/file")
    }

    var snapshot: URL {
        repository.appendingPathComponent("machines/\(name)")
    }

    var environment: [String: String] {
        var values = ["HOME": home.path, "TMPDIR": root.appendingPathComponent("tmp").path, "USER": "test", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                      "GIT_CONFIG_NOSYSTEM": "1", "MAC_SYNC_MACHINE": name, "MAC_SYNC_MACHINES_REPO": repository.path, "MAC_SYNC_STATUS_DIR": status.path,
                      "MAC_SYNC_DYNAMIC_REFS": "0", "MAC_SYNC_HOMEBREW": "0", "MAC_SYNC_VSCODE_EXTENSIONS": "0", "MAC_SYNC_GITHUB_REPOS": "0", "MAC_SYNC_SECRETS": "0", "MAC_SYNC_QUIET": "1"]
        if let cloudFolder {
            values["MAC_SYNC_STORAGE_KIND"] = "cloudFolder"; values["MAC_SYNC_CLOUD_FOLDER"] = cloudFolder.path
        }
        return values
    }

    init(name: String, cloudFolder: URL? = nil) throws {
        self.name = name
        self.cloudFolder = cloudFolder
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-peer-\(UUID().uuidString)")
        for directory in [home, repository, status, root.appendingPathComponent("tmp"), snapshot.appendingPathComponent("config")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for args in [["init", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"]] {
            let result = ProcessRunner(environment: environment).run("git", ["-C", repository.path] + args)
            XCTAssertEqual(result.status, 0)
        }
        try Data(".settings\n".utf8).write(to: snapshot.appendingPathComponent("config/sync-paths.txt"))
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func read() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    func run() -> Int {
        MacSyncApp(arguments: ["mac-sync", "sync"], environment: environment).run()
    }

    func sync() throws {
        XCTAssertEqual(run(), 0)
    }

    func engine() throws -> IncomingSyncEngine {
        try IncomingSyncEngine(repository: repository.path, status: status.path, home: home.path, machine: name, environment: environment)
    }

    func importPeer(_ peer: Self) throws {
        let target = repository.appendingPathComponent("machines/\(peer.name)")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: peer.snapshot, to: target)
        // Local generated commits stand in for the transport, so conflicts
        // refer to immutable source bytes just as they do after a Git fetch.
        let runner = ProcessRunner(environment: environment)
        _ = runner.run("git", ["-C", repository.path, "add", "--all"])
        _ = runner.run("git", ["-C", repository.path, "commit", "-m", "test: import peer"])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
