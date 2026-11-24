import Foundation

/// This is the entire automatic capability set. Model output cannot add capabilities.
enum LocalRepairAction: String, CaseIterable, Sendable {
    case refreshStatus, reconnectObserver, clearFinishedActivity

    var title: String {
        switch self {
        case .refreshStatus: "Refresh stale status in app memory"
        case .reconnectObserver: "Reconnect the local status observer"
        case .clearFinishedActivity: "Clear a finished operation's busy indicator"
        }
    }
}

enum LocalWorkerState: Sendable { case idle, active, unknown }

struct LocalRepairInspection: Sendable {
    // Private to the app. Never encoded in the model prompt.
    let scope: String
    let worker: LocalWorkerState
    let candidates: [LocalRepairAction]
}

struct LocalRepairReadState: Sendable {
    let worker: LocalWorkerState
    let status: SyncStatus?
    let scope: String
}

struct LocalRepairPlan: Codable, Sendable {
    let actionIDs: [String]

    func validated(for candidates: [LocalRepairAction]) throws -> [LocalRepairAction] {
        let expected = Set(candidates.map(\.rawValue))
        guard actionIDs.count == expected.count, Set(actionIDs) == expected else {
            throw LocalRepairError.invalidPlan
        }
        return try actionIDs.map {
            guard let action = LocalRepairAction(rawValue: $0) else { throw LocalRepairError.invalidPlan }
            return action
        }
    }
}

enum LocalRepairError: LocalizedError {
    case invalidPlan, changedScope, workerNotIdle, unreadableStatus, verificationFailed, timedOut

    var errorDescription: String? {
        switch self {
        case .invalidPlan: "The local AI returned an invalid repair plan. No proposed actions were run."
        case .changedScope: "The destination, selection or operation changed. Run the assistant again."
        case .workerNotIdle: "A worker is active, or its state cannot be verified. No further repairs were run."
        case .unreadableStatus: "Saved status cannot be read safely. No further repairs were run."
        case .verificationFailed: "The repair could not be verified. No further repairs were run."
        case .timedOut: "The local AI did not finish in time. No proposed actions were run."
        }
    }
}

protocol OnDeviceRepairPlanning: Sendable {
    func planRepairs(candidateIDs: [String]) async throws -> LocalRepairPlan
}

/// No sync, file-write, credential or security method is exposed to this executor.
@MainActor
protocol LocalRepairRuntime: AnyObject {
    func inspectLocalRepairs() async throws -> LocalRepairInspection
    func applyLocalRepair(_ action: LocalRepairAction, scope: String) async throws
}

@MainActor
enum LocalRepairSession {
    static func run(
        runtime: any LocalRepairRuntime,
        planner: any OnDeviceRepairPlanning,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        receipt: (String) -> Void
    ) async throws {
        let initial = try await runtime.inspectLocalRepairs()
        try Task.checkCancellation()
        guard initial.worker == .idle else { throw LocalRepairError.workerNotIdle }
        guard !initial.candidates.isEmpty else {
            receipt("No safe operational faults found. No AI repair request or changes were needed.")
            return
        }
        let plan = try await boundedPlan(planner, candidates: initial.candidates, timeout: timeoutNanoseconds)
        // Validate the WHOLE batch before the first effect. Never accept a valid prefix.
        let actions = try plan.validated(for: initial.candidates)
        for action in actions {
            try await repair(action, runtime: runtime, scope: initial.scope, receipt: receipt)
        }
        let final = try await checkedInspection(runtime, scope: initial.scope)
        guard final.candidates.isEmpty else { throw LocalRepairError.verificationFailed }
    }

    private static func repair(
        _ action: LocalRepairAction, runtime: any LocalRepairRuntime, scope: String, receipt: (String) -> Void
    ) async throws {
        let before = try await checkedInspection(runtime, scope: scope)
        guard before.candidates.contains(action) else {
            receipt("Already recovered: \(action.title).")
            return
        }
        try await runtime.applyLocalRepair(action, scope: scope)
        let after = try await checkedInspection(runtime, scope: scope)
        guard !after.candidates.contains(action) else { throw LocalRepairError.verificationFailed }
        receipt("Verified: \(action.title).")
    }

    private static func checkedInspection(
        _ runtime: any LocalRepairRuntime, scope: String
    ) async throws -> LocalRepairInspection {
        try Task.checkCancellation()
        let inspection = try await runtime.inspectLocalRepairs()
        try Task.checkCancellation()
        guard inspection.scope == scope else { throw LocalRepairError.changedScope }
        guard inspection.worker == .idle else { throw LocalRepairError.workerNotIdle }
        return inspection
    }

    private static func boundedPlan(
        _ planner: any OnDeviceRepairPlanning, candidates: [LocalRepairAction], timeout: UInt64
    ) async throws -> LocalRepairPlan {
        try await withThrowingTaskGroup(of: LocalRepairPlan.self) { group in
            group.addTask { try await planner.planRepairs(candidateIDs: candidates.map(\.rawValue)) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw LocalRepairError.timedOut
            }
            defer { group.cancelAll() }
            guard let plan = try await group.next() else { throw LocalRepairError.invalidPlan }
            try Task.checkCancellation()
            return plan
        }
    }
}
