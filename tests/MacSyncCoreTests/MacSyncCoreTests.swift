import LocalAuthentication
@testable import MacSyncCore
import Security
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
            MacSyncPaths.normalizeGitHubRemoteURL("git@github.com:owner/repo.git"),
        )
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("ssh://git@ssh.github.com:443/owner/repo.git"),
        )
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("https://token@github.com/owner/repo.git?x=y#frag"),
        )
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://gitlab.com/owner/repo.git"))
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://github.com/owner/repo/extra.git"))
        XCTAssertNil(MacSyncPaths.normalizeGitHubRemoteURL("https://github.com/own er/repo.git"))
        XCTAssertEqual(
            "git@github.com:owner/repo.git",
            MacSyncPaths.githubSSHRemoteURL("https://github.com/owner/repo.git"),
        )
        XCTAssertEqual(
            "https://github.com/owner/repo.git",
            MacSyncPaths.normalizeGitHubRemoteURL("http://user@github.com/owner/repo.git///"),
        )
        XCTAssertNil(MacSyncPaths.githubSSHRemoteURL("https://gitlab.com/owner/repo.git"))
    }

    func testKeychainIdentityMapsSecurityResultsWithoutInteraction() throws {
        var capturedQuery: [CFString: Any] = [:]
        let available = MacSyncKeychain.identity(
            service: "test-service",
            account: "test-account",
            allowInteraction: false,
            backend: MacSyncKeychainBackend(
                copyMatching: { query in
                    capturedQuery = query
                    return (errSecSuccess, Data("AGE-SECRET-KEY-TEST\n".utf8))
                },
                update: { _, _ in errSecSuccess },
                add: { _ in errSecSuccess },
            ),
        )

        XCTAssertEqual(available.availability, .available)
        XCTAssertEqual(available.identity, "AGE-SECRET-KEY-TEST\n")
        XCTAssertEqual(capturedQuery[kSecAttrService] as? String, "test-service")
        XCTAssertEqual(capturedQuery[kSecAttrAccount] as? String, "test-account")
        let context = try XCTUnwrap(capturedQuery[kSecUseAuthenticationContext] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)

        let missing = MacSyncKeychain.identity(
            service: "test-service",
            account: "test-account",
            allowInteraction: true,
            backend: keychainBackend(copyStatus: errSecItemNotFound),
        )
        XCTAssertEqual(missing.availability, .missing)

        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled] {
            let result = MacSyncKeychain.identity(
                service: "test-service",
                account: "test-account",
                allowInteraction: true,
                backend: keychainBackend(copyStatus: status),
            )
            XCTAssertEqual(result.availability, .interactionRequired)
        }

        let unavailable = MacSyncKeychain.identity(
            service: "test-service",
            account: "test-account",
            allowInteraction: true,
            backend: keychainBackend(copyStatus: errSecNotAvailable),
        )
        XCTAssertEqual(unavailable.availability, .unavailable(status: errSecNotAvailable))

        let undecodable = MacSyncKeychain.identity(
            service: "test-service",
            account: "test-account",
            allowInteraction: true,
            backend: keychainBackend(copyStatus: errSecSuccess, copyItem: Data([0xFF])),
        )
        XCTAssertEqual(undecodable.availability, .unavailable(status: errSecDecode))
    }

    func testKeychainStoreUpdatesOrAddsDeviceOnlyItem() {
        var addCount = 0
        let updated = MacSyncKeychain.storeIdentity(
            "AGE-SECRET-KEY-UPDATED",
            service: "test-service",
            account: "test-account",
            backend: MacSyncKeychainBackend(
                copyMatching: { _ in (errSecItemNotFound, nil) },
                update: { _, _ in errSecSuccess },
                add: { _ in
                    addCount += 1
                    return errSecSuccess
                },
            ),
        )
        XCTAssertEqual(updated, errSecSuccess)
        XCTAssertEqual(addCount, 0)

        let updateFailure = MacSyncKeychain.storeIdentity(
            "AGE-SECRET-KEY-FAILED",
            service: "test-service",
            account: "test-account",
            backend: keychainBackend(updateStatus: errSecAuthFailed),
        )
        XCTAssertEqual(updateFailure, errSecAuthFailed)

        var addedItem: [CFString: Any] = [:]
        let added = MacSyncKeychain.storeIdentity(
            "AGE-SECRET-KEY-ADDED",
            service: "test-service",
            account: "test-account",
            backend: MacSyncKeychainBackend(
                copyMatching: { _ in (errSecItemNotFound, nil) },
                update: { _, _ in errSecItemNotFound },
                add: { item in
                    addedItem = item
                    return errSecSuccess
                },
            ),
        )
        XCTAssertEqual(added, errSecSuccess)
        XCTAssertEqual(addedItem[kSecValueData] as? Data, Data("AGE-SECRET-KEY-ADDED".utf8))
        XCTAssertTrue(CFEqual(
            addedItem[kSecAttrAccessible] as CFTypeRef,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ))
    }

    func testLiveKeychainRoundTripUsesScopedDeviceOnlyItem() {
        let service = "tools.xyzzy.mac-sync.tests.\(UUID().uuidString)"
        let account = "keychain-round-trip"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        defer { SecItemDelete(query as CFDictionary) }

        let missing = MacSyncKeychain.identity(
            service: service,
            account: account,
            allowInteraction: false,
        )
        XCTAssertEqual(missing.availability, .missing)

        XCTAssertEqual(
            MacSyncKeychain.storeIdentity(
                "AGE-SECRET-KEY-TEST-ONE",
                service: service,
                account: account,
            ),
            errSecSuccess,
        )
        XCTAssertEqual(
            MacSyncKeychain.storeIdentity(
                "AGE-SECRET-KEY-TEST-TWO",
                service: service,
                account: account,
            ),
            errSecSuccess,
        )

        let available = MacSyncKeychain.identity(
            service: service,
            account: account,
            allowInteraction: false,
        )
        XCTAssertEqual(available.availability, .available)
        XCTAssertEqual(available.identity, "AGE-SECRET-KEY-TEST-TWO")
    }

    func testLegacyHistoryRecordDecodesWithoutStructuredDiagnostics() throws {
        let data = Data(
            """
            {
              "id": "legacy",
              "action": "sync",
              "result": "success",
              "startedAt": "2026-07-30 10:00:00 BST",
              "finishedAt": "2026-07-30 10:00:01 BST",
              "durationSeconds": 1,
              "warningCount": 0,
              "errorCount": 0,
              "entries": [],
              "warnings": [],
              "errors": []
            }
            """.utf8,
        )

        let record = try JSONDecoder().decode(SyncHistoryRecord.self, from: data)

        XCTAssertEqual(record.id, "legacy")
        XCTAssertNil(record.conditions)
        XCTAssertNil(record.commands)
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

        let uncaptured = runner.run("/usr/bin/true", capture: false)
        XCTAssertEqual(0, uncaptured.status)
        XCTAssertEqual("", uncaptured.stdout)
        XCTAssertEqual("", uncaptured.stderr)
    }

    func testUserConfigurationErrorDescription() {
        XCTAssertEqual(
            MacSyncUserConfigurationError.invalidRepositoryLocation.errorDescription,
            "Repository locations must not be empty or contain new lines.",
        )
    }

    func testProcessRunnerDrainsLargeOutputWithoutDeadlocking() {
        let runner = ProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
        let result = runner.run(
            "/bin/bash",
            ["-c", "yes stdout | head -c 262144; yes stderr | head -c 262144 >&2"],
        )
        XCTAssertEqual(0, result.status)
        XCTAssertEqual(262_144, result.stdout.utf8.count)
        XCTAssertEqual(262_144, result.stderr.utf8.count)
    }

    func testProcessLockAllowsOnlyOneOwnerAndCanBeReacquired() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("instance.lock")
        var firstLock = try XCTUnwrap(
            MacSyncProcessLock.acquire(at: lockURL, ownerProcessID: 101),
        )

        XCTAssertEqual("101\n", try String(contentsOf: lockURL, encoding: .utf8))
        XCTAssertNil(try MacSyncProcessLock.acquire(at: lockURL, ownerProcessID: 202))

        firstLock.release()
        firstLock = try XCTUnwrap(
            MacSyncProcessLock.acquire(at: lockURL, ownerProcessID: 303),
        )
        XCTAssertEqual("303\n", try String(contentsOf: lockURL, encoding: .utf8))
    }

    func testProcessLockReleasesReservationWhenLockFileCannotBeOpened() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("instance.lock")
        try FileManager.default.createDirectory(
            at: lockURL,
            withIntermediateDirectories: true,
        )

        XCTAssertThrowsError(try MacSyncProcessLock.acquire(at: lockURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("open failed"))
        }

        try FileManager.default.removeItem(at: lockURL)
        XCTAssertNotNil(try MacSyncProcessLock.acquire(at: lockURL))
    }

    func testUserInterfaceAndServiceUseSeparateGlobalLocks() {
        let environment = ["TMPDIR": "/tmp/mac-sync-lock-tests"]

        XCTAssertEqual(
            "/tmp/mac-sync-lock-tests/mac-sync-ui.lock",
            MacSyncProcessLock.userInterfaceLockURL(environment: environment).path,
        )
        XCTAssertEqual(
            "/tmp/mac-sync-lock-tests/mac-sync-service.lock",
            MacSyncProcessLock.syncServiceLockURL(environment: environment).path,
        )
    }

    func testRunExitsSuccessfullyWhenServiceInstanceIsAlreadyActive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [
            "HOME": root.appendingPathComponent("home").path,
            "TMPDIR": root.path,
            "MAC_SYNC_MACHINE": "target",
        ]
        let serviceLock = try XCTUnwrap(
            MacSyncProcessLock.acquire(
                at: MacSyncProcessLock.syncServiceLockURL(environment: environment),
                ownerProcessID: 404,
            ),
        )
        let executable = Bundle(for: MacSyncCoreTests.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("mac-sync")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let result = ProcessRunner(environment: environment).run(executable.path, ["run"])

        XCTAssertEqual(0, result.status)
        XCTAssertEqual(
            "another mac-sync service is already running; exiting: pid 404\n",
            result.stdout,
        )
        XCTAssertEqual("", result.stderr)
        withExtendedLifetime(serviceLock) {}
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
            try MacSyncUserInterface.open(applicationURL: nil) { _ in 0 },
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI is not installed.")
        }

        let application = URL(fileURLWithPath: "/tmp/MacSync.app")
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in 7 },
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI could not be opened: open exited with status 7")
        }
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in
                throw NSError(domain: "MacSyncTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "launcher unavailable"])
            },
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Mac Sync UI could not be opened: launcher unavailable")
        }
        XCTAssertThrowsError(
            try MacSyncUserInterface.open(applicationURL: application) { _ in
                throw MacSyncUserInterfaceError.launchFailed("existing launch error")
            },
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
            environment: environment,
        )

        let resolved = MacSyncUserConfiguration.resolvedEnvironment(environment)
        XCTAssertNil(resolved["MAC_SYNC_REPO"])
        XCTAssertEqual(resolved["MAC_SYNC_MACHINES_REPO"], "/Volumes/Sync/mac-sync-data")
        XCTAssertEqual(MacSyncUserConfiguration.configurationFilePath(environment: environment), config.path)
        XCTAssertFalse(try String(contentsOf: config, encoding: .utf8).lowercased().contains("token"))

        let directOverride = MacSyncUserConfiguration.resolvedEnvironment(
            environment.merging(["MAC_SYNC_MACHINES_REPO": "/override/mac-sync-data"]) { _, direct in direct },
        )
        XCTAssertEqual(directOverride["MAC_SYNC_MACHINES_REPO"], "/override/mac-sync-data")
    }

    func testUserConfigurationRejectsUnsafeRepositoryLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try MacSyncUserConfiguration.saveDataRepository(
                "/tmp/mac-sync-data\nother",
                environment: ["HOME": root.path],
            ),
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

    private func keychainBackend(
        copyStatus: OSStatus = errSecItemNotFound,
        copyItem: Any? = nil,
        updateStatus: OSStatus = errSecSuccess,
        addStatus: OSStatus = errSecSuccess,
    ) -> MacSyncKeychainBackend {
        MacSyncKeychainBackend(
            copyMatching: { _ in (copyStatus, copyItem) },
            update: { _, _ in updateStatus },
            add: { _ in addStatus },
        )
    }
}
