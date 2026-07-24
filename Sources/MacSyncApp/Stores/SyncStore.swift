import AppKit
import Darwin
import Foundation
import MacSyncCore

@MainActor
final class SyncStore: ObservableObject {
    @Published private(set) var overview: SyncOverview
    @Published var selectedPaths: [String]
    @Published private(set) var activeAction: SyncAction?
    @Published private(set) var commandOutput = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var repositoryInspections: [LocalRepositoryInspection]
    @Published private(set) var gitHubReports: [GitHubConnectionReport]
    @Published private(set) var isSetupComplete: Bool
    @Published private(set) var isCheckingGitHubAccess = false
    @Published private(set) var encryptedSecretEntries: [String: [String]] = [:]
    @Published private(set) var encryptedSecretErrors: [String: String] = [:]
    @Published private(set) var encryptedSecretFailures: [String: EncryptedSecretsInspectionError] = [:]
    @Published private(set) var loadingEncryptedSecrets = Set<String>()
    @Published private(set) var syncScheduleStatus: SyncScheduleStatus
    @Published private(set) var syncIssues: [SyncIssue]
    @Published private(set) var requestedNavigation: NavigationItem?
    @Published var isSetupSheetPresented = false

    private var repository: SyncRepository
    private let baseEnvironment: [String: String]
    private var commandEnvironment: [String: String]
    private var issueRepository: SyncIssueRepository
    private var process: Process?
    private var savedSelection: [String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let resolvedEnvironment = MacSyncUserConfiguration.resolvedEnvironment(environment)
        let locations = Self.locations(from: resolvedEnvironment)
        var appEnvironment = MacSyncRuntimeEnvironment.prepared(resolvedEnvironment)
        appEnvironment.removeValue(forKey: "MAC_SYNC_REPO")
        appEnvironment["MAC_SYNC_MACHINES_REPO"] = locations.dataRepository
        let repository = SyncRepository(environment: appEnvironment)
        let setupService = RepositorySetupService(environment: appEnvironment)
        let inspections = setupService.inspect(locations)

        // A newly-cloned data repository starts empty. Carry the reviewed
        // selection from the existing command checkout forward once, before
        // presenting the selection editor. This never overwrites a tracked
        // machine configuration and does not create a snapshot or push.
        if inspections.allSatisfy(\.isReady) {
            try? repository.seedMachineConfigurationIfNeeded()
        }
        let configuredPaths = repository.configuredPaths()

        baseEnvironment = environment
        commandEnvironment = appEnvironment
        self.repository = repository
        let initialOverview = repository.load()
        let initialIssueRepository = SyncIssueRepository(configuration: initialOverview.configuration)
        overview = initialOverview
        selectedPaths = configuredPaths
        savedSelection = configuredPaths
        repositoryInspections = inspections
        gitHubReports = setupService.initialGitHubReports(for: inspections)
        isSetupComplete = inspections.allSatisfy(\.isReady)
        syncScheduleStatus = SyncScheduleManager(
            configuration: initialOverview.configuration,
            executableURL: MacSyncCommandLocator.scheduledExecutableURL(environment: appEnvironment),
            environment: appEnvironment
        ).status()
        issueRepository = initialIssueRepository
        syncIssues = initialIssueRepository.issues(for: initialOverview)
        requestedNavigation = nil
        updateDockBadge()
    }

    var isRunning: Bool {
        activeAction != nil || overview.isLocalSyncActive
    }

    var repositoryLocations: RepositoryLocations {
        Self.locations(from: commandEnvironment)
    }

    var hasUnsavedSelection: Bool {
        selectedPaths != savedSelection
    }

    var openIssueCount: Int {
        syncIssues.filter(\.requiresManualIntervention).count
    }

    func reload() {
        let selectionHasChanges = hasUnsavedSelection
        overview = repository.load()
        reloadSyncIssues()
        if !selectionHasChanges {
            savedSelection = repository.configuredPaths()
            selectedPaths = savedSelection
        }
    }

    func requestSetup() {
        isSetupSheetPresented = true
    }

    func completeSetup(with locations: RepositoryLocations) {
        do {
            try MacSyncUserConfiguration.saveDataRepository(
                locations.dataRepository,
                environment: baseEnvironment
            )
            applyRepositoryLocations(locations)
            guard isSetupComplete else {
                errorMessage = "The selected folder must be a Git repository before setup can finish."
                return
            }
            try repository.seedMachineConfigurationIfNeeded()
            try repository.clearStaleLocalStatusWhenSnapshotIsMissing()
            reload()
            isSetupSheetPresented = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkGitHubAccess() {
        guard isSetupComplete, !isCheckingGitHubAccess else { return }
        let locations = repositoryLocations
        let environment = commandEnvironment
        let service = RepositorySetupService(environment: environment)
        gitHubReports = service.checkingGitHubReports(for: repositoryInspections)
        isCheckingGitHubAccess = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reports = RepositorySetupService(environment: environment).checkGitHubAccess(for: locations)
            DispatchQueue.main.async {
                self?.repositoryInspections = reports.map(\.repository)
                self?.gitHubReports = reports
                self?.isCheckingGitHubAccess = false
            }
        }
    }

    func add(paths: [String]) {
        let allPaths = selectedPaths + paths
        var seen = Set<String>()
        selectedPaths = allPaths.filter {
            let path = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && seen.insert(path).inserted
        }
    }

    func add(fileURLs: [URL]) {
        add(paths: fileURLs.map(repository.pathForUserSelection))
    }

    func remove(path: String) {
        selectedPaths.removeAll { $0 == path }
    }

    func removeArchivedConfiguredRoot(_ path: String) {
        guardSetup()
        guard isSetupComplete else { return }
        guard !isRunning else { return }
        guard !hasUnsavedSelection else {
            errorMessage = "Save or discard Sync Selection changes before removing an archived root."
            return
        }

        do {
            try repository.removeArchivedConfiguredPath(path)
            let configuredPaths = repository.configuredPaths()
            selectedPaths = configuredPaths
            savedSelection = configuredPaths
            reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardSelectionChanges() {
        savedSelection = repository.configuredPaths()
        selectedPaths = savedSelection
    }

    func saveSelection() {
        do {
            try repository.saveConfiguredPaths(selectedPaths)
            savedSelection = selectedPaths
            errorMessage = nil
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncSelection() {
        guardSetup()
        guard isSetupComplete else { return }
        do {
            try repository.saveConfiguredPaths(selectedPaths)
            savedSelection = selectedPaths
            reload()
            run(arguments: ["sync"], action: .syncing)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewSync() {
        guardSetup()
        guard isSetupComplete else { return }
        do {
            try repository.saveConfiguredPaths(selectedPaths)
            savedSelection = selectedPaths
            reload()
            run(
                arguments: ["sync"],
                action: .syncing,
                extraEnvironment: ["MAC_SYNC_DRY_RUN": "1"]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewRestore(from machine: String, paths: [String]? = nil) {
        guardSetup()
        guard isSetupComplete else { return }
        let arguments = restoreArguments(from: machine, paths: paths)
        run(
            arguments: arguments,
            action: .previewingRestore(machine),
            extraEnvironment: ["MAC_SYNC_DRY_RUN": "1"]
        )
    }

    func restore(from machine: String, force: Bool, paths: [String]? = nil) {
        guardSetup()
        guard isSetupComplete else { return }
        var arguments = restoreArguments(from: machine, paths: paths)
        if force {
            arguments.append("--force")
        }
        run(arguments: arguments, action: .restoring(machine))
    }

    func stopSync() {
        if let process {
            process.terminate()
            return
        }
        if let processID = overview.localSyncProcessID {
            _ = kill(processID, SIGTERM)
        }
    }

    func requestManualTriage() {
        requestedNavigation = .triage
    }

    func consumeNavigationRequest() {
        requestedNavigation = nil
    }

    func updateIssue(_ issue: SyncIssue, disposition: SyncIssueDisposition, note: String) {
        do {
            try issueRepository.update(issueID: issue.id, disposition: disposition, note: note)
            reloadSyncIssues()
        } catch {
            errorMessage = "Unable to save manual triage: \(error.localizedDescription)"
        }
    }

    func reloadSyncSchedule() {
        syncScheduleStatus = scheduleManager().status()
    }

    func configureSyncSchedule(schedule: SyncSchedule?) {
        guardSetup()
        guard isSetupComplete else { return }

        do {
            syncScheduleStatus = try scheduleManager().configure(schedule: schedule)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func encryptedSecrets(for machine: String) -> [String]? {
        encryptedSecretEntries[machine]
    }

    func encryptedSecretsError(for machine: String) -> String? {
        encryptedSecretErrors[machine]
    }

    func encryptedSecretsRecoverySuggestion(for machine: String) -> String? {
        encryptedSecretFailures[machine]?.recoverySuggestion
    }

    func canPrepareEncryptedSecretsAccess(for machine: String) -> Bool {
        encryptedSecretFailures[machine]?.supportsAccessSetup == true
    }

    func isLoadingEncryptedSecrets(for machine: String) -> Bool {
        loadingEncryptedSecrets.contains(machine)
    }

    func inspectEncryptedSecrets(from machine: String) {
        guardSetup()
        guard isSetupComplete, !isRunning, !loadingEncryptedSecrets.contains(machine) else { return }

        loadingEncryptedSecrets.insert(machine)
        encryptedSecretErrors[machine] = nil
        encryptedSecretFailures[machine] = nil
        let environment = commandEnvironment

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<[String], Error> = Result {
                try EncryptedSecretsInspector(environment: environment).entries(from: machine)
            }
            DispatchQueue.main.async {
                self?.loadingEncryptedSecrets.remove(machine)
                switch result {
                case let .success(entries):
                    self?.encryptedSecretEntries[machine] = entries
                case let .failure(error):
                    self?.encryptedSecretEntries[machine] = nil
                    self?.encryptedSecretErrors[machine] = error.localizedDescription
                    self?.encryptedSecretFailures[machine] = error as? EncryptedSecretsInspectionError
                }
            }
        }
    }

    func prepareEncryptedSecretsAccess() {
        guardSetup()
        guard isSetupComplete else { return }
        run(arguments: ["secrets", "init"], action: .preparingEncryptedSecretsAccess)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func run(
        arguments: [String],
        action: SyncAction,
        extraEnvironment: [String: String] = [:]
    ) {
        guard isSetupComplete else {
            errorMessage = SyncConfigurationError.setupRequired.localizedDescription
            return
        }
        guard activeAction == nil else { return }
        guard let executableURL = MacSyncCommandLocator.executableURL() else {
            errorMessage = SyncConfigurationError.missingExecutable.localizedDescription
            return
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = commandEnvironment.merging(extraEnvironment) { _, replacement in replacement }
        process.standardOutput = standardOutput
        process.standardError = standardError

        commandOutput = ""
        errorMessage = nil
        activeAction = action
        self.process = process

        standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }
        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }
        process.terminationHandler = { [weak self, weak standardOutput, weak standardError] completedProcess in
            standardOutput?.fileHandleForReading.readabilityHandler = nil
            standardError?.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.finish(process: completedProcess)
            }
        }

        do {
            try process.run()
        } catch {
            activeAction = nil
            self.process = nil
            errorMessage = error.localizedDescription
        }
    }

    private func appendOutput(_ text: String) {
        commandOutput += text
        if commandOutput.count > 50000 {
            commandOutput = String(commandOutput.suffix(50000))
        }
    }

    private func finish(process: Process) {
        let status = process.terminationStatus
        let completedAction = activeAction
        if status != 0 {
            errorMessage = "mac-sync finished with exit status \(status)."
        }
        activeAction = nil
        self.process = nil
        if completedAction == .preparingEncryptedSecretsAccess {
            encryptedSecretEntries.removeAll()
            encryptedSecretErrors.removeAll()
            encryptedSecretFailures.removeAll()
        }
        reload()
    }

    private func applyRepositoryLocations(_ locations: RepositoryLocations) {
        var environment = MacSyncRuntimeEnvironment.prepared(baseEnvironment)
        environment.removeValue(forKey: "MAC_SYNC_REPO")
        environment["MAC_SYNC_MACHINES_REPO"] = locations.dataRepository
        commandEnvironment = environment
        repository = SyncRepository(environment: environment)
        let setupService = RepositorySetupService(environment: environment)
        repositoryInspections = setupService.inspect(locations)
        gitHubReports = setupService.initialGitHubReports(for: repositoryInspections)
        isSetupComplete = repositoryInspections.allSatisfy(\.isReady)
        overview = repository.load()
        issueRepository = SyncIssueRepository(configuration: overview.configuration)
        reloadSyncIssues()
        let configuredPaths = repository.configuredPaths()
        selectedPaths = configuredPaths
        savedSelection = configuredPaths
        reloadSyncSchedule()
    }

    private func guardSetup() {
        guard !isSetupComplete else { return }
        errorMessage = SyncConfigurationError.setupRequired.localizedDescription
    }

    private func scheduleManager() -> SyncScheduleManager {
        SyncScheduleManager(
            configuration: overview.configuration,
            executableURL: MacSyncCommandLocator.scheduledExecutableURL(environment: commandEnvironment),
            environment: commandEnvironment
        )
    }

    private static func locations(from environment: [String: String]) -> RepositoryLocations {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let defaults = RepositoryLocations.defaults(homeDirectory: home)
        return RepositoryLocations(
            dataRepository: environment["MAC_SYNC_MACHINES_REPO"] ?? defaults.dataRepository
        )
    }

    private func restoreArguments(from machine: String, paths: [String]?) -> [String] {
        var arguments = ["restore", "--from", machine]
        let uniquePaths = Set(paths ?? [])
        for path in uniquePaths.sorted() {
            arguments += ["--path", path]
        }
        return arguments
    }

    private func reloadSyncIssues() {
        syncIssues = issueRepository.issues(for: overview)
        updateDockBadge()
    }

    private func updateDockBadge() {
        let badge = openIssueCount == 0 ? nil : "\(openIssueCount)"
        NSApplication.shared.dockTile.badgeLabel = badge
        NSApplication.shared.dockTile.display()
    }
}
