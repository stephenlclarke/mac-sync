import Foundation
import MacSyncCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SyncStore
    @State private var scheduleChoice = SyncScheduleChoice.hourly
    @State private var customIntervalMinutes = ""
    @State private var calendarRules = [CalendarScheduleRule.standard]
    @State private var scheduleValidationMessage: String?

    var body: some View {
        Form {
            Section("Sync locations") {
                LabeledContent("This Mac") {
                    Text(store.overview.configuration.machineName)
                        .textSelection(.enabled)
                }
                LabeledContent("mac-sync data repository") {
                    Text(store.overview.configuration.dataRepository)
                        .textSelection(.enabled)
                }
                LabeledContent("Status records") {
                    Text(store.overview.configuration.statusDirectory)
                        .textSelection(.enabled)
                }
                Button("Configure Data Repository…") {
                    store.requestSetup()
                }
            }

            Section("GitHub access") {
                Text("Mac Sync uses SSH or Keychain-backed Git credentials already configured on this Mac. It never stores a GitHub token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.isSetupComplete {
                    ForEach(store.gitHubReports) { report in
                        GitHubConnectionRow(report: report)
                    }
                    Button(store.isCheckingGitHubAccess ? "Checking GitHub Access…" : "Test GitHub Access") {
                        store.checkGitHubAccess()
                    }
                    .disabled(store.isCheckingGitHubAccess)
                } else {
                    Label("Finish local repository setup before testing GitHub access.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Link(
                    "Set up SSH or Git credential access",
                    destination: URL(string: "https://docs.github.com/authentication/keeping-your-account-and-data-secure/about-authentication-to-github")!
                )
                .font(.caption)
            }

            Section("Homebrew integration") {
                Text("The setup assistant saves only repository locations to \(MacSyncUserConfiguration.configurationFilePath()). The Homebrew CLI and automatic sync agent use the same locations; credentials remain in Git and Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Automatic sync") {
                Text(store.syncScheduleStatus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Schedule", selection: $scheduleChoice) {
                    ForEach(SyncScheduleChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }

                if scheduleChoice == .custom {
                    TextField("Minutes", text: $customIntervalMinutes)
                        .textFieldStyle(.roundedBorder)
                }

                if scheduleChoice == .daysAndTime {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($calendarRules) { ruleBinding in
                            HStack(spacing: 10) {
                                Picker("Day", selection: ruleBinding.weekday) {
                                    ForEach(SyncScheduleWeekday.displayOrder) { weekday in
                                        Text(weekday.shortTitle).tag(weekday)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 96)

                                DatePicker(
                                    "Time",
                                    selection: ruleBinding.time,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                Button {
                                    calendarRules.removeAll { $0.id == ruleBinding.wrappedValue.id }
                                } label: {
                                    Label("Remove time", systemImage: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(calendarRules.count == 1)
                                .help("Remove this day-and-time entry")
                            }
                        }

                        Button {
                            calendarRules.append(CalendarScheduleRule.standard)
                        } label: {
                            Label("Add day and time", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)

                        Text("Add one or more local sync times. A day can appear more than once.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let scheduleValidationMessage {
                    Label(scheduleValidationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Save Schedule") {
                        saveSchedule()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Disable Automatic Sync") {
                        scheduleChoice = .disabled
                        customIntervalMinutes = ""
                        scheduleValidationMessage = nil
                        store.configureSyncSchedule(schedule: nil)
                    }
                    .disabled(store.syncScheduleStatus.state == .disabled)
                }

                Text("This creates a per-user Mac Sync launchd agent. If you have started the Homebrew mac-sync service, stop it first so there is only one automatic sync schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Legal") {
                Text("Mac Sync by xyzzy.tools is licensed under AGPL-3.0-or-later. It is provided without warranty.")
                Link("View the source and licence", destination: URL(string: "https://github.com/stephenlclarke/mac-sync")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 760)
        .onAppear {
            store.reloadSyncSchedule()
            updateScheduleControls(from: store.syncScheduleStatus)
        }
        .onChange(of: store.syncScheduleStatus) { status in
            updateScheduleControls(from: status)
        }
    }

    private func saveSchedule() {
        let schedule: SyncSchedule?
        switch scheduleChoice {
        case .disabled:
            schedule = nil
        case .custom:
            guard let minutes = Int(customIntervalMinutes),
                  (SyncScheduleManager.minimumIntervalMinutes ... SyncScheduleManager.maximumIntervalMinutes).contains(minutes)
            else {
                scheduleValidationMessage = "Enter a whole number from \(SyncScheduleManager.minimumIntervalMinutes) to \(SyncScheduleManager.maximumIntervalMinutes)."
                return
            }
            schedule = .interval(minutes: minutes)
        case .daysAndTime:
            let entries = calendarRules.map(\.entry)
            guard !entries.isEmpty else {
                scheduleValidationMessage = "Add at least one day and time for the automatic sync."
                return
            }
            guard Set(entries).count == entries.count else {
                scheduleValidationMessage = "Each day and time combination can only be scheduled once."
                return
            }
            schedule = .calendar(entries: entries)
        default:
            guard let minutes = scheduleChoice.intervalMinutes else {
                return
            }
            schedule = .interval(minutes: minutes)
        }

        scheduleValidationMessage = nil
        store.configureSyncSchedule(schedule: schedule)
    }

    private func updateScheduleControls(from status: SyncScheduleStatus) {
        guard let schedule = status.schedule else {
            scheduleChoice = .disabled
            customIntervalMinutes = ""
            return
        }

        switch schedule {
        case let .interval(minutes):
            if let choice = SyncScheduleChoice.preset(for: minutes) {
                scheduleChoice = choice
                customIntervalMinutes = ""
            } else {
                scheduleChoice = .custom
                customIntervalMinutes = "\(minutes)"
            }
        case let .calendar(entries):
            scheduleChoice = .daysAndTime
            calendarRules = entries.map(CalendarScheduleRule.init)
        }
    }
}

private struct CalendarScheduleRule: Identifiable {
    let id = UUID()
    var weekday: SyncScheduleWeekday
    var time: Date

    static var standard: CalendarScheduleRule {
        CalendarScheduleRule(weekday: .monday, time: time(hour: 9, minute: 0))
    }

    init(weekday: SyncScheduleWeekday, time: Date) {
        self.weekday = weekday
        self.time = time
    }

    init(entry: SyncScheduleCalendarEntry) {
        self.init(weekday: entry.weekday, time: Self.time(hour: entry.hour, minute: entry.minute))
    }

    var entry: SyncScheduleCalendarEntry {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: time)
        return SyncScheduleCalendarEntry(
            weekday: weekday,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.autoupdatingCurrent.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

private enum SyncScheduleChoice: String, CaseIterable, Identifiable {
    case disabled
    case everyThirtyMinutes
    case hourly
    case everyFourHours
    case everyTwelveHours
    case daily
    case daysAndTime
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .disabled:
            "Disabled"
        case .everyThirtyMinutes:
            "Every 30 minutes"
        case .hourly:
            "Every hour"
        case .everyFourHours:
            "Every 4 hours"
        case .everyTwelveHours:
            "Every 12 hours"
        case .daily:
            "Every day"
        case .daysAndTime:
            "Days and times"
        case .custom:
            "Custom interval"
        }
    }

    var intervalMinutes: Int? {
        switch self {
        case .disabled, .daysAndTime, .custom:
            nil
        case .everyThirtyMinutes:
            30
        case .hourly:
            60
        case .everyFourHours:
            4 * 60
        case .everyTwelveHours:
            12 * 60
        case .daily:
            24 * 60
        }
    }

    static func preset(for intervalMinutes: Int) -> Self? {
        allCases.first { choice in
            choice != .daysAndTime && choice != .custom && choice.intervalMinutes == intervalMinutes
        }
    }
}
