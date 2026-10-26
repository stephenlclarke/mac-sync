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
    @Published private(set) var historyOffset = 0
    @Published private(set) var historyTotal = 0
    @Published private(set) var historyEntryCounts: [String: Int] = [:]
    @Published private(set) var backgroundDetail = ""
    @Published private(set) var isRefreshing = false
    private var stateObservation: LocalStateObservation?
    // Global queues do not guarantee a per-work-item autorelease pool.
    private let readQueue = DispatchQueue(label: "tools.xyzzy.mac-sync.overview", qos: .utility, autoreleaseFrequency: .workItem)
    private let healthQueue = DispatchQueue(label: "tools.xyzzy.mac-sync.health", qos: .utility, autoreleaseFrequency: .workItem)
    private var refreshPending = false
    private var generation = 0

    private var repository: SyncRepository
    private let baseEnvironment: [String: String]
    private var commandEnvironment: [String: String]
    private var issueRepository: SyncIssueRepository
    private var process: Process?
    private var activityObservation: LocalStateObservation?
    private var activityHandle: FileHandle?
    private var activityURL: URL?
    private var savedSelection: [String]
    private var activeConditionCodes: Set<SyncHealthConditionCode>?
    private var healthEvaluationInProgress = false
    private var healthEvaluationPending = false
    private var lastHealthEvaluationAt: Date?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let resolvedEnvironment = MacSyncUserConfiguration.resolvedEnvironment(environment)
        let locations = Self.locations(from: resolvedEnvironment)
        var appEnvironment = MacSyncRuntimeEnvironment.prepared(resolvedEnvironment)
        appEnvironment.removeValue(forKey: "MAC_SYNC_REPO")
        appEnvironment["MAC_SYNC_MACHINES_REPO"] = locations.dataRepository
        let repository = SyncRepository(environment: appEnvironment)
        let setupService = RepositorySetupService(environment: appEnvironment)
        let inspections = setupService.inspect(locations)

        // Read the selection without changing snapshots or launching recovery.
        let configuredPaths = repository.configuredPaths()

        baseEnvironment = environment
        commandEnvironment = appEnvironment
        self.repository = repository
        let configuration = repository.configuration()
        let initialOverview = SyncOverview(configuration: configuration, status: .empty, history: [], currentMachine: nil,
                                           peerMachines: [], localSyncProcessID: nil, isLocalSyncActive: false)
        let initialIssueRepository = SyncIssueRepository(configuration: initialOverview.configuration)
        overview = initialOverview
        selectedPaths = configuredPaths
        savedSelection = configuredPaths
        repositoryInspections = inspections
        gitHubReports = setupService.initialGitHubReports(for: inspections)
        isSetupComplete = inspections.allSatisfy(\.isReady)
        let scheduleManager = SyncScheduleManager(
            configuration: initialOverview.configuration,
            executableURL: MacSyncCommandLocator.scheduledExecutableURL(environment: appEnvironment),
            applicationURL: MacSyncCommandLocator.scheduledApplicationURL(environment: appEnvironment),
            environment: appEnvironment,
        )
        let initialScheduleStatus = scheduleManager.status()
        syncScheduleStatus = initialScheduleStatus
        issueRepository = initialIssueRepository
        syncIssues = initialIssueRepository.issues(for: initialOverview)
        requestedNavigation = nil
        errorMessage = nil
        updateDockBadge()
        // Opening the UI observes saved state; it never repairs jobs or probes
        // GitHub/Keychain. Explicit recovery actions perform those checks.
        activeConditionCodes = Set(initialOverview.status.conditions.map(\.code))
        observeLocalState()
        reload()
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
        syncIssues.filter(requiresAttention).count
    }

    var activeHealthIssueCount: Int {
        syncIssues.filter { healthActivity(for: $0) == .active }.count
    }

    var isCheckingHealth: Bool {
        isSetupComplete && activeConditionCodes == nil
    }

    func healthActivity(for issue: SyncIssue) -> SyncHealthActivity {
        SyncHealthActivity.resolve(
            conditionCode: issue.conditionCode,
            recordedAsActive: issue.isActive,
            activeConditionCodes: activeConditionCodes,
        )
    }

    func healthActivity(for message: String) -> SyncHealthActivity? {
        guard let conditionCode = SyncHealthMessage.conditionCode(for: message) else {
            return nil
        }
        return SyncHealthActivity.resolve(
            conditionCode: conditionCode,
            activeConditionCodes: activeConditionCodes,
        )
    }

    func requiresAttention(_ issue: SyncIssue) -> Bool {
        issue.disposition == .open && healthActivity(for: issue) == .active
    }

    func reload() {
        if isRefreshing {
            refreshPending = true; return
        }
        isRefreshing = true
        generation += 1
        let requestedGeneration = generation
        let repository = repository
        let offset = historyOffset
        readQueue.async { [weak self] in
            let snapshot = repository.load(includeSnapshotDetails: false, historyOffset: offset)
            let path = "\(snapshot.configuration.statusDirectory)/history/\(snapshot.configuration.machineName)"
            let history = FileManager.default.fileExists(atPath: path) ? try? LocalHistoryStore(directory: path) : nil
            let count = (try? history?.count()) ?? 0
            let counts = Dictionary(uniqueKeysWithValues: snapshot.history.map { ($0.id, (try? history?.entryCount(runID: $0.id)) ?? 0) })
            let checkpoint = BackgroundCheckpoint.load(from: "\(snapshot.configuration.statusDirectory)/\(snapshot.configuration.machineName).background.json", repository: snapshot.configuration.dataRepository)
            DispatchQueue.main.async {
                guard let self, self.generation == requestedGeneration else { return }
                self.overview = snapshot
                self.observeLocalState()
                self.historyTotal = count
                self.historyEntryCounts = counts
                self.backgroundDetail = checkpoint.detail
                self.activeConditionCodes = Set(snapshot.status.conditions.map(\.code)
                    + (snapshot.status.warnings + snapshot.status.errors).compactMap(SyncHealthMessage.conditionCode))
                if checkpoint.consecutiveFailures < 3, snapshot.status.result == .deferred {
                    self.activeConditionCodes?.remove(.remoteUnavailable)
                }
                self.reloadSyncIssues()
                self.isRefreshing = false
                if !self.hasUnsavedSelection {
                    self.savedSelection = repository.configuredPaths()
                    self.selectedPaths = self.savedSelection
                }
                if self.refreshPending {
                    self.refreshPending = false; self.reload()
                }
            }
        }
    }

    func changeHistoryPage(by pages: Int) {
        historyOffset = max(0, historyOffset + pages * 50)
        reload()
    }

    private func observeLocalState() {
        stateObservation = LocalStateObservation(directory: overview.configuration.statusDirectory) { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func requestSetup() {
        isSetupSheetPresented = true
    }

    func completeSetup(with locations: RepositoryLocations) {
        do {
            try MacSyncUserConfiguration.saveDataRepository(
                locations.dataRepository,
                environment: baseEnvironment,
            )
            applyRepositoryLocations(locations)
            guard isSetupComplete else {
                errorMessage = "The selected folder must be a Git repository before setup can finish."
                return
            }
            try repository.seedMachineConfigurationIfNeeded()
            savedSelection = repository.configuredPaths()
            selectedPaths = savedSelection
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
                self?.refreshHealth(force: true)
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
                extraEnvironment: ["MAC_SYNC_DRY_RUN": "1"],
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
            extraEnvironment: ["MAC_SYNC_DRY_RUN": "1"],
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
        if let processID = overview.localSyncProcessID,
           MacSyncProcessIdentity.isWorker(processID, environment: commandEnvironment)
        {
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
            try issueRepository.update(
                issueID: issue.id,
                latestOccurrenceID: issue.latestOccurrenceID,
                disposition: disposition,
                note: note,
            )
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

    func testEncryptedSecretsAccess() {
        guardSetup()
        guard isSetupComplete else { return }
        run(arguments: ["secrets", "test"], action: .testingEncryptedSecretsAccess)
    }

    func useSSHForDataRepository() {
        guardSetup()
        guard isSetupComplete, !isCheckingGitHubAccess else { return }
        let locations = repositoryLocations
        let environment = commandEnvironment
        isCheckingGitHubAccess = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try RepositorySetupService(environment: environment)
                    .useSSHRemote(for: locations)
            }
            let reports = RepositorySetupService(environment: environment)
                .checkGitHubAccess(for: locations)
            DispatchQueue.main.async {
                self?.repositoryInspections = reports.map(\.repository)
                self?.gitHubReports = reports
                self?.isCheckingGitHubAccess = false
                if case let .failure(error) = result {
                    self?.errorMessage = error.localizedDescription
                }
                self?.refreshHealth(force: true)
            }
        }
    }

    func performRecoveryAction(_ action: SyncIssueRecoveryAction) {
        switch action {
        case .retrySync:
            syncSelection()
        case .testGitHubAccess:
            checkGitHubAccess()
        case .useSSH:
            useSSHForDataRepository()
        case .testEncryptedSecrets:
            testEncryptedSecretsAccess()
        case .openKeychainAccess:
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app")
            guard NSWorkspace.shared.open(url) else {
                errorMessage = "Keychain Access could not be opened."
                return
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func run(
        arguments: [String],
        action: SyncAction,
        extraEnvironment: [String: String] = [:],
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
        let directory = URL(fileURLWithPath: overview.configuration.statusDirectory).appendingPathComponent("activity")
        let url = directory.appendingPathComponent("\(UUID().uuidString).log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let logs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "log" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
            for old in logs.dropFirst(4) {
                try? FileManager.default.removeItem(at: old)
            }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            activityHandle = try FileHandle(forWritingTo: url)
            activityURL = url
        } catch { errorMessage = error.localizedDescription; return }
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = commandEnvironment.merging(extraEnvironment) { _, replacement in replacement }
        process.environment?["MAC_SYNC_QUIET"] = "1"
        process.standardOutput = activityHandle
        process.standardError = activityHandle

        commandOutput = ""
        errorMessage = nil
        activeAction = action
        self.process = process

        activityObservation = LocalStateObservation(directory: url.path) { [weak self] in
            DispatchQueue.main.async { self?.readActivityTail() }
        }
        process.terminationHandler = { [weak self] completedProcess in
            DispatchQueue.main.async {
                self?.finish(process: completedProcess)
            }
        }

        do {
            try process.run()
        } catch {
            activeAction = nil
            self.process = nil
            activityObservation = nil
            try? activityHandle?.close()
            activityHandle = nil
            errorMessage = error.localizedDescription
        }
    }

    private func readActivityTail() {
        guard let activityURL, let handle = try? FileHandle(forReadingFrom: activityURL) else { return }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: size > 50000 ? size - 50000 : 0)
            commandOutput = try String(decoding: handle.read(upToCount: 50000) ?? Data(), as: UTF8.self)
        } catch { /* The next status update retries a transient read failure. */ }
    }

    private func finish(process: Process) {
        readActivityTail()
        activityObservation = nil
        try? activityHandle?.close()
        activityHandle = nil
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
        if status == 0, completedAction == .testingEncryptedSecretsAccess {
            do {
                try SyncHealthVerificationStore(configuration: overview.configuration)
                    .markEncryptedSecretsVerified(for: overview)
            } catch {
                errorMessage = "Encrypted-secrets access passed, but Mac Sync could not save the verification: \(error.localizedDescription)"
            }
        }
        reload()
        refreshHealth(force: true)
    }

    private func applyRepositoryLocations(_ locations: RepositoryLocations) {
        generation += 1
        isRefreshing = false
        refreshPending = false
        var environment = MacSyncRuntimeEnvironment.prepared(baseEnvironment)
        environment.removeValue(forKey: "MAC_SYNC_REPO")
        environment["MAC_SYNC_MACHINES_REPO"] = locations.dataRepository
        commandEnvironment = environment
        repository = SyncRepository(environment: environment)
        let setupService = RepositorySetupService(environment: environment)
        repositoryInspections = setupService.inspect(locations)
        gitHubReports = setupService.initialGitHubReports(for: repositoryInspections)
        isSetupComplete = repositoryInspections.allSatisfy(\.isReady)
        overview = repository.load(includeSnapshotDetails: false)
        issueRepository = SyncIssueRepository(configuration: overview.configuration)
        activeConditionCodes = nil
        reloadSyncIssues()
        refreshHealth(force: true)
        let configuredPaths = repository.configuredPaths()
        selectedPaths = configuredPaths
        savedSelection = configuredPaths
        reloadSyncSchedule()
        observeLocalState()
    }

    private func guardSetup() {
        guard !isSetupComplete else { return }
        errorMessage = SyncConfigurationError.setupRequired.localizedDescription
    }

    private func scheduleManager() -> SyncScheduleManager {
        SyncScheduleManager(
            configuration: overview.configuration,
            executableURL: MacSyncCommandLocator.scheduledExecutableURL(environment: commandEnvironment),
            applicationURL: MacSyncCommandLocator.scheduledApplicationURL(environment: commandEnvironment),
            environment: commandEnvironment,
        )
    }

    private static func locations(from environment: [String: String]) -> RepositoryLocations {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let defaults = RepositoryLocations.defaults(homeDirectory: home)
        return RepositoryLocations(
            dataRepository: environment["MAC_SYNC_MACHINES_REPO"] ?? defaults.dataRepository,
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
        syncIssues = issueRepository.issues(
            for: overview,
            activeConditionCodes: activeConditionCodes,
        )
        updateDockBadge()
    }

    private func refreshHealth(force: Bool = false) {
        guard isSetupComplete else { return }
        if healthEvaluationInProgress {
            healthEvaluationPending = true
            return
        }
        if !force,
           let lastHealthEvaluationAt,
           Date().timeIntervalSince(lastHealthEvaluationAt) < 15
        {
            return
        }

        let snapshot = overview
        let environment = commandEnvironment
        healthEvaluationInProgress = true
        lastHealthEvaluationAt = Date()
        healthQueue.async { [weak self] in
            let activeCodes = SyncHealthEvaluator(environment: environment)
                .activeConditionCodes(in: snapshot)
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeConditionCodes = activeCodes
                self.healthEvaluationInProgress = false
                self.reloadSyncIssues()
                if self.healthEvaluationPending {
                    self.healthEvaluationPending = false
                    self.refreshHealth(force: true)
                }
            }
        }
    }

    private func updateDockBadge() {
        let badge = openIssueCount == 0 ? nil : "\(openIssueCount)"
        NSApplication.shared.dockTile.badgeLabel = badge
        NSApplication.shared.dockTile.display()
    }
}
