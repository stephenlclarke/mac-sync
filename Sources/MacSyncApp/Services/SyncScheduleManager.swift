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

struct SyncScheduleCalendarEntry: Equatable, Hashable {
    let weekday: SyncScheduleWeekday
    let hour: Int
    let minute: Int
}

enum SyncSchedule: Equatable {
    case interval(minutes: Int)
    case calendar(entries: [SyncScheduleCalendarEntry])

    static func calendar(days: [SyncScheduleWeekday], hour: Int, minute: Int) -> SyncSchedule {
        .calendar(entries: days.map { weekday in
            SyncScheduleCalendarEntry(weekday: weekday, hour: hour, minute: minute)
        })
    }
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
            "Choose a valid automatic sync interval, or at least one day-and-time entry."
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
        case let .calendar(entries):
            let sortedEntries = sortedCalendarEntries(entries)
            guard let first = sortedEntries.first else { return "at an invalid time" }
            if sortedEntries.allSatisfy({ $0.hour == first.hour && $0.minute == first.minute }) {
                let weekdayNames = sortedEntries.map(\.weekday.shortTitle).joined(separator: ", ")
                return "every \(weekdayNames) at \(formattedTime(hour: first.hour, minute: first.minute))"
            }
            let entriesByWeekday = Dictionary(grouping: sortedEntries, by: \.weekday)
            return SyncScheduleWeekday.displayOrder.compactMap { weekday in
                guard let weekdayEntries = entriesByWeekday[weekday] else { return nil }
                let times = weekdayEntries
                    .map { formattedTime(hour: $0.hour, minute: $0.minute) }
                    .joined(separator: ", ")
                return "\(weekday.shortTitle) at \(times)"
            }
            .joined(separator: "; ")
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
        case let .calendar(entries):
            let uniqueEntries = Set(entries)
            return !entries.isEmpty
                && uniqueEntries.count == entries.count
                && entries.allSatisfy { entry in
                    SyncScheduleWeekday.allCases.contains(entry.weekday)
                        && (0 ... 23).contains(entry.hour)
                        && (0 ... 59).contains(entry.minute)
                }
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
        let parsedEntries = entries.compactMap { entry -> SyncScheduleCalendarEntry? in
            guard let rawWeekday = (entry["Weekday"] as? NSNumber)?.intValue,
                  let weekday = SyncScheduleWeekday(rawValue: rawWeekday == 7 ? 0 : rawWeekday),
                  let hour = (entry["Hour"] as? NSNumber)?.intValue,
                  let minute = (entry["Minute"] as? NSNumber)?.intValue,
                  (0 ... 23).contains(hour),
                  (0 ... 59).contains(minute)
            else {
                return nil
            }
            return SyncScheduleCalendarEntry(weekday: weekday, hour: hour, minute: minute)
        }

        guard parsedEntries.count == entries.count else {
            return nil
        }

        let schedule = SyncSchedule.calendar(entries: parsedEntries)
        return isValid(schedule: schedule) ? schedule : nil
    }

    private static func displayOrder(for weekday: SyncScheduleWeekday) -> Int {
        SyncScheduleWeekday.displayOrder.firstIndex(of: weekday) ?? Int.max
    }

    private static func sortedCalendarEntries(_ entries: [SyncScheduleCalendarEntry]) -> [SyncScheduleCalendarEntry] {
        entries.sorted { left, right in
            let leftDay = displayOrder(for: left.weekday)
            let rightDay = displayOrder(for: right.weekday)
            if leftDay != rightDay {
                return leftDay < rightDay
            }
            if left.hour != right.hour {
                return left.hour < right.hour
            }
            return left.minute < right.minute
        }
    }

    private static func formattedTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
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
        case let .calendar(entries):
            values["StartCalendarInterval"] = Self.sortedCalendarEntries(entries)
                .map { entry in
                    [
                        "Weekday": entry.weekday.rawValue,
                        "Hour": entry.hour,
                        "Minute": entry.minute,
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
