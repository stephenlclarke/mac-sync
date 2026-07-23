import Darwin
import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class SyncScheduleManagerTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCreatesLaunchAgentForSelectedInterval() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeLaunchdRunner()
        let manager = scheduleManager(fixture: fixture, runner: runner)

        let status = try manager.configure(schedule: .interval(minutes: 4 * 60))

        XCTAssertEqual(status.state, .configured(.interval(minutes: 4 * 60)))
        XCTAssertEqual(status.detail, "Runs every 4 hours through this Mac's launchd agent.")
        let data = try Data(contentsOf: manager.agentURL)
        let propertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(propertyList["Label"] as? String, SyncScheduleManager.label)
        XCTAssertEqual((propertyList["StartInterval"] as? NSNumber)?.intValue, 4 * 60 * 60)
        XCTAssertEqual(propertyList["ProgramArguments"] as? [String], ["/tmp/mac-sync", "run"])
        let environment = try XCTUnwrap(propertyList["EnvironmentVariables"] as? [String: String])
        XCTAssertEqual(environment["MAC_SYNC_MACHINE"], "work-mac")
        XCTAssertEqual(environment["MAC_SYNC_MACHINES_REPO"], fixture.data.path)
        XCTAssertEqual(runner.arguments, [
            ["bootout", "gui/501", manager.agentURL.path],
            ["bootstrap", "gui/501", manager.agentURL.path],
        ])
    }

    func testDisablingRemovesOnlyTheAppOwnedLaunchAgent() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeLaunchdRunner()
        let manager = scheduleManager(fixture: fixture, runner: runner)
        _ = try manager.configure(schedule: .interval(minutes: 60))

        let status = try manager.configure(schedule: nil)

        XCTAssertEqual(status.state, .disabled)
        XCTAssertFalse(fileManager.fileExists(atPath: manager.agentURL.path))
        XCTAssertEqual(runner.arguments.last, ["bootout", "gui/501", manager.agentURL.path])
    }

    func testRejectsIntervalsOutsideTheSupportedRange() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let manager = scheduleManager(fixture: fixture, runner: FakeLaunchdRunner())

        XCTAssertThrowsError(try manager.configure(schedule: .interval(minutes: 14))) { error in
            XCTAssertEqual(error as? SyncScheduleError, .invalidSchedule)
        }
    }

    func testCreatesCalendarLaunchAgentForSelectedDaysAndTime() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeLaunchdRunner()
        let manager = scheduleManager(fixture: fixture, runner: runner)
        let schedule = SyncSchedule.calendar(
            days: [.monday, .wednesday, .friday],
            hour: 21,
            minute: 15
        )

        let status = try manager.configure(schedule: schedule)

        XCTAssertEqual(status.state, .configured(schedule))
        XCTAssertEqual(
            status.detail,
            "Runs every Mon, Wed, Fri at 21:15 through this Mac's launchd agent."
        )
        let data = try Data(contentsOf: manager.agentURL)
        let propertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let calendarEntries = try XCTUnwrap(propertyList["StartCalendarInterval"] as? [[String: Any]])
        XCTAssertEqual(
            calendarEntries.map { entry in
                [
                    (entry["Weekday"] as? NSNumber)?.intValue ?? -1,
                    (entry["Hour"] as? NSNumber)?.intValue ?? -1,
                    (entry["Minute"] as? NSNumber)?.intValue ?? -1,
                ]
            },
            [[1, 21, 15], [3, 21, 15], [5, 21, 15]]
        )
        XCTAssertNil(propertyList["StartInterval"])
    }

    private func makeFixture() throws -> Fixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home")
        let data = root.appendingPathComponent("mac-sync-data")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, data: data)
    }

    private func scheduleManager(fixture: Fixture, runner: FakeLaunchdRunner) -> SyncScheduleManager {
        SyncScheduleManager(
            configuration: SyncConfiguration(
                homeDirectory: fixture.home.path,
                dataRepository: fixture.data.path,
                statusDirectory: fixture.home.appendingPathComponent("Library/Application Support/mac-sync/status").path,
                machineName: "work-mac",
                pathsFile: fixture.data.appendingPathComponent("machines/work-mac/config/sync-paths.txt").path
            ),
            executableURL: URL(fileURLWithPath: "/tmp/mac-sync"),
            environment: ["PATH": "/custom/bin"],
            userID: uid_t(501),
            fileManager: fileManager,
            runner: runner
        )
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let data: URL
}

private final class FakeLaunchdRunner: LaunchdCommandRunning {
    private(set) var arguments = [[String]]()

    func run(arguments: [String]) -> CommandResult {
        self.arguments.append(arguments)
        return CommandResult(status: 0, stdout: "", stderr: "")
    }
}
