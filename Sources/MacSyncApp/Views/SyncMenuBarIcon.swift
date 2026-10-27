import SwiftUI

/// Status-item labels are rendered into AppKit images. Keep this view static:
/// animation ticks can re-enter status-button layout and starve the main loop.
struct SyncMenuBarIcon: View {
    let isRunning: Bool
    let needsAttention: Bool

    var systemName: String {
        if isRunning {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        if needsAttention {
            return "exclamationmark.triangle.fill"
        }
        return "arrow.triangle.2.circlepath"
    }

    var accessibilityLabel: String {
        if isRunning {
            return "Mac Sync is syncing"
        }
        if needsAttention {
            return "Mac Sync needs attention"
        }
        return "Mac Sync"
    }

    var body: some View {
        Image(systemName: systemName)
            .accessibilityLabel(accessibilityLabel)
    }
}
