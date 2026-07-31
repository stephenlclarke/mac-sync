import Foundation
import MacSyncCore

enum SyncIssueSeverity: String, Codable, Hashable {
    case warning
    case error

    var title: String {
        switch self {
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .warning:
            "exclamationmark.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }
}

enum SyncIssueDisposition: String, Codable, Hashable {
    case open
    case acknowledged
    case resolved

    var title: String {
        switch self {
        case .open:
            "Needs attention"
        case .acknowledged:
            "Acknowledged"
        case .resolved:
            "Resolved"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            "exclamationmark.circle.fill"
        case .acknowledged:
            "eye.fill"
        case .resolved:
            "checkmark.circle.fill"
        }
    }
}

enum SyncIssueRecoveryAction: String, CaseIterable, Hashable, Identifiable {
    case retrySync
    case testGitHubAccess
    case useSSH
    case testEncryptedSecrets
    case openKeychainAccess

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .retrySync:
            "Retry Sync"
        case .testGitHubAccess:
            "Test GitHub Access"
        case .useSSH:
            "Use SSH"
        case .testEncryptedSecrets:
            "Test Encrypted Secrets"
        case .openKeychainAccess:
            "Open Keychain Access"
        }
    }

    var systemImage: String {
        switch self {
        case .retrySync:
            "arrow.clockwise"
        case .testGitHubAccess:
            "network"
        case .useSSH:
            "key.horizontal"
        case .testEncryptedSecrets:
            "lock.shield"
        case .openKeychainAccess:
            "key"
        }
    }
}

struct SyncIssue: Identifiable, Equatable {
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
    let disposition: SyncIssueDisposition
    let note: String
    let updatedAt: Date?

    var requiresManualIntervention: Bool {
        isActive && disposition == .open
    }

    var dispositionTitle: String {
        isActive ? disposition.title : "Recovered"
    }

    var dispositionSystemImage: String {
        isActive ? disposition.systemImage : "checkmark.circle.fill"
    }
}
