import Foundation
@testable import MacSyncCore
import XCTest

final class MacSyncAccessPolicyTests: XCTestCase {
    func testWorkerUsesItsImmutableGrantSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("lease.json")
        try JSONEncoder().encode([MacSyncAccessRoot(path: root.appendingPathComponent("allowed").path, isDirectory: true)]).write(to: manifest)
        let env = ["MAC_SYNC_DISTRIBUTION": "app-store", "MAC_SYNC_PRIVATE_SUPPORT": root.path, "MAC_SYNC_ACCESS_MANIFEST": manifest.path]
        XCTAssertNoThrow(try MacSyncAccessPolicy.validate(paths: [root.appendingPathComponent("allowed/file").path], environment: env))
        XCTAssertThrowsError(try MacSyncAccessPolicy.validate(paths: [root.appendingPathComponent("allowed-sibling/file").path], environment: env))
        XCTAssertThrowsError(try MacSyncAccessPolicy.validate(paths: ["/ungranted"], environment: env))
        XCTAssertThrowsError(try MacSyncAccessPolicy.validate(paths: [], environment: ["MAC_SYNC_DISTRIBUTION": "app-store"]))
        XCTAssertNoThrow(try MacSyncAccessPolicy.validate(paths: ["/ungranted"], environment: [:]))
    }

    func testRejectsExternalManifestAndOversizedRoots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("lease.json")
        try JSONEncoder().encode(Array(repeating: MacSyncAccessRoot(path: "/", isDirectory: true), count: 4097)).write(to: manifest)
        var env = ["MAC_SYNC_DISTRIBUTION": "app-store", "MAC_SYNC_PRIVATE_SUPPORT": root.path, "MAC_SYNC_ACCESS_MANIFEST": manifest.path]
        XCTAssertThrowsError(try MacSyncAccessPolicy.validate(paths: [], environment: env))
        env["MAC_SYNC_PRIVATE_SUPPORT"] = root.appendingPathComponent("elsewhere").path
        XCTAssertThrowsError(try MacSyncAccessPolicy.validate(paths: [], environment: env))
    }
}
