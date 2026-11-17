import Foundation
@testable import MacSyncCore
import XCTest

final class FolderSnapshotStoreTests: XCTestCase {
    func testPortableSnapshotContainsOnlyOneMachineAndCanBeVerifiedAndFetched() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("first", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        let folder = fixture.root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FolderSnapshotStore(folder: folder.path, environment: fixture.environment)
        let record = try store.publish(repository: fixture.repository.path, machine: "target")
        XCTAssertEqual(try store.machines(), ["target"])
        XCTAssertEqual(try store.records(machine: "target"), [record])
        XCTAssertEqual(try store.publish(repository: fixture.repository.path, machine: "target"), record)
        try store.verify(record)
        let commit = try store.fetch(record, into: fixture.repository.path)
        let workspace = try SnapshotReadWorkspace(repository: fixture.repository.path, revision: commit, environment: fixture.environment)
        XCTAssertEqual(try String(contentsOf: workspace.root.appendingPathComponent("machines/target/home/.tool"), encoding: .utf8), "first")
        let parents = ProcessRunner(environment: fixture.environment).run("git", ["-C", fixture.repository.path, "rev-list", "--count", commit])
        XCTAssertEqual(parents.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "1")
        let archive = folder.appendingPathComponent("MacSyncSnapshots/target/\(record.id)/snapshot.bundle")
        try Data("corrupt partial cloud download".utf8).write(to: archive)
        XCTAssertThrowsError(try store.fetch(record, into: fixture.repository.path))
    }

    func testCloudModePublishesWithoutTreatingTheFolderAsARemoteGitRepository() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let folder = fixture.root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.write("settings", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"], extra: ["MAC_SYNC_STORAGE_KIND": "cloudFolder", "MAC_SYNC_CLOUD_FOLDER": folder.path]), 0)
        let store = FolderSnapshotStore(folder: folder.path, environment: fixture.environment)
        XCTAssertEqual(try store.records(machine: "target").count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path))
    }

    func testMissingFolderAndRecursiveSelectionsFailWithoutClaimingSuccess() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        XCTAssertThrowsError(try FolderSnapshotStore(folder: fixture.root.appendingPathComponent("missing").path).machines())
        try fixture.write(fixture.root.path + "\n", to: fixture.repository.appendingPathComponent("machines/target/config/sync-paths.txt"))
        XCTAssertEqual(fixture.run(["sync"]), 2)
    }
}
