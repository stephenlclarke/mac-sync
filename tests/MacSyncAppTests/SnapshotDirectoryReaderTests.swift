import Foundation
@testable import MacSyncApp
import XCTest

final class SnapshotDirectoryReaderTests: XCTestCase {
    func testDirectoryPagesDoNotEnumerateDescendants() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("machines/local/home")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: directory.appendingPathComponent("nested/deep"))
        for index in 0 ..< 205 {
            try Data().write(to: directory.appendingPathComponent("file-\(index)"))
        }
        let reader = SnapshotDirectoryReader(dataRepository: root.path)
        let first = try reader.page(machine: "local", directory: "~/")
        let second = try reader.page(machine: "local", directory: "~/", offset: 100)
        let third = try reader.page(machine: "local", directory: "~/", offset: 200)
        XCTAssertEqual(first.files.count, 100)
        XCTAssertTrue(first.hasNext)
        XCTAssertEqual(second.files.count, 100)
        XCTAssertEqual(third.files.count, 6)
        XCTAssertFalse(third.hasNext)
        XCTAssertFalse(first.files.contains { $0.displayPath.hasSuffix("deep") })
        XCTAssertEqual(try reader.page(machine: "local", directory: "~/nested/").files.count, 1)
        XCTAssertThrowsError(try reader.page(machine: "../bad", directory: "~/"))
        XCTAssertThrowsError(try reader.page(machine: "local", directory: "~/../"))
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("outside").path, withDestinationPath: "/private")
        XCTAssertThrowsError(try reader.page(machine: "local", directory: "~/outside/"))
    }
}
