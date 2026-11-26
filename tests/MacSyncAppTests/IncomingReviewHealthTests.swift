import AppKit
import Foundation
@testable import MacSyncApp
@testable import MacSyncCore
import XCTest

final class IncomingReviewHealthTests: XCTestCase {
    @MainActor
    func testStoreRecoversAfterLastDecisionWithoutSyncAndRetainsRecordedWarning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let status = root.appendingPathComponent("status")
        let repository = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: status, withIntermediateDirectories: true)
        let warning = "WARN: " + IncomingSyncEngine.reviewRequiredMessage
        let statusFile = status.appendingPathComponent("fixture.env")
        let statusBytes = Data("result=success\nfinished_at=recorded-run\nwarning_count=1\n".utf8)
        try statusBytes.write(to: statusFile)
        let warningsFile = status.appendingPathComponent("fixture.warnings.log")
        let warningBytes = Data((warning + "\n").utf8)
        try warningBytes.write(to: warningsFile)
        let ledger = URL(fileURLWithPath: IncomingSyncEngine.reviewLedgerPath(
            repository: repository.path, status: status.path, machine: "fixture"
        ))
        var writer: SyncStateDatabase? = try SyncStateDatabase(path: ledger.path)
        try writer?.put("change:one", ReviewFixture())
        let store = makeStore(home: root, status: status, repository: repository)
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 1 }
        XCTAssertEqual(store.incomingChanges.count, 1)
        XCTAssertEqual(store.healthActivity(for: warning), .active)

        // Keep the writer open: the observer must see the committed WAL write,
        // not depend on journal removal, process exit, window activation or sync.
        try writer?.remove("change:one")
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 0 }
        XCTAssertTrue(store.incomingChanges.isEmpty)
        XCTAssertEqual(store.healthActivity(for: warning), .recovered)
        let recovered = try XCTUnwrap(store.syncIssues.first { $0.message == warning })
        XCTAssertEqual(store.healthActivity(for: recovered), .recovered)
        XCTAssertEqual(recovered.disposition, .open)
        XCTAssertEqual(store.overview.status.warnings, [warning])
        XCTAssertEqual(try Data(contentsOf: statusFile), statusBytes)
        XCTAssertEqual(try Data(contentsOf: warningsFile), warningBytes)
        XCTAssertNil(store.activeAction)
        XCTAssertNil(NSApplication.shared.dockTile.badgeLabel)

        try writer?.put("change:one", ReviewFixture())
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 1 }
        XCTAssertEqual(store.healthActivity(for: warning), .active)
        try writer?.remove("change:one")
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 0 }
        writer = nil

        writer = try SyncStateDatabase(path: ledger.path)
        try writer?.put("change:one", ReviewFixture())
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 1 }
        try writer?.remove("change:one")
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 0 }
        writer = nil

        try await verifyErrorIsActive(store: store, status: status, message: warning)
        // A disappearing ledger must invalidate the earlier healthy reading.
        try FileManager.default.removeItem(at: ledger)
        store.reload()
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 1 }
        XCTAssertEqual(store.healthActivity(for: warning), .active)
    }

    func testJournalObservationRejectsASubstitutedSymbolicLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("database")
        let bytes = Data("do not open this as a journal".utf8)
        try bytes.write(to: target)
        let journal = root.appendingPathComponent("database-wal")
        try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: target)
        XCTAssertNil(LocalStateObservation(directory: journal.path, noFollow: true) {
            XCTFail("A substituted journal must not be observed")
        })
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    @MainActor
    private func verifyErrorIsActive(store: SyncStore, status: URL, message: String) async throws {
        let errorFile = status.appendingPathComponent("fixture.errors.log")
        try Data((message + "\n").utf8).write(to: errorFile)
        store.reload()
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 1 }
        XCTAssertNotEqual(store.healthActivity(for: message), .recovered)
        XCTAssertEqual(store.syncIssues.first { $0.severity == .error }?.isActive, true)
        try FileManager.default.removeItem(at: errorFile)
        store.reload()
        try await waitUntil { !store.isRefreshing && store.openIssueCount == 0 }
    }

    @MainActor
    private func makeStore(home: URL, status: URL, repository: URL) -> SyncStore {
        SyncStore(environment: [
            "HOME": home.path, "MAC_SYNC_MACHINE": "fixture", "MAC_SYNC_STATUS_DIR": status.path,
            "TMPDIR": home.path, "MAC_SYNC_MACHINES_REPO": repository.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ])
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The local health refresh did not complete")
    }
}

private struct ReviewFixture: Encodable {
    let id = "one"
    let machine = "peer"
    let revision = "fixture"
    let path = "example.txt"
    let reason = "Both Macs changed this file"
    let deletion = false
    let encodedVersion = Data("{}".utf8)
}
