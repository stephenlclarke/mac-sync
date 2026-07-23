import Darwin
import Foundation
import MacSyncCore

enum SyncScheduleWeekday: Int, CaseIterable, Hashable, Identifiable {
    case sunday = 0
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6

    static let displayOrder: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var id: Int {
        rawValue
    }

    var shortTitle: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }
}

enum SyncSchedule: Equatable {
    case interval(minutes: Int)
    case calendar(days: [SyncScheduleWeekday], hour: Int, minute: Int)
}

enum SyncScheduleState: Equatable {
    case disabled
    case configured(SyncSchedule)
    case invalid
}

struct SyncScheduleStatus: Equatable {
    let state: SyncScheduleState
    let agentPath: String

    var schedule: SyncSchedule? {
        if case let .configured(schedule) = state {
            return schedule
        }
        return nil
    }

    var detail: String {
        switch state {
        case .disabled:
            "No automatic sync schedule is installed by Mac Sync."
        case let .configured(schedule):
            "Runs \(SyncScheduleManager.description(for: schedule)) through this Mac's launchd agent."
        case .invalid:
            "The existing Mac Sync schedule could not be read. Save a new schedule to repair it."
        }
    }
}

enum SyncScheduleError: LocalizedError, Equatable {
    case invalidSchedule
    case missingExecutable
    case launchdUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSchedule:
            "Choose a valid automatic sync interval, or at least one day and time."
        case .missingExecutable:
            "The mac-sync command is unavailable. Reinstall the app before scheduling automatic sync."
        case .launchdUnavailable:
            "macOS could not install the automatic sync schedule. Try again after signing in to this Mac."
        }
    }
}

protocol LaunchdCommandRunning {
    func run(arguments: [String]) -> CommandResult
}

struct SystemLaunchdCommandRunner: LaunchdCommandRunning {
    let environment: [String: String]

    func run(arguments: [String]) -> CommandResult {
        ProcessRunner(environment: environment).run("/bin/launchctl", arguments)
    }
}

/// Manages the app-owned user LaunchAgent. The Homebrew service remains an
/// optional alternative and is deliberately not changed by this manager.
struct SyncScheduleManager {
    static let label = "tools.xyzzy.mac-sync"
    static let minimumIntervalMinutes = 15
    static let maximumIntervalMinutes = 31 * 24 * 60

    private let configuration: SyncConfiguration
    private let executableURL: URL?
    private let environment: [String: String]
    private let userID: uid_t
    private let fileManager: FileManager
    private let runner: any LaunchdCommandRunning

    init(
        configuration: SyncConfiguration,
        executableURL: URL?,
        environment: [String: String],
        userID: uid_t = getuid(),
        fileManager: FileManager = .default,
        runner: (any LaunchdCommandRunning)? = nil
    ) {
        self.configuration = configuration
        self.executableURL = executableURL
        self.environment = environment
        self.userID = userID
        self.fileManager = fileManager
        self.runner = runner ?? SystemLaunchdCommandRunner(environment: environment)
    }

    var agentURL: URL {
        URL(fileURLWithPath: configuration.homeDirectory)
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(Self.label).plist")
    }

    func status() -> SyncScheduleStatus {
        guard let data = try? Data(contentsOf: agentURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = propertyList as? [String: Any],
              values["Label"] as? String == Self.label
        else {
            let state: SyncScheduleState = fileManager.fileExists(atPath: agentURL.path) ? .invalid : .disabled
            return SyncScheduleStatus(state: state, agentPath: agentURL.path)
        }

        if let seconds = (values["StartInterval"] as? NSNumber)?.intValue,
           seconds > 0,
           seconds % 60 == 0,
           Self.isValid(intervalMinutes: seconds / 60)
        {
            return SyncScheduleStatus(
                state: .configured(.interval(minutes: seconds / 60)),
                agentPath: agentURL.path
            )
        }

        if let schedule = Self.calendarSchedule(from: values["StartCalendarInterval"]) {
            return SyncScheduleStatus(state: .configured(schedule), agentPath: agentURL.path)
        }

        return SyncScheduleStatus(state: .invalid, agentPath: agentURL.path)
    }

    func configure(schedule: SyncSchedule?) throws -> SyncScheduleStatus {
        if let schedule, !Self.isValid(schedule: schedule) {
            throw SyncScheduleError.invalidSchedule
        }

        try fileManager.createDirectory(
            at: agentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // bootout is deliberately best-effort: the agent may be configured on
        // disk but not yet loaded, which is normal for a first-time schedule.
        _ = runner.run(arguments: ["bootout", launchdDomain, agentURL.path])

        guard let schedule else {
            if fileManager.fileExists(atPath: agentURL.path) {
                try fileManager.removeItem(at: agentURL)
            }
            return status()
        }

        guard let executableURL else {
            throw SyncScheduleError.missingExecutable
        }

        let logsDirectory = URL(fileURLWithPath: configuration.homeDirectory)
            .appendingPathComponent("Library/Logs/mac-sync")
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: launchAgentValues(
                executableURL: executableURL,
                schedule: schedule,
                logsDirectory: logsDirectory
            ),
            format: .xml,
            options: 0
        )
        try data.write(to: agentURL, options: .atomic)

        guard runner.run(arguments: ["bootstrap", launchdDomain, agentURL.path]).status == 0 else {
            try? fileManager.removeItem(at: agentURL)
            throw SyncScheduleError.launchdUnavailable
        }
        return status()
    }

    static func description(for schedule: SyncSchedule) -> String {
        switch schedule {
        case let .interval(minutes):
            return intervalDescription(minutes: minutes)
        case let .calendar(days, hour, minute):
            let weekdayNames = days
                .sorted { displayOrder(for: $0) < displayOrder(for: $1) }
                .map(\.shortTitle)
                .joined(separator: ", ")
            return "every \(weekdayNames) at \(String(format: "%02d:%02d", hour, minute))"
        }
    }

    static func intervalDescription(minutes: Int) -> String {
        if minutes == 60 {
            return "every hour"
        }
        if minutes % (24 * 60) == 0 {
            let days = minutes / (24 * 60)
            return "every \(days) day\(days == 1 ? "" : "s")"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "every \(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "every \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private var launchdDomain: String {
        "gui/\(userID)"
    }

    private static func isValid(schedule: SyncSchedule) -> Bool {
        switch schedule {
        case let .interval(minutes):
            return isValid(intervalMinutes: minutes)
        case let .calendar(days, hour, minute):
            let uniqueDays = Set(days)
            return !uniqueDays.isEmpty
                && uniqueDays.count == days.count
                && days.allSatisfy { SyncScheduleWeekday.allCases.contains($0) }
                && (0 ... 23).contains(hour)
                && (0 ... 59).contains(minute)
        }
    }

    private static func isValid(intervalMinutes: Int) -> Bool {
        (minimumIntervalMinutes ... maximumIntervalMinutes).contains(intervalMinutes)
    }

    private static func calendarSchedule(from value: Any?) -> SyncSchedule? {
        let entries: [[String: Any]]
        if let values = value as? [[String: Any]] {
            entries = values
        } else if let values = value as? [Any] {
            entries = values.compactMap { $0 as? [String: Any] }
            guard entries.count == values.count else { return nil }
        } else if let value = value as? [String: Any] {
            entries = [value]
        } else {
            return nil
        }

        guard !entries.isEmpty else { return nil }
        let parsedEntries = entries.compactMap { entry -> (SyncScheduleWeekday, Int, Int)? in
            guard let rawWeekday = (entry["Weekday"] as? NSNumber)?.intValue,
                  let weekday = SyncScheduleWeekday(rawValue: rawWeekday == 7 ? 0 : rawWeekday),
                  let hour = (entry["Hour"] as? NSNumber)?.intValue,
                  let minute = (entry["Minute"] as? NSNumber)?.intValue,
                  (0 ... 23).contains(hour),
                  (0 ... 59).contains(minute)
            else {
                return nil
            }
            return (weekday, hour, minute)
        }

        guard parsedEntries.count == entries.count,
              let firstEntry = parsedEntries.first,
              parsedEntries.allSatisfy({ $0.1 == firstEntry.1 && $0.2 == firstEntry.2 })
        else {
            return nil
        }

        let days = parsedEntries.map(\.0)
        let schedule = SyncSchedule.calendar(days: days, hour: firstEntry.1, minute: firstEntry.2)
        return isValid(schedule: schedule) ? schedule : nil
    }

    private static func displayOrder(for weekday: SyncScheduleWeekday) -> Int {
        SyncScheduleWeekday.displayOrder.firstIndex(of: weekday) ?? Int.max
    }

    private func launchAgentValues(
        executableURL: URL,
        schedule: SyncSchedule,
        logsDirectory: URL
    ) -> [String: Any] {
        var values: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executableURL.path, "run"],
            "ProcessType": "Background",
            "EnvironmentVariables": launchEnvironment,
            "StandardOutPath": logsDirectory.appendingPathComponent("scheduler.log").path,
            "StandardErrorPath": logsDirectory.appendingPathComponent("scheduler-error.log").path,
        ]

        switch schedule {
        case let .interval(minutes):
            values["StartInterval"] = minutes * 60
        case let .calendar(days, hour, minute):
            values["StartCalendarInterval"] = days
                .sorted { Self.displayOrder(for: $0) < Self.displayOrder(for: $1) }
                .map { weekday in
                    [
                        "Weekday": weekday.rawValue,
                        "Hour": hour,
                        "Minute": minute,
                    ]
                }
        }
        return values
    }

    private var launchEnvironment: [String: String] {
        let preparedEnvironment = MacSyncRuntimeEnvironment.prepared(environment)
        return [
            "MAC_SYNC_MACHINE": configuration.machineName,
            "MAC_SYNC_MACHINES_REPO": configuration.dataRepository,
            "MAC_SYNC_PATHS_FILE": configuration.pathsFile,
            "MAC_SYNC_STATUS_DIR": configuration.statusDirectory,
            "PATH": preparedEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    }
}
