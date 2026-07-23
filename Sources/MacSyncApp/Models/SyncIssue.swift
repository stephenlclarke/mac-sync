import Foundation

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

struct SyncIssue: Identifiable, Equatable {
    let id: String
    let severity: SyncIssueSeverity
    let message: String
    let recommendedAction: String
    let source: String
    let recordedAt: String
    let detail: String?
    let disposition: SyncIssueDisposition
    let note: String
    let updatedAt: Date?

    var requiresManualIntervention: Bool {
        disposition == .open
    }
}
