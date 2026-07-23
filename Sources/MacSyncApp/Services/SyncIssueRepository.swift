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
    }

    private struct Candidate {
        let id: String
        let severity: SyncIssueSeverity
        let message: String
        let recommendedAction: String
        let source: String
        let recordedAt: String
        let detail: String?
    }

    private let storageURL: URL
    private let fileManager: FileManager

    init(configuration: SyncConfiguration, fileManager: FileManager = .default) {
        storageURL = URL(fileURLWithPath: configuration.statusDirectory)
            .appendingPathComponent("issues")
            .appendingPathComponent("\(configuration.machineName).json")
        self.fileManager = fileManager
    }

    func issues(for overview: SyncOverview) -> [SyncIssue] {
        let states = readStates()
        return candidates(for: overview)
            .map { candidate in
                let state = states[candidate.id]
                return SyncIssue(
                    id: candidate.id,
                    severity: candidate.severity,
                    message: candidate.message,
                    recommendedAction: candidate.recommendedAction,
                    source: candidate.source,
                    recordedAt: candidate.recordedAt,
                    detail: candidate.detail,
                    disposition: state?.disposition ?? .open,
                    note: state?.note ?? "",
                    updatedAt: state?.updatedAt
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

    func update(issueID: String, disposition: SyncIssueDisposition, note: String) throws {
        var states = readStates()
        states[issueID] = PersistedState(
            disposition: disposition,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: Date()
        )
        try writeStates(states)
    }

    private func candidates(for overview: SyncOverview) -> [Candidate] {
        var result: [Candidate] = []
        let latestHistoryID = overview.history.first?.id

        for record in overview.history {
            let source = sourceDescription(for: record)
            for (index, message) in record.errors.enumerated() {
                result.append(candidate(
                    id: "history:\(record.id):error:\(index)",
                    severity: .error,
                    message: message,
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview
                ))
            }
            for (index, message) in record.warnings.enumerated() {
                guard shouldIncludeLocalChangesWarning(
                    message,
                    sourceRunID: record.id,
                    latestHistoryID: latestHistoryID,
                    overview: overview
                ) else {
                    continue
                }
                result.append(candidate(
                    id: "history:\(record.id):warning:\(index)",
                    severity: .warning,
                    message: message,
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview
                ))
            }
            if record.result == .failed, record.errors.isEmpty {
                result.append(candidate(
                    id: "history:\(record.id):error:result",
                    severity: .error,
                    message: "Sync did not complete. Review this run for the underlying cause.",
                    source: source,
                    recordedAt: record.finishedAt,
                    overview: overview
                ))
            }
        }

        if !latestHistoryMatchesCurrentStatus(overview) {
            let timestamp = overview.status.finishedAt ?? overview.status.startedAt ?? "latest"
            for (index, message) in overview.status.errors.enumerated() {
                result.append(candidate(
                    id: "status:\(timestamp):error:\(index)",
                    severity: .error,
                    message: message,
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview
                ))
            }
            for (index, message) in overview.status.warnings.enumerated() {
                guard shouldIncludeLocalChangesWarning(
                    message,
                    sourceRunID: nil,
                    latestHistoryID: latestHistoryID,
                    overview: overview
                ) else {
                    continue
                }
                result.append(candidate(
                    id: "status:\(timestamp):warning:\(index)",
                    severity: .warning,
                    message: message,
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview
                ))
            }
            if overview.status.result == .failed, overview.status.errors.isEmpty {
                result.append(candidate(
                    id: "status:\(timestamp):error:result",
                    severity: .error,
                    message: "Sync did not complete. Review the latest sync status for the underlying cause.",
                    source: "Latest sync status",
                    recordedAt: timestamp,
                    overview: overview
                ))
            }
        }

        return result
    }

    private func candidate(
        id: String,
        severity: SyncIssueSeverity,
        message: String,
        source: String,
        recordedAt: String,
        overview: SyncOverview
    ) -> Candidate {
        Candidate(
            id: id,
            severity: severity,
            message: message,
            recommendedAction: recommendedAction(for: message, severity: severity),
            source: source,
            recordedAt: recordedAt,
            detail: localChangesDetail(for: message, overview: overview)
        )
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
        overview: SyncOverview
    ) -> Bool {
        guard isLocalChangesWarning(message) else { return true }
        guard overview.status.currentLocalChanges?.isEmpty != true else { return false }
        return sourceRunID == nil || sourceRunID == latestHistoryID
    }

    private func isLocalChangesWarning(_ message: String) -> Bool {
        message.contains("current machine snapshot has local changes")
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
