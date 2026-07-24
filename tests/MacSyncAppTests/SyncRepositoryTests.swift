import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncRepositoryTests: XCTestCase {
    private let fileManager = FileManager.default

    func testLoadsCurrentAndPeerSnapshotWithoutListingSecretContents() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }

        try write(
            """
            # selected paths
            .zshrc
            .config/example
            """,
            to: fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt")
        )
        try write(".config/example", to: fixture.data.appendingPathComponent("machines/peer/config/sync-paths.txt"))
        try write("current shell", to: fixture.data.appendingPathComponent("machines/local/home/.zshrc"))
        try write("peer shell", to: fixture.data.appendingPathComponent("machines/peer/home/.zshrc"))
        try write("Finder metadata", to: fixture.data.appendingPathComponent("machines/.DS_Store"))
        try write("age1sharedrecipient", to: fixture.data.appendingPathComponent("machines/_shared/config/age-recipients.txt"))
        try write("setting", to: fixture.data.appendingPathComponent("machines/peer/home/.config/example/settings.json"))
        try write("hidden", to: fixture.data.appendingPathComponent("machines/peer/secrets/included-paths.txt"))
        try write("encrypted", to: fixture.data.appendingPathComponent("machines/peer/secrets/secrets.tar.gz.age"))
        try write(
            machineMetadata(computerName: "Peer Mac"),
            to: fixture.data.appendingPathComponent("machines/peer/MACHINE.md")
        )
        try write(
            """
            result=success
            updated_file_count=3
            storage_byte_count=42
            """,
            to: fixture.status.appendingPathComponent("local.env")
        )

        let overview = SyncRepository(environment: fixture.environment).load()

        XCTAssertEqual(overview.status.result, .success)
        XCTAssertEqual(overview.status.updatedFileCount, 3)
        XCTAssertEqual(overview.currentMachine?.name, "local")
        XCTAssertEqual(overview.peerMachines.map(\.name), ["peer"])
        XCTAssertFalse(overview.peerMachines.contains { $0.name == "_shared" })
        XCTAssertEqual(overview.peerMachines.first?.computerName, "Peer Mac")
        XCTAssertTrue(overview.peerMachines.first?.hasEncryptedSecrets == true)
        XCTAssertTrue(overview.peerMachines.first?.files.contains { $0.displayPath == "~/.zshrc" } == true)
        XCTAssertFalse(overview.peerMachines.first?.files.contains { $0.displayPath.contains("secrets") } == true)
        XCTAssertEqual(overview.peerMachines.first?.configuredPaths.map(\.path), [".config/example"])
    }

    func testLoadsRecordedCurrentMachineLocalChanges() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try write(
            "result=success\n",
            to: fixture.status.appendingPathComponent("local.env")
        )
        try write(
            "WARN: current machine snapshot has local changes; skipping pre-operation git pull\n",
            to: fixture.status.appendingPathComponent("local.warnings.log")
        )
        try write(
            " M machines/local/home/.zshrc\n?? machines/local/home/.config/tool/new-setting.json\n",
            to: fixture.status.appendingPathComponent("local.local-changes.log")
        )

        let overview = SyncRepository(environment: fixture.environment).load()

        XCTAssertEqual(
            overview.status.recordedLocalChanges,
            [
                " M machines/local/home/.zshrc",
                "?? machines/local/home/.config/tool/new-setting.json",
            ]
        )
        XCTAssertNil(overview.status.currentLocalChanges)
    }

    func testClearsStaleStatusAndHistoryForAConfigOnlyFreshCheckout() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)
        try fileManager.removeItem(at: fixture.data.appendingPathComponent("machines/local/home"))
        try write(".zshrc\n", to: fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt"))
        try write("result=success\n", to: fixture.status.appendingPathComponent("local.env"))
        try write("old warning\n", to: fixture.status.appendingPathComponent("local.warnings.log"))
        try write("old error\n", to: fixture.status.appendingPathComponent("local.errors.log"))
        try write(" M machines/local/home/.zshrc\n", to: fixture.status.appendingPathComponent("local.local-changes.log"))
        try write("previous run\n", to: fixture.status.appendingPathComponent("history/local/old-run.json"))

        XCTAssertTrue(try repository.clearStaleLocalStatusWhenSnapshotIsMissing())

        XCTAssertEqual(repository.load().status, .empty)
        XCTAssertTrue(repository.load().history.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.status.appendingPathComponent("local.env").path))
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.status.appendingPathComponent("history/local").path))
    }

    func testPreservesStatusWhenTheCurrentSnapshotExists() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)
        try write("current shell\n", to: fixture.data.appendingPathComponent("machines/local/home/.zshrc"))
        try write("result=success\n", to: fixture.status.appendingPathComponent("local.env"))

        XCTAssertFalse(try repository.clearStaleLocalStatusWhenSnapshotIsMissing())
        XCTAssertEqual(repository.load().status.result, .success)
    }

    func testSeparatesCurrentSnapshotChangesFromHistoricalWarning() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        XCTAssertEqual(ProcessRunner().run("git", ["-C", fixture.data.path, "init"]).status, 0)
        try write(
            "result=success\n",
            to: fixture.status.appendingPathComponent("local.env")
        )
        try write(
            "WARN: current machine snapshot has local changes; skipping pre-operation git pull\n",
            to: fixture.status.appendingPathComponent("local.warnings.log")
        )
        try write("shell", to: fixture.data.appendingPathComponent("machines/local/home/.zshrc"))

        let overview = SyncRepository(environment: fixture.environment).load()

        XCTAssertEqual(overview.status.recordedLocalChanges, [])
        XCTAssertEqual(overview.status.currentLocalChanges, ["?? machines/local/home/.zshrc"])
    }

    func testSaveConfiguredPathsNormalizesAndPreservesOrder() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)
        let pathsFile = fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt")
        try write(
            """
            # existing header
            .zshrc
            .config/tool
            """,
            to: pathsFile
        )

        try repository.saveConfiguredPaths([" .zshrc ", ".config/tool", ".zshrc"])

        XCTAssertEqual(repository.configuredPaths(), [".zshrc", ".config/tool"])
        XCTAssertEqual(
            try String(contentsOf: pathsFile, encoding: .utf8),
            "# existing header\n.zshrc\n.config/tool"
        )
    }

    func testRemoveArchivedConfiguredRootDeletesArchiveAndUpdatesSelection() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)
        let pathsFile = fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt")
        let removedArchive = fixture.data.appendingPathComponent("machines/local/home/.zshrc")
        let retainedArchive = fixture.data.appendingPathComponent("machines/local/home/.config/tool")
        try write(".zshrc\n.config/tool\n", to: pathsFile)
        try write("shell", to: removedArchive)
        try write("setting", to: retainedArchive)

        try repository.removeArchivedConfiguredPath(".zshrc")

        XCTAssertEqual(repository.configuredPaths(), [".config/tool"])
        XCTAssertFalse(fileManager.fileExists(atPath: removedArchive.path))
        XCTAssertTrue(fileManager.fileExists(atPath: retainedArchive.path))
    }

    func testRemoveArchivedConfiguredRootAllowsAnEmptySelection() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)
        let pathsFile = fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt")
        let archive = fixture.data.appendingPathComponent("machines/local/home/.zshrc")
        try write(".zshrc\n", to: pathsFile)
        try write("shell", to: archive)

        try repository.removeArchivedConfiguredPath(".zshrc")

        XCTAssertEqual(repository.configuredPaths(), [])
        XCTAssertFalse(fileManager.fileExists(atPath: archive.path))
    }

    func testPathForUserSelectionMakesHomePathsPortable() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let repository = SyncRepository(environment: fixture.environment)

        XCTAssertEqual(
            repository.pathForUserSelection(fixture.home.appendingPathComponent(".config/tool")),
            ".config/tool"
        )
        XCTAssertEqual(
            repository.pathForUserSelection(URL(fileURLWithPath: "/Applications/Example.app")),
            "/Applications/Example.app"
        )
    }

    @MainActor
    func testStoreAddsFinderURLsAsSyncSelections() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let store = SyncStore(environment: fixture.environment)
        let homeFile = fixture.home.appendingPathComponent(".config/tool/settings.json")
        let externalFolder = URL(fileURLWithPath: "/Applications/Example.app")

        store.add(fileURLs: [homeFile, externalFolder, homeFile])

        XCTAssertEqual(store.selectedPaths, [".config/tool/settings.json", "/Applications/Example.app"])
    }

    func testLoadsNewestLocalSyncHistoryRecord() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let record = SyncHistoryRecord(
            id: "run-1",
            action: .restore,
            sourceMachine: "peer",
            result: .success,
            timing: SyncHistoryTiming(
                startedAt: "2026-07-23 10:00:00 BST",
                finishedAt: "2026-07-23 10:00:02 BST",
                durationSeconds: 2
            ),
            entries: [
                SyncHistoryEntry(
                    id: "entry-1",
                    direction: .download,
                    outcome: .new,
                    path: ".zshrc",
                    source: "/snapshot/.zshrc",
                    destination: "/home/.zshrc"
                ),
            ],
            diagnostics: SyncHistoryDiagnostics(
                warningCount: 0,
                errorCount: 0,
                warnings: [],
                errors: []
            )
        )
        let historyFile = fixture.status.appendingPathComponent("history/local/0000000000001-run-1.json")
        try fileManager.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: historyFile)

        let overview = SyncRepository(environment: fixture.environment).load()

        XCTAssertEqual(overview.history, [record])
        XCTAssertEqual(overview.history.first?.entries.first?.direction, .download)
        XCTAssertEqual(overview.history.first?.entries.first?.outcome, .new)
    }

    @MainActor
    func testStoreSeedsLegacySelectionForANewDataCheckout() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        try fileManager.createDirectory(at: fixture.data.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try write(
            "# existing selection\n.zshrc\n.config/tool\n",
            to: fixture.home.appendingPathComponent("github/mac-sync/config/sync-paths.txt")
        )
        try write(
            ".cache\n",
            to: fixture.home.appendingPathComponent("github/mac-sync/config/excludes.txt")
        )
        try write(
            "age1example\n",
            to: fixture.home.appendingPathComponent("github/mac-sync/config/age-recipients.txt")
        )

        let store = SyncStore(environment: fixture.environment)

        XCTAssertTrue(store.isSetupComplete)
        XCTAssertEqual(store.selectedPaths, [".zshrc", ".config/tool"])
        XCTAssertEqual(
            try String(
                contentsOf: fixture.data.appendingPathComponent("machines/local/config/sync-paths.txt"),
                encoding: .utf8
            ),
            "# existing selection\n.zshrc\n.config/tool\n"
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.data.appendingPathComponent("machines/local/config/excludes.txt"), encoding: .utf8),
            ".cache\n"
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.data.appendingPathComponent("machines/_shared/config/age-recipients.txt"), encoding: .utf8),
            "age1example\n"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.data.appendingPathComponent("machines/local/config/age-recipients.txt").path))
    }

    private func makeFixture() throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home")
        let data = root.appendingPathComponent("mac-sync-data")
        let status = root.appendingPathComponent("status")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data.appendingPathComponent("machines/local/home"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data.appendingPathComponent("machines/peer/home"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: status, withIntermediateDirectories: true)

        let environment = [
            "HOME": home.path,
            "MAC_SYNC_MACHINES_REPO": data.path,
            "MAC_SYNC_STATUS_DIR": status.path,
            "MAC_SYNC_MACHINE": "local",
        ]
        return Fixture(root: root, home: home, data: data, status: status, environment: environment)
    }

    private func write(_ text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func machineMetadata(computerName: String) -> String {
        let quote = "\u{0060}"
        return "- ComputerName: \(quote)\(computerName)\(quote)\n"
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let data: URL
    let status: URL
    let environment: [String: String]
}
