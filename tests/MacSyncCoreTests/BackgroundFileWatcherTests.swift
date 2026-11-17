import Darwin
import Foundation
@testable import MacSyncCore
import XCTest

final class BackgroundFileWatcherTests: XCTestCase {
    func testActualWatchWorkerSyncsChangesWithoutSchedulingItselfForever() throws {
        let adjacent = Bundle(for: BackgroundFileWatcherTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("mac-sync")
        let fallback = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/mac-sync")
        let binary = FileManager.default.isExecutableFile(atPath: adjacent.path) ? adjacent : fallback
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Build the CLI before the process-level watcher test") }
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("first", to: fixture.source)
        var preferences = BackupPreferences()
        preferences.allowLowPowerMode = true
        preferences.pausedUntil = Date().addingTimeInterval(4)
        try preferences.save(directory: fixture.status.path, machine: "target")
        let process = Process()
        process.executableURL = binary
        process.arguments = ["watch"]
        var environment = fixture.environment
        environment["LLVM_PROFILE_FILE"] = ProcessInfo.processInfo.environment["LLVM_PROFILE_FILE"]
        environment["ASAN_OPTIONS"] = ProcessInfo.processInfo.environment["ASAN_OPTIONS"]
        environment["TSAN_OPTIONS"] = ProcessInfo.processInfo.environment["TSAN_OPTIONS"]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
            if ended.wait(timeout: .now() + 12) == .timedOut, process.isRunning {
                XCTFail("The watcher did not stop gracefully")
                kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
            }
        }
        let checkpointPath = fixture.status.appendingPathComponent("target.background.json").path
        let initialDeadline = Date().addingTimeInterval(25)
        while Date() < initialDeadline, BackgroundCheckpoint.load(from: checkpointPath).lastSuccess == nil {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let first = try XCTUnwrap(BackgroundCheckpoint.load(from: checkpointPath).lastSuccess)
        XCTAssertEqual(try String(contentsOf: fixture.snapshot, encoding: .utf8), "first")
        // More than debounce + stream latency: self-generated checkpoint or
        // manifest writes must not trigger an endless sequence of workers.
        Thread.sleep(forTimeInterval: 24)
        XCTAssertEqual(BackgroundCheckpoint.load(from: checkpointPath).lastSuccess, first)
        try fixture.write("other", to: fixture.source)
        let deadline = Date().addingTimeInterval(35)
        while Date() < deadline, (try? String(contentsOf: fixture.snapshot, encoding: .utf8)) != "other" {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(try String(contentsOf: fixture.snapshot, encoding: .utf8), "other")
        XCTAssertTrue(process.isRunning)
    }

    func testDebouncesBurstsAndRetainsEventsDuringWorker() {
        let now = Date(timeIntervalSince1970: 1000)
        var policy = WatchSyncPolicy(interval: 3600, now: now)
        XCTAssertTrue(policy.begin(now: now))
        XCTAssertFalse(policy.begin(now: now))
        policy.changed(now: now.addingTimeInterval(1))
        policy.finished(success: true, now: now.addingTimeInterval(2))
        XCTAssertFalse(policy.begin(now: now.addingTimeInterval(10)))
        XCTAssertTrue(policy.begin(now: now.addingTimeInterval(17)))
        policy.finished(success: true, now: now.addingTimeInterval(18))
        for second in 19 ... 40 {
            policy.changed(now: now.addingTimeInterval(Double(second)))
        }
        XCTAssertFalse(policy.begin(now: now.addingTimeInterval(50)))
        XCTAssertTrue(policy.begin(now: now.addingTimeInterval(55)))
        policy.finished(success: true, now: now.addingTimeInterval(56))
        XCTAssertFalse(policy.begin(now: now.addingTimeInterval(100)))
        XCTAssertTrue(policy.begin(now: now.addingTimeInterval(3656)))
    }

    func testContinuousEditsHaveMaximumDelayAndFailuresKeepDirtyWork() {
        let now = Date(timeIntervalSince1970: 1000)
        var policy = WatchSyncPolicy(interval: 3600, now: now)
        XCTAssertTrue(policy.begin(now: now))
        policy.finished(success: true, now: now)
        for second in 1 ... 121 {
            policy.changed(now: now.addingTimeInterval(Double(second)))
        }
        XCTAssertTrue(policy.begin(now: now.addingTimeInterval(121)))
        let retry = now.addingTimeInterval(2000)
        policy.finished(success: false, now: now.addingTimeInterval(122), deferredUntil: retry)
        policy.changed(now: now.addingTimeInterval(130))
        XCTAssertFalse(policy.begin(now: now.addingTimeInterval(500)))
        XCTAssertTrue(policy.begin(now: retry))
        policy.finished(success: true, now: retry)
        XCTAssertEqual(policy.completed, policy.generation)
    }

    func testRealEventsDetectAtomicSavesAndIgnoreUnselectedSiblings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("settings")
        let hit = expectation(description: "selected file changed")
        hit.assertForOverFulfill = false
        let observation = try FolderChangeObservation(paths: [selected.path], queue: DispatchQueue(label: "watch-test")) { _ in hit.fulfill() }
        defer { withExtendedLifetime(observation) {} }
        XCTAssertTrue(observation.matches(selected.appendingPathComponent("child").path))
        XCTAssertTrue(observation.matches(root.path))
        XCTAssertFalse(observation.matches(root.appendingPathComponent("settings-unselected").path))
        try Data("new setting".utf8).write(to: selected, options: .atomic)
        wait(for: [hit], timeout: 12)
    }
}
