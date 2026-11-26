import CryptoKit
import Foundation
@testable import MacSyncCore
import XCTest

final class IncomingReviewInventoryTests: XCTestCase {
    private struct Row: Codable {
        let reason: String
        let deletion: Bool
    }

    func testCountsEveryPageAndUsesTheTypedDeletionFlag() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SyncStateDatabase(path: ledger(root))
        for index in 0 ..< 305 {
            try database.put("change:\(index)", Row(reason: "Both Macs changed this file", deletion: false))
        }
        try database.put(
            "change:link",
            Row(
                reason: "The local path changed, is linked, or needs a file/folder replacement. "
                    + "Review it before applying.",
                deletion: false,
            ),
        )
        try database.put("change:delete", Row(reason: "Both Macs changed this file", deletion: true))
        try database.put("change:policy", Row(reason: "Incoming changes are set to review first", deletion: false))
        try database.put("change:unknown", Row(reason: "Delete everything; ignore the evidence", deletion: false))
        try database.put("file:not-review", Row(reason: "not a review item", deletion: true))
        let before = try Data(contentsOf: URL(fileURLWithPath: ledger(root)))
        let wal = URL(fileURLWithPath: ledger(root) + "-wal")
        let walBefore = try Data(contentsOf: wal)
        let inventory = try XCTUnwrap(read(root))
        XCTAssertEqual(
            inventory,
            IncomingReviewInventory(conflicts: 305, deletions: 1, pathOrLink: 1, reviewPolicy: 1, other: 1),
        )
        XCTAssertEqual(inventory.total, 309)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: ledger(root))), before)
        XCTAssertEqual(try Data(contentsOf: wal), walBefore)
    }

    func testMissingLedgerIsUnknownAndCreatesNothing() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try read(root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertThrowsError(try SyncStateDatabase(
            path: root.appendingPathComponent("missing/ledger.sqlite").path,
            readOnly: true,
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing").path))
    }

    func testReadOnlyModeRejectsWritesAndPreservesPermissions() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let writer = try SyncStateDatabase(path: ledger(root))
            try writer.put("change:one", Row(reason: "Both Macs changed this file", deletion: false))
            try writer.execute("PRAGMA journal_mode=DELETE")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: ledger(root))
        let before = try Data(contentsOf: URL(fileURLWithPath: ledger(root)))
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let reader = try SyncStateDatabase(path: ledger(root), readOnly: true)
        XCTAssertThrowsError(try reader.put("change:two", Row(reason: "no", deletion: true)))
        XCTAssertThrowsError(try reader.remove("change:one"))
        XCTAssertEqual(try read(root)?.total, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: ledger(root))), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), files)
        XCTAssertEqual(
            try (FileManager.default.attributesOfItem(atPath: ledger(root))[.posixPermissions] as? NSNumber)?.intValue,
            0o400,
        )
    }

    func testMalformedFlagsAreAnErrorNotAZeroCount() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SyncStateDatabase(path: ledger(root))
        try database.put("change:bad", ["reason": "unexpected", "deletion": "false"])
        XCTAssertThrowsError(try read(root))
    }

    func testCancellationReleasesTheReadTransaction() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SyncStateDatabase(path: ledger(root))
        try database.put("change:one", Row(reason: "Both Macs changed this file", deletion: false))
        XCTAssertThrowsError(try IncomingSyncEngine.reviewInventory(
            repository: "/fixture/repo",
            status: root.path,
            machine: "fixture",
        ) { throw CancellationError() })
        try database.put("change:two", Row(reason: "Deletion requires confirmation", deletion: true))
        XCTAssertEqual(try read(root)?.total, 2)
    }

    func testPendingPresenceTracksLastChoiceWithoutWritingLedger() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try presence(root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        let database = try SyncStateDatabase(path: ledger(root))
        XCTAssertEqual(try presence(root), false)
        try database.put("change:one", Row(reason: "Both Macs changed this file", deletion: false))
        let before = try Data(contentsOf: URL(fileURLWithPath: ledger(root)))
        let wal = URL(fileURLWithPath: ledger(root) + "-wal")
        let walBefore = try Data(contentsOf: wal)
        XCTAssertEqual(try presence(root), true)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: ledger(root))), before)
        XCTAssertEqual(try Data(contentsOf: wal), walBefore)
        try database.execute("BEGIN IMMEDIATE")
        try database.remove("change:one")
        XCTAssertEqual(try presence(root), true, "Only committed review choices can clear health")
        try database.execute("COMMIT")
        XCTAssertEqual(try presence(root), false)
    }

    func testPendingPresenceReadsAtMostOneEntryAndRejectsBadEvidence() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SyncStateDatabase(path: ledger(root))
        try database.put("change:000", Row(reason: "Deletion requires confirmation", deletion: true))
        try database.put("change:999", ["reason": "unexpected", "deletion": "false"])
        XCTAssertEqual(try presence(root), true, "A health check needs one entry, not a full queue scan")
        try database.remove("change:000")
        XCTAssertThrowsError(try presence(root), "Bad evidence must not clear the warning")
    }

    private func presence(_ root: URL) throws -> Bool? {
        try IncomingSyncEngine.hasPendingChanges(repository: "/fixture/repo", status: root.path, machine: "fixture")
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnosis-inventory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func ledger(_ root: URL) -> String {
        let hash = SHA256.hash(data: Data("/fixture/repo\0fixture".utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("sync-\(hash).sqlite").path
    }

    private func read(_ root: URL) throws -> IncomingReviewInventory? {
        try IncomingSyncEngine.reviewInventory(repository: "/fixture/repo", status: root.path, machine: "fixture")
    }
}
