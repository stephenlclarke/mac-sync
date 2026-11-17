import Foundation
@testable import MacSyncCore
import XCTest

@MainActor
final class MacSyncFileAccessTests: XCTestCase {
    func testPersistsGrantsBalancesLeasesAndRejectsSiblingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var starts = 0
        var stops = 0
        let backend = backend(start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        let file = root.appendingPathComponent("permissions.json")
        let access = try MacSyncFileAccess(file: file, backend: backend)
        try access.remember(folder)
        access.restore()
        access.restore()
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(access.covers(folder.appendingPathComponent("new-file.txt").path))
        XCTAssertFalse(access.covers(root.appendingPathComponent("source-other/file.txt").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        access.stop()
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(access.covers(folder.path))
        let restored = try MacSyncFileAccess(file: file, backend: backend)
        restored.restore()
        XCTAssertTrue(restored.covers(folder.path))
        restored.stop()
        XCTAssertEqual(starts, stops)
    }

    func testDeniedGrantDoesNotAuthorizeAccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let access = try MacSyncFileAccess(file: root.appendingPathComponent("permissions.json"), backend: backend(start: { _ in false }))
        try access.remember(root)
        XCTAssertEqual(access.unavailablePaths, [root.path])
        XCTAssertFalse(access.covers(root.path))
        access.stop()
    }

    func testFileGrantDoesNotAuthorizeDescendantsOrEscapingSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("source.txt")
        try Data("test".utf8).write(to: file)
        let access = try MacSyncFileAccess(file: root.appendingPathComponent("permissions.json"), backend: backend())
        try access.remember(file)
        XCTAssertTrue(access.covers(file.path))
        XCTAssertFalse(access.covers(file.appendingPathComponent("child").path))
        let folder = root.appendingPathComponent("granted")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape"), withDestinationURL: root)
        try access.remember(folder)
        XCTAssertFalse(access.covers(folder.appendingPathComponent("escape/source.txt").path + ".other"))
        access.stop()
    }

    func testMalformedPermissionFileFailsClosed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("broken-json".utf8).write(to: file)
        XCTAssertThrowsError(try MacSyncFileAccess(file: file, backend: backend()))
    }

    private func backend(start: @escaping (URL) -> Bool = { _ in true }, stop: @escaping (URL) -> Void = { _ in }) -> MacSyncFileAccessBackend {
        MacSyncFileAccessBackend(make: { Data($0.path.utf8) }, resolve: { URL(fileURLWithPath: String(decoding: $0, as: UTF8.self)) }, start: start, stop: stop)
    }
}
