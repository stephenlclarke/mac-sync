import Foundation
@testable import MacSyncCore
import XCTest

final class MacSyncDistributionTests: XCTestCase {
    func testLocalTransferDoesNotReadUnapprovedAncestorsOrDisableSafety() {
        let file = MacSyncStoreRuntime.localTransfer(arguments: ["-a", "/source/file", "/approved/destination/file"], workingDirectory: nil)
        XCTAssertEqual(file.0, ["-a", "/source/file", "./file"])
        XCTAssertEqual(file.1, "/approved/destination")
        let folder = MacSyncStoreRuntime.localTransfer(arguments: ["-a", "/source/", "/approved/destination/"], workingDirectory: nil)
        XCTAssertEqual(folder.0.last, "./")
        XCTAssertEqual(folder.1, "/approved/destination")
        XCTAssertFalse(folder.0.contains("--insecure-links"))
    }
    func testStoreRuntimeCannotInheritHomebrewOrExecutableInjection() throws {
        let result = MacSyncStoreRuntime.environment([
            "PATH": "/opt/homebrew/bin:/usr/local/bin", "GIT_EXEC_PATH": "/untrusted",
            "GIT_SSH_COMMAND": "/untrusted/proxy", "GIT_SSL_NO_VERIFY": "1",
            "DYLD_INSERT_LIBRARIES": "/untrusted/lib.dylib", "BASH_ENV": "/untrusted/startup",
            "MAC_SYNC_HOMEBREW": "1", "MAC_SYNC_VSCODE_EXTENSIONS": "1",
        ], bundle: URL(fileURLWithPath: "/Applications/MacSync.app"), containerHome: "/nonexistent-container", sourceHome: "/Users/test")
        XCTAssertEqual(result["PATH"], "/Applications/MacSync.app/Contents/Helpers:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(result["HOME"], "/Users/test")
        XCTAssertEqual(result["TMPDIR"], "/nonexistent-container/tmp")
        XCTAssertTrue(try XCTUnwrap(result["MAC_SYNC_APP_CONFIG"]?.hasPrefix("/nonexistent-container/")))
        XCTAssertTrue(try XCTUnwrap(result["MAC_SYNC_MACHINES_REPO"]?.hasPrefix("/nonexistent-container/")))
        XCTAssertEqual(result["MAC_SYNC_HOMEBREW"], "0")
        XCTAssertEqual(result["MAC_SYNC_VSCODE_EXTENSIONS"], "0")
        XCTAssertEqual(result["GIT_CONFIG_VALUE_2"], "")
        XCTAssertNil(result["GIT_SSL_NO_VERIFY"])
        XCTAssertNil(result["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(result["BASH_ENV"])
        XCTAssertTrue(try XCTUnwrap(result["GIT_SSH_COMMAND"]?.contains("StrictHostKeyChecking=yes")))
        XCTAssertFalse(MacSyncDistribution(environment: result).supportsDeveloperTools)
        XCTAssertTrue(MacSyncDistribution(environment: [:]).supportsDeveloperTools)
    }

    func testMissingToolsNeverAcceptsSystemFallback() {
        XCTAssertEqual(MacSyncStoreRuntime.missingTools(bundle: URL(fileURLWithPath: "/nonexistent-app.app")), MacSyncStoreRuntime.tools)
    }

    func testStoreDeveloperToolCommandsFailWithoutRunningAnInstaller() {
        let result = MacSyncApp(arguments: ["mac-sync", "packages", "install"], environment: ["MAC_SYNC_DISTRIBUTION": "app-store", "MAC_SYNC_MACHINE": "test", "PATH": "/usr/bin:/bin"]).run()
        XCTAssertEqual(result, 2)
    }
}
