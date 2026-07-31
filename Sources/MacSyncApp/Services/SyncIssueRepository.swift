import Foundation
import MacSyncCore

/// Keeps local manual-triage decisions separate from sync history. The source
/// history remains append-only, so a scheduled CLI sync can continue without
/// waiting for the app or changing a user's triage decisions.
struct SyncIssueRepository {
    private struct PersistedState: Codable {
        let disposition: SyncIssueDisposition
        let note: String
        let updatedAt: Date
        let latestOccurrenceID: String?
    }

    private struct Candidate {
        let occurrenceID: String
        let conditionCode: SyncHealthConditionCode?
        let severity: SyncIssueSeverity
        let message: String
        let recommendedAction: String
        let source: String
        let recordedAt: String
        let detail: String?
        let recoveryActions: [SyncIssueRecoveryAction]
        let isActive: Bool
    }

    private struct CandidateActivity {
        let isLatestRun: Bool
        let activeConditionCodes: Set<SyncHealthConditionCode>?
    }

    private struct GroupedCandidate {
        let id: String
        let conditionCode: SyncHealthConditionCode?
        let severity: SyncIssueSeverity
        let message: String
        let recommendedAction: String
        let source: String
        let recordedAt: String
        let firstRecordedAt: String
        let occurrenceCount: Int
        let latestOccurrenceID: String
        let detail: String?
        let recoveryActions: [SyncIssueRecoveryAction]
        let isActive: Bool
    }

    private let storageURL: URL
    private let fileManager: FileManager

    init(configuration: SyncConfiguration, fileManager: FileManager = .default) {
        storageURL = URL(fileURLWithPath: configuration.statusDirectory)
            .appendingPathComponent("issues")
            .appendingPathComponent("\(configuration.machineName).json")
        self.fileManager = fileManager
    }

    func issues(
        for overview: SyncOverview,
        activeConditionCodes: Set<SyncHealthConditionCode>? = nil,
    ) -> [SyncIssue] {
        let states = readStates()
        return groupedCandidates(for: overview, activeConditionCodes: activeConditionCodes)
            .map { candidate in
                let state = states[candidate.id] ?? states[candidate.latestOccurrenceID]
                let stateAppliesToLatestOccurrence = state?.latestOccurrenceID == nil
                    || state?.latestOccurrenceID == candidate.latestOccurrenceID
                return SyncIssue(
                    id: candidate.id,
                    conditionCode: candidate.conditionCode,
                    severity: candidate.severity,
                    message: candidate.message,
                    recommendedAction: candidate.recommendedAction,
                    source: candidate.source,
                    recordedAt: candidate.recordedAt,
                    firstRecordedAt: candidate.firstRecordedAt,
                    occurrenceCount: candidate.occurrenceCount,
                    latestOccurrenceID: candidate.latestOccurrenceID,
                    detail: candidate.detail,
                    recoveryActions: candidate.recoveryActions,
                    isActive: candidate.isActive,
                    disposition: stateAppliesToLatestOccurrence ? state?.disposition ?? .open : .open,
                    note: state?.note ?? "",
                    updatedAt: state?.updatedAt,
                )
            }
            .sorted { left, right in
                if left.requiresManualIntervention != right.requiresManualIntervention {
                    return left.requiresManualIntervention
                }
                if left.severity != right.severity {
                    return left.severity == .error
                }
                return left.recordedAt > right.recordedAt
            }
    }

    func update(
        issueID: String,
        latestOccurrenceID: String,
        disposition: SyncIssueDisposition,
        note: String,
    ) throws {
        var states = readStates()
        states[issueID] = PersistedState(
            disposition: disposition,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: Date(),
            latestOccurrenceID: latestOccurrenceID,
        )
        try writeStates(states)
    }

    private func groupedCandidates(
        for overview: SyncOverview,
        activeConditionCodes: Set<SyncHealthConditionCode>?,
    ) -> [GroupedCandidate] {
        Dictionary(
            grouping: candidates(for: overview, activeConditionCodes: activeConditionCodes),
            by: conditionKey,
        )
        .compactMap { _, occurrences in
            let ordered = occurrences.sorted { $0.recordedAt > $1.recordedAt }
            guard let latest = ordered.first, let first = ordered.last else { return nil }
            return GroupedCandidate(
                id: conditionID(for: latest),
                conditionCode: latest.conditionCode,
                severity: latest.severity,
                message: latest.message,
                recommendedAction: latest.recommendedAction,
                source: latest.source,
                recordedAt: latest.recordedAt,
                firstRecordedAt: first.recordedAt,
                occurrenceCount: ordered.count,
                latestOccurrenceID: latest.occurrenceID,
                detail: latest.detail,
                recoveryActions: latest.recoveryActions,
                isActive: occurrences.contains(where: \.isActive),
            )
        }
    }

    private func conditionKey(for candidate: Candidate) -> String {
        if let conditionCode = candidate.conditionCode {
            return "condition\u{0}\(conditionCode.rawValue)"
        }
        return "\(candidate.severity.rawValue)\u{0}\(candidate.message)"
    }

    private func conditionID(for candidate: Candidate) -> String {
        let encoded = Data(conditionKey(for: candidate).utf8).base64EncodedString()
        return "condition:\(encoded)"
    }

    private func candidates(
        for overview: SyncOverview,
        activeConditionCodes: Set<SyncHealthConditionCode>?,
    ) -> [Candidate] {
        var result: [Candidate] = []
        let latestHistoryID = overview.history.first?.id

        for record in overview.history {
            let source = sourceDescription(for: record)
            if let conditions = record.conditions, !conditions.isEmpty {
                for condition in conditions {
                    result.append(candidate(
                        condition: condition,
                        id: "history:\(record.id):condition:\(condition.id)",
                        source: source,
                        recordedAt: record.finishedAt,
                        activity: CandidateActivity(
                            isLatestRun: record.id == latestHistoryID,
                            activeConditionCodes: activeConditionCodes,
                        ),
                    ))
                }
                continue
            }
            for (index, message) in record.errors.enumerated() {
                result.append(candidate(
                    id: "history:\(record.id):error:\(index)",
                    severity: .error,
                    message: message,
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: record.id == latestHistoryID,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
            for (index, message) in record.warnings.enumerated() {
                guard shouldIncludeLocalChangesWarning(
                    message,
                    sourceRunID: record.id,
                    latestHistoryID: latestHistoryID,
                    overview: overview,
                ) else {
                    continue
                }
                result.append(candidate(
                    id: "history:\(record.id):warning:\(index)",
                    severity: .warning,
                    message: message,
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: record.id == latestHistoryID,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
            if record.result == .failed, record.errors.isEmpty {
                result.append(candidate(
                    id: "history:\(record.id):error:result",
                    severity: .error,
                    message: "Sync did not complete. Review this run for the underlying cause.",
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: record.id == latestHistoryID,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
        }

        if !latestHistoryMatchesCurrentStatus(overview) {
            let timestamp = overview.status.finishedAt ?? overview.status.startedAt ?? "latest"
            if !overview.status.conditions.isEmpty {
                for condition in overview.status.conditions {
                    result.append(candidate(
                        condition: condition,
                        id: "status:\(timestamp):condition:\(condition.id)",
                        source: "Latest sync status",
                        recordedAt: timestamp,
                        activity: CandidateActivity(
                            isLatestRun: true,
                            activeConditionCodes: activeConditionCodes,
                        ),
                    ))
                }
                return result
            }
            for (index, message) in overview.status.errors.enumerated() {
                result.append(candidate(
                    id: "status:\(timestamp):error:\(index)",
                    severity: .error,
                    message: message,
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: true,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
            for (index, message) in overview.status.warnings.enumerated() {
                guard shouldIncludeLocalChangesWarning(
                    message,
                    sourceRunID: nil,
                    latestHistoryID: latestHistoryID,
                    overview: overview,
                ) else {
                    continue
                }
                result.append(candidate(
                    id: "status:\(timestamp):warning:\(index)",
                    severity: .warning,
                    message: message,
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: true,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
            if overview.status.result == .failed, overview.status.errors.isEmpty {
                result.append(candidate(
                    id: "status:\(timestamp):error:result",
                    severity: .error,
                    message: "Sync did not complete. Review the latest sync status for the underlying cause.",
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview,
                    activity: CandidateActivity(
                        isLatestRun: true,
                        activeConditionCodes: activeConditionCodes,
                    ),
                ))
            }
        }

        return result
    }

    private func candidate(
        condition: SyncHealthCondition,
        id: String,
        source: String,
        recordedAt: String,
        activity: CandidateActivity,
    ) -> Candidate {
        Candidate(
            occurrenceID: id,
            conditionCode: condition.code,
            severity: condition.severity == .error ? .error : .warning,
            message: condition.title,
            recommendedAction: condition.recovery,
            source: source,
            recordedAt: recordedAt,
            detail: condition.detail,
            recoveryActions: recoveryActions(for: condition.code),
            isActive: activity.isLatestRun
                && (activity.activeConditionCodes?.contains(condition.code) ?? true),
        )
    }

    private func candidate(
        id: String,
        severity: SyncIssueSeverity,
        message: String,
        source: String,
        recordedAt: String,
        overview: SyncOverview,
        activity: CandidateActivity,
    ) -> Candidate {
        let conditionCode = legacyConditionCode(for: message)
        let conditionIsActive = conditionCode.map {
            activity.activeConditionCodes?.contains($0) ?? true
        } ?? true
        return Candidate(
            occurrenceID: id,
            conditionCode: conditionCode,
            severity: severity,
            message: message,
            recommendedAction: recommendedAction(for: message, severity: severity),
            source: source,
            recordedAt: recordedAt,
            detail: localChangesDetail(for: message, overview: overview),
            recoveryActions: conditionCode.map { recoveryActions(for: $0) } ?? [.retrySync],
            isActive: activity.isLatestRun && conditionIsActive,
        )
    }

    private func legacyConditionCode(for message: String) -> SyncHealthConditionCode? {
        if isLocalChangesWarning(message) {
            return .remoteRefreshBlockedByLocalChanges
        }
        if message.contains("could not pull machines repo") {
            return .remoteRefreshFailed
        }
        if message.contains("missing local Keychain age identity")
            || message.contains("no local Keychain age identity")
        {
            return .encryptedSecretsIdentityMissing
        }
        if message.contains("Keychain age identity requires user interaction")
            || message.contains("Keychain age identity is unavailable")
        {
            return .encryptedSecretsIdentityUnavailable
        }
        if message.contains("encrypted-secrets tools are unavailable")
            || message.contains("age, age-keygen, gzip, or gtar not found")
        {
            return .encryptedSecretsRuntimeUnavailable
        }
        if message.contains("encrypted secrets snapshot cannot be decrypted") {
            return .encryptedSecretsSnapshotSkipped
        }
        return nil
    }

    private func recoveryActions(
        for code: SyncHealthConditionCode,
    ) -> [SyncIssueRecoveryAction] {
        switch code {
        case .remoteAuthenticationFailed, .remoteRefreshFailed, .remoteUnavailable:
            [.testGitHubAccess, .useSSH, .retrySync]
        case .remoteConfigurationMissing:
            [.testGitHubAccess]
        case .remoteRefreshBlockedByLocalChanges:
            [.testGitHubAccess, .retrySync]
        case .encryptedSecretsIdentityMissing:
            [.testEncryptedSecrets, .openKeychainAccess, .retrySync]
        case .encryptedSecretsIdentityUntrusted,
             .encryptedSecretsIdentityUnavailable,
             .encryptedSecretsSnapshotSkipped:
            [.testEncryptedSecrets, .openKeychainAccess, .retrySync]
        case .encryptedSecretsRuntimeUnavailable:
            [.testEncryptedSecrets, .retrySync]
        }
    }

    private func latestHistoryMatchesCurrentStatus(_ overview: SyncOverview) -> Bool {
        guard let finishedAt = overview.status.finishedAt else { return false }
        return overview.history.contains {
            $0.finishedAt == finishedAt
                && $0.warnings == overview.status.warnings
                && $0.errors == overview.status.errors
        }
    }

    private func shouldIncludeLocalChangesWarning(
        _ message: String,
        sourceRunID: String?,
        latestHistoryID: String?,
        overview: SyncOverview,
    ) -> Bool {
        guard isLocalChangesWarning(message) else { return true }
        guard overview.status.currentLocalChanges?.isEmpty != true else { return false }
        return sourceRunID == nil || sourceRunID == latestHistoryID
    }

    private func isLocalChangesWarning(_ message: String) -> Bool {
        message.contains("current machine snapshot has local changes")
            || message.contains("local repo has local changes")
    }

    private func localChangesDetail(for message: String, overview: SyncOverview) -> String? {
        guard isLocalChangesWarning(message) else { return nil }
        let changes = overview.status.currentLocalChanges ?? overview.status.recordedLocalChanges
        guard !changes.isEmpty else { return nil }
        return "Snapshot changes:\n\(changes.joined(separator: "\n"))"
    }

    private func recommendedAction(for message: String, severity: SyncIssueSeverity) -> String {
        if isLocalChangesWarning(message) {
            return "Review the listed Git changes in mac-sync-data, then commit or revert them outside Mac Sync. Syncs continue and publish this Mac's selected files, but the pre-sync pull stays paused until the checkout is clean."
        }
        if severity == .error {
            return "Review Sync History and the command activity, fix the external condition, then let the next scheduled sync retry or run Sync Now."
        }
        return "Review this warning and resolve the condition outside Mac Sync if needed. Acknowledge it when you have triaged it to clear the Dock badge."
    }

    private func sourceDescription(for record: SyncHistoryRecord) -> String {
        switch record.action {
        case .sync:
            "Sync this Mac"
        case .restore:
            if let sourceMachine = record.sourceMachine {
                "Copy from \(sourceMachine)"
            } else {
                "Copy to this Mac"
            }
        }
    }

    private func readStates() -> [String: PersistedState] {
        guard let data = try? Data(contentsOf: storageURL),
              let states = try? JSONDecoder().decode([String: PersistedState].self, from: data)
        else {
            return [:]
        }
        return states
    }

    private func writeStates(_ states: [String: PersistedState]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(states).write(to: storageURL, options: .atomic)
    }
}
