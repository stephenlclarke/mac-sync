@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncHealthActivityTests: XCTestCase {
    func testKnownConditionIsNeutralUntilTheLiveCheckCompletes() {
        XCTAssertEqual(
            SyncHealthActivity.resolve(
                conditionCode: .remoteRefreshFailed,
                activeConditionCodes: nil,
            ),
            .checking,
        )
    }

    func testKnownConditionUsesTheLiveCheckResult() {
        XCTAssertEqual(
            SyncHealthActivity.resolve(
                conditionCode: .remoteRefreshFailed,
                activeConditionCodes: [.remoteRefreshFailed],
            ),
            .active,
        )
        XCTAssertEqual(
            SyncHealthActivity.resolve(
                conditionCode: .remoteRefreshFailed,
                activeConditionCodes: [],
            ),
            .recovered,
        )
    }

    func testHistoricalAndUnclassifiedConditionsDoNotWaitForLiveChecks() {
        XCTAssertEqual(
            SyncHealthActivity.resolve(
                conditionCode: .encryptedSecretsIdentityMissing,
                recordedAsActive: false,
                activeConditionCodes: nil,
            ),
            .recovered,
        )
        XCTAssertEqual(
            SyncHealthActivity.resolve(
                conditionCode: nil,
                activeConditionCodes: nil,
            ),
            .active,
        )
    }

    func testLegacyWarningsMapToTypedHealthConditions() {
        let expectations: [(String, SyncHealthConditionCode)] = [
            (
                "WARN: could not pull machines repo before sync; continuing and retrying before push",
                .remoteRefreshFailed,
            ),
            (
                "WARN: missing local Keychain age identity; skipping encrypted secrets snapshot",
                .encryptedSecretsIdentityMissing,
            ),
            (
                "WARN: local repo has local changes; skipping pre-operation git pull",
                .remoteRefreshBlockedByLocalChanges,
            ),
            (
                "WARN: encrypted-secrets tools are unavailable",
                .encryptedSecretsRuntimeUnavailable,
            ),
            (
                "ERROR: existing encrypted secrets snapshot cannot be decrypted",
                .encryptedSecretsSnapshotSkipped,
            ),
        ]

        for (message, conditionCode) in expectations {
            XCTAssertEqual(SyncHealthMessage.conditionCode(for: message), conditionCode)
        }
        XCTAssertNil(SyncHealthMessage.conditionCode(for: "WARN: unexpected condition"))
    }
}
