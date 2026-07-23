@testable import MacSyncApp
import XCTest

final class PathOutlineTreeTests: XCTestCase {
    func testGroupsConfiguredPathsUnderExpandableFolders() {
        let tree = PathOutlineTree.nodes(for: [
            item("bin/run_all_blades.sh"),
            item("bin/run_remote_command.sh"),
            item("Library/Application Support/Code/User/settings.json"),
            item(".zshrc"),
        ])

        XCTAssertEqual(tree.map(\.path), ["bin", "Library", ".zshrc"])
        XCTAssertEqual(tree[0].title, "bin")
        XCTAssertFalse(tree[0].isExplicitSelection)
        XCTAssertEqual(tree[0].children?.map(\.path), ["bin/run_all_blades.sh", "bin/run_remote_command.sh"])
        XCTAssertEqual(tree[1].children?.first?.path, "Library/Application Support")
        XCTAssertTrue(tree[2].isExplicitSelection)
    }

    func testRetainsAnExplicitFolderAsASelectableRoot() {
        let tree = PathOutlineTree.nodes(for: [
            PathOutlineItem(path: "Library", kind: .folder),
            item("Library/Application Support/Code/User/settings.json"),
        ])

        XCTAssertEqual(tree.map(\.path), ["Library"])
        XCTAssertTrue(tree[0].isExplicitSelection)
        XCTAssertEqual(tree[0].kind, .folder)
        XCTAssertEqual(tree[0].children?.first?.path, "Library/Application Support")
    }

    private func item(_ path: String) -> PathOutlineItem {
        PathOutlineItem(path: path, kind: .file)
    }
}
