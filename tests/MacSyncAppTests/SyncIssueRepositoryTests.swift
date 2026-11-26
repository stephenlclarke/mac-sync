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
                    durationSeconds: 2,
                ),
                entries: [],
                diagnostics: SyncHistoryDiagnostics(
                    warningCount: 1,
                    errorCount: 1,
                    warnings: ["WARN: remote needs attention"],
                    errors: ["ERROR: git push failed"],
                ),
            ),
        ]
        let overview = makeOverview(fixture: fixture, history: history)
        let repository = SyncIssueRepository(configuration: overview.configuration)

        let initialIssues = repository.issues(for: overview)
        XCTAssertEqual(initialIssues.count, 2)
        let error = try XCTUnwrap(initialIssues.first { $0.severity == .error })

        try repository.update(
            issueID: error.id,
            latestOccurrenceID: error.latestOccurrenceID,
            disposition: .acknowledged,
            note: "Will repair remote access after the maintenance window.",
        )

        let reloadedIssues = repository.issues(for: overview)
        let reloadedError = try XCTUnwrap(reloadedIssues.first { $0.id == error.id })
        XCTAssertEqual(reloadedError.disposition, .acknowledged)
        XCTAssertEqual(reloadedError.note, "Will repair remote access after the maintenance window.")
        XCTAssertEqual(history.first?.errors, ["ERROR: git push failed"])
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.status.appendingPathComponent("issues/local.json").path))

        // A memory-only refresh must retain cached decisions without rereading or replacing this file.
        let triageURL = fixture.status.appendingPathComponent("issues/local.json")
        let unreadable = Data("not valid triage JSON".utf8)
        try unreadable.write(to: triageURL)
        let cached = try XCTUnwrap(repository.issues(for: overview, cachedDecisions: reloadedIssues)
            .first { $0.id == error.id })
        XCTAssertEqual(cached.disposition, .acknowledged)
        XCTAssertEqual(cached.note, reloadedError.note)
        XCTAssertEqual(cached.updatedAt, reloadedError.updatedAt)
        XCTAssertEqual(try Data(contentsOf: triageURL), unreadable)
        XCTAssertEqual(repository.issues(for: overview).first { $0.id == error.id }?.disposition, .open)
    }

    func testRepeatedConditionIsGroupedAndReopensWhenItRecurs() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncIssueRepository(configuration: makeOverview(fixture: fixture, history: []).configuration)
        let repeatedError = "ERROR: existing encrypted secrets snapshot cannot be decrypted"
        let initialHistory = [
            makeHistoryRecord(id: "newer", finishedAt: "2026-07-30 10:00:00 BST", error: repeatedError),
            makeHistoryRecord(id: "older", finishedAt: "2026-07-30 09:00:00 BST", error: repeatedError),
        ]

        let initialIssue = try XCTUnwrap(
            repository.issues(for: makeOverview(fixture: fixture, history: initialHistory)).first,
        )
        XCTAssertEqual(initialIssue.occurrenceCount, 2)
        XCTAssertEqual(initialIssue.firstRecordedAt, "2026-07-30 09:00:00 BST")
        XCTAssertEqual(initialIssue.recordedAt, "2026-07-30 10:00:00 BST")

        try repository.update(
            issueID: initialIssue.id,
            latestOccurrenceID: initialIssue.latestOccurrenceID,
            disposition: .acknowledged,
            note: "Recovering the trusted identity.",
        )
        let acknowledged = try XCTUnwrap(
            repository.issues(for: makeOverview(fixture: fixture, history: initialHistory)).first,
        )
        XCTAssertEqual(acknowledged.disposition, .acknowledged)

        let recurringHistory = [
            makeHistoryRecord(id: "latest", finishedAt: "2026-07-30 11:00:00 BST", error: repeatedError),
        ] + initialHistory
        let reopened = try XCTUnwrap(
            repository.issues(for: makeOverview(fixture: fixture, history: recurringHistory)).first,
        )
        XCTAssertEqual(reopened.occurrenceCount, 3)
        XCTAssertEqual(reopened.disposition, .open)
        XCTAssertEqual(reopened.note, "Recovering the trusted identity.")
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
                    durationSeconds: 3,
                ),
                entries: [],
                diagnostics: SyncHistoryDiagnostics(
                    warningCount: 1,
                    errorCount: 0,
                    warnings: [localChangesWarning],
                    errors: [],
                ),
            ),
        ]
        let overview = makeOverview(
            fixture: fixture,
            status: makeStatus(
                warnings: [localChangesWarning],
                finishedAt: "2026-07-23 09:00:03 BST",
                currentLocalChanges: [],
            ),
            history: history,
        )

        XCTAssertTrue(SyncIssueRepository(configuration: overview.configuration).issues(for: overview).isEmpty)
    }

    func testResolvedLegacyLocalRepositoryWarningDoesNotCreateManualTriageItem() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let warning = "WARN: local repo has local changes; skipping pre-operation git pull"
        let overview = makeOverview(
            fixture: fixture,
            status: makeStatus(
                warnings: [warning],
                finishedAt: "2026-06-28 22:15:18 BST",
                currentLocalChanges: [],
            ),
            history: [],
        )

        XCTAssertTrue(SyncIssueRepository(configuration: overview.configuration).issues(for: overview).isEmpty)
    }

    func testTypedConditionRemainsInHistoryAfterLiveHealthRecovers() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let condition = SyncHealthCondition(
            code: .encryptedSecretsIdentityMissing,
            component: .encryptedSecrets,
            severity: .warning,
            title: "Encrypted secrets were not updated",
            detail: "No age identity was found in this Mac's Keychain.",
            recovery: "Test encrypted-secrets access, then retry.",
        )
        let history = [
            SyncHistoryRecord(
                id: "partial-sync",
                action: .sync,
                result: .partial,
                timing: SyncHistoryTiming(
                    startedAt: "2026-07-31 09:00:00 BST",
                    finishedAt: "2026-07-31 09:00:03 BST",
                    durationSeconds: 3,
                ),
                entries: [],
                diagnostics: SyncHistoryDiagnostics(
                    warningCount: 1,
                    errorCount: 0,
                    warnings: ["WARN: no local Keychain age identity"],
                    errors: [],
                    conditions: [condition],
                ),
            ),
        ]
        let overview = makeOverview(fixture: fixture, history: history)
        let repository = SyncIssueRepository(configuration: overview.configuration)

        let active = try XCTUnwrap(
            repository.issues(
                for: overview,
                activeConditionCodes: [.encryptedSecretsIdentityMissing],
            ).first,
        )
        XCTAssertTrue(active.isActive)
        XCTAssertTrue(active.requiresManualIntervention)
        XCTAssertEqual(
            active.recoveryActions,
            [.testEncryptedSecrets, .openKeychainAccess, .retrySync],
        )

        let recovered = try XCTUnwrap(
            repository.issues(for: overview, activeConditionCodes: []).first,
        )
        XCTAssertFalse(recovered.isActive)
        XCTAssertFalse(recovered.requiresManualIntervention)
        XCTAssertEqual(recovered.dispositionTitle, "Recovered")
    }

    func testTypedStatusConditionKeepsItsRecoveryActionsWithoutHistory() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let condition = SyncHealthCondition(
            code: .remoteAuthenticationFailed,
            component: .remoteRepository,
            severity: .error,
            title: "The data repository could not be refreshed",
            detail: "Git authentication failed.",
            recovery: "Test GitHub access, use SSH if offered, then retry.",
        )
        let status = makeStatus(
            result: .failed,
            errors: ["ERROR: the data repository could not be refreshed"],
            finishedAt: "2026-07-31 09:00:03 BST",
            conditions: [condition],
        )
        let overview = makeOverview(fixture: fixture, status: status, history: [])

        let issue = try XCTUnwrap(
            SyncIssueRepository(configuration: overview.configuration)
                .issues(
                    for: overview,
                    activeConditionCodes: [.remoteAuthenticationFailed],
                )
                .first,
        )

        XCTAssertEqual(issue.conditionCode, .remoteAuthenticationFailed)
        XCTAssertEqual(issue.message, condition.title)
        XCTAssertEqual(issue.recoveryActions, [.testGitHubAccess, .useSSH, .retrySync])
    }

    func testEmptyReviewQueueRecoversWarningAndPreservesHistoryAndTriage() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let warning = "WARN: " + IncomingSyncEngine.reviewRequiredMessage
        let finishedAt = "2026-11-26 14:28:04 GMT+0"
        let record = SyncHistoryRecord(
            id: "review-needed", action: .sync, result: .success,
            timing: SyncHistoryTiming(startedAt: finishedAt, finishedAt: finishedAt, durationSeconds: 0),
            entries: [], diagnostics: SyncHistoryDiagnostics(warningCount: 1, errorCount: 0, warnings: [warning], errors: []),
        )
        let overview = makeOverview(fixture: fixture, status: makeStatus(warnings: [warning], finishedAt: finishedAt), history: [record])
        let repository = SyncIssueRepository(configuration: overview.configuration)
        let active = try XCTUnwrap(repository.issues(for: overview, hasPendingIncomingChanges: true).first)
        XCTAssertTrue(active.requiresManualIntervention)
        try repository.update(issueID: active.id, latestOccurrenceID: active.latestOccurrenceID,
                              disposition: .open, note: "Keep this Mac; no sync approved.")
        let triage = fixture.status.appendingPathComponent("issues/local.json")
        let before = try Data(contentsOf: triage)

        let recovered = try XCTUnwrap(repository.issues(for: overview, hasPendingIncomingChanges: false).first)
        XCTAssertFalse(recovered.isActive)
        XCTAssertFalse(recovered.requiresManualIntervention)
        XCTAssertEqual(recovered.dispositionTitle, "Recovered")
        XCTAssertEqual(recovered.id, active.id)
        XCTAssertEqual(recovered.latestOccurrenceID, active.latestOccurrenceID)
        XCTAssertEqual(recovered.occurrenceCount, active.occurrenceCount)
        XCTAssertEqual(recovered.note, "Keep this Mac; no sync approved.")
        XCTAssertEqual(recovered.disposition, .open)
        XCTAssertEqual(recovered.recoveryActions, [])
        XCTAssertTrue(recovered.recommendedAction.contains("No sync or file action is needed"))
        XCTAssertEqual(overview.history.first?.warnings, [warning])
        XCTAssertEqual(overview.status.warnings, [warning])
        XCTAssertEqual(try Data(contentsOf: triage), before)

        let unknown = try XCTUnwrap(repository.issues(for: overview, hasPendingIncomingChanges: nil).first)
        XCTAssertTrue(unknown.isActive, "An unreadable/missing ledger is not a healthy queue")
        let recurring = try XCTUnwrap(repository.issues(for: overview, hasPendingIncomingChanges: true).first)
        XCTAssertTrue(recurring.isActive)
    }

    func testEmptyReviewQueueRecoversLegacyStatusWithoutHidingOtherIssues() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let warning = IncomingSyncEngine.reviewRequiredMessage
        let otherWarning = "WARN: Incoming changes need review. Unknown safety failure."
        let overview = makeOverview(fixture: fixture,
                                    status: makeStatus(warnings: [warning, otherWarning], errors: ["ERROR: git push failed"]), history: [])
        let issues = SyncIssueRepository(configuration: overview.configuration)
            .issues(for: overview, hasPendingIncomingChanges: false)
        XCTAssertEqual(issues.count, 3)
        XCTAssertFalse(try XCTUnwrap(issues.first { $0.message == warning }).isActive)
        XCTAssertTrue(try XCTUnwrap(issues.first { $0.message == otherWarning }).isActive)
        XCTAssertTrue(try XCTUnwrap(issues.first { $0.severity == .error }).isActive)
        XCTAssertFalse(SyncHealthMessage.isIncomingReviewWarning("ERROR: " + warning))
    }

    private func makeOverview(
        fixture: Fixture,
        status: SyncStatus? = nil,
        history: [SyncHistoryRecord],
    ) -> SyncOverview {
        SyncOverview(
            configuration: SyncConfiguration(
                homeDirectory: fixture.home.path,
                dataRepository: fixture.data.path,
                statusDirectory: fixture.status.path,
                machineName: "local",
                pathsFile: fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt").path,
            ),
            status: status ?? makeStatus(),
            history: history,
            currentMachine: nil,
            peerMachines: [],
            localSyncProcessID: nil,
            isLocalSyncActive: false,
        )
    }

    private func makeStatus(
        result: SyncResult = .success,
        warnings: [String] = [],
        errors: [String] = [],
        finishedAt: String? = nil,
        conditions: [SyncHealthCondition] = [],
        currentLocalChanges: [String]? = nil,
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
            conditions: conditions,
            commandDiagnostics: [],
            recordedLocalChanges: [],
            currentLocalChanges: currentLocalChanges,
        )
    }

    private func makeHistoryRecord(id: String, finishedAt: String, error: String) -> SyncHistoryRecord {
        SyncHistoryRecord(
            id: id,
            action: .sync,
            sourceMachine: nil,
            result: .failed,
            timing: SyncHistoryTiming(
                startedAt: finishedAt,
                finishedAt: finishedAt,
                durationSeconds: 1,
            ),
            entries: [],
            diagnostics: SyncHistoryDiagnostics(
                warningCount: 0,
                errorCount: 1,
                warnings: [],
                errors: [error],
            ),
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
