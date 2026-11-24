import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

protocol OnDeviceDiagnosisGenerating: Sendable {
    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer
}

/// One user-requested, bounded session. No subprocess, tools, remote provider,
/// credentials or sync/recovery API is reachable from this service.
actor OnDeviceDiagnosisService: OnDeviceDiagnosisGenerating, OnDeviceRepairPlanning {
    static let shared = OnDeviceDiagnosisService()
    private var running = false

    func planRepairs(candidateIDs: [String]) async throws -> LocalRepairPlan {
        try Task.checkCancellation()
        let input = LocalRepairPlan(actionIDs: candidateIDs)
        let candidates = candidateIDs.compactMap(LocalRepairAction.init(rawValue:))
        _ = try input.validated(for: candidates)
        guard !candidateIDs.isEmpty else { return input }
        guard !running else { throw LocalDiagnosisError.busy }
        running = true
        defer { running = false }
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let model = SystemLanguageModel.default
                guard case .available = model.availability else { throw LocalDiagnosisError.notReady }
                let session = LanguageModelSession(model: model, instructions: """
                Order the supplied verified Mac Sync operational repair IDs. Return each ID exactly once.
                The app has already verified these faults. Do not invent, omit or duplicate an ID.
                refreshStatus updates app memory only. reconnectObserver replaces a read-only status observer.
                clearFinishedActivity clears app memory only after its process has exited.
                No sync, file changes, conflict decisions, credentials or security changes are permitted.
                You have no tools. Return only actionIDs. The app independently rechecks and verifies each repair.
                """)
                #if compiler(>=6.4)
                    let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256)
                #else
                    let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 256)
                #endif
                guard let prompt = String(data: try JSONEncoder().encode(candidateIDs), encoding: .utf8) else {
                    throw LocalRepairError.invalidPlan
                }
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedLocalRepairPlan.self,
                    options: options
                )
                try Task.checkCancellation()
                return .init(actionIDs: response.content.actionIDs)
            }
        #endif
        throw LocalDiagnosisError.unsupportedOS
    }

    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
        try Task.checkCancellation()
        guard evidence.requiresModelOrdering else {
            return .init(
                runResult: evidence.runResult, totalReviewItems: evidence.totalReviewItems,
                pendingDeletions: evidence.pendingDeletions, orderedFindingIDs: evidence.requiredFindingIDs
            )
        }
        guard !running else { throw LocalDiagnosisError.busy }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return try await generateLocally(evidence)
            }
        #endif
        throw LocalDiagnosisError.unsupportedOS
    }

    #if canImport(FoundationModels)
        @available(macOS 26.0, *)
        private func generateLocally(_ evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: break
            case .unavailable(.deviceNotEligible): throw LocalDiagnosisError.deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): throw LocalDiagnosisError.notEnabled
            case .unavailable: throw LocalDiagnosisError.notReady
            }
            let session = LanguageModelSession(model: model, instructions: """
            Organise a read-only Mac Sync diagnosis from the supplied structured evidence.
            Copy runResult, totalReviewItems and pendingDeletions exactly. When a count is absent, return null for it.
            Order every ID in requiredFindingIDs once, most important first. Never invent or omit an ID.
            Include normal and zero-count findings too. The deletions ID is REQUIRED even when pendingDeletions is zero.
            Your orderedFindingIDs array must be a complete permutation of requiredFindingIDs, not a shortlist.
            The inventory counts are authoritative. Review items are not necessarily deletions.
            Generic warning wording and absent paths do not establish deletions.
            Recorded causes and unknowns are separate. Missing edit history is not a recorded cause.
            Unknown and empty review inventories are handled by the app without an AI request.
            The app supplies a separate, fixed-order safety checklist. Never invent repair advice or file choices.
            Saved publication success is not a live connectivity test. Unconfirmed cloud upload is not a failure.
            Do not propose or perform actions. There are no tools and no cloud fallback.
            """)
            // CodeQL still uses Xcode 26; match each SDK's public spelling.
            #if compiler(>=6.4)
                let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 768)
            #else
                let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 768)
            #endif
            let response = try await session.respond(
                to: evidence.prompt(), generating: GeneratedLocalDiagnosis.self,
                options: options
            )
            try Task.checkCancellation()
            let value = response.content
            return LocalDiagnosisAnswer(
                runResult: value.runResult,
                totalReviewItems: value.totalReviewItems,
                pendingDeletions: value.pendingDeletions,
                orderedFindingIDs: value.orderedFindingIDs
            )
        }
    #endif
}

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    private struct GeneratedLocalRepairPlan {
        @Guide(description: "A complete permutation of the supplied repair IDs. No new IDs.")
        var actionIDs: [String]
    }

    @available(macOS 26.0, *)
    @Generable
    private struct GeneratedLocalDiagnosis {
        @Guide(description: "Copy the input runResult exactly.")
        var runResult: String
        @Guide(description: "Copy totalReviewItems from the input. Null if absent.")
        var totalReviewItems: Int?
        @Guide(description: "Copy pendingDeletions, not totalReviewItems. Null if absent.")
        var pendingDeletions: Int?
        @Guide(description: "All requiredFindingIDs once, including zero-count findings. Do not shortlist.")
        var orderedFindingIDs: [String]
    }
#endif
