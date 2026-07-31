import Foundation
@testable import MacSyncApp
import XCTest

final class MacSyncCommandLocatorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testScheduledApplicationUsesEnvironmentOverride() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let applicationURL = root.appendingPathComponent("Custom Mac Sync.app")
        let executableURL = applicationURL.appendingPathComponent("Contents/MacOS/MacSync")
        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(fileManager.createFile(atPath: executableURL.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let locatedURL = MacSyncCommandLocator.scheduledApplicationURL(
            environment: ["MAC_SYNC_APPLICATION": applicationURL.path],
            bundleURL: root.appendingPathComponent("NotAnApplication"),
            fileManager: fileManager
        )

        XCTAssertEqual(
            locatedURL?.resolvingSymlinksInPath().path,
            applicationURL.resolvingSymlinksInPath().path
        )
    }

    func testScheduledPathsUseTheFormulaOptPrefixAcrossUpgrades() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let versionRoot = root.appendingPathComponent("Cellar/mac-sync-current/current.42.test")
        let applicationURL = versionRoot.appendingPathComponent("MacSync.app")
        let appExecutable = applicationURL.appendingPathComponent("Contents/MacOS/MacSync")
        let commandURL = versionRoot.appendingPathComponent("bin/mac-sync")
        try fileManager.createDirectory(
            at: appExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try fileManager.createDirectory(
            at: commandURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        XCTAssertTrue(fileManager.createFile(atPath: appExecutable.path, contents: Data()))
        XCTAssertTrue(fileManager.createFile(atPath: commandURL.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appExecutable.path)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)

        let optRoot = root.appendingPathComponent("opt/mac-sync-current")
        try fileManager.createDirectory(at: optRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: optRoot, withDestinationURL: versionRoot)

        XCTAssertEqual(
            MacSyncCommandLocator.scheduledExecutableURL(
                environment: [:],
                bundleURL: applicationURL,
                fileManager: fileManager,
            )?.path,
            optRoot.appendingPathComponent("bin/mac-sync").path,
        )
        XCTAssertEqual(
            MacSyncCommandLocator.scheduledApplicationURL(
                environment: [:],
                bundleURL: applicationURL,
                fileManager: fileManager,
            )?.path,
            optRoot.appendingPathComponent("MacSync.app").path,
        )
    }
}
