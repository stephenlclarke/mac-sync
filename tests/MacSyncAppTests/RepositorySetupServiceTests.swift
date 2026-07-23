import Foundation
@testable import MacSyncApp
import XCTest

final class RepositorySetupServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testGitHubCheckRedactsCredentialedRemoteAndVerifiesPush() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try makeGitDirectory(at: fixture.locations.dataRepository)

        let runner = FakeGitRunner { arguments, directory, _ in
            switch (directory, arguments) {
            case (fixture.locations.dataRepository, ["remote", "get-url", "origin"]):
                GitCommandResult(status: 0, stdout: "https://token-value@github.com/example/mac-sync-data.git\n", stderr: "")
            case (_, ["branch", "--show-current"]):
                GitCommandResult(status: 0, stdout: "main\n", stderr: "")
            case (_, ["ls-remote", "origin"]):
                GitCommandResult(status: 0, stdout: "head\n", stderr: "")
            case (_, ["rev-parse", "--verify", "HEAD"]):
                GitCommandResult(status: 0, stdout: "head\n", stderr: "")
            case (fixture.locations.dataRepository, ["push", "--dry-run", "--porcelain", "origin", "HEAD:refs/heads/main"]):
                GitCommandResult(status: 0, stdout: "", stderr: "")
            default:
                GitCommandResult(status: 1, stdout: "", stderr: "unexpected command")
            }
        }
        let service = RepositorySetupService(fileManager: fileManager, runner: runner)

        let reports = service.checkGitHubAccess(for: fixture.locations)

        XCTAssertEqual(reports.map(\.state), [.syncAccessReady])
        XCTAssertEqual(reports[0].repository.remoteURL, "https://github.com/example/mac-sync-data.git")
        XCTAssertFalse(reports.joinedDescription.contains("token-value"))
        XCTAssertTrue(runner.extraEnvironments.allSatisfy { $0["GIT_TERMINAL_PROMPT"] == "0" })
        XCTAssertTrue(runner.commands.contains { $0.arguments.first == "push" })
    }

    func testGitHubCheckReportsAuthenticationFailureWithoutLeakingToken() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try makeGitDirectory(at: fixture.locations.dataRepository)

        let runner = FakeGitRunner { arguments, directory, _ in
            switch (directory, arguments) {
            case (fixture.locations.dataRepository, ["remote", "get-url", "origin"]):
                GitCommandResult(status: 0, stdout: "https://token-value@github.com/example/mac-sync-data.git\n", stderr: "")
            case (_, ["branch", "--show-current"]):
                GitCommandResult(status: 0, stdout: "main\n", stderr: "")
            case (_, ["ls-remote", "origin"]):
                GitCommandResult(
                    status: 128,
                    stdout: "",
                    stderr: "fatal: Authentication failed for 'https://token-value@github.com/example/mac-sync-data.git'\n"
                )
            default:
                GitCommandResult(status: 1, stdout: "", stderr: "unexpected command")
            }
        }
        let reports = RepositorySetupService(fileManager: fileManager, runner: runner).checkGitHubAccess(for: fixture.locations)

        XCTAssertEqual(reports[0].state, .authenticationRequired)
        XCTAssertFalse(reports[0].detail.contains("token-value"))
    }

    func testGitHubCheckAcceptsAnEmptyDataRepositoryUntilFirstSync() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try makeGitDirectory(at: fixture.locations.dataRepository)

        let runner = FakeGitRunner { arguments, directory, _ in
            switch (directory, arguments) {
            case (fixture.locations.dataRepository, ["remote", "get-url", "origin"]):
                GitCommandResult(status: 0, stdout: "https://github.com/example/mac-sync-data.git\n", stderr: "")
            case (_, ["branch", "--show-current"]):
                GitCommandResult(status: 0, stdout: "main\n", stderr: "")
            case (_, ["ls-remote", "origin"]):
                GitCommandResult(status: 0, stdout: "", stderr: "")
            case (_, ["rev-parse", "--verify", "HEAD"]):
                GitCommandResult(status: 128, stdout: "", stderr: "fatal: Needed a single revision\n")
            default:
                GitCommandResult(status: 1, stdout: "", stderr: "unexpected command")
            }
        }

        let reports = RepositorySetupService(fileManager: fileManager, runner: runner).checkGitHubAccess(for: fixture.locations)

        XCTAssertEqual(reports[0].state, .readAccessReady)
        XCTAssertTrue(reports[0].detail.contains("first sync"))
        XCTAssertFalse(runner.commands.contains { $0.arguments.first == "push" })
    }

    func testCloneFailurePrefersGitDiagnosticOverClonePreamble() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }

        let runner = FakeGitRunner { arguments, _, _ in
            guard arguments.first == "clone" else {
                return GitCommandResult(status: 1, stdout: "", stderr: "unexpected command")
            }
            return GitCommandResult(
                status: 128,
                stdout: "",
                stderr: "Cloning into '\(fixture.locations.dataRepository)'...\nfatal: Authentication failed for 'https://token-value@github.com/example/mac-sync-data.git'\n"
            )
        }

        let result = RepositorySetupService(fileManager: fileManager, runner: runner).cloneMissing(fixture.locations)

        XCTAssertEqual(
            result.messages,
            ["Unable to clone mac-sync data: fatal: Authentication failed for 'https://***@github.com/example/mac-sync-data.git'"]
        )
        XCTAssertFalse(result.messages.joined().contains(fixture.locations.dataRepository))
        XCTAssertFalse(result.messages.joined().contains("token-value"))
    }

    func testCloneAndRecoveryKeepLegacyFolderSafe() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }

        let runner = FakeGitRunner { arguments, _, _ in
            guard arguments.first == "clone", let destination = arguments.last else {
                return GitCommandResult(status: 0, stdout: "", stderr: "")
            }
            try? self.makeGitDirectory(at: destination)
            return GitCommandResult(status: 0, stdout: "", stderr: "")
        }
        let service = RepositorySetupService(fileManager: fileManager, runner: runner)

        let result = service.cloneMissing(fixture.locations)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.messages, ["Cloned mac-sync data."])
        XCTAssertTrue(result.inspections.allSatisfy(\.isReady))

        let legacy = fixture.root.appendingPathComponent("legacy")
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "keep".write(to: legacy.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        let legacyLocations = RepositoryLocations(dataRepository: legacy.path)
        let rejected = service.cloneMissing(legacyLocations)
        XCTAssertEqual(rejected.messages.first, "Unable to clone mac-sync data: choose an empty folder, a different location, or back up this legacy folder first.")

        let plan = try XCTUnwrap(service.recoveryPlan(for: .syncData, locations: legacyLocations))
        let repaired = service.backUpAndClone(plan, locations: legacyLocations)
        XCTAssertTrue(repaired.succeeded)
        XCTAssertTrue(fileManager.fileExists(atPath: legacy.appendingPathComponent(".git").path))
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: plan.backupPath).appendingPathComponent("file")), "keep")
    }

    private func makeFixture() throws -> SetupFixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return SetupFixture(
            root: root,
            locations: RepositoryLocations(dataRepository: root.appendingPathComponent("mac-sync-data").path)
        )
    }

    private func makeGitDirectory(at path: String) throws {
        try fileManager.createDirectory(at: URL(fileURLWithPath: path).appendingPathComponent(".git"), withIntermediateDirectories: true)
    }
}

private struct SetupFixture {
    let root: URL
    let locations: RepositoryLocations
}

private final class FakeGitRunner: GitCommandRunning {
    typealias Handler = ([String], String?, [String: String]) -> GitCommandResult

    let handler: Handler
    private(set) var commands: [(arguments: [String], directory: String?)] = []
    private(set) var extraEnvironments: [[String: String]] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        arguments: [String],
        workingDirectory: String?,
        extraEnvironment: [String: String]
    ) -> GitCommandResult {
        commands.append((arguments, workingDirectory))
        extraEnvironments.append(extraEnvironment)
        return handler(arguments, workingDirectory, extraEnvironment)
    }
}

private extension [GitHubConnectionReport] {
    var joinedDescription: String {
        map { "\($0.repository.remoteURL ?? "") \($0.detail)" }.joined(separator: "\n")
    }
}
