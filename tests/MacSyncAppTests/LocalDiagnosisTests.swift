import AppKit
import Foundation
@testable import MacSyncApp
import MacSyncCore
import SwiftUI
import XCTest

final class LocalDiagnosisEvidenceTests: XCTestCase {
    func testGenericDeletionWarningCannotCreatePendingDeletions() throws {
        let facts = diagnosisFixture()
        XCTAssertEqual(facts.inventory?.total, 31)
        XCTAssertEqual(facts.inventory?.deletions, 0)
        XCTAssertEqual(try facts.validatedFindings(answer(for: facts)).count, facts.findings.count)
        let prompt = try facts.prompt()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
        XCTAssertEqual(json["totalReviewItems"] as? Int, 31)
        XCTAssertEqual(json["pendingDeletions"] as? Int, 0)
        XCTAssertEqual(json["requiredFindingIDs"] as? [String], facts.findings.map(\.id))
        XCTAssertTrue(facts.requiredFindingIDs.contains("deletions"))
        XCTAssertFalse(prompt.contains("Deletions were not applied automatically"))
        XCTAssertTrue(facts.findings.contains { $0.title == "0 pending deletions" })
        var incorrect = answer(for: facts)
        incorrect = .init(
            runResult: incorrect.runResult,
            totalReviewItems: 31,
            pendingDeletions: 31,
            orderedFindingIDs: incorrect.orderedFindingIDs
        )
        XCTAssertThrowsError(try facts.validatedFindings(incorrect)) { XCTAssertEqual(
            $0 as? LocalDiagnosisError,
            .inconsistentAnswer
        ) }
    }

    func testRealDeletionCountsAreNotForcedToZero() throws {
        let facts = diagnosisFixture(inventory: .init(conflicts: 28, deletions: 2, pathOrLink: 1))
        XCTAssertNoThrow(try facts.validatedFindings(answer(for: facts)))
        let wrong = LocalDiagnosisAnswer(
            runResult: facts.runResult,
            totalReviewItems: 31,
            pendingDeletions: 0,
            orderedFindingIDs: facts.findings.map(\.id)
        )
        XCTAssertThrowsError(try facts.validatedFindings(wrong))
    }

    func testInventedOmittedAndDuplicateFindingsAreRejected() throws {
        let facts = diagnosisFixture()
        let ids = facts.findings.map(\.id)
        for invalid in [
            Array(ids.dropLast()),
            ids + ["resolve_everything"],
            Array(repeating: ids[0], count: ids.count)
        ] {
            XCTAssertThrowsError(try facts.validatedFindings(.init(
                runResult: facts.runResult,
                totalReviewItems: 31,
                pendingDeletions: 0,
                orderedFindingIDs: invalid
            )))
        }
        let reordered = LocalDiagnosisAnswer(
            runResult: facts.runResult,
            totalReviewItems: 31,
            pendingDeletions: 0,
            orderedFindingIDs: ids.reversed()
        )
        XCTAssertEqual(try facts.validatedFindings(reordered).map(\.id), Array(ids.reversed()))
    }

    func testMissingInventoryIsNotPresentedAsZero() throws {
        let facts = diagnosisFixture(inventory: nil)
        XCTAssertTrue(facts.findings.contains { $0.id == "inventory_unknown" })
        XCTAssertNoThrow(try facts.validatedFindings(answer(for: facts)))
        XCTAssertThrowsError(try facts.validatedFindings(.init(
            runResult: facts.runResult,
            totalReviewItems: 0,
            pendingDeletions: 0,
            orderedFindingIDs: facts.findings.map(\.id)
        )))
    }

    func testChangedResultAndStaleTotalAreRejected() {
        let facts = diagnosisFixture()
        let ids = facts.findings.map(\.id)
        XCTAssertThrowsError(try facts.validatedFindings(.init(
            runResult: "failed", totalReviewItems: 31, pendingDeletions: 0, orderedFindingIDs: ids
        )))
        XCTAssertThrowsError(try facts.validatedFindings(.init(
            runResult: facts.runResult, totalReviewItems: 30, pendingDeletions: 0, orderedFindingIDs: ids
        )))
    }

    func testCloudFolderDoesNotClaimAConfirmedCloudUpload() {
        let facts = diagnosisFixture(storage: .cloudFolder)
        XCTAssertTrue(facts.findings.contains { $0.id == "folder_upload_unverified" })
        XCTAssertFalse(facts.findings.contains { $0.id == "publish_command" })
    }

    func testPromptOmitsRawWarningsCommandsPathsAndCredentials() throws {
        let status = diagnosisStatus(
            conditions: [.init(
                code: .remoteAuthenticationFailed,
                component: .remoteRepository,
                severity: .error,
                title: "PRIVATE_VALUE",
                detail: "PRIVATE_VALUE",
                recovery: "PRIVATE_VALUE"
            )],
            commands: [.init(
                step: "Publishing the data repository",
                command: "PRIVATE_VALUE",
                attempt: 1,
                exitStatus: 0,
                output: "PRIVATE_VALUE"
            )]
        )
        let facts = LocalDiagnosisEvidence(status: status, storageKind: .git, inventory: .init(other: 1))
        let prompt = try facts.prompt()
        XCTAssertFalse(prompt.contains("PRIVATE_VALUE"))
        XCTAssertFalse(prompt.contains("/Users/"))
        XCTAssertTrue(prompt.contains("remoteAuthenticationFailed"))
    }

    func testLatestFailedPublishIsNotHiddenByAnEarlierSuccess() {
        let commands: [SyncCommandDiagnostic] = [0, 128].map {
            .init(
                step: "Publishing the data repository",
                command: "git push",
                attempt: 1,
                exitStatus: Int32($0),
                output: ""
            )
        }
        let facts = LocalDiagnosisEvidence(
            status: diagnosisStatus(commands: commands),
            storageKind: .git,
            inventory: .init()
        )
        XCTAssertEqual(facts.publishExitStatus, 128)
        XCTAssertTrue(facts.findings.contains { $0.title == "Git publish command failed" })
    }

    func testNoHistoryAndOtherReviewReasonsRemainUnknown() {
        let facts = LocalDiagnosisEvidence(
            status: .empty,
            storageKind: .git,
            inventory: .init(reviewPolicy: 2, other: 3)
        )
        XCTAssertTrue(facts.findings.contains { $0.id == "run_unknown" })
        XCTAssertTrue(facts.findings.contains { $0.id == "publish_unknown" })
        XCTAssertTrue(facts.findings.contains { $0.id == "review_policy" })
        XCTAssertTrue(facts.findings.contains { $0.id == "other_review" })
    }

    func testAllKnownConditionCodesHaveBoundedTrustedExplanations() throws {
        let codes: [SyncHealthConditionCode] = [
            .remoteAuthenticationFailed,
            .remoteConfigurationMissing,
            .remoteRefreshFailed,
            .remoteRefreshBlockedByLocalChanges,
            .remoteUnavailable,
            .encryptedSecretsIdentityMissing,
            .encryptedSecretsIdentityUntrusted,
            .encryptedSecretsIdentityUnavailable,
            .encryptedSecretsRuntimeUnavailable,
            .encryptedSecretsSnapshotSkipped
        ]
        let conditions = codes.map { SyncHealthCondition(
            code: $0,
            component: .remoteRepository,
            severity: .warning,
            title: "PRIVATE_VALUE",
            detail: "PRIVATE_VALUE",
            recovery: "PRIVATE_VALUE"
        ) }
        let facts = LocalDiagnosisEvidence(
            status: diagnosisStatus(conditions: conditions),
            storageKind: .git,
            inventory: nil
        )
        XCTAssertEqual(facts.findings.filter { $0.id.hasPrefix("condition_") }.count, codes.count)
        XCTAssertLessThan(try facts.prompt().utf8.count, 12000)
        XCTAssertFalse(try facts.prompt().contains("PRIVATE_VALUE"))
    }
}

@MainActor
final class LocalDiagnosisSessionTests: XCTestCase {
    func testValidatedResponseUsesOnlyTrustedDescriptions() async throws {
        let facts = diagnosisFixture()
        let result = try await LocalDiagnosisSession.run(evidence: facts, generator: EchoDiagnosisGenerator())
        XCTAssertEqual(Set(result), Set(facts.findings))
    }

    func testUnavailableModelHasNoAlternativeProvider() async {
        do {
            _ = try await LocalDiagnosisSession.run(
                evidence: diagnosisFixture(),
                generator: FailingDiagnosisGenerator()
            )
            XCTFail("Expected local-model failure")
        } catch { XCTAssertEqual(error as? LocalDiagnosisError, .notReady) }
    }

    func testDeadlineCancelsTheLocalRequest() async {
        do {
            _ = try await LocalDiagnosisSession.run(
                evidence: diagnosisFixture(),
                generator: SleepingDiagnosisGenerator(),
                timeoutNanoseconds: 1_000_000
            )
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual(error as? LocalDiagnosisError, .timedOut) }
    }

    func testCancelledRequestProducesNoDiagnosis() async {
        let task = Task { try await LocalDiagnosisSession.run(
            evidence: diagnosisFixture(),
            generator: SleepingDiagnosisGenerator()
        ) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testControllerDoesNotCreateAMissingLedgerOrIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnosis-controller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = SyncConfiguration(
            homeDirectory: root.path,
            dataRepository: root.appendingPathComponent("repo").path,
            statusDirectory: root.appendingPathComponent("status").path,
            machineName: "fixture",
            pathsFile: root.appendingPathComponent("paths").path
        )
        let overview = SyncOverview(
            configuration: configuration,
            status: diagnosisStatus(),
            history: [],
            currentMachine: nil,
            peerMachines: [],
            localSyncProcessID: nil,
            isLocalSyncActive: false
        )
        let controller = LocalDiagnosisController(generator: EchoDiagnosisGenerator())
        controller.start(overview: overview)
        for _ in 0 ..< 100 where controller.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.isRunning)
        XCTAssertNotNil(controller.orderedFindings)
        XCTAssertEqual(controller.recordedRunFinishedAt, overview.status.finishedAt)
        XCTAssertNil(controller.evidence?.inventory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testControllerKeepsVerifiedEvidenceWhenTheModelIsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnosis-unavailable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let overview = diagnosisOverview(root: root)
        let controller = LocalDiagnosisController(generator: FailingDiagnosisGenerator())
        controller.start(overview: overview)
        for _ in 0 ..< 100 where controller.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(controller.evidence)
        XCTAssertNil(controller.orderedFindings)
        XCTAssertEqual(controller.message, LocalDiagnosisError.notReady.localizedDescription)
        controller.cancel()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testDiagnosisSheetHasABoundedLayoutWithAGeneratedFixture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnosis-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = LocalDiagnosisController(generator: EchoDiagnosisGenerator())
        let host = NSHostingView(rootView: LocalDiagnosisView(
            overview: diagnosisOverview(root: root),
            controller: controller
        ))
        host.setFrameSize(NSSize(width: 760, height: 700))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 1000)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 900)
        controller.cancel()
    }

    func testLiveOnDeviceDiagnosisWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["MAC_SYNC_TEST_LOCAL_AI"] == "1" else {
            throw XCTSkip("Opt-in native on-device integration test; no model runs in ordinary CI.")
        }
        for inventory in [
            IncomingReviewInventory(conflicts: 30, pathOrLink: 1),
            IncomingReviewInventory(conflicts: 28, deletions: 2, pathOrLink: 1),
            IncomingReviewInventory(conflicts: 30, pathOrLink: 1)
        ] {
            let facts = diagnosisFixture(inventory: inventory)
            let generated = try await OnDeviceDiagnosisService.shared.generate(evidence: facts)
            XCTAssertEqual(generated.runResult, facts.runResult)
            XCTAssertEqual(generated.totalReviewItems, inventory.total)
            XCTAssertEqual(generated.pendingDeletions, inventory.deletions)
            XCTAssertEqual(generated.orderedFindingIDs.count, facts.findings.count)
            XCTAssertEqual(Set(generated.orderedFindingIDs), Set(facts.findings.map(\.id)))
            let findings = try facts.validatedFindings(generated)
            XCTAssertEqual(Set(findings), Set(facts.findings))
        }
    }
}

private struct EchoDiagnosisGenerator: OnDeviceDiagnosisGenerating {
    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
        answer(for: evidence)
    }
}

private struct FailingDiagnosisGenerator: OnDeviceDiagnosisGenerating {
    func generate(evidence _: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
        throw LocalDiagnosisError.notReady
    }
}

private struct SleepingDiagnosisGenerator: OnDeviceDiagnosisGenerating {
    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return answer(for: evidence)
    }
}

private func diagnosisFixture(
    inventory: IncomingReviewInventory? = .init(conflicts: 30, pathOrLink: 1),
    storage: BackupStorageKind = .git
) -> LocalDiagnosisEvidence {
    .init(status: diagnosisStatus(), storageKind: storage, inventory: inventory)
}

private func answer(for facts: LocalDiagnosisEvidence) -> LocalDiagnosisAnswer {
    .init(
        runResult: facts.runResult,
        totalReviewItems: facts.inventory?.total,
        pendingDeletions: facts.inventory?.deletions,
        orderedFindingIDs: facts.findings.map(\.id)
    )
}

private func diagnosisOverview(root: URL) -> SyncOverview {
    let configuration = SyncConfiguration(
        homeDirectory: root.path,
        dataRepository: root.appendingPathComponent("repo").path,
        statusDirectory: root.appendingPathComponent("status").path,
        machineName: "fixture",
        pathsFile: root.appendingPathComponent("paths").path
    )
    return SyncOverview(
        configuration: configuration,
        status: diagnosisStatus(),
        history: [],
        currentMachine: nil,
        peerMachines: [],
        localSyncProcessID: nil,
        isLocalSyncActive: false
    )
}
