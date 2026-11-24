import CryptoKit
import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class LocalDiagnosisAdviceTests: XCTestCase {
    func testUnknownCountsStayNullAndHaveOnlyInventoryAdvice() throws {
        let facts = evidence(nil)
        XCTAssertEqual(facts.reviewState, .unknown)
        XCTAssertFalse(facts.requiresModelOrdering)
        XCTAssertNil(facts.totalReviewItems)
        XCTAssertNil(facts.pendingDeletions)
        XCTAssertEqual(facts.advice.steps.map(\.id), ["inspect_inventory"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(facts.prompt().utf8)) as? [String: Any])
        XCTAssertTrue(json["inventory"] is NSNull)
        XCTAssertTrue(json["pendingDeletions"] is NSNull)
        XCTAssertTrue(json["totalReviewItems"] is NSNull)
        XCTAssertEqual(json["reviewState"] as? String, "unknown")
        XCTAssertTrue(facts.advice.summary.contains("unknown, not zero"))
    }

    func testHealthyQueueHasNoRepairStepsEvenWithAHistoricalGenericWarning() {
        // diagnosisStatus has the ambiguous deletion warning; it is not an action source.
        let facts = evidence(.init())
        XCTAssertEqual(facts.reviewState, .empty)
        XCTAssertFalse(facts.requiresModelOrdering)
        XCTAssertEqual(facts.pendingDeletions, 0)
        XCTAssertTrue(facts.advice.steps.isEmpty)
        XCTAssertTrue(facts.advice.summary.contains("No repair is indicated"))
    }

    func testCurrentCasePreservesVersionsBeforeChoicesAndVerification() {
        let facts = evidence(.init(conflicts: 30, pathOrLink: 1))
        XCTAssertTrue(facts.requiresModelOrdering)
        XCTAssertEqual(facts.advice.steps.map(\.id), [
            "preserve_versions", "compare_conflicts", "inspect_paths", "deletion_decisions",
            "approve_choices", "verify_after_approval"
        ])
        XCTAssertTrue(facts.advice.steps[1].title.contains("30"))
        XCTAssertTrue(facts.advice.steps[2].title.contains("1"))
        XCTAssertEqual(facts.advice.steps[3].title, "No deletion action is needed")
        XCTAssertTrue(facts.advice.steps[1].detail.contains("Keep Both"))
        XCTAssertTrue(facts.advice.steps[1].detail.contains("does not merge"))
        XCTAssertTrue(facts.advice.steps[2].detail.contains("precise failed safety check is unknown"))
        XCTAssertFalse(facts.advice.steps.contains { $0.id == "inspect_publish" })
    }

    func testRealDeletionsAreSeparateAndDoNotInventConflictsOrPathItems() {
        let facts = evidence(.init(deletions: 3))
        XCTAssertEqual(facts.pendingDeletions, 3)
        XCTAssertEqual(facts.advice.steps.map(\.id), [
            "preserve_versions", "deletion_decisions", "approve_choices", "verify_after_approval"
        ])
        XCTAssertEqual(facts.advice.steps[1].title, "Review 3 explicit deletions separately")
        XCTAssertTrue(facts.advice.steps[1].detail.contains("Nothing here authorises deletion"))
    }

    func testAIOrderingCannotChangeTheSafetyPlanOrIntroduceAnAction() throws {
        let facts = evidence(.init(conflicts: 30, pathOrLink: 1))
        let original = facts.advice
        let reordered = LocalDiagnosisAnswer(
            runResult: facts.runResult, totalReviewItems: 31, pendingDeletions: 0,
            orderedFindingIDs: facts.requiredFindingIDs.reversed()
        )
        XCTAssertNoThrow(try facts.validatedFindings(reordered))
        XCTAssertEqual(facts.advice, original)
        let invented = LocalDiagnosisAnswer(
            runResult: facts.runResult, totalReviewItems: 31, pendingDeletions: 0,
            orderedFindingIDs: facts.requiredFindingIDs + ["delete_everything"]
        )
        XCTAssertThrowsError(try facts.validatedFindings(invented))
        XCTAssertEqual(facts.advice, original)
    }

    func testCloudFolderDoesNotInventPathItemsOrAGitFailure() {
        let facts = evidence(.init(conflicts: 2), storage: .cloudFolder)
        let ids = facts.advice.steps.map(\.id)
        XCTAssertFalse(ids.contains("inspect_paths"))
        XCTAssertFalse(ids.contains("inspect_publish"))
        XCTAssertTrue(ids.contains("provider_upload"))
        XCTAssertTrue(facts.advice.steps.last?.detail.contains("provider upload") == true)
        let empty = evidence(.init(), storage: .cloudFolder)
        XCTAssertEqual(empty.advice.steps.map(\.id), ["provider_upload"])
        XCTAssertFalse(empty.requiresModelOrdering)
    }

    func testEmptyQueueDoesNotHideAFailedPublishOrRecordedErrors() {
        let command = SyncCommandDiagnostic(
            step: "Publishing the data repository", command: "PRIVATE_VALUE", attempt: 1,
            exitStatus: 128, output: "PRIVATE_VALUE"
        )
        let facts = evidence(.init(), status: diagnosisStatus(commands: [command], result: .failed, errorCount: 1))
        XCTAssertFalse(facts.requiresModelOrdering)
        XCTAssertEqual(facts.advice.steps.map(\.id), ["inspect_publish", "inspect_recorded_health"])
        XCTAssertFalse(facts.advice.summary.contains("No repair is indicated"))
        XCTAssertFalse(facts.advice.steps.contains { $0.id == "compare_conflicts" })
        XCTAssertTrue(facts.advice.steps[0].detail.contains("does not prove an authentication"))
        XCTAssertFalse(facts.advice.steps.description.contains("PRIVATE_VALUE"))
    }

    func testMissingPublishRecordAndOtherReviewsRemainExplicit() {
        let facts = evidence(.init(reviewPolicy: 2, other: 1), status: diagnosisStatus(commands: []))
        XCTAssertTrue(facts.advice.steps.contains { $0.id == "inspect_other_reviews" })
        XCTAssertTrue(facts.advice.steps.contains { $0.id == "inspect_publish_record" })
        XCTAssertFalse(facts.advice.steps.contains { $0.id == "compare_conflicts" })
    }

    func testRecognisedHealthConditionStillNeedsAttentionWithAnEmptyQueue() {
        let condition = SyncHealthCondition(
            code: .encryptedSecretsIdentityMissing, component: .encryptedSecrets, severity: .warning,
            title: "PRIVATE_VALUE", detail: "PRIVATE_VALUE", recovery: "PRIVATE_VALUE"
        )
        let facts = evidence(.init(), status: diagnosisStatus(conditions: [condition]))
        XCTAssertEqual(facts.advice.steps.map(\.id), ["inspect_recorded_health"])
        XCTAssertFalse(facts.advice.steps.description.contains("PRIVATE_VALUE"))
    }

    func testOnlyKnownPendingReviewsCallTheGenerator() async throws {
        let generator = CountingAdviceGenerator()
        for inventory: IncomingReviewInventory? in [nil, .init(), .init(conflicts: 1)] {
            let facts = evidence(inventory)
            _ = try await LocalDiagnosisSession.run(evidence: facts, generator: generator)
        }
        let calls = await generator.calls
        XCTAssertEqual(calls, 1)
    }

    func testDirectNativeServiceAlsoBypassesUnknownAndEmptyWithoutModelAvailability() async throws {
        for inventory: IncomingReviewInventory? in [nil, .init()] {
            let facts = evidence(inventory)
            let answer = try await OnDeviceDiagnosisService.shared.generate(evidence: facts)
            XCTAssertEqual(answer.pendingDeletions, inventory?.deletions)
            XCTAssertEqual(try facts.validatedFindings(answer), facts.findings)
        }
    }

    @MainActor
    func testUnreadableLedgerProducesUnknownAdviceWithoutChangingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("advice-corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo").path
        let digest = SHA256.hash(data: Data((repo + "\0fixture").utf8)).map { String(format: "%02x", $0) }.joined()
        let ledger = root.appendingPathComponent("sync-\(digest).sqlite")
        let original = Data("not a SQLite ledger".utf8)
        try original.write(to: ledger)
        let configuration = SyncConfiguration(
            homeDirectory: root.path, dataRepository: repo, statusDirectory: root.path,
            machineName: "fixture", pathsFile: root.appendingPathComponent("paths").path
        )
        let overview = SyncOverview(
            configuration: configuration, status: diagnosisStatus(), history: [], currentMachine: nil,
            peerMachines: [], localSyncProcessID: nil, isLocalSyncActive: false
        )
        let generator = CountingAdviceGenerator()
        let controller = LocalDiagnosisController(generator: generator)
        controller.start(overview: overview)
        for _ in 0 ..< 100 where controller.isRunning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.usedModel)
        XCTAssertEqual(controller.evidence?.reviewState, .unknown)
        XCTAssertEqual(controller.evidence?.advice.steps.map(\.id), ["inspect_inventory"])
        XCTAssertTrue(controller.message?.contains("Counts remain unknown") == true)
        XCTAssertEqual(try Data(contentsOf: ledger), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [ledger.lastPathComponent])
        let calls = await generator.calls
        XCTAssertEqual(calls, 0)
    }

    private func evidence(
        _ inventory: IncomingReviewInventory?, storage: BackupStorageKind = .git,
        status: SyncStatus = diagnosisStatus()
    ) -> LocalDiagnosisEvidence {
        .init(status: status, storageKind: storage, inventory: inventory)
    }
}

private actor CountingAdviceGenerator: OnDeviceDiagnosisGenerating {
    private(set) var calls = 0

    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
        calls += 1
        return .init(
            runResult: evidence.runResult, totalReviewItems: evidence.totalReviewItems,
            pendingDeletions: evidence.pendingDeletions, orderedFindingIDs: evidence.requiredFindingIDs
        )
    }
}
