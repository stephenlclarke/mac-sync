import Foundation
@testable import MacSyncApp
import XCTest

final class SnapshotContentsTreeTests: XCTestCase {
    func testGroupsNestedFilesUnderFolders() {
        let tree = SnapshotContentsTree.nodes(for: [
            file("~/Library/Application Support/Code/User/settings.json"),
            folder("~/Library"),
            folder("~/Library/Application Support"),
            folder("~/Library/Application Support/Code"),
            folder("~/Library/Application Support/Code/User"),
            file("~/.zshrc"),
        ])

        XCTAssertEqual(tree.map(\.file.displayPath), ["~/Library", "~/.zshrc"])
        XCTAssertEqual(tree[0].title, "~/Library")
        XCTAssertEqual(tree[0].contents, SnapshotFolderContents(fileCount: 1, folderCount: 3))
        XCTAssertEqual(tree[0].children?.map(\.file.displayPath), ["~/Library/Application Support"])
        XCTAssertEqual(tree[0].children?[0].title, "Application Support")
        XCTAssertEqual(tree[0].children?[0].children?.map(\.file.displayPath), ["~/Library/Application Support/Code"])
        XCTAssertEqual(
            tree[0].children?[0].children?[0].children?[0].children?.map(\.file.displayPath),
            ["~/Library/Application Support/Code/User/settings.json"]
        )
    }

    func testCreatesCollapsibleParentsWhenDirectoryEntriesAreAbsent() {
        let tree = SnapshotContentsTree.nodes(for: [
            file("/Applications/Example.app/Contents/Info.plist"),
        ])

        XCTAssertEqual(tree.map(\.file.displayPath), ["/Applications"])
        XCTAssertEqual(tree[0].file.kind, .folder)
        XCTAssertEqual(tree[0].contents, SnapshotFolderContents(fileCount: 1, folderCount: 2))
        XCTAssertEqual(tree[0].children?.map(\.file.displayPath), ["/Applications/Example.app"])
    }

    func testProvidesAllParentsNeededToRevealAnItem() {
        XCTAssertEqual(
            SnapshotContentsTree.ancestorPaths(for: "~/Library/Application Support/Code/User/settings.json"),
            [
                "~/Library",
                "~/Library/Application Support",
                "~/Library/Application Support/Code",
                "~/Library/Application Support/Code/User",
                "~/Library/Application Support/Code/User/settings.json",
            ]
        )
    }

    func testRestorePathsKeepAbsoluteRootsAndRemoveNestedDuplicates() {
        XCTAssertEqual(
            SnapshotContentsTree.restorePaths(for: [
                "~/Library/Application Support/Code",
                "~/Library/Application Support/Code/User/settings.json",
                "~/Library",
                "/Applications/Example.app",
                "/Applications/Example.app/Contents/Info.plist",
            ]),
            ["Library", "/Applications/Example.app"]
        )
    }

    private func file(_ path: String) -> SnapshotFile {
        SnapshotFile(displayPath: path, kind: .file, byteCount: 42, modifiedAt: nil)
    }

    private func folder(_ path: String) -> SnapshotFile {
        SnapshotFile(displayPath: path, kind: .folder, byteCount: 0, modifiedAt: nil)
    }
}
