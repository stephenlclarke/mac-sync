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
}
