import Foundation
@testable import MacSyncApp
import XCTest

final class SyncActivityIconTests: XCTestCase {
    func testRotatesOncePerAnimationPeriod() {
        let quarterTurn = Date(
            timeIntervalSinceReferenceDate: SyncActivityIcon.rotationPeriod / 4,
        )
        let fullTurn = Date(
            timeIntervalSinceReferenceDate: SyncActivityIcon.rotationPeriod,
        )

        XCTAssertEqual(
            90,
            SyncActivityIcon.rotationDegrees(
                at: quarterTurn,
                isAnimating: true,
                reduceMotion: false,
            ),
            accuracy: 0.001,
        )
        XCTAssertEqual(
            0,
            SyncActivityIcon.rotationDegrees(
                at: fullTurn,
                isAnimating: true,
                reduceMotion: false,
            ),
            accuracy: 0.001,
        )
    }

    func testStopsRotationWhenSyncIsIdleOrReducedMotionIsEnabled() {
        let date = Date(timeIntervalSinceReferenceDate: 0.4)

        XCTAssertEqual(
            0,
            SyncActivityIcon.rotationDegrees(
                at: date,
                isAnimating: false,
                reduceMotion: false,
            ),
        )
        XCTAssertEqual(
            0,
            SyncActivityIcon.rotationDegrees(
                at: date,
                isAnimating: true,
                reduceMotion: true,
            ),
        )
    }
}
