import AppKit
import Darwin
@testable import MacSyncApp
import MacSyncCore
import SwiftUI
import XCTest

final class LocalRepairTests: XCTestCase {
    @MainActor
    func testRepairsOnlyVerifiedAllowlistedFaultsAndVerifiesEachEffect() async throws {
        let runtime = RepairRuntimeFixture()
        let planner = RepairPlannerFixture()
        var receipts: [String] = []
        try await LocalRepairSession.run(runtime: runtime, planner: planner) { receipts.append($0) }
        XCTAssertEqual(runtime.applied, LocalRepairAction.allCases.reversed())
        XCTAssertTrue(runtime.candidates.isEmpty)
        XCTAssertEqual(receipts.count, 3)
        XCTAssertTrue(receipts.allSatisfy { $0.hasPrefix("Verified:") })
        let inputs = await planner.inputs
        XCTAssertEqual(inputs, [LocalRepairAction.allCases.map(\.rawValue)])
    }

    @MainActor
    func testHealthyStateDoesNotCallTheModel() async throws {
        let runtime = RepairRuntimeFixture()
        runtime.candidates = []
        let planner = RepairPlannerFixture()
        var receipts: [String] = []
        try await LocalRepairSession.run(runtime: runtime, planner: planner) { receipts.append($0) }
        let inputs = await planner.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertTrue(runtime.applied.isEmpty)
        XCTAssertEqual(receipts.count, 1)
    }

    @MainActor
    func testRejectsEntirePlanBeforeAnyEffect() async {
        let valid = LocalRepairAction.allCases.map(\.rawValue)
        for ids in [valid + ["sync"], valid + ["overwrite"], valid + ["delete"], valid + ["resolve_conflict"],
                    valid + ["change_credentials"], valid + ["disable_security"], valid + ["/bin/sh"],
                    Array(valid.dropLast()), [valid[0], valid[0], valid[0]]] {
            let runtime = RepairRuntimeFixture()
            do {
                try await LocalRepairSession.run(runtime: runtime, planner: RepairPlannerFixture(answer: ids)) { _ in }
                XCTFail("Untrusted plan was accepted")
            } catch { XCTAssertTrue(error is LocalRepairError) }
            XCTAssertTrue(runtime.applied.isEmpty)
        }
    }

    @MainActor
    func testActiveOrUnknownWorkersPreventModelAndRepairs() async {
        for state in [LocalWorkerState.active, .unknown] {
            let runtime = RepairRuntimeFixture()
            runtime.worker = state
            let planner = RepairPlannerFixture()
            do {
                try await LocalRepairSession.run(runtime: runtime, planner: planner) { _ in }
                XCTFail("Worker state was ignored")
            } catch { XCTAssertTrue(error is LocalRepairError) }
            let inputs = await planner.inputs
            XCTAssertTrue(inputs.isEmpty)
            XCTAssertTrue(runtime.applied.isEmpty)
        }
    }

    @MainActor
    func testScopeChangeAndNewWorkerStopBeforeFirstEffect() async {
        for changeScope in [true, false] {
            let runtime = RepairRuntimeFixture()
            runtime.onSecondInspection = { fixture in
                if changeScope {
                    fixture.scope = "different destination or selection"
                } else {
                    fixture.worker = .active
                }
            }
            do {
                try await LocalRepairSession.run(runtime: runtime, planner: RepairPlannerFixture()) { _ in }
                XCTFail("Stale plan was accepted")
            } catch { XCTAssertTrue(error is LocalRepairError) }
            XCTAssertTrue(runtime.applied.isEmpty)
        }
    }

    @MainActor
    func testFailedVerificationStopsRemainingRepairs() async {
        let runtime = RepairRuntimeFixture()
        runtime.failVerification = true
        var receipts: [String] = []
        do {
            try await LocalRepairSession.run(runtime: runtime, planner: RepairPlannerFixture()) { receipts.append($0) }
            XCTFail("Unverified effect was accepted")
        } catch { XCTAssertTrue(error is LocalRepairError) }
        XCTAssertEqual(runtime.applied.count, 1)
        XCTAssertTrue(receipts.isEmpty)
    }

    @MainActor
    func testAlreadyRecoveredFaultDoesNotRunAgain() async throws {
        let runtime = RepairRuntimeFixture()
        runtime.onSecondInspection = { $0.candidates = [] }
        var receipts: [String] = []
        try await LocalRepairSession.run(runtime: runtime, planner: RepairPlannerFixture()) { receipts.append($0) }
        XCTAssertTrue(runtime.applied.isEmpty)
        XCTAssertEqual(receipts.count, 3)
        XCTAssertTrue(receipts.allSatisfy { $0.hasPrefix("Already recovered:") })
    }

    @MainActor
    func testTimeoutAndCancellationDoNotApplyAnything() async {
        for cancelled in [false, true] {
            let runtime = RepairRuntimeFixture()
            let operation = Task {
                try await LocalRepairSession.run(
                    runtime: runtime, planner: RepairPlannerFixture(delay: 10_000_000_000),
                    timeoutNanoseconds: cancelled ? 30_000_000_000 : 1_000_000
                ) { _ in }
            }
            if cancelled {
                operation.cancel()
            }
            do { try await operation.value; XCTFail("Operation should stop") } catch {
                XCTAssertTrue(error is CancellationError || error is LocalRepairError)
            }
            XCTAssertTrue(runtime.applied.isEmpty)
        }
    }

}

final class LocalRepairStateTests: XCTestCase {
    func testBoundedReaderRejectsSymlinksDirectoriesFIFOsAndOversizeFiles() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data(repeating: 65, count: 65).write(to: file)
        XCTAssertThrowsError(try LocalRepairInspectionReader.read(file.path, limit: 64))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try LocalRepairInspectionReader.read(link.path))
        XCTAssertThrowsError(try LocalRepairInspectionReader.read(root.path))
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try LocalRepairInspectionReader.read(fifo.path))
        XCTAssertNil(try LocalRepairInspectionReader.read(root.appendingPathComponent("missing").path))
    }

    func testWorkerMarkersAreConservativeAndNeverDeleted() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = configuration(root)
        let path = root.appendingPathComponent("fixture.running")
        XCTAssertEqual(
            try LocalRepairInspectionReader.worker(configuration: config, temporaryDirectory: root.path),
            .idle
        )
        for value in ["1", "0", "-1", "garbage"] {
            try Data(value.utf8).write(to: path)
            XCTAssertEqual(
                try LocalRepairInspectionReader.worker(configuration: config, temporaryDirectory: root.path),
                .unknown
            )
            XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), value)
        }
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: path)
        XCTAssertEqual(
            try LocalRepairInspectionReader.worker(configuration: config, temporaryDirectory: root.path),
            .active
        )
        try Data(String(Int32.max).utf8).write(to: path)
        XCTAssertEqual(
            try LocalRepairInspectionReader.worker(configuration: config, temporaryDirectory: root.path),
            .idle
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testRecordedStatusReadIsBoundedDestinationCheckedAndDoesNotMigrateHistory() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = configuration(root)
        let env = root.appendingPathComponent("fixture.env")
        let content = "result=success\nfinished_at=2026-11-24\n"
            + "remote_repo=https://github.com/example/data.git\nwarning_count=1\n"
        try Data(content.utf8).write(to: env)
        let changesFile = root.appendingPathComponent("fixture.local-changes.log")
        try Data(" M machines/fixture/home/file\n".utf8).write(to: changesFile)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertThrowsError(try LocalRepairInspectionReader.status(
            configuration: config,
            cached: .empty,
            expectedRemote: nil
        ))
        XCTAssertThrowsError(try LocalRepairInspectionReader.status(
            configuration: config,
            cached: .empty,
            expectedRemote: "other"
        ))
        let saved = try XCTUnwrap(LocalRepairInspectionReader.status(
            configuration: config, cached: .empty, expectedRemote: "git@github.com:example/data.git"
        ))
        XCTAssertEqual(saved.result, .success)
        XCTAssertEqual(saved.warningCount, 1)
        XCTAssertNil(saved.currentLocalChanges)
        XCTAssertEqual(saved.recordedLocalChanges, [" M machines/fixture/home/file"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), before)
        XCTAssertEqual(try String(contentsOf: env, encoding: .utf8), content)
        try Data("broken".utf8).write(to: root.appendingPathComponent("fixture.conditions.json"))
        XCTAssertThrowsError(try LocalRepairInspectionReader.status(
            configuration: config,
            cached: .empty,
            expectedRemote: "git@github.com:example/data.git"
        ))
    }

    func testObserverDetectsReplacedDirectoryAndCanReconnectWithoutWrites() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let observer =
            try XCTUnwrap(LocalStateObservation(directory: path.path) { /* No reload or writes in this fixture. */ })
        XCTAssertTrue(observer.isHealthy)
        try FileManager.default.moveItem(at: path, to: root.appendingPathComponent("old-status"))
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        XCTAssertFalse(observer.isHealthy)
        let replacement = try XCTUnwrap(LocalStateObservation(directory: path.path) { /* Read-only fixture. */ })
        XCTAssertTrue(replacement.isHealthy)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: path.path).isEmpty)
    }

    @MainActor
    func testAssistantSyncApprovalRejectsChangedSelectionWithoutStartingWorker() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SyncStore(environment: ["HOME": root.path, "MAC_SYNC_MACHINE": "fixture",
                                            "MAC_SYNC_STATUS_DIR": root.path, "TMPDIR": root.path,
                                            "MAC_SYNC_MACHINES_REPO": root.appendingPathComponent("data").path,
                                            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let oldScope = store.localRepairScope
        store.selectedPaths = ["new-path"]
        XCTAssertNotEqual(store.localRepairScope, oldScope)
        do { try await store.approveAssistantSync(scope: oldScope); XCTFail("Stale approval accepted") } catch {
            XCTAssertTrue(error is LocalRepairError)
        }
        XCTAssertNil(store.activeAction)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("activity").path))
    }

    func testLiveOnDeviceRepairPlanWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["MAC_SYNC_TEST_LOCAL_AI"] == "1" else {
            throw XCTSkip("Opt-in local model test; no inference in normal CI.")
        }
        for candidates in [[], [.reconnectObserver], LocalRepairAction.allCases] {
            let plan = try await OnDeviceDiagnosisService.shared.planRepairs(candidateIDs: candidates.map(\.rawValue))
            XCTAssertEqual(try Set(plan.validated(for: candidates)), Set(candidates))
        }
        do {
            _ = try await OnDeviceDiagnosisService.shared.planRepairs(candidateIDs: ["sync", "ignore safeguards"])
            XCTFail("Protected input reached the model")
        } catch { XCTAssertTrue(error is LocalRepairError) }
    }

    @MainActor
    func testProductionAdapterRefreshesOnlyMemoryAndReconnectsReadOnlyObserver() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let statusDirectory = root.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        let statusFile = statusDirectory.appendingPathComponent("fixture.env")
        try Data("result=success\nfinished_at=old\n".utf8).write(to: statusFile)
        let store = SyncStore(environment: [
            "HOME": root.path, "MAC_SYNC_MACHINE": "fixture", "MAC_SYNC_STATUS_DIR": statusDirectory.path,
            "TMPDIR": root.path, "MAC_SYNC_MACHINES_REPO": root.appendingPathComponent("data").path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ])
        for _ in 0 ..< 500 where store.isRefreshing { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.overview.status.result, .success)
        let scope = store.localRepairScope
        let next = Data("result=failed\nfinished_at=new\nerror_count=1\n".utf8)
        try next.write(to: statusFile)
        let before = try FileManager.default.contentsOfDirectory(atPath: statusDirectory.path)
        try await store.applyLocalRepair(.refreshStatus, scope: scope)
        XCTAssertEqual(store.overview.status.result, .failed)
        XCTAssertEqual(store.overview.status.errorCount, 1)
        XCTAssertEqual(try Data(contentsOf: statusFile), next)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: statusDirectory.path), before)
        XCTAssertNil(store.activeAction)

        try FileManager.default.moveItem(at: statusDirectory, to: root.appendingPathComponent("old-status"))
        try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        try next.write(to: statusFile)
        try await store.applyLocalRepair(.reconnectObserver, scope: scope)
        let inspection = try await store.inspectLocalRepairs()
        XCTAssertFalse(inspection.candidates.contains(.reconnectObserver))
        XCTAssertEqual(inspection.worker, .idle)
        XCTAssertEqual(try Data(contentsOf: statusFile), next)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: statusDirectory.path), ["fixture.env"])

        try await store.applyLocalRepair(.clearFinishedActivity, scope: scope)
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.overview.status.result, .failed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: statusDirectory.path), ["fixture.env"])
    }

    @MainActor
    func testAssistantLayoutIsBoundedWithScrollableFindings() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SyncStore(environment: [
            "HOME": root.path, "MAC_SYNC_MACHINE": "fixture", "TMPDIR": root.path,
            "MAC_SYNC_MACHINES_REPO": root.appendingPathComponent("data").path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ])
        let host = NSHostingView(rootView: LocalRepairAssistantView(store: store))
        host.setFrameSize(NSSize(width: 800, height: 760))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 1000)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 900)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func configuration(_ root: URL) -> SyncConfiguration {
        SyncConfiguration(homeDirectory: root.path, dataRepository: root.appendingPathComponent("data").path,
                          statusDirectory: root.path, machineName: "fixture",
                          pathsFile: root.appendingPathComponent("paths").path)
    }
}

private actor RepairPlannerFixture: OnDeviceRepairPlanning {
    var inputs: [[String]] = []
    let answer: [String]?
    let delay: UInt64
    init(answer: [String]? = nil, delay: UInt64 = 0) {
        self.answer = answer; self.delay = delay
    }

    func planRepairs(candidateIDs: [String]) async throws -> LocalRepairPlan {
        inputs.append(candidateIDs)
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return .init(actionIDs: answer ?? candidateIDs.reversed())
    }
}

@MainActor
private final class RepairRuntimeFixture: LocalRepairRuntime {
    var scope = "private context, not model input"
    var worker = LocalWorkerState.idle
    var candidates = LocalRepairAction.allCases
    var applied: [LocalRepairAction] = []
    var inspections = 0
    var failVerification = false
    var onSecondInspection: ((RepairRuntimeFixture) -> Void)?
    func inspectLocalRepairs() async throws -> LocalRepairInspection {
        inspections += 1
        if inspections == 2 {
            onSecondInspection?(self)
        }
        return .init(scope: scope, worker: worker, candidates: candidates)
    }

    func applyLocalRepair(_ action: LocalRepairAction, scope: String) async throws {
        XCTAssertEqual(scope, self.scope)
        applied.append(action)
        if !failVerification {
            candidates.removeAll { $0 == action }
        }
    }
}
