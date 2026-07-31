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
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        )
        XCTAssertEqual(propertyList["Label"] as? String, SyncScheduleManager.label)
        XCTAssertEqual((propertyList["StartInterval"] as? NSNumber)?.intValue, 4 * 60 * 60)
        XCTAssertEqual(propertyList["ProgramArguments"] as? [String], ["/tmp/mac-sync", "run"])
        let environment = try XCTUnwrap(propertyList["EnvironmentVariables"] as? [String: String])
        XCTAssertEqual(environment["MAC_SYNC_MACHINE"], "work-mac")
        XCTAssertEqual(environment["MAC_SYNC_MACHINES_REPO"], fixture.data.path)
        XCTAssertEqual(environment["HOME"], fixture.home.path)
        XCTAssertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertNotNil(environment["USER"])
        XCTAssertEqual(propertyList["ProcessType"] as? String, "Interactive")
        let applicationData = try Data(contentsOf: manager.applicationAgentURL)
        let applicationPropertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: applicationData, format: nil) as? [String: Any],
        )
        XCTAssertEqual(applicationPropertyList["Label"] as? String, SyncScheduleManager.applicationLabel)
        XCTAssertEqual(
            applicationPropertyList["ProgramArguments"] as? [String],
            ["/usr/bin/open", "-g", "/tmp/MacSync.app"],
        )
        XCTAssertEqual(applicationPropertyList["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(applicationPropertyList["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(runner.arguments, [
            ["bootout", "gui/501", manager.agentURL.path],
            ["bootout", "gui/501", manager.applicationAgentURL.path],
            ["bootstrap", "gui/501", manager.agentURL.path],
            ["bootstrap", "gui/501", manager.applicationAgentURL.path],
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
        XCTAssertFalse(fileManager.fileExists(atPath: manager.applicationAgentURL.path))
        XCTAssertEqual(
            Array(runner.arguments.suffix(2)),
            [
                ["bootout", "gui/501", manager.agentURL.path],
                ["bootout", "gui/501", manager.applicationAgentURL.path],
            ],
        )
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
            minute: 15,
        )

        let status = try manager.configure(schedule: schedule)

        XCTAssertEqual(status.state, .configured(schedule))
        XCTAssertEqual(
            status.detail,
            "Runs every Mon, Wed, Fri at 21:15 through this Mac's launchd agent.",
        )
        let data = try Data(contentsOf: manager.agentURL)
        let propertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
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
            [[1, 21, 15], [3, 21, 15], [5, 21, 15]],
        )
        XCTAssertNil(propertyList["StartInterval"])
    }

    func testCreatesCalendarLaunchAgentForDifferentTimesOnTheSameDay() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeLaunchdRunner()
        let manager = scheduleManager(fixture: fixture, runner: runner)
        let schedule = SyncSchedule.calendar(entries: [
            SyncScheduleCalendarEntry(weekday: .monday, hour: 9, minute: 0),
            SyncScheduleCalendarEntry(weekday: .tuesday, hour: 11, minute: 30),
            SyncScheduleCalendarEntry(weekday: .monday, hour: 17, minute: 45),
        ])

        let status = try manager.configure(schedule: schedule)

        XCTAssertEqual(
            status.state,
            .configured(.calendar(entries: [
                SyncScheduleCalendarEntry(weekday: .monday, hour: 9, minute: 0),
                SyncScheduleCalendarEntry(weekday: .monday, hour: 17, minute: 45),
                SyncScheduleCalendarEntry(weekday: .tuesday, hour: 11, minute: 30),
            ])),
        )
        XCTAssertEqual(
            status.detail,
            "Runs Mon at 09:00, 17:45; Tue at 11:30 through this Mac's launchd agent.",
        )
        let data = try Data(contentsOf: manager.agentURL)
        let propertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
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
            [[1, 9, 0], [1, 17, 45], [2, 11, 30]],
        )
    }

    func testAddsApplicationLaunchAgentToAnExistingSchedule() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let initialRunner = FakeLaunchdRunner()
        let initialManager = scheduleManager(fixture: fixture, runner: initialRunner)
        _ = try initialManager.configure(schedule: .interval(minutes: 60))
        try fileManager.removeItem(at: initialManager.applicationAgentURL)
        let migrationRunner = FakeLaunchdRunner()
        let migrationManager = scheduleManager(fixture: fixture, runner: migrationRunner)

        try migrationManager.ensureApplicationLaunchAgent()

        XCTAssertTrue(fileManager.fileExists(atPath: migrationManager.applicationAgentURL.path))
        XCTAssertEqual(migrationRunner.arguments, [
            ["bootout", "gui/501", migrationManager.agentURL.path],
            ["bootout", "gui/501", migrationManager.applicationAgentURL.path],
            ["bootstrap", "gui/501", migrationManager.agentURL.path],
            ["bootstrap", "gui/501", migrationManager.applicationAgentURL.path],
        ])
    }

    func testRewritesStaleExecutablePathAfterUpgrade() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let initialManager = scheduleManager(fixture: fixture, runner: FakeLaunchdRunner())
        _ = try initialManager.configure(schedule: .interval(minutes: 12 * 60))
        let data = try Data(contentsOf: initialManager.agentURL)
        var values = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        )
        values["ProgramArguments"] = ["/old/Cellar/mac-sync-current/bin/mac-sync", "run"]
        let staleData = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0,
        )
        try staleData.write(to: initialManager.agentURL, options: .atomic)
        let migrationRunner = FakeLaunchdRunner()
        let migrationManager = scheduleManager(fixture: fixture, runner: migrationRunner)

        try migrationManager.ensureApplicationLaunchAgent()

        let repairedData = try Data(contentsOf: migrationManager.agentURL)
        let repairedValues = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: repairedData, format: nil) as? [String: Any],
        )
        XCTAssertEqual(repairedValues["ProgramArguments"] as? [String], ["/tmp/mac-sync", "run"])
        XCTAssertEqual(migrationRunner.arguments, [
            ["bootout", "gui/501", migrationManager.agentURL.path],
            ["bootout", "gui/501", migrationManager.applicationAgentURL.path],
            ["bootstrap", "gui/501", migrationManager.agentURL.path],
            ["bootstrap", "gui/501", migrationManager.applicationAgentURL.path],
        ])
    }

    func testRewritesLegacyBackgroundAgentWithUnattendedEnvironment() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let initialManager = scheduleManager(fixture: fixture, runner: FakeLaunchdRunner())
        _ = try initialManager.configure(schedule: .interval(minutes: 60))
        let data = try Data(contentsOf: initialManager.agentURL)
        var values = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        )
        values["ProcessType"] = "Background"
        values["EnvironmentVariables"] = ["PATH": "/custom/bin"]
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0,
        )
        try legacyData.write(to: initialManager.agentURL, options: .atomic)
        let migrationRunner = FakeLaunchdRunner()
        let migrationManager = scheduleManager(fixture: fixture, runner: migrationRunner)

        try migrationManager.ensureApplicationLaunchAgent()

        let repairedData = try Data(contentsOf: migrationManager.agentURL)
        let repairedValues = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: repairedData, format: nil) as? [String: Any],
        )
        XCTAssertEqual(repairedValues["ProcessType"] as? String, "Interactive")
        let environment = try XCTUnwrap(
            repairedValues["EnvironmentVariables"] as? [String: String],
        )
        XCTAssertEqual(environment["HOME"], fixture.home.path)
        XCTAssertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(migrationRunner.arguments.count, 4)
    }

    func testLeavesExistingApplicationLaunchAgentLoaded() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let initialManager = scheduleManager(fixture: fixture, runner: FakeLaunchdRunner())
        _ = try initialManager.configure(schedule: .interval(minutes: 60))
        let migrationRunner = FakeLaunchdRunner()
        let migrationManager = scheduleManager(fixture: fixture, runner: migrationRunner)

        try migrationManager.ensureApplicationLaunchAgent()

        XCTAssertTrue(migrationRunner.arguments.isEmpty)
    }

    func testRemovesBothAgentsWhenApplicationLaunchFails() throws {
        let fixture = try makeFixture()
        defer { try? fileManager.removeItem(at: fixture.root) }
        let runner = FakeLaunchdRunner(statuses: [0, 0, 0, 1, 0])
        let manager = scheduleManager(fixture: fixture, runner: runner)

        XCTAssertThrowsError(try manager.configure(schedule: .interval(minutes: 60))) { error in
            XCTAssertEqual(error as? SyncScheduleError, .launchdUnavailable)
        }

        XCTAssertFalse(fileManager.fileExists(atPath: manager.agentURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: manager.applicationAgentURL.path))
        XCTAssertEqual(runner.arguments.last, ["bootout", "gui/501", manager.agentURL.path])
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
                pathsFile: fixture.data.appendingPathComponent("machines/work-mac/config/sync-paths.txt").path,
            ),
            executableURL: URL(fileURLWithPath: "/tmp/mac-sync"),
            applicationURL: URL(fileURLWithPath: "/tmp/MacSync.app"),
            environment: ["PATH": "/custom/bin"],
            userID: uid_t(501),
            fileManager: fileManager,
            runner: runner,
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
    private var statuses: [Int32]

    init(statuses: [Int32] = []) {
        self.statuses = statuses
    }

    func run(arguments: [String]) -> CommandResult {
        self.arguments.append(arguments)
        let status = statuses.isEmpty ? 0 : statuses.removeFirst()
        return CommandResult(status: status, stdout: "", stderr: "")
    }
}
