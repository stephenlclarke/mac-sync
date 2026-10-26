import Foundation
@testable import MacSyncCore
import XCTest

final class BackgroundArchitectureTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testStreamingComparisonHandlesEmptyDifferentAndLargeFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a")
        let b = root.appendingPathComponent("b")
        try Data().write(to: a)
        try Data().write(to: b)
        XCTAssertTrue(StreamingFileComparison.equal(a.path, b.path))
        let block = Data(repeating: 65, count: 64 * 1024)
        for url in [a, b] {
            let handle = try FileHandle(forWritingTo: url)
            for _ in 0 ..< 128 {
                try handle.write(contentsOf: block)
            }
            try handle.close()
        }
        XCTAssertTrue(StreamingFileComparison.equal(a.path, b.path))
        let handle = try FileHandle(forWritingTo: b)
        try handle.seek(toOffset: 4 * 1024 * 1024)
        try handle.write(contentsOf: Data([66]))
        try handle.close()
        XCTAssertFalse(StreamingFileComparison.equal(a.path, b.path))
        XCTAssertFalse(StreamingFileComparison.equal(a.path, root.appendingPathComponent("missing").path))
    }

    func testCaptureLimitFailsExplicitlyWhileDrainingBothPipes() {
        let result = ProcessRunner().run("/bin/sh", ["-c", "head -c 1048576 /dev/zero; head -c 1048576 /dev/zero >&2"], outputLimit: 4096)
        XCTAssertEqual(result.status, 75)
        XCTAssertEqual(result.stdout.utf8.count, 4096)
        XCTAssertLessThan(result.stderr.utf8.count, 4300)
        XCTAssertTrue(result.stderr.contains("safe capture limit"))
    }

    func testStreamingOutputDoesNotRetainTheFullTranscript() {
        var count = 0
        let result = ProcessRunner().run("/usr/bin/awk", ["BEGIN { for (i=0;i<20000;i++) print i }"], outputLimit: 1024, onStdoutLine: { _ in count += 1 })
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(count, 20000)
        XCTAssertTrue(result.stdout.isEmpty)
    }

    func testOversizedStreamLineFailsInsteadOfSilentlyTruncating() {
        let result = ProcessRunner().run("/usr/bin/head", ["-c", "1048576", "/dev/zero"], onStdoutLine: { _ in })
        XCTAssertEqual(result.status, 75)
    }

    func testCommandDeadlineStopsAStalledChild() {
        let started = Date()
        let result = ProcessRunner().run("/bin/sleep", ["30"], timeout: 0.1)
        XCTAssertEqual(result.status, 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testEscapedPipeOwnerCannotKeepAReadTaskAliveForever() {
        let started = Date()
        let result = ProcessRunner().run("/bin/sh", ["-c", "sleep 3 & exit 0"], timeout: 1)
        XCTAssertTrue(result.status == 0 || result.status == 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testBackgroundBackoffSurvivesRestartAndIsBounded() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("checkpoint.json").path
        let now = Date(timeIntervalSince1970: 1000)
        var state = BackgroundCheckpoint.load(from: path)
        state.failed(now: now, authentication: false)
        XCTAssertEqual(state.nextAttempt, now.addingTimeInterval(900))
        for _ in 0 ..< 20 {
            state.failed(now: now, authentication: false)
        }
        XCTAssertEqual(state.nextAttempt, now.addingTimeInterval(6 * 3600))
        try state.save(to: path)
        XCTAssertEqual(BackgroundCheckpoint.load(from: path), state)
        state.failed(now: now, authentication: true)
        XCTAssertEqual(state.nextAttempt, now.addingTimeInterval(12 * 3600))
        state.repository = root.appendingPathComponent("old-repository").path
        try state.save(to: path)
        let changedRepository = BackgroundCheckpoint.load(from: path, repository: root.appendingPathComponent("new-repository").path)
        XCTAssertEqual(changedRepository.consecutiveFailures, 0)
        XCTAssertNil(changedRepository.nextAttempt)
        XCTAssertEqual(BackgroundCheckpoint.load(from: path, repository: state.repository), state)
        try Data(repeating: 0, count: 65537).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(BackgroundCheckpoint.load(from: path), BackgroundCheckpoint())
    }

    func testJournalExportsCompatibleJSONAndPagesItsSQLiteEntries() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try HistoryJournal(directory: root.path)
        for index in 0 ..< 600 {
            try journal.append(SyncHistoryEntry(id: "entry-\(index)", direction: .upload, outcome: .updated, path: "file-\(index)", source: "/source", destination: "/snapshot"))
        }
        let record = SyncHistoryRecord(id: journal.id, action: .sync, result: .success,
                                       timing: SyncHistoryTiming(startedAt: "start", finishedAt: "finish", durationSeconds: 1), entries: [],
                                       diagnostics: SyncHistoryDiagnostics(warningCount: 0, errorCount: 0, warnings: [], errors: []))
        try journal.finish(record)
        let store = try LocalHistoryStore(directory: root.path)
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.page(), [record])
        XCTAssertEqual(try store.entryCount(runID: journal.id), 600)
        XCTAssertEqual(try store.entries(runID: journal.id).count, 200)
        XCTAssertEqual(try store.entries(runID: journal.id, offset: 200).first?.id, "entry-200")
        XCTAssertEqual(try store.entries(runID: journal.id, limit: 10000).count, 500)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        let exported = try JSONDecoder().decode(SyncHistoryRecord.self, from: Data(contentsOf: file))
        XCTAssertEqual(exported.entries.count, 600)
        try store.importLegacy(directory: root.path)
        try store.importLegacy(directory: root.path)
        XCTAssertEqual(try store.count(), 1)
    }

    func testHistoryPagesAndLegacyImportAreBoundedAndIdempotent() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalHistoryStore(directory: root.path)
        for index in 0 ..< 125 {
            let record = SyncHistoryRecord(id: "run-\(index)", action: .sync, result: .success,
                                           timing: SyncHistoryTiming(startedAt: "start", finishedAt: "finish", durationSeconds: 1), entries: [],
                                           diagnostics: SyncHistoryDiagnostics(warningCount: 0, errorCount: 0, warnings: [], errors: []))
            try store.finish(record, entryCount: 0, ordering: Double(index))
        }
        XCTAssertEqual(try store.page().count, 50)
        XCTAssertEqual(try store.page().first?.id, "run-124")
        XCTAssertEqual(try store.page(offset: 100).count, 25)
        XCTAssertEqual(try store.page(limit: 10000).count, 100)
        XCTAssertEqual(try store.page(offset: 200).count, 0)
        try Data("bad json".utf8).write(to: root.appendingPathComponent("bad.json"))
        try store.importLegacy(directory: root.path)
        XCTAssertEqual(try store.count(), 125)
    }

    func testLegacyReaderStreamsLargeEscapedUnicodeEntriesAndRejectsCorruption() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try HistoryJournal(directory: root.path)
        let path = "folder/quoted-\"-brace-}-café-☕/" + String(repeating: "a", count: 1024)
        for index in 0 ..< 18000 {
            try journal.append(SyncHistoryEntry(id: "entry-\(index)", direction: .upload, outcome: .updated, path: path, source: "/source", destination: "/snapshot"))
        }
        let record = SyncHistoryRecord(id: journal.id, action: .sync, result: .deferred,
                                       timing: SyncHistoryTiming(startedAt: "start", finishedAt: "finish", durationSeconds: 1), entries: [],
                                       diagnostics: SyncHistoryDiagnostics(warningCount: 0, errorCount: 0, warnings: [], errors: []))
        try journal.finish(record)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        XCTAssertGreaterThan(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 16 * 1024 * 1024)
        let importedRoot = root.appendingPathComponent("imported")
        try FileManager.default.createDirectory(at: importedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: importedRoot.appendingPathComponent(file.lastPathComponent))
        let store = try LocalHistoryStore(directory: importedRoot.path)
        try store.importLegacy(directory: importedRoot.path)
        XCTAssertEqual(try store.entryCount(runID: journal.id), 18000)
        XCTAssertEqual(try store.entries(runID: journal.id).first?.path, path)
        try Data("{\"entries\":[{broken}".utf8).write(to: root.appendingPathComponent("broken.json"))
        XCTAssertThrowsError(try StreamingHistoryReader.read(root.appendingPathComponent("broken.json")) { _ in })
        try Data("{\"entries\":[]}".utf8).write(to: root.appendingPathComponent("empty.json"))
        XCTAssertThrowsError(try StreamingHistoryReader.read(root.appendingPathComponent("empty.json")) { _ in })
    }

    func testStreamingFingerprintAndAppOwnedAgentMigration() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try StreamingFileFingerprint.sha256(file.path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let runner = ProcessRunner()
        try BackgroundAgentMigration.migrate(homeDirectory: root.path, executable: "/bin/false", runner: runner)
        let agent = root.appendingPathComponent("Library/LaunchAgents/tools.xyzzy.mac-sync.plist")
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let values: [String: Any] = ["Label": "tools.xyzzy.mac-sync", "ProgramArguments": ["/old/bin/mac-sync", "run"], "EnvironmentVariables": ["MAC_SYNC_SECRETS": "0"]]
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: agent)
        try BackgroundAgentMigration.migrate(homeDirectory: root.path, executable: "/opt/homebrew/Cellar/mac-sync/1.1.0/bin/mac-sync", runner: runner)
        let migrated = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: agent), format: nil) as? [String: Any])
        XCTAssertEqual(migrated["ProgramArguments"] as? [String], ["/opt/homebrew/opt/mac-sync/bin/mac-sync", "run"])
        XCTAssertEqual(migrated["Nice"] as? Int, 10)
        XCTAssertEqual((migrated["EnvironmentVariables"] as? [String: String])?["MAC_SYNC_SECRETS"], "0")
        let before = try Data(contentsOf: agent)
        try BackgroundAgentMigration.migrate(homeDirectory: root.path, executable: "/opt/homebrew/Cellar/mac-sync/1.1.0/bin/mac-sync", runner: runner)
        XCTAssertEqual(try Data(contentsOf: agent), before)
        _ = BackgroundResources().deferralReason
    }
}
