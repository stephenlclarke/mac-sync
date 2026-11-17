import Foundation
@testable import MacSyncCore
import XCTest

final class MachineFileDeliveryTests: XCTestCase {
    func testRealGitRoundTripPublishesReplacementAndReceivingReceipt() throws {
        let a = try SyncPeer(name: "alpha")
        let b = try SyncPeer(name: "bravo")
        let remote = FileManager.default.temporaryDirectory.appendingPathComponent("delivery-remote-\(UUID().uuidString).git")
        defer { a.remove(); b.remove(); try? FileManager.default.removeItem(at: remote) }
        let runner = ProcessRunner(environment: a.environment)
        XCTAssertEqual(runner.run("git", ["init", "--bare", "--initial-branch=main", remote.path]).status, 0)
        try a.write("base"); try a.sync()
        XCTAssertEqual(runner.run("git", ["-C", a.repository.path, "remote", "add", "origin", remote.path]).status, 0)
        XCTAssertEqual(runner.run("git", ["-C", a.repository.path, "push", "-u", "origin", "main"]).status, 0)
        try FileManager.default.removeItem(at: b.repository)
        XCTAssertEqual(runner.run("git", ["clone", remote.path, b.repository.path]).status, 0)
        try FileManager.default.createDirectory(at: b.snapshot.appendingPathComponent("config"), withIntermediateDirectories: true)
        try Data(".settings\n".utf8).write(to: b.snapshot.appendingPathComponent("config/sync-paths.txt"))
        try b.sync()
        XCTAssertEqual(try b.read(), "base")
        let replacement = b.home.appendingPathComponent("send-this")
        try Data("replacement".utf8).write(to: replacement)
        let sent = MachineFileDeliveryStore(repository: b.repository.path, environment: b.environment)
        XCTAssertEqual(MacSyncApp(arguments: ["mac-sync", "deliver", "--to", a.name, "--path", ".settings/file", "--file", replacement.path], environment: b.environment).run(), 0)
        let record = try XCTUnwrap(sent.deliveries(target: a.name).first)
        try a.sync(); try b.sync()
        XCTAssertEqual(try a.read(), "replacement")
        XCTAssertEqual(sent.receipt(record)?.state, "applied")
        XCTAssertEqual(MacSyncApp(arguments: ["mac-sync", "deliveries", "list"], environment: a.environment).run(), 0)
        XCTAssertEqual(MacSyncApp(arguments: ["mac-sync", "deliveries", "resolve", record.id, "--keep-local"], environment: a.environment).run(), 0)
    }

    func testReplacementAppliesAtNextSyncAndDoesNotOverwriteLaterEdits() throws {
        let sender = try SyncPeer(name: "sender")
        let receiver = try SyncPeer(name: "receiver")
        defer { sender.remove(); receiver.remove() }
        try receiver.write("original"); try receiver.sync()
        try sender.importPeer(receiver)
        let store = MachineFileDeliveryStore(repository: sender.repository.path, environment: sender.environment)
        let source = sender.home.appendingPathComponent("replacement")
        try Data("replacement".utf8).write(to: source)
        let delivery = try store.send(file: source.path, sender: sender.name, target: receiver.name, path: ".settings/file")
        XCTAssertEqual(try receiver.read(), "original")
        let receiving = MachineFileDeliveryStore(repository: receiver.repository.path, environment: receiver.environment)
        try receiving.importDeliveries(from: sender.repository.path, sender: sender.name)
        try receiver.sync()
        XCTAssertEqual(try receiver.read(), "replacement")
        XCTAssertEqual(receiving.receipt(delivery)?.state, "applied")
        try receiver.write("later local edit"); try receiver.sync()
        XCTAssertEqual(try receiver.read(), "later local edit")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "replacement")
    }

    func testConflictingReplacementWaitsForExplicitDecision() throws {
        let sender = try SyncPeer(name: "sender")
        let receiver = try SyncPeer(name: "receiver")
        defer { sender.remove(); receiver.remove() }
        try receiver.write("original"); try receiver.sync(); try sender.importPeer(receiver)
        let source = sender.home.appendingPathComponent("replacement")
        try Data("incoming".utf8).write(to: source)
        let sent = MachineFileDeliveryStore(repository: sender.repository.path, environment: sender.environment)
        let delivery = try sent.send(file: source.path, sender: sender.name, target: receiver.name, path: ".settings/file")
        try receiver.write("local edit")
        let received = MachineFileDeliveryStore(repository: receiver.repository.path, environment: receiver.environment)
        try received.importDeliveries(from: sender.repository.path, sender: sender.name)
        try receiver.sync()
        XCTAssertEqual(try receiver.read(), "local edit")
        XCTAssertEqual(received.receipt(delivery)?.state, "needsReview")
        try received.apply(delivery, home: receiver.home.path, status: receiver.status.path, force: true)
        XCTAssertEqual(try receiver.read(), "incoming")
        let recovery = BackupRecoveryService(repository: receiver.repository.path, statusDirectory: receiver.status.path, home: receiver.home.path, environment: receiver.environment)
        XCTAssertFalse(recovery.undoRecords().isEmpty)
        XCTAssertThrowsError(try sent.send(file: source.path, sender: sender.name, target: receiver.name, path: "../escape"))
    }

    func testCloudFolderCarriesTargetedReplacementAndReceipt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sender = try SyncPeer(name: "sender", cloudFolder: folder)
        let receiver = try SyncPeer(name: "receiver", cloudFolder: folder)
        defer { sender.remove(); receiver.remove() }
        try receiver.write("base"); try receiver.sync()
        try sender.sync()
        let source = sender.home.appendingPathComponent("replacement")
        try Data("sent via cloud folder".utf8).write(to: source)
        let sent = MachineFileDeliveryStore(repository: sender.repository.path, environment: sender.environment)
        let delivery = try sent.send(file: source.path, sender: sender.name, target: receiver.name, path: ".settings/file")
        try sender.sync(); try receiver.sync()
        XCTAssertEqual(try receiver.read(), "sent via cloud folder")
        try sender.sync()
        XCTAssertEqual(sent.receipt(delivery)?.state, "applied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sender.repository.appendingPathComponent("machines/receiver/inbox/sender/\(delivery.id)/file").path))
    }
}
