import Foundation
import MacSyncCore

@main
enum MacSyncEntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst() == ["--background-agent"] {
            runBackgroundAgent()
        } else {
            MacSyncDesktopApp.main()
        }
    }

    @MainActor
    private static func runBackgroundAgent() {
        let runtime = MacSyncApplicationRuntime.shared
        guard runtime.distribution == .appStore else { Foundation.exit(2) }
        var environment = runtime.environment
        let manager = ManagedAgentService(environment: environment)
        guard let schedule = manager.savedSchedule() else { return }
        let repository = SyncRepository(environment: environment)
        let configuration = repository.configuration()
        let paths = repository.configuredPaths().map { $0.hasPrefix("/") ? $0 : "\(configuration.homeDirectory)/\($0)" }
        let required = paths + [configuration.dataRepository] + (configuration.cloudFolder.map { [$0] } ?? [])
        if let problem = runtime.accessProblem(paths: required) {
            try? FileManager.default.createDirectory(at: manager.errorURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? Data(problem.utf8).write(to: manager.errorURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manager.errorURL.path)
            return // Successful exit prevents a permission-error restart loop.
        }
        let access: (values: [String: String], manifest: URL?)
        do { access = try runtime.workerEnvironment() }
        catch { return }
        environment = access.values
        var arguments = [environment["MAC_SYNC_EXECUTABLE"]!, "watch"]
        switch schedule {
        case .watch: break
        case let .interval(minutes):
            arguments += ["--interval-minutes", String(minutes)]
            environment["MAC_SYNC_OBSERVE_FILES"] = "0"
        case let .calendar(entries):
            environment["MAC_SYNC_OBSERVE_FILES"] = "0"
            let values = entries.map { BackgroundCalendarEntry(weekday: $0.weekday.rawValue, hour: $0.hour, minute: $0.minute) }
            guard let encoded = try? JSONEncoder().encode(values), let text = String(data: encoded, encoding: .utf8) else { return }
            environment["MAC_SYNC_CALENDAR_ENTRIES"] = text
        }
        let status = MacSyncApp(arguments: arguments, environment: environment).run()
        if let manifest = access.manifest {
            try? FileManager.default.removeItem(at: manifest)
        }
        runtime.fileAccess?.stop()
        Foundation.exit(Int32(status))
    }
}
