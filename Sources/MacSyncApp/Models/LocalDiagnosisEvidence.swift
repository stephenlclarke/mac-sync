import Foundation
import MacSyncCore

struct LocalDiagnosisFinding: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct LocalDiagnosisEvidence: Encodable, Equatable, Sendable {
    enum ReviewState: String, Encodable, Sendable {
        case unknown, empty, pending
    }

    let runResult: String
    let warningCount: Int
    let errorCount: Int
    let publishExitStatus: Int32?
    let storageKind: BackupStorageKind
    let inventory: IncomingReviewInventory?
    let totalReviewItems: Int?
    let pendingDeletions: Int?
    let findings: [LocalDiagnosisFinding]
    let requiredFindingIDs: [String]
    let reviewState: ReviewState
    /// Advice is deliberately not model-generated or included in its schema.
    let advice: LocalDiagnosisAdvice

    var requiresModelOrdering: Bool {
        reviewState == .pending
    }

    init(status: SyncStatus, storageKind: BackupStorageKind, inventory: IncomingReviewInventory?) {
        runResult = status.result.rawValue
        warningCount = max(0, status.warningCount)
        errorCount = max(0, status.errorCount)
        publishExitStatus = status.commandDiagnostics.last { $0.step == "Publishing the data repository" }?.exitStatus
        self.storageKind = storageKind
        self.inventory = inventory
        totalReviewItems = inventory?.total
        pendingDeletions = inventory?.deletions
        reviewState = inventory.map { $0.total == 0 ? .empty : .pending } ?? .unknown
        advice = LocalDiagnosisAdvice(
            status: status, storageKind: storageKind, inventory: inventory, publishExitStatus: publishExitStatus
        )
        findings = Self.runFindings(status: status, storageKind: storageKind, publishExitStatus: publishExitStatus)
            + Self.reviewFindings(inventory)
            + Self.messageFindings(warnings: warningCount, errors: errorCount)
            + Set(status.conditions.map(\.code)).sorted(by: { $0.rawValue < $1.rawValue }).map { code in
                LocalDiagnosisFinding(
                    id: "condition_\(code.rawValue)", title: "Recorded: \(Self.conditionTitle(code))",
                    detail: "Saved condition, not a live check. Diagnosis does not probe the network or Keychain."
                )
            }
        requiredFindingIDs = findings.map(\.id)
    }

    private static func runFindings(
        status: SyncStatus, storageKind: BackupStorageKind, publishExitStatus: Int32?
    ) -> [LocalDiagnosisFinding] {
        var items = [LocalDiagnosisFinding(
            id: "run_\(status.result.rawValue)",
            title: "Last recorded run: \(status.result.title)",
            detail: "This is the saved run result, not a live connectivity check."
        )]
        if storageKind == .cloudFolder {
            items.append(.init(
                id: "folder_upload_unverified",
                title: "Cloud upload is not verified",
                detail: "A cloud-folder save does not confirm that the provider uploaded it."
            ))
        } else if let publishExitStatus {
            items.append(.init(
                id: "publish_command",
                title: publishExitStatus == 0 ? "Git publish command succeeded" : "Git publish command failed",
                detail: "Saved publish exit status: \(publishExitStatus). This is not a live connectivity check."
            ))
        } else {
            items.append(.init(
                id: "publish_unknown",
                title: "No publish result is recorded",
                detail: "The available records do not establish a successful upload."
            ))
        }
        return items
    }

    private static func reviewFindings(_ inventory: IncomingReviewInventory?) -> [LocalDiagnosisFinding] {
        guard let inventory else {
            return [.init(
                id: "inventory_unknown",
                title: "Incoming review counts are unavailable",
                detail: """
                The review ledger is missing or unreadable for this destination and Mac identifier. All \
                review counts, including deletions, are unknown, not zero.
                """
            )]
        }
        var items = [LocalDiagnosisFinding(
            id: "deletions", title: "\(inventory.deletions) pending deletions",
            detail: inventory.deletions == 0
                ? """
                No review entry is marked as a deletion. Generic warnings and absent paths are not deletion \
                records.
                """
                : "These entries are marked as deletions. They still require a separate user decision."
        )]
        if inventory.total == 0 {
            items.append(.init(
                id: "no_pending_review", title: "No incoming items are pending review",
                detail: "The current review ledger is empty. Older warnings can remain in history."
            ))
        }
        let categories: [(count: Int, finding: LocalDiagnosisFinding)] = [
            (inventory.conflicts, .init(
                id: "file_conflicts", title: "\(inventory.conflicts) file-version conflicts",
                detail: "Recorded reason: both Macs changed this file. No version was selected by this diagnosis."
            )),
            (inventory.pathOrLink, .init(
                id: "path_or_link", title: "\(inventory.pathOrLink) path or symbolic-link review items",
                detail: "The path changed, is linked, or needs file/folder replacement. The precise check is unknown."
            )),
            (inventory.reviewPolicy, .init(
                id: "review_policy", title: "\(inventory.reviewPolicy) items held by review-only policy",
                detail: "The saved incoming policy requires review before these changes are applied."
            )),
            (inventory.other, .init(
                id: "other_review", title: "\(inventory.other) other incoming review items",
                detail: "The recorded reason is not a recognised diagnosis category. No cause is inferred."
            ))
        ]
        return items + categories.filter { $0.count > 0 }.map(\.finding)
    }

    private static func messageFindings(warnings: Int, errors: Int) -> [LocalDiagnosisFinding] {
        guard warnings > 0 || errors > 0 else { return [] }
        return [.init(
            id: "recorded_messages", title: "\(warnings) recorded warnings, \(errors) recorded errors",
            detail: "Raw messages are not sent to the model. Review Sync Health and Sync History for their full text."
        )]
    }

    func prompt() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let value = try String(data: encoder.encode(self), encoding: .utf8) else {
            throw LocalDiagnosisError.failed
        }
        return value
    }

    /// Explicit nulls preserve unknown counts in the wire format as well as UI.
    private enum CodingKeys: String, CodingKey {
        case runResult, warningCount, errorCount, publishExitStatus, storageKind
        case inventory, totalReviewItems, pendingDeletions, findings, requiredFindingIDs, reviewState
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(runResult, forKey: .runResult)
        try values.encode(warningCount, forKey: .warningCount)
        try values.encode(errorCount, forKey: .errorCount)
        try values.encode(publishExitStatus, forKey: .publishExitStatus)
        try values.encode(storageKind, forKey: .storageKind)
        try values.encode(inventory, forKey: .inventory)
        try values.encode(totalReviewItems, forKey: .totalReviewItems)
        try values.encode(pendingDeletions, forKey: .pendingDeletions)
        try values.encode(findings, forKey: .findings)
        try values.encode(requiredFindingIDs, forKey: .requiredFindingIDs)
        try values.encode(reviewState, forKey: .reviewState)
    }

    func validatedFindings(_ answer: LocalDiagnosisAnswer) throws -> [LocalDiagnosisFinding] {
        guard answer.runResult == runResult,
              answer.totalReviewItems == inventory?.total,
              answer.pendingDeletions == inventory?.deletions,
              answer.orderedFindingIDs.count == findings.count,
              Set(answer.orderedFindingIDs) == Set(findings.map(\.id))
        else { throw LocalDiagnosisError.inconsistentAnswer }
        let byID = Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) })
        return answer.orderedFindingIDs.compactMap { byID[$0] }
    }

    private static func conditionTitle(_ code: SyncHealthConditionCode) -> String {
        switch code {
        case .remoteAuthenticationFailed: "repository authentication failed"
        case .remoteConfigurationMissing: "repository configuration needs attention"
        case .remoteRefreshFailed: "repository refresh failed"
        case .remoteRefreshBlockedByLocalChanges: "local repository changes blocked refresh"
        case .remoteUnavailable: "the remote destination was unavailable"
        case .encryptedSecretsIdentityMissing: "the encrypted-secrets identity was missing"
        case .encryptedSecretsIdentityUntrusted: "the encrypted-secrets identity was not trusted"
        case .encryptedSecretsIdentityUnavailable: "the encrypted-secrets identity was unavailable"
        case .encryptedSecretsRuntimeUnavailable: "encrypted-secrets tools were unavailable"
        case .encryptedSecretsSnapshotSkipped: "the encrypted-secrets snapshot was skipped"
        }
    }
}

struct LocalDiagnosisAnswer: Equatable, Sendable {
    let runResult: String
    let totalReviewItems: Int?
    let pendingDeletions: Int?
    let orderedFindingIDs: [String]
}

enum LocalDiagnosisError: LocalizedError, Equatable {
    case unsupportedOS, deviceNotEligible, notEnabled, notReady, busy, timedOut, inconsistentAnswer, failed

    var errorDescription: String? {
        switch self {
        case .unsupportedOS: "On-device diagnosis requires macOS 26 or later. Verified records remain available below."
        case .deviceNotEligible: "This Mac does not support Apple's on-device model. There is no cloud fallback."
        case .notEnabled: "Enable Apple Intelligence in System Settings to use its on-device model."
        case .notReady: "Apple's local model is not ready. macOS may need to prepare it. No cloud model was used."
        case .busy: "An on-device diagnosis is already running. Wait for it to finish."
        case .timedOut: "The on-device diagnosis took too long. Verified records are shown below."
        case .inconsistentAnswer:
            "The AI answer disagreed with the records and was discarded. Verified records are shown."
        case .failed: "The on-device diagnosis failed. No cloud model was used. Only verified records are shown."
        }
    }
}
