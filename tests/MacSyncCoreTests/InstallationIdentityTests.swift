import Foundation
@testable import MacSyncCore
import XCTest

final class InstallationIdentityTests: XCTestCase {
    func testExplicitHandoffPreservesIdentityAndNeverReplacesAnother() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("device-id")
        let identity = Data(UUID().uuidString.utf8)
        try identity.write(to: source)
        let status = root.appendingPathComponent("new-status")
        try InstallationIdentity.importIdentity(from: source, statusDirectory: status)
        XCTAssertEqual(try Data(contentsOf: status.appendingPathComponent("device-id")), identity)
        XCTAssertNoThrow(try InstallationIdentity.importIdentity(from: source, statusDirectory: status))
        try Data(UUID().uuidString.utf8).write(to: source)
        XCTAssertThrowsError(try InstallationIdentity.importIdentity(from: source, statusDirectory: status))
        XCTAssertEqual(try Data(contentsOf: status.appendingPathComponent("device-id")), identity)
    }

    func testRejectsArbitraryOrOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("device-id")
        try Data(repeating: 65, count: 129).write(to: source)
        XCTAssertThrowsError(try InstallationIdentity.importIdentity(from: source, statusDirectory: root.appendingPathComponent("status")))
        try Data("invalid".utf8).write(to: source)
        XCTAssertThrowsError(try InstallationIdentity.importIdentity(from: source, statusDirectory: root.appendingPathComponent("status")))
    }
}
