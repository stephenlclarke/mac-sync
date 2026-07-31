import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncHealthEvaluatorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testClearsConditionsThatCanBeCheckedWithoutReadingTheIdentity() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeSyncHealthRunner(
            commandAvailability: true,
        ) { executable, arguments in
            if executable == "git",
               arguments == ["-C", fixture.data.path, "ls-remote", "origin", "HEAD"]
            {
                return CommandResult(status: 0, stdout: "head\n", stderr: "")
            }
            return CommandResult(status: 1, stdout: "", stderr: "unexpected command")
        }
        let overview = makeOverview(
            fixture: fixture,
            conditions: [
                condition(.remoteRefreshFailed, component: .remoteRepository),
                condition(.encryptedSecretsIdentityMissing, component: .encryptedSecrets),
                condition(.encryptedSecretsRuntimeUnavailable, component: .encryptedSecrets),
            ],
        )
        let evaluator = SyncHealthEvaluator(
            environment: ["USER": "local"],
            runner: runner,
            keychainPresenceLookup: { _, _ in .present },
            encryptedSecretsVerificationLookup: { _ in false },
        )

        XCTAssertTrue(evaluator.activeConditionCodes(in: overview).isEmpty)
    }

    func testKeepsConditionsThatNeedAnExplicitEncryptedSecretsTest() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeSyncHealthRunner(commandAvailability: true) { _, _ in
            CommandResult(status: 1, stdout: "", stderr: "unexpected command")
        }
        let overview = makeOverview(
            fixture: fixture,
            conditions: [
                condition(.encryptedSecretsIdentityUnavailable, component: .encryptedSecrets),
                condition(.encryptedSecretsIdentityUntrusted, component: .encryptedSecrets),
                condition(.encryptedSecretsSnapshotSkipped, component: .encryptedSecrets),
            ],
        )
        let evaluator = SyncHealthEvaluator(
            environment: ["USER": "local"],
            runner: runner,
            keychainPresenceLookup: { _, _ in .present },
        )

        XCTAssertEqual(
            evaluator.activeConditionCodes(in: overview),
            [
                .encryptedSecretsIdentityUnavailable,
                .encryptedSecretsIdentityUntrusted,
                .encryptedSecretsSnapshotSkipped,
            ],
        )
    }

    func testClearsEncryptedSecretsConditionsAfterAnExplicitTestPasses() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeSyncHealthRunner(commandAvailability: true) { _, _ in
            CommandResult(status: 1, stdout: "", stderr: "unexpected command")
        }
        let overview = makeOverview(
            fixture: fixture,
            conditions: [
                condition(.encryptedSecretsIdentityUnavailable, component: .encryptedSecrets),
                condition(.encryptedSecretsIdentityUntrusted, component: .encryptedSecrets),
                condition(.encryptedSecretsSnapshotSkipped, component: .encryptedSecrets),
            ],
        )
        let evaluator = SyncHealthEvaluator(
            environment: ["USER": "local"],
            runner: runner,
            keychainPresenceLookup: { _, _ in .present },
            encryptedSecretsVerificationLookup: { _ in true },
        )

        XCTAssertTrue(evaluator.activeConditionCodes(in: overview).isEmpty)
    }

    func testEncryptedSecretsVerificationAppliesOnlyToTheStatusThatWasTested() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let testedOverview = makeOverview(
            fixture: fixture,
            conditions: [],
            finishedAt: "2026-07-31 09:00:03 BST",
        )
        let store = SyncHealthVerificationStore(configuration: testedOverview.configuration)

        try store.markEncryptedSecretsVerified(for: testedOverview)

        XCTAssertTrue(store.encryptedSecretsWereVerified(for: testedOverview))
        XCTAssertFalse(store.encryptedSecretsWereVerified(for: makeOverview(
            fixture: fixture,
            conditions: [],
            finishedAt: "2026-07-31 10:00:03 BST",
        )))
    }

    func testRetainsConditionsWhenChecksStillFail() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeSyncHealthRunner(commandAvailability: false) { _, _ in
            CommandResult(status: 128, stdout: "", stderr: "unavailable")
        }
        let overview = makeOverview(
            fixture: fixture,
            conditions: [
                condition(.remoteUnavailable, component: .remoteRepository),
                condition(.encryptedSecretsIdentityMissing, component: .encryptedSecrets),
                condition(.encryptedSecretsRuntimeUnavailable, component: .encryptedSecrets),
            ],
        )
        let evaluator = SyncHealthEvaluator(
            environment: ["USER": "local"],
            runner: runner,
            keychainPresenceLookup: { _, _ in .missing },
        )

        XCTAssertEqual(
            evaluator.activeConditionCodes(in: overview),
            [
                .remoteUnavailable,
                .encryptedSecretsIdentityMissing,
                .encryptedSecretsRuntimeUnavailable,
            ],
        )
    }

    private func condition(
        _ code: SyncHealthConditionCode,
        component: SyncHealthComponent,
    ) -> SyncHealthCondition {
        SyncHealthCondition(
            code: code,
            component: component,
            severity: .warning,
            title: code.rawValue,
            detail: "test",
            recovery: "test",
        )
    }

    private func makeOverview(
        fixture: Fixture,
        conditions: [SyncHealthCondition],
        finishedAt: String = "2026-07-31 09:00:03 BST",
    ) -> SyncOverview {
        SyncOverview(
            configuration: SyncConfiguration(
                homeDirectory: fixture.home.path,
                dataRepository: fixture.data.path,
                statusDirectory: fixture.status.path,
                machineName: "local",
                pathsFile: fixture.data
                    .appendingPathComponent("machines/local/config/sync-paths.txt")
                    .path,
            ),
            status: SyncStatus(
                result: .partial,
                startedAt: nil,
                finishedAt: finishedAt,
                durationSeconds: 3,
                updatedFileCount: 1,
                updatedByteCount: 1,
                storageFileCount: 1,
                storageByteCount: 1,
                warningCount: conditions.count,
                errorCount: 0,
                lastCommit: "abc123",
                remoteRepository: "https://github.com/example/mac-sync-data.git",
                warnings: [],
                errors: [],
                conditions: conditions,
                commandDiagnostics: [],
                recordedLocalChanges: [],
                currentLocalChanges: [],
            ),
            history: [],
            currentMachine: nil,
            peerMachines: [],
            localSyncProcessID: nil,
            isLocalSyncActive: false,
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home")
        let data = root.appendingPathComponent("mac-sync-data")
        let status = root.appendingPathComponent("status")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: status, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, data: data, status: status)
    }
}

private final class FakeSyncHealthRunner: SyncHealthCommandRunning {
    typealias Handler = (String, [String]) -> CommandResult

    private let commandAvailability: Bool
    private let handler: Handler

    init(commandAvailability: Bool, handler: @escaping Handler) {
        self.commandAvailability = commandAvailability
        self.handler = handler
    }

    func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        handler(executable, arguments)
    }

    func commandExists(_: String) -> Bool {
        commandAvailability
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let data: URL
    let status: URL
}
