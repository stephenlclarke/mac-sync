import Foundation
@testable import MacSyncApp
import XCTest

final class SnapshotFileInspectorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testReadsBoundedTextPreviewFromTheMachineSnapshot() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let fileURL = fixture.machineHome.appendingPathComponent(".config/example.txt")
        try write("line one\nline two\n", to: fileURL)
        let inspector = SnapshotFileInspector(dataRepository: fixture.data.path)

        let inspection = try inspector.inspect(
            machineName: "peer",
            file: file("~/.config/example.txt")
        )

        XCTAssertEqual(inspection.url, fileURL)
        XCTAssertEqual(inspection.byteCount, 18)
        XCTAssertFalse(inspection.isBinary)
        XCTAssertEqual(inspection.content, .text("line one\nline two\n", isTruncated: false))
    }

    func testTreatsNullContainingFilesAsBinary() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try write(Data([0x00, 0x01, 0xFF]), to: fixture.machineHome.appendingPathComponent("payload.bin"))
        let inspector = SnapshotFileInspector(dataRepository: fixture.data.path)

        let inspection = try inspector.inspect(machineName: "peer", file: file("~/payload.bin"))

        XCTAssertTrue(inspection.isBinary)
        XCTAssertEqual(inspection.content, .binary)
    }

    func testTruncatesTextPreviewAtTheConfiguredLimit() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let contents = String(repeating: "a", count: SnapshotFileInspector.maximumPreviewByteCount + 1)
        try write(contents, to: fixture.machineHome.appendingPathComponent("large.txt"))
        let inspector = SnapshotFileInspector(dataRepository: fixture.data.path)

        let inspection = try inspector.inspect(machineName: "peer", file: file("~/large.txt"))

        guard case let .text(preview, isTruncated) = inspection.content else {
            return XCTFail("Expected a text preview")
        }
        XCTAssertTrue(isTruncated)
        XCTAssertEqual(preview.utf8.count, SnapshotFileInspector.maximumPreviewByteCount)
    }

    func testRejectsSnapshotPathThatResolvesOutsideTheMachineArchive() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let outsideFile = fixture.root.appendingPathComponent("outside.txt")
        try write("not part of the snapshot", to: outsideFile)
        let link = fixture.machineHome.appendingPathComponent("outside-link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outsideFile)
        let inspector = SnapshotFileInspector(dataRepository: fixture.data.path)

        XCTAssertThrowsError(try inspector.fileURL(machineName: "peer", file: file("~/outside-link"))) { error in
            XCTAssertEqual(error as? SnapshotFileInspectionError, .outsideSnapshot)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("mac-sync-data")
        let machineHome = data.appendingPathComponent("machines/peer/home")
        try fileManager.createDirectory(at: machineHome, withIntermediateDirectories: true)
        return Fixture(root: root, data: data, machineHome: machineHome)
    }

    private func file(_ displayPath: String) -> SnapshotFile {
        SnapshotFile(displayPath: displayPath, kind: .file, byteCount: 0, modifiedAt: nil)
    }

    private func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

private struct Fixture {
    let root: URL
    let data: URL
    let machineHome: URL
}
