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
    @Published private(set) var repositoryReports: [RepositoryConnectionReport]
    @Published private(set) var isSetupComplete: Bool
    @Published private(set) var isCheckingRepositoryAccess = false
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
    @Published private(set) var backupPreferences = BackupPreferences()
    @Published private(set) var protection: BackupProtectionRecord?
    @Published private(set) var incomingChanges: [IncomingSyncChange] = []
    private var hasPendingIncomingChanges: Bool?
    private var stateObservation: LocalStateObservation?
    private var incomingReviewObservation: LocalStateObservation?
    private var observedReviewLedger: String?
    // Global queues do not guarantee a per-work-item autorelease pool.
    private let readQueue = DispatchQueue(label: "tools.xyzzy.mac-sync.overview", qos: .utility, autoreleaseFrequency: .workItem)
    private let healthQueue = DispatchQueue(label: "tools.xyzzy.mac-sync.health", qos: .utility, autoreleaseFrequency: .workItem)
    private var refreshPending = false
    private var generation = 0
    private var repairScopeNonce = UUID()

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
        repositoryReports = setupService.initialRepositoryReports(for: inspections)
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
        reloadPreferences()
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
        if SyncHealthMessage.isIncomingReviewWarning(message), !overview.status.errors.contains(message) {
            return hasPendingIncomingChanges == false ? .recovered : .active
        }
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
            let protection = BackupProtectionRecord.load(directory: snapshot.configuration.statusDirectory, machine: snapshot.configuration.machineName)
            let incoming = try? IncomingSyncEngine.pendingChanges(repository: snapshot.configuration.dataRepository,
                                                                  status: snapshot.configuration.statusDirectory, machine: snapshot.configuration.machineName)
            let incomingPending = try? IncomingSyncEngine.hasPendingChanges(
                repository: snapshot.configuration.dataRepository,
                status: snapshot.configuration.statusDirectory, machine: snapshot.configuration.machineName
            )
            DispatchQueue.main.async {
                guard let self, self.generation == requestedGeneration else { return }
                self.overview = snapshot
                self.observeLocalState()
                self.historyTotal = count
                self.historyEntryCounts = counts
                self.backgroundDetail = checkpoint.detail
                let expected = snapshot.configuration.storageKind == .cloudFolder
                    ? "folder:\(snapshot.configuration.cloudFolder ?? "")"
                    : "git:\(self.repositoryInspections.first?.remoteURL ?? "local-only")"
                self.protection = protection?.destination == expected ? protection : nil
                if let incoming {
                    self.incomingChanges = incoming
                }
                self.hasPendingIncomingChanges = incomingPending
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
        let config = overview.configuration
        let ledger = IncomingSyncEngine.reviewLedgerPath(
            repository: config.dataRepository, status: config.statusDirectory, machine: config.machineName
        )
        let journal = ledger + "-wal"
        if !FileManager.default.fileExists(atPath: journal) {
            incomingReviewObservation = nil
        } else if incomingReviewObservation?.isHealthy != true || observedReviewLedger != ledger {
            // Watch only WAL data, not the database or SHM files that carry
            // SQLite locks. Reject a substituted symbolic link.
            incomingReviewObservation = LocalStateObservation(directory: journal, noFollow: true) { [weak self] in
                DispatchQueue.main.async { self?.reload() }
            }
        }
        observedReviewLedger = ledger
    }

    private var incomingReviewObservationIsHealthy: Bool {
        let config = overview.configuration
        let ledger = IncomingSyncEngine.reviewLedgerPath(
            repository: config.dataRepository, status: config.statusDirectory, machine: config.machineName
        )
        guard observedReviewLedger == ledger else { return false }
        return !FileManager.default.fileExists(atPath: ledger + "-wal") || incomingReviewObservation?.isHealthy == true
    }

    func requestSetup() {
        isSetupSheetPresented = true
    }

    @discardableResult
    func completeSetup(with locations: RepositoryLocations, machineIdentifier: String? = nil) -> Bool {
        guard !isRunning else { errorMessage = "Wait for the current operation before changing the destination."; return false }
        guard RepositorySetupService(environment: commandEnvironment).inspect(locations).allSatisfy(\.isReady) else {
            errorMessage = "The selected folder must be a Git repository before setup can finish."
            return false
        }
        let previousSchedule = syncScheduleStatus.schedule
        let previousLocations = repositoryLocations
        let previousEnvironment = commandEnvironment
        let previousSelection = savedSelection
        var setupEnvironment = baseEnvironment
        setupEnvironment["MAC_SYNC_MACHINE"] = machineIdentifier ?? commandEnvironment["MAC_SYNC_MACHINE"]
        let configURL = URL(fileURLWithPath: MacSyncUserConfiguration.configurationFilePath(environment: baseEnvironment))
        let previousConfig = try? Data(contentsOf: configURL)
        do {
            try MacSyncUserConfiguration.saveDestination(
                BackupDestinationSettings(workspace: locations.dataRepository, kind: locations.storageKind, cloudFolder: locations.cloudFolder),
                environment: setupEnvironment,
            )
            commandEnvironment["MAC_SYNC_MACHINE"] = setupEnvironment["MAC_SYNC_MACHINE"]
            applyRepositoryLocations(locations)
            guard isSetupComplete else {
                throw SyncConfigurationError.setupRequired
            }
            try repository.seedMachineConfigurationIfNeeded()
            if !FileManager.default.fileExists(atPath: repository.configuration().pathsFile) {
                try repository.saveConfiguredPaths(machineIdentifier == nil ? [] : previousSelection)
            }
            savedSelection = repository.configuredPaths()
            selectedPaths = savedSelection
            try repository.clearStaleLocalStatusWhenSnapshotIsMissing()
            reload()
            if let previousSchedule {
                _ = try scheduleManager().configure(schedule: previousSchedule); reloadSyncSchedule()
            }
            isSetupSheetPresented = false
            errorMessage = nil
            if locations.storageKind == .cloudFolder {
                refreshAvailableBackups()
            }
            return true
        } catch {
            if let previousConfig {
                try? previousConfig.write(to: configURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: configURL.path) {
                try? FileManager.default.removeItem(at: configURL)
            }
            commandEnvironment = previousEnvironment
            applyRepositoryLocations(previousLocations)
            errorMessage = error.localizedDescription
            return false
        }
    }

    func checkRepositoryAccess() {
        guard isSetupComplete, !isCheckingRepositoryAccess else { return }
        let locations = repositoryLocations
        let environment = commandEnvironment
        let service = RepositorySetupService(environment: environment)
        repositoryReports = service.checkingRepositoryReports(for: repositoryInspections)
        isCheckingRepositoryAccess = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reports = RepositorySetupService(environment: environment).checkRepositoryAccess(for: locations)
            DispatchQueue.main.async {
                self?.repositoryInspections = reports.map(\.repository)
                self?.repositoryReports = reports
                self?.isCheckingRepositoryAccess = false
                self?.refreshHealth(force: true)
            }
        }
    }

    func add(paths: [String]) {
        if MacSyncDistribution(environment: commandEnvironment) == .appStore,
           let problem = MacSyncApplicationRuntime.shared.accessProblem(paths: paths.map { $0.hasPrefix("/") ? $0 : "\(overview.configuration.homeDirectory)/\($0)" })
        {
            errorMessage = problem
            return
        }
        let allPaths = selectedPaths + paths
        var seen = Set<String>()
        selectedPaths = allPaths.filter {
            let path = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && seen.insert(path).inserted
        }
    }

    func add(fileURLs: [URL]) {
        do {
            if MacSyncDistribution(environment: commandEnvironment) == .appStore {
                try MacSyncApplicationRuntime.shared.authorize(fileURLs)
            }
        } catch { errorMessage = error.localizedDescription; return }
        add(paths: fileURLs.map(repository.pathForUserSelection))
    }

    func remove(path: String) {
        selectedPaths.removeAll { $0 == path }
    }

    func removeArchivedConfiguredRoot(_ path: String) {
        guardSetup()
        guard isSetupComplete, !isRunning else { return }
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
        guard isSetupComplete, authorizeCopyPaths(paths) else { return }
        let arguments = restoreArguments(from: machine, paths: paths)
        run(
            arguments: arguments,
            action: .previewingRestore(machine),
            extraEnvironment: ["MAC_SYNC_DRY_RUN": "1"],
        )
    }

    func restore(from machine: String, force: Bool, paths: [String]? = nil) {
        guardSetup()
        guard isSetupComplete, authorizeCopyPaths(paths) else { return }
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
        guard !isRunning else { errorMessage = "Wait for the current sync to finish before changing its background schedule."; return }

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

    var recoveryService: BackupRecoveryService {
        let config = overview.configuration
        return BackupRecoveryService(repository: config.dataRepository, statusDirectory: config.statusDirectory,
                                     home: config.homeDirectory, environment: commandEnvironment)
    }

    func verifyRecovery(machine: String, revision: String) {
        run(arguments: ["verify", "--from", machine, "--revision", revision], action: .testingRecovery(machine))
    }

    func refreshAvailableBackups() {
        run(arguments: ["refresh"], action: .refreshingBackups)
    }

    func restoreVersion(machine: String, revision: String, paths: [String], force: Bool = false, preview: Bool = false, output: String? = nil) {
        guard authorizeCopyPaths(output.map { [$0] } ?? paths) else { return }
        var arguments = ["restore", "--from", machine, "--revision", revision]
        for path in paths {
            arguments += ["--path", path]
        }
        if force {
            arguments.append("--force")
        }
        if let output {
            arguments += ["--output", output]
        }
        run(arguments: arguments, action: preview ? .previewingRestore(machine) : .restoring(machine),
            extraEnvironment: preview ? ["MAC_SYNC_DRY_RUN": "1"] : [:])
    }

    func undoRestore(id: String, preview: Bool) {
        if MacSyncDistribution(environment: commandEnvironment) == .appStore {
            do {
                guard try authorizeCopyPaths(recoveryService.undoPreview(id: id).map(\.path)) else { return }
            } catch { errorMessage = error.localizedDescription; return }
        }
        run(arguments: ["undo-restore", id, preview ? "--preview" : "--force"], action: .undoingRestore)
    }

    func exportRecoveryKey(to url: URL) {
        run(arguments: ["secrets", "export-key", "--output", url.path, "--confirm-sensitive-export"], action: .exportingRecoveryKey)
    }

    func loadIncomingChanges(offset: Int) async throws -> [IncomingSyncChange] {
        let configuration = overview.configuration
        return try await Task.detached(priority: .utility) {
            try IncomingSyncEngine.pendingChanges(repository: configuration.dataRepository, status: configuration.statusDirectory,
                                                  machine: configuration.machineName, limit: 100, offset: offset)
        }.value
    }

    func resolveIncoming(_ change: IncomingSyncChange, choice: String) {
        guard authorizeCopyPaths([change.path]) else { return }
        run(arguments: ["incoming", "resolve", change.id, choice], action: .restoring(change.machine))
    }

    func sendFiles(_ files: [URL], to machine: String, paths: [String]) {
        guard !files.isEmpty, files.count == paths.count, files.count <= 100 else { errorMessage = "Choose between 1 and 100 regular files per delivery."; return }
        do { try MacSyncApplicationRuntime.shared.authorize(files) }
        catch { errorMessage = error.localizedDescription; return }
        var arguments = ["deliver", "--to", machine]
        for (file, path) in zip(files, paths) {
            arguments += ["--path", path, "--file", file.path]
        }
        run(arguments: arguments, action: .restoring(machine))
    }

    func loadDeliveries(target: String, offset: Int) async throws -> [(MachineFileDelivery, MachineDeliveryReceipt?)] {
        let repository = overview.configuration.dataRepository
        let environment = commandEnvironment
        return try await Task.detached(priority: .utility) {
            let store = MachineFileDeliveryStore(repository: repository, environment: environment)
            return try store.deliveries(target: target, offset: offset).map { ($0, store.receipt($0)) }
        }.value
    }

    func resolveDelivery(_ record: MachineFileDelivery, apply: Bool) {
        if apply, !authorizeCopyPaths([record.path]) {
            return
        }
        run(arguments: ["deliveries", "resolve", record.id, apply ? "--apply" : "--keep-local"], action: .restoring(record.sender))
    }

    func savePreferences(_ preferences: BackupPreferences) {
        do {
            try preferences.save(directory: overview.configuration.statusDirectory, machine: overview.configuration.machineName)
            backupPreferences = preferences
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setMachineIdentifier(_ identifier: String) {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, MacSyncPaths.safeMachineName(value) else { errorMessage = "Choose a unique name containing letters, numbers, dots, dashes or underscores. Wait for any active sync first."; return }
        guard value != overview.configuration.machineName else { return }
        guard !FileManager.default.fileExists(atPath: repositoryLocations.dataRepository + "/machines/" + value) else {
            errorMessage = "That identifier already has a snapshot. Choose a new unique identifier so it cannot overwrite another Mac."
            return
        }
        completeSetup(with: repositoryLocations, machineIdentifier: value)
    }

    func pauseBackup(until: Date? = nil, indefinitely: Bool = false) {
        var preferences = backupPreferences
        preferences.pausedUntil = until
        preferences.pauseIndefinitely = indefinitely
        savePreferences(preferences)
    }

    private func reloadPreferences() {
        do { backupPreferences = try BackupPreferences.load(directory: overview.configuration.statusDirectory, machine: overview.configuration.machineName) }
        catch { errorMessage = "Backup preferences could not be read. Save them again in Settings before automatic backup can resume." }
    }

    func useSSHForDataRepository() {
        guardSetup()
        guard isSetupComplete, !isCheckingRepositoryAccess else { return }
        let locations = repositoryLocations
        let environment = commandEnvironment
        isCheckingRepositoryAccess = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try RepositorySetupService(environment: environment)
                    .useSSHRemote(for: locations)
            }
            let reports = RepositorySetupService(environment: environment)
                .checkRepositoryAccess(for: locations)
            DispatchQueue.main.async {
                self?.repositoryInspections = reports.map(\.repository)
                self?.repositoryReports = reports
                self?.isCheckingRepositoryAccess = false
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
            checkRepositoryAccess()
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

    private func authorizeCopyPaths(_ paths: [String]?) -> Bool {
        guard MacSyncDistribution(environment: commandEnvironment) == .appStore else { return true }
        let home = overview.configuration.homeDirectory
        let targets = (paths?.isEmpty == false ? paths! : [home]).map { URL(fileURLWithPath: $0.hasPrefix("/") ? $0 : "\(home)/\($0)") }
        do { try MacSyncApplicationRuntime.shared.authorize(targets); return true }
        catch { errorMessage = error.localizedDescription; return false }
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
        if MacSyncDistribution(environment: commandEnvironment) == .appStore {
            let configuration = overview.configuration
            let paths = action == .syncing ? selectedPaths.map { $0.hasPrefix("/") ? $0 : "\(configuration.homeDirectory)/\($0)" } : []
            if let problem = MacSyncApplicationRuntime.shared.accessProblem(paths: paths + [configuration.dataRepository] + (configuration.cloudFolder.map { [$0] } ?? [])) {
                errorMessage = problem
                return
            }
        }
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
        var accessManifest: URL?
        if MacSyncDistribution(environment: commandEnvironment) == .appStore {
            do {
                let lease = try MacSyncApplicationRuntime.shared.workerEnvironment()
                accessManifest = lease.manifest
                for key in ["MAC_SYNC_ACCESS_MANIFEST", "MAC_SYNC_ACCESS_BOOKMARKS_FILE"] {
                    process.environment?[key] = lease.values[key]
                }
            } catch {
                try? activityHandle?.close()
                activityHandle = nil
                activityURL = nil
                errorMessage = error.localizedDescription
                return
            }
        }
        process.environment?["MAC_SYNC_QUIET"] = "1"
        process.standardOutput = activityHandle
        process.standardError = activityHandle

        commandOutput = ""
        errorMessage = nil
        activeAction = action
        repairScopeNonce = UUID()
        self.process = process

        activityObservation = LocalStateObservation(directory: url.path) { [weak self] in
            DispatchQueue.main.async { self?.readActivityTail() }
        }
        let manifestToRemove = accessManifest
        process.terminationHandler = { [weak self] completedProcess in
            if let manifestToRemove {
                try? FileManager.default.removeItem(at: manifestToRemove)
            }
            DispatchQueue.main.async {
                self?.finish(process: completedProcess)
            }
        }

        do {
            try process.run()
        } catch {
            if let accessManifest {
                try? FileManager.default.removeItem(at: accessManifest)
            }
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
        // A late callback must not finish an operation started after a safe repair.
        guard self.process === process else { return }
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
        repairScopeNonce = UUID()
        generation += 1
        isRefreshing = false
        refreshPending = false
        var environment = MacSyncRuntimeEnvironment.prepared(baseEnvironment)
        environment.removeValue(forKey: "MAC_SYNC_REPO")
        environment["MAC_SYNC_MACHINES_REPO"] = locations.dataRepository
        environment["MAC_SYNC_STORAGE_KIND"] = locations.storageKind.rawValue
        environment["MAC_SYNC_CLOUD_FOLDER"] = locations.cloudFolder
        environment["MAC_SYNC_MACHINE"] = commandEnvironment["MAC_SYNC_MACHINE"]
        commandEnvironment = environment
        repository = SyncRepository(environment: environment)
        let setupService = RepositorySetupService(environment: environment)
        repositoryInspections = setupService.inspect(locations)
        repositoryReports = setupService.initialRepositoryReports(for: repositoryInspections)
        isSetupComplete = repositoryInspections.allSatisfy(\.isReady)
        overview = repository.load(includeSnapshotDetails: false)
        hasPendingIncomingChanges = nil
        issueRepository = SyncIssueRepository(configuration: overview.configuration)
        activeConditionCodes = nil
        reloadSyncIssues()
        refreshHealth(force: true)
        let configuredPaths = repository.configuredPaths()
        selectedPaths = configuredPaths
        savedSelection = configuredPaths
        reloadSyncSchedule()
        reloadPreferences()
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
            storageKind: BackupStorageKind(rawValue: environment["MAC_SYNC_STORAGE_KIND"] ?? "") ?? .git,
            cloudFolder: environment["MAC_SYNC_CLOUD_FOLDER"],
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
            hasPendingIncomingChanges: hasPendingIncomingChanges,
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

extension SyncStore: LocalRepairRuntime {
    /// Private app context is never sent to the model. Selection changes invalidate approval too.
    var localRepairScope: String {
        let config = overview.configuration
        let fields = [repairScopeNonce.uuidString, config.homeDirectory, config.dataRepository, config.statusDirectory,
                      config.machineName, config.storageKind.rawValue, config.cloudFolder ?? ""] + selectedPaths
        return String(data: (try? JSONEncoder().encode(fields)) ?? Data(), encoding: .utf8) ?? ""
    }

    func inspectLocalRepairs() async throws -> LocalRepairInspection {
        let state = try await readLocalRepairState()
        var candidates: [LocalRepairAction] = []
        if let status = state.status, status != overview.status {
            candidates.append(.refreshStatus)
        }
        if stateObservation?.isHealthy != true || !incomingReviewObservationIsHealthy {
            candidates.append(.reconnectObserver)
        }
        if (activeAction != nil && process?.isRunning != true) || overview.isLocalSyncActive {
            if state.worker == .idle {
                candidates.append(.clearFinishedActivity)
            }
        }
        return .init(scope: state.scope, worker: state.worker, candidates: candidates)
    }

    func applyLocalRepair(_ action: LocalRepairAction, scope: String) async throws {
        let state = try await readLocalRepairState()
        guard state.scope == scope, localRepairScope == scope else { throw LocalRepairError.changedScope }
        guard state.worker == .idle else { throw LocalRepairError.workerNotIdle }
        // No suspension between this final check and the bounded memory/handle change.
        switch action {
        case .refreshStatus:
            guard let status = state.status else { throw LocalRepairError.unreadableStatus }
            replaceOperationalOverview(status: status, clearWorker: false)
            activeConditionCodes = Set(status.conditions.map(\.code)
                + (status.warnings + status.errors).compactMap(SyncHealthMessage.conditionCode))
            syncIssues = issueRepository.issues(
                for: overview, activeConditionCodes: activeConditionCodes,
                hasPendingIncomingChanges: hasPendingIncomingChanges, cachedDecisions: syncIssues
            )
            updateDockBadge()
        case .reconnectObserver:
            if stateObservation?.isHealthy != true || !incomingReviewObservationIsHealthy {
                observeLocalState()
            }
            guard stateObservation?.isHealthy == true, incomingReviewObservationIsHealthy else { throw LocalRepairError.verificationFailed }
        case .clearFinishedActivity:
            guard process?.isRunning != true else { throw LocalRepairError.workerNotIdle }
            // Do not call finish/reload: those paths may migrate history or probe credentials/network.
            if let process, process.terminationStatus != 0 {
                errorMessage = "mac-sync finished with exit status \(process.terminationStatus)."
            }
            process = nil
            activeAction = nil
            activityObservation = nil
            try? activityHandle?.close()
            activityHandle = nil
            activityURL = nil
            replaceOperationalOverview(status: overview.status, clearWorker: true)
        }
    }

    /// Call only from an explicit native confirmation, never from the model or automatic executor.
    func approveAssistantSync(scope: String) async throws {
        let inspection = try await inspectLocalRepairs()
        guard inspection.scope == scope, localRepairScope == scope else { throw LocalRepairError.changedScope }
        guard inspection.worker == .idle, !isRunning else { throw LocalRepairError.workerNotIdle }
        repairScopeNonce = UUID() // Single use, including a failed launch.
        syncSelection()
    }

    private func readLocalRepairState() async throws -> LocalRepairReadState {
        try Task.checkCancellation()
        let scope = localRepairScope
        let config = overview.configuration
        let cached = overview.status
        let remote = repositoryInspections.first?.remoteURL
        let temporaryDirectory = commandEnvironment["TMPDIR"] ?? "/tmp"
        let state = try await Task.detached(priority: .utility) {
            let worker = try LocalRepairInspectionReader.worker(
                configuration: config,
                temporaryDirectory: temporaryDirectory
            )
            let status = try LocalRepairInspectionReader.status(
                configuration: config,
                cached: cached,
                expectedRemote: remote
            )
            guard status != nil || cached.result == .unknown else { throw LocalRepairError.unreadableStatus }
            return (worker, status)
        }.value
        try Task.checkCancellation()
        guard scope == localRepairScope else { throw LocalRepairError.changedScope }
        return .init(worker: process?.isRunning == true ? .active : state.0, status: state.1, scope: scope)
    }

    private func replaceOperationalOverview(status: SyncStatus, clearWorker: Bool) {
        overview = SyncOverview(
            configuration: overview.configuration, status: status, history: overview.history,
            currentMachine: overview.currentMachine, peerMachines: overview.peerMachines,
            localSyncProcessID: clearWorker ? nil : overview.localSyncProcessID,
            isLocalSyncActive: clearWorker ? false : overview.isLocalSyncActive
        )
    }
}
