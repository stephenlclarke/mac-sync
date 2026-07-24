import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncIssueRepositoryTests: XCTestCase {
    private let fileManager = FileManager.default

    func testAcknowledgementPersistsLocallyWithoutChangingSyncHistory() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }

        let history = [
            SyncHistoryRecord(
                id: "failed-sync",
                action: .sync,
                sourceMachine: nil,
                result: .failed,
                timing: SyncHistoryTiming(
                    startedAt: "2026-07-23 10:00:00 BST",
                    finishedAt: "2026-07-23 10:00:02 BST",
                    durationSeconds: 2
                ),
                entries: [],
                diagnostics: SyncHistoryDiagnostics(
                    warningCount: 1,
                    errorCount: 1,
                    warnings: ["WARN: remote needs attention"],
                    errors: ["ERROR: git push failed"]
                )
            ),
        ]
        let overview = makeOverview(fixture: fixture, history: history)
        let repository = SyncIssueRepository(configuration: overview.configuration)

        let initialIssues = repository.issues(for: overview)
        XCTAssertEqual(initialIssues.count, 2)
        let error = try XCTUnwrap(initialIssues.first { $0.severity == .error })

        try repository.update(
            issueID: error.id,
            disposition: .acknowledged,
            note: "Will repair remote access after the maintenance window."
        )

        let reloadedIssues = repository.issues(for: overview)
        let reloadedError = try XCTUnwrap(reloadedIssues.first { $0.id == error.id })
        XCTAssertEqual(reloadedError.disposition, .acknowledged)
        XCTAssertEqual(reloadedError.note, "Will repair remote access after the maintenance window.")
        XCTAssertEqual(history.first?.errors, ["ERROR: git push failed"])
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.status.appendingPathComponent("issues/local.json").path))
    }

    func testResolvedCurrentMachineWarningDoesNotCreateManualTriageItem() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }

        let localChangesWarning = "WARN: current machine snapshot has local changes; skipping pre-operation git pull"
        let history = [
            SyncHistoryRecord(
                id: "old-warning",
                action: .sync,
                sourceMachine: nil,
                result: .success,
                timing: SyncHistoryTiming(
                    startedAt: "2026-07-23 09:00:00 BST",
                    finishedAt: "2026-07-23 09:00:03 BST",
                    durationSeconds: 3
                ),
                entries: [],
                diagnostics: SyncHistoryDiagnostics(
                    warningCount: 1,
                    errorCount: 0,
                    warnings: [localChangesWarning],
                    errors: []
                )
            ),
        ]
        let overview = makeOverview(
            fixture: fixture,
            status: makeStatus(
                warnings: [localChangesWarning],
                finishedAt: "2026-07-23 09:00:03 BST",
                currentLocalChanges: []
            ),
            history: history
        )

        XCTAssertTrue(SyncIssueRepository(configuration: overview.configuration).issues(for: overview).isEmpty)
    }

    private func makeOverview(
        fixture: Fixture,
        status: SyncStatus? = nil,
        history: [SyncHistoryRecord]
    ) -> SyncOverview {
        SyncOverview(
            configuration: SyncConfiguration(
                homeDirectory: fixture.home.path,
                dataRepository: fixture.data.path,
                statusDirectory: fixture.status.path,
                machineName: "local",
                pathsFile: fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt").path
            ),
            status: status ?? makeStatus(),
            history: history,
            currentMachine: nil,
            peerMachines: [],
            localSyncProcessID: nil,
            isLocalSyncActive: false
        )
    }

    private func makeStatus(
        result: SyncResult = .success,
        warnings: [String] = [],
        errors: [String] = [],
        finishedAt: String? = nil,
        currentLocalChanges: [String]? = nil
    ) -> SyncStatus {
        SyncStatus(
            result: result,
            startedAt: nil,
            finishedAt: finishedAt,
            durationSeconds: nil,
            updatedFileCount: nil,
            updatedByteCount: nil,
            storageFileCount: nil,
            storageByteCount: nil,
            warningCount: warnings.count,
            errorCount: errors.count,
            lastCommit: nil,
            remoteRepository: nil,
            warnings: warnings,
            errors: errors,
            recordedLocalChanges: [],
            currentLocalChanges: currentLocalChanges
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home")
        let data = root.appendingPathComponent("mac-sync-data")
        let status = root.appendingPathComponent("status")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: status, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, data: data, status: status)
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let data: URL
    let status: URL
}
