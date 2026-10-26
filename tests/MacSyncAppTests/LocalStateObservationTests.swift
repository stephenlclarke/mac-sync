import Foundation
@testable import MacSyncApp
import XCTest

final class LocalStateObservationTests: XCTestCase {
    func testCoalescesAStatusWriteBurst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let changed = expectation(description: "Coalesced status refresh")
        changed.assertForOverFulfill = true
        let observer = try XCTUnwrap(LocalStateObservation(directory: root.path) { changed.fulfill() })
        for index in 0 ..< 20 {
            try Data("status".utf8).write(to: root.appendingPathComponent("\(index).env"), options: .atomic)
        }
        withExtendedLifetime(observer) { wait(for: [changed], timeout: 3) }
    }

    func testObservesTheParentUntilAStatusDirectoryExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let changed = expectation(description: "New status directory")
        let status = root.appendingPathComponent("status")
        let observer = try XCTUnwrap(LocalStateObservation(directory: status.path) { changed.fulfill() })
        try FileManager.default.createDirectory(at: status, withIntermediateDirectories: true)
        withExtendedLifetime(observer) { wait(for: [changed], timeout: 3) }
    }
}
