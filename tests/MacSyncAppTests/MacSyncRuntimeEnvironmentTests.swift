@testable import MacSyncApp
import XCTest

final class MacSyncRuntimeEnvironmentTests: XCTestCase {
    func testPreparesFinderEnvironmentWithHomebrewAndSystemCommandDirectories() {
        let environment = MacSyncRuntimeEnvironment.prepared(["PATH": "/usr/bin:/bin"])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/Applications/Visual Studio Code.app/Contents/Resources/app/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    func testPreparesPathWithoutDuplicatingExistingDirectories() {
        let environment = MacSyncRuntimeEnvironment.prepared([
            "PATH": "/custom/bin:/opt/homebrew/bin:/usr/bin",
        ])

        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertEqual(paths.last, "/custom/bin")
    }
}
