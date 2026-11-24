import Foundation
import MacSyncCore

enum LocalDiagnosisSession {
    static func run(
        evidence: LocalDiagnosisEvidence,
        generator: any OnDeviceDiagnosisGenerating,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) async throws -> [LocalDiagnosisFinding] {
        try Task.checkCancellation()
        // Do not ask a model to invent counts or work for an empty queue.
        guard evidence.requiresModelOrdering else { return evidence.findings }
        return try await withThrowingTaskGroup(of: LocalDiagnosisAnswer.self) { group in
            group.addTask { try await generator.generate(evidence: evidence) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LocalDiagnosisError.timedOut
            }
            defer { group.cancelAll() }
            guard let answer = try await group.next() else { throw LocalDiagnosisError.failed }
            try Task.checkCancellation()
            return try evidence.validatedFindings(answer)
        }
    }
}

@MainActor
final class LocalDiagnosisController: ObservableObject {
    @Published private(set) var evidence: LocalDiagnosisEvidence?
    @Published private(set) var orderedFindings: [LocalDiagnosisFinding]?
    @Published private(set) var message: String?
    @Published private(set) var isRunning = false
    @Published private(set) var capturedAt: Date?
    @Published private(set) var recordedRunFinishedAt: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private let generator: any OnDeviceDiagnosisGenerating

    var usedModel: Bool {
        orderedFindings != nil && evidence?.requiresModelOrdering == true
    }

    init(generator: any OnDeviceDiagnosisGenerating = OnDeviceDiagnosisService.shared) {
        self.generator = generator
    }

    func start(overview: SyncOverview) {
        guard !isRunning else { return }
        generation += 1
        let expectedGeneration = generation
        let configuration = overview.configuration
        let status = overview.status
        orderedFindings = nil
        evidence = nil
        message = nil
        capturedAt = nil
        recordedRunFinishedAt = nil
        isRunning = true
        task = Task {
            do {
                let inventory = try await Self.readInventory(configuration)
                try Task.checkCancellation()
                guard generation == expectedGeneration else { return }
                let facts = LocalDiagnosisEvidence(
                    status: status,
                    storageKind: configuration.storageKind,
                    inventory: inventory
                )
                evidence = facts
                capturedAt = Date()
                recordedRunFinishedAt = status.finishedAt
                let findings = try await LocalDiagnosisSession.run(evidence: facts, generator: generator)
                guard generation == expectedGeneration, !Task.isCancelled else { return }
                orderedFindings = findings
            } catch is CancellationError {
                // Dismissal and cancellation never apply partial model output.
            } catch let error as LocalDiagnosisError {
                if generation == expectedGeneration {
                    message = error.localizedDescription
                }
            } catch {
                if generation == expectedGeneration {
                    if evidence == nil {
                        recordUnavailableInventory(status: status, storageKind: configuration.storageKind)
                    } else {
                        message = LocalDiagnosisError.failed.localizedDescription
                    }
                }
            }
            guard generation == expectedGeneration else { return }
            isRunning = false
            task = nil
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isRunning = false
        message = "Diagnosis cancelled. Nothing was changed."
    }

    private static func readInventory(_ configuration: SyncConfiguration) async throws -> IncomingReviewInventory? {
        let reader = Task.detached(priority: .utility) {
            try IncomingSyncEngine.reviewInventory(
                repository: configuration.dataRepository,
                status: configuration.statusDirectory,
                machine: configuration.machineName
            ) {
                try Task.checkCancellation()
            }
        }
        return try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: { reader.cancel() }
    }

    private func recordUnavailableInventory(status: SyncStatus, storageKind: BackupStorageKind) {
        let facts = LocalDiagnosisEvidence(status: status, storageKind: storageKind, inventory: nil)
        evidence = facts
        orderedFindings = facts.findings
        capturedAt = Date()
        recordedRunFinishedAt = status.finishedAt
        message = """
        The review ledger could not be read safely. Counts remain unknown. \
        No AI request was made and nothing was changed.
        """
    }
}
