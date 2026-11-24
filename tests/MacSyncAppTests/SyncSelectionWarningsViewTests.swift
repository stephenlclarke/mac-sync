import AppKit
@testable import MacSyncApp
import SwiftUI
import XCTest

@MainActor
final class SyncSelectionWarningsViewTests: XCTestCase {
    func testLargeWarningListDoesNotForceAnUnboundedWindow() {
        let warnings = (0 ..< 200).map {
            SyncSelectionWarning(path: ".aws/profile-\($0)", reason: "A generated warning for the layout regression test.")
        }
        let view = NSHostingView(rootView: SyncSelectionWarningsView(warnings: warnings, initiallyExpanded: true).frame(width: 900))
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThan(view.fittingSize.height, 350)
    }
}
