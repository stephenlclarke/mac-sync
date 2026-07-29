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

    func testUserInterfaceLocatorPrefersTheFirstCompleteApplicationBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("MacSyncCurrent.app")
        let stable = root.appendingPathComponent("MacSync.app")
        let incomplete = root.appendingPathComponent("Incomplete.app")
        try makeMacSyncApplication(at: current)
        try makeMacSyncApplication(at: stable)
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)

        let resolved = MacSyncUserInterface.applicationURL(
            candidates: [incomplete.path, current.path, stable.path],
            fileManager: .default,
        )

        XCTAssertEqual(current.path, resolved?.path)
    }

    func testUserInterfaceVersionReadsApplicationMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("MacSync.app")
        try makeMacSyncApplication(at: application, version: "2.3.4", build: "56")

        XCTAssertEqual("mac-sync 2.3.4 (56)", MacSyncUserInterface.versionDescription(applicationURL: application))
        XCTAssertEqual("mac-sync development build", MacSyncUserInterface.versionDescription(applicationURL: nil))
    }

    func testUserInterfaceVersionHandlesMissingBuildNumber() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("MacSync.app")
        try makeMacSyncApplication(at: application, version: "2.3.4", build: "")

        XCTAssertEqual("mac-sync 2.3.4", MacSyncUserInterface.versionDescription(applicationURL: application))
    }

    func testUserInterfaceOpenLaunchesResolvedApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("MacSync.app")
        try makeMacSyncApplication(at: application)
        var launchedApplication: URL?

        try MacSyncUserInterface.open(applicationURL: application) { resolvedApplication in
            launchedApplication = resolvedApplication
            return 0
        }

        XCTAssertEqual(application, launchedApplication)
    }

    func testUserInterfaceOpenUsesLaunchServicesForACompleteApplicationBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("MacSync.app")
        try makeMacSyncApplication(at: application)

        try MacSyncUserInterface.open(environment: ["MAC_SYNC_APPLICATION": application.path])
    }

    func testUserInterfaceOpenReportsUnavailableAndFailedLaunches() throws {
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: nil) { _ in 0 }
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI is not installed.")
        }

        let application = URL(fileURLWithPath: "/tmp/MacSync.app")
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in 7 }
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI could not be opened: open exited with status 7")
        }
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in
                throw NSError(domain: "MacSyncTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "launcher unavailable"])
            }
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI could not be opened: launcher unavailable")
        }
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in
                throw MacSyncUserInterfaceError.launchFailed("existing launch error")
            }
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI could not be opened: existing launch error")
        }
    }

    func testUICommandStartsInjectedLauncherWithoutRequiringMachineConfiguration() {
        var didLaunch = false
        let app = MacSyncApp(
            arguments: ["mac-sync", "ui"],
            environment: ["MAC_SYNC_MACHINE": ".."],
            userInterfaceLauncher: { _ in didLaunch = true },
        )

        XCTAssertEqual(0, app.run())
        XCTAssertTrue(didLaunch)
    }

    func testUICommandRejectsOptionsBeforeLaunching() {
        var didLaunch = false
        let app = MacSyncApp(
            arguments: ["mac-sync", "ui", "--unexpected"],
            environment: ["MAC_SYNC_MACHINE": "target"],
            userInterfaceLauncher: { _ in didLaunch = true },
        )

        XCTAssertEqual(2, app.run())
        XCTAssertFalse(didLaunch)
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

    private func makeMacSyncApplication(at application: URL, version: String = "1.0.0", build: String = "1") throws {
        let executable = application.appendingPathComponent("Contents/MacOS/MacSync")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let info = [
            "CFBundleIdentifier": "tools.xyzzy.mac-sync",
            "CFBundleExecutable": "MacSync",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: application.appendingPathComponent("Contents/Info.plist"))
    }
}
