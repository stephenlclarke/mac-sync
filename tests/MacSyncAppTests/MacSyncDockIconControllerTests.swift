import AppKit
@testable import MacSyncApp
import XCTest

final class MacSyncDockIconControllerTests: XCTestCase {
    func testDockIconIsHiddenByDefault() throws {
        let suiteName = "MacSyncDockIconControllerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(MacSyncDockIconController.isVisible(in: defaults))
    }

    func testStoredDockIconVisibilityIsUsed() throws {
        let suiteName = "MacSyncDockIconControllerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: MacSyncDockIconController.preferenceKey)

        XCTAssertTrue(MacSyncDockIconController.isVisible(in: defaults))
    }

    func testDockIconVisibilityMapsToActivationPolicy() {
        XCTAssertEqual(MacSyncDockIconController.activationPolicy(isVisible: true), .regular)
        XCTAssertEqual(MacSyncDockIconController.activationPolicy(isVisible: false), .accessory)
    }
}
