@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncHistoryPresentationTests: XCTestCase {
    func testHistoryTitlesDoNotClaimTransfersSucceeded() {
        for result in [SyncHistoryResult.success, .partial, .failed, .deferred] {
            for action in [SyncHistoryAction.sync, .restore] {
                let record = SyncHistoryRecord(
                    action: action, result: result,
                    timing: SyncHistoryTiming(startedAt: "start", finishedAt: "finish", durationSeconds: 1),
                    entries: [], diagnostics: SyncHistoryDiagnostics(warningCount: 0, errorCount: 0, warnings: [], errors: []),
                )
                XCTAssertEqual(record.actionTitle, action == .sync ? "Sync from this Mac" : "Restore to this Mac")
                XCTAssertEqual(record.summary.actionTitle, record.actionTitle)
            }
        }
    }
}
