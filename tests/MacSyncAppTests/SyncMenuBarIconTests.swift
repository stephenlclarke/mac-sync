@testable import MacSyncApp
import XCTest

final class SyncMenuBarIconTests: XCTestCase {
    @MainActor
    func testIdleStatus() {
        let icon = SyncMenuBarIcon(isRunning: false, needsAttention: false)
        XCTAssertEqual(icon.systemName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(icon.accessibilityLabel, "Mac Sync")
    }

    @MainActor
    func testSyncingTakesPriorityOverAttention() {
        for needsAttention in [false, true] {
            let icon = SyncMenuBarIcon(isRunning: true, needsAttention: needsAttention)
            XCTAssertEqual(icon.systemName, "arrow.triangle.2.circlepath.circle.fill")
            XCTAssertEqual(icon.accessibilityLabel, "Mac Sync is syncing")
        }
    }

    @MainActor
    func testAttentionStatus() {
        let icon = SyncMenuBarIcon(isRunning: false, needsAttention: true)
        XCTAssertEqual(icon.systemName, "exclamationmark.triangle.fill")
        XCTAssertEqual(icon.accessibilityLabel, "Mac Sync needs attention")
    }
}
