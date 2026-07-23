@testable import MacSyncApp
import MacSyncCore
import XCTest

final class EncryptedSecretsInspectorTests: XCTestCase {
    func testListsOnlySafeArchiveEntries() throws {
        let runner = FakeEncryptedSecretsRunner(
            result: CommandResult(
                status: 0,
                stdout: ".ssh/config\n../outside\n.secrets/token\n/absolute\n",
                stderr: ""
            )
        )
        let inspector = EncryptedSecretsInspector(
            environment: ["MAC_SYNC_MACHINES_REPO": "/tmp/mac-sync-data"],
            executablePath: "/tmp/mac-sync",
            runner: runner
        )

        XCTAssertEqual(try inspector.entries(from: "peer-mac"), [".ssh/config", ".secrets/token"])
        XCTAssertEqual(runner.executablePath, "/tmp/mac-sync")
        XCTAssertEqual(runner.arguments, ["secrets", "list", "--from", "peer-mac"])
    }

    func testRejectsInvalidMachineBeforeRunningACommand() {
        let runner = FakeEncryptedSecretsRunner(result: CommandResult(status: 0, stdout: ".ssh/config\n", stderr: ""))
        let inspector = EncryptedSecretsInspector(
            environment: [:],
            executablePath: "/tmp/mac-sync",
            runner: runner
        )

        XCTAssertThrowsError(try inspector.entries(from: "../peer"))
        XCTAssertNil(runner.arguments)
    }

    func testDoesNotExposeCommandErrorOutput() {
        let runner = FakeEncryptedSecretsRunner(
            result: CommandResult(status: 1, stdout: "sensitive output", stderr: "sensitive failure")
        )
        let inspector = EncryptedSecretsInspector(
            environment: [:],
            executablePath: "/tmp/mac-sync",
            runner: runner
        )

        XCTAssertThrowsError(try inspector.entries(from: "peer")) { error in
            XCTAssertEqual(error.localizedDescription, EncryptedSecretsInspectionError.unavailable.localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("sensitive"))
        }
    }
}

private final class FakeEncryptedSecretsRunner: EncryptedSecretsCommandRunning {
    let result: CommandResult
    private(set) var executablePath: String?
    private(set) var arguments: [String]?

    init(result: CommandResult) {
        self.result = result
    }

    func run(executablePath: String, arguments: [String], environment _: [String: String]) -> CommandResult {
        self.executablePath = executablePath
        self.arguments = arguments
        return result
    }
}
