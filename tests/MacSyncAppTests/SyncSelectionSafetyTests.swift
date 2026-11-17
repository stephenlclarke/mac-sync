@testable import MacSyncApp
import XCTest

@MainActor
final class SyncSelectionSafetyTests: XCTestCase {
    func testScanPreservesCredentialPathWarnings() async {
        let paths = [".aws/config", ".ssh/config", ".gnupg/common.conf"]
        let warnings = await SyncSelectionSafety.scan(paths: paths, home: "/nonexistent-test-home")
        XCTAssertEqual(warnings.map(\.path), paths)
    }

    func testCancellingParentCancelsTheScanner() async {
        // The main-actor task cannot start until this test yields below.
        let scan = Task { await SyncSelectionSafety.scan(paths: [".aws/config"], home: "/nonexistent-test-home") }
        scan.cancel()
        let warnings = await scan.value
        XCTAssertTrue(warnings.isEmpty)
    }
}
