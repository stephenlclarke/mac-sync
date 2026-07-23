@testable import MacSyncCore
import XCTest

final class MacSyncCoreTests: XCTestCase {
    func testShellQuoterLeavesSafeValuesUnquoted() {
        XCTAssertEqual("abc_123/def.git", ShellQuoter.quote("abc_123/def.git"))
        XCTAssertEqual("user@host:path", ShellQuoter.quote("user@host:path"))
    }

    func testShellQuoterQuotesUnsafeValues() {
        XCTAssertEqual("''", ShellQuoter.quote(""))
        XCTAssertEqual("'two words'", ShellQuoter.quote("two words"))
        XCTAssertEqual("'it'\\''s'", ShellQuoter.quote("it's"))
    }

    func testSafeMachineName() {
        XCTAssertTrue(MacSyncPaths.safeMachineName("work-mbp_14.3"))
        XCTAssertFalse(MacSyncPaths.safeMachineName(""))
        XCTAssertFalse(MacSyncPaths.safeMachineName("."))
        XCTAssertFalse(MacSyncPaths.safeMachineName(".."))
        XCTAssertFalse(MacSyncPaths.safeMachineName("-work"))
        XCTAssertFalse(MacSyncPaths.safeMachineName("../work"))
        XCTAssertFalse(MacSyncPaths.safeMachineName("work mbp"))
    }

    func testSafeSyncPath() {
        XCTAssertTrue(MacSyncPaths.safeSyncPath(".config/tool"))
        XCTAssertTrue(MacSyncPaths.safeSyncPath("Library/Application Support/Code/User/settings.json"))
        XCTAssertTrue(MacSyncPaths.safeSyncPath("/etc/hosts"))
        XCTAssertFalse(MacSyncPaths.safeSyncPath(""))
        XCTAssertFalse(MacSyncPaths.safeSyncPath("."))
        XCTAssertFalse(MacSyncPaths.safeSyncPath("/"))
        XCTAssertFalse(MacSyncPaths.safeSyncPath("../outside"))
        XCTAssertFalse(MacSyncPaths.safeSyncPath(".config/../../outside"))
    }

    func testSelectedMachineName() {
        let machines = ["desktop", "work-mbp"]
        XCTAssertEqual("desktop", MacSyncPaths.selectedMachineName(input: "1", available: machines))
        XCTAssertEqual("work-mbp", MacSyncPaths.selectedMachineName(input: "WORK-MBP", available: machines))
        XCTAssertNil(MacSyncPaths.selectedMachineName(input: "0", available: machines))
        XCTAssertNil(MacSyncPaths.selectedMachineName(input: "missing", available: machines))
    }

    func testSafeGitHubRepositoryRelativePath() {
        XCTAssertTrue(MacSyncPaths.safeGitHubRepositoryRelativePath("owner/repo"))
        XCTAssertTrue(MacSyncPaths.safeGitHubRepositoryRelativePath("owner/team/repo"))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath(""))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath("/owner/repo"))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath("owner//repo"))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath("owner/../repo"))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath("owner/-repo"))
        XCTAssertFalse(MacSyncPaths.safeGitHubRepositoryRelativePath("owner/repo\nnext"))
    }

    func testNormalizeGitHubRemoteURL() {
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("git@github.com:owner/repo.git")
        )
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("ssh://git@ssh.github.com:443/owner/repo.git")
        )
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("https://token@github.com/owner/repo.git?x=y#frag")
        )
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://gitlab.com/owner/repo.git"))
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://github.com/owner/repo/extra.git"))
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://github.com/own er/repo.git"))
    }

    func testProcessRunnerCapturesOutputAndStatus() {
        let runner = ProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
        let result = runner.run("/bin/echo", ["hello"])
        XCTAssertEqual(0, result.status)
        XCTAssertEqual("hello\n", result.stdout)
        XCTAssertEqual("", result.stderr)

        let missing = runner.run("/definitely/missing/mac-sync-test-tool")
        XCTAssertEqual(127, missing.status)
        XCTAssertFalse(missing.stderr.isEmpty)
    }

    func testProcessRunnerShellAndCommandLookup() {
        let runner = ProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
        let shell = runner.shell("printf '%s' \"$MAC_SYNC_TEST_VALUE\"", extraEnvironment: ["MAC_SYNC_TEST_VALUE": "ok"])
        XCTAssertEqual(0, shell.status)
        XCTAssertEqual("ok", shell.stdout)

        XCTAssertTrue(runner.commandExists("sh"))
        XCTAssertFalse(runner.commandExists("definitely-missing-mac-sync-test-tool"))
    }

    func testProcessRunnerDrainsLargeOutputWithoutDeadlocking() {
        let runner = ProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
        let result = runner.run(
            "/bin/bash",
            ["-c", "yes stdout | head -c 262144; yes stderr | head -c 262144 >&2"]
        )
        XCTAssertEqual(0, result.status)
        XCTAssertEqual(262_144, result.stdout.utf8.count)
        XCTAssertEqual(262_144, result.stderr.utf8.count)
    }

    func testUserConfigurationPersistsDataRepositoryWithoutCredentials() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let config = root.appendingPathComponent("runtime.env")
        let environment = [
            "HOME": home.path,
            "MAC_SYNC_APP_CONFIG": config.path,
        ]

        try MacSyncUserConfiguration.saveDataRepository(
            "/Volumes/Sync/mac-sync-data",
            environment: environment
        )

        let resolved = MacSyncUserConfiguration.resolvedEnvironment(environment)
        XCTAssertNil(resolved["MAC_SYNC_REPO"])
        XCTAssertEqual(resolved["MAC_SYNC_MACHINES_REPO"], "/Volumes/Sync/mac-sync-data")
        XCTAssertEqual(MacSyncUserConfiguration.configurationFilePath(environment: environment), config.path)
        XCTAssertFalse(try String(contentsOf: config, encoding: .utf8).lowercased().contains("token"))

        let directOverride = MacSyncUserConfiguration.resolvedEnvironment(
            environment.merging(["MAC_SYNC_MACHINES_REPO": "/override/mac-sync-data"]) { _, direct in direct }
        )
        XCTAssertEqual(directOverride["MAC_SYNC_MACHINES_REPO"], "/override/mac-sync-data")
    }

    func testUserConfigurationRejectsUnsafeRepositoryLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try MacSyncUserConfiguration.saveDataRepository(
                "/tmp/mac-sync-data\nother",
                environment: ["HOME": root.path]
            )
        ) { error in
            XCTAssertEqual(error as? MacSyncUserConfigurationError, .invalidRepositoryLocation)
        }
    }
}
