import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

protocol OnDeviceDiagnosisGenerating: Sendable {
    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer
}

/// One user-requested, bounded session. No subprocess, tools, remote provider,
/// credentials or sync/recovery API is reachable from this service.
actor OnDeviceDiagnosisService: OnDeviceDiagnosisGenerating {
    static let shared = OnDeviceDiagnosisService()
    private var running = false

    func generate(evidence: LocalDiagnosisEvidence) async throws -> LocalDiagnosisAnswer {
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
