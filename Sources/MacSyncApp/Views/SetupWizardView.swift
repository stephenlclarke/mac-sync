import AppKit
import MacSyncCore
import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var store: SyncStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SetupWizardModel
    @State private var recoveryPlan: RepositoryRecoveryPlan?
    @State private var folderAccessError: String?

    init(store: SyncStore) {
        self.store = store
        _model = StateObject(wrappedValue: SetupWizardModel(locations: store.repositoryLocations))
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Set up Mac Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title.bold())
                Text("Use your own private Git repository. GitHub, GitLab, Bitbucket and other HTTPS/SSH Git servers are supported.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("1. mac-sync data repository") {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Backup destination", selection: $model.storageKind) {
                        ForEach(BackupStorageKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }.pickerStyle(.segmented)
                        .disabled(model.isWorking)
                        .onChange(of: model.storageKind) { model.changeStorageKind($0) }
                    if model.storageKind == .cloudFolder {
                        Text("Choose a private folder already synced by iCloud Drive, OneDrive, Dropbox or another provider. Mac Sync saves independent versions there; only that provider can confirm their upload.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("Cloud-synced folder", text: $model.cloudFolder).textFieldStyle(.roundedBorder)
                            Button("Choose Folder…") { chooseCloudFolder() }
                        }
                        Button("Prepare Folder Destination") { model.prepareCloudFolder() }
                            .disabled(model.isWorking || model.cloudFolder.isEmpty)
                        Text("The live working repository stays outside the synced folder. Existing unrelated files will not be changed.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Git host", selection: $model.provider) {
                            ForEach(GitHostingProvider.allCases) { provider in Text(provider.title).tag(provider) }
                        }
                        if let creationURL = model.provider.creationURL {
                            Link("Create a private repository on \(model.provider.title)…", destination: creationURL)
                        }
                        Text("Create the repository in your browser, choose Private, then paste its HTTPS or SSH clone URL below. Mac Sync does not create accounts. Provider tokens must stay in Keychain, never in clone URLs.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Repository setup instructions", destination: model.provider.instructionsURL)
                        TextField("Your repository clone URL", text: $model.remoteURL)
                            .textFieldStyle(.roundedBorder)
                        if MacSyncDistribution.current == .appStore {
                            DisclosureGroup("Set up HTTPS access") {
                                GitCredentialsView(remote: model.remoteURL)
                            }
                        }
                        Toggle("I confirmed that this repository is private", isOn: $model.confirmedPrivate)
                        HStack {
                            Label("mac-sync-data", systemImage: "externaldrive.connected.to.line.below")
                                .font(.headline)
                            Spacer()
                            RepositoryStateLabel(state: model.inspection(for: .syncData)?.state)
                        }
                        HStack(spacing: 8) {
                            TextField("Local folder", text: model.pathBinding(for: .syncData))
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") {
                                chooseDirectory()
                            }
                        }
                        Text("Choose a checkout or an empty local folder. Clone imports the private data repository; the first sync writes its initial snapshot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            if let folderAccessError {
                Label(folderAccessError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }

            if model.storageKind == .git {
                GroupBox("2. Create or validate") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button("Refresh") {
                                model.refresh()
                            }
                            .disabled(model.isWorking)

                            if let plan = model.recoveryPlan() {
                                Button("Back Up Legacy Folder and Clone…") {
                                    recoveryPlan = plan
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorking)
                            } else {
                                Button("Clone mac-sync-data Repository") {
                                    model.cloneMissingRepositories()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorking || model.hasAllRepositories || !model.canClone)
                            }

                            if model.isWorking, model.activeProgress == nil {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if let progress = model.activeProgress {
                            SetupProgressRow(progress: progress)
                        } else if let message = model.messages.last {
                            Label(message, systemImage: message.hasPrefix("Unable") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(message.hasPrefix("Unable") ? .orange : .secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if model.storageKind == .git {
                GroupBox("3. Repository access") {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Checks read access and a dry-run push without opening a credential prompt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Button(model.isCheckingRepositoryAccess ? "Checking…" : "Test Repository Access") {
                                model.checkRepositoryAccess()
                            }
                            .disabled(!model.hasAllRepositories || model.isWorking || model.isCheckingRepositoryAccess)
                        }
                        if let report = model.repositoryReports.first {
                            CompactRepositoryConnectionRow(report: report)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            InstallationIdentityImportView(store: store)

            HStack(alignment: .bottom) {
                Text(MacSyncDistribution.current == .appStore
                    ? "Finish saves this destination. Choose Automatic sync in Settings to allow background sync. Folder access and Keychain access must be granted in this edition."
                    : "Finish saves this destination and updates any Mac Sync-managed schedule. Git credentials stay in Git and Keychain. Background Homebrew services remain a separate scheduling choice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Finish Setup") {
                    if store.completeSetup(with: model.locations) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasAllRepositories || model.isWorking)
            }
        } }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 900, maxWidth: 980, minHeight: 560, idealHeight: 720, maxHeight: 800, alignment: .topLeading)
        .task {
            model.refresh()
        }
        .alert("Mac Sync setup", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: {
                if !$0 {
                    model.dismissError()
                }
            },
        )) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "An unknown setup error occurred.")
        }
        .confirmationDialog(
            "Back up legacy folder?",
            isPresented: Binding(
                get: { recoveryPlan != nil },
                set: {
                    if !$0 {
                        recoveryPlan = nil
                    }
                },
            ),
            presenting: recoveryPlan,
        ) { plan in
            Button("Back Up and Clone", role: .destructive) {
                model.backUpAndClone(plan)
                recoveryPlan = nil
            }
            Button("Cancel", role: .cancel) {
                recoveryPlan = nil
            }
        } message: { plan in
            Text("Mac Sync will move \(plan.originalPath) to \(plan.backupPath), then clone mac-sync-data into the original location. Nothing is deleted; if cloning fails, it restores the original folder.")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the mac-sync-data checkout or an empty folder to clone into."
        if panel.runModal() == .OK, let url = panel.url {
            do { try MacSyncApplicationRuntime.shared.remember(url) }
            catch { folderAccessError = error.localizedDescription; return }
            folderAccessError = nil
            model.setPath(url.standardizedFileURL.path, for: .syncData)
        }
    }

    private func chooseCloudFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try MacSyncApplicationRuntime.shared.remember(url) }
            catch { folderAccessError = error.localizedDescription; return }
            folderAccessError = nil
            model.cloudFolder = url.path
        }
    }
}

private struct SetupProgress: Equatable {
    let title: String
    let detail: String
    let startedAt: Date
}

private struct SetupProgressRow: View {
    let progress: SetupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.title)
                        .font(.caption.weight(.semibold))
                    Text(progress.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                    Text(elapsedTime(at: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 44, alignment: .trailing)
            }
            ProgressView()
                .progressViewStyle(.linear)
        }
        .padding(.top, 2)
    }

    private func elapsedTime(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(progress.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

private struct RepositoryStateLabel: View {
    let state: LocalRepositoryState?

    var body: some View {
        switch state {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .missing:
            Label("Missing", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .notGitRepository:
            Label("Legacy folder", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case nil:
            ProgressView()
                .controlSize(.small)
        }
    }
}

private struct CompactRepositoryConnectionRow: View {
    let report: RepositoryConnectionReport

    var body: some View {
        Label(report.detail, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(colour)
            .lineLimit(2)
    }

    private var systemImage: String {
        switch report.state {
        case .syncAccessReady:
            "checkmark.shield.fill"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .notChecked, .noOrigin:
            "questionmark.circle"
        case .readAccessReady, .unsupportedRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var colour: Color {
        switch report.state {
        case .syncAccessReady:
            .green
        case .checking, .notChecked, .noOrigin:
            .secondary
        case .readAccessReady, .unsupportedRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            .orange
        }
    }
}

struct RepositoryConnectionRow: View {
    let report: RepositoryConnectionReport

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: image)
                .foregroundStyle(colour)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(report.repository.kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(colour)
                Text(report.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let remote = report.repository.remoteURL {
                    Text(remote)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch report.state {
        case .notChecked:
            "Not checked"
        case .checking:
            "Checking"
        case .readAccessReady:
            "Read access ready"
        case .syncAccessReady:
            "Read and write access ready"
        case .noOrigin:
            "No origin remote"
        case .unsupportedRemote:
            "Unsupported Git remote"
        case .authenticationRequired:
            "Authentication required"
        case .writeAccessDenied:
            "Write access unavailable"
        case .unavailable:
            "Repository unavailable"
        case .failed:
            "Needs attention"
        }
    }

    private var image: String {
        switch report.state {
        case .readAccessReady, .syncAccessReady:
            "checkmark.shield.fill"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .notChecked, .noOrigin:
            "questionmark.circle"
        case .unsupportedRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var colour: Color {
        switch report.state {
        case .readAccessReady, .syncAccessReady:
            .green
        case .notChecked, .checking, .noOrigin:
            .secondary
        case .unsupportedRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            .orange
        }
    }
}

@MainActor
final class SetupWizardModel: ObservableObject {
    @Published var storageKind: BackupStorageKind
    @Published var cloudFolder: String
    @Published var provider = GitHostingProvider.github
    @Published var remoteURL = ""
    @Published var confirmedPrivate = false
    @Published private(set) var locations: RepositoryLocations
    @Published private(set) var inspections: [LocalRepositoryInspection] = []
    @Published private(set) var repositoryReports: [RepositoryConnectionReport] = []
    @Published private(set) var messages: [String] = []
    @Published private(set) var isWorking = false
    @Published private(set) var isCheckingRepositoryAccess = false
    @Published private(set) var errorMessage: String?
    @Published fileprivate var activeProgress: SetupProgress?

    private let environment: [String: String]
    private var gitLocation: String

    init(
        locations: RepositoryLocations,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.locations = locations
        gitLocation = locations.storageKind == .git ? locations.dataRepository : (environment["HOME"] ?? NSHomeDirectory()) + "/github/mac-sync-data"
        storageKind = locations.storageKind
        cloudFolder = locations.cloudFolder ?? ""
        self.environment = MacSyncUserConfiguration.resolvedEnvironment(MacSyncDistribution.current == .appStore ? MacSyncRuntimeEnvironment.prepared(environment) : environment)
    }

    var hasAllRepositories: Bool {
        inspections.count == LocalRepositoryKind.allCases.count && inspections.allSatisfy(\.isReady)
            && locations.storageKind == storageKind && (storageKind == .git || locations.cloudFolder == cloudFolder)
    }

    var canClone: Bool {
        guard let remote = GitRemote(remoteURL) else { return false }
        return confirmedPrivate && (remote.isSSH || remote.user == nil)
    }

    func changeStorageKind(_ kind: BackupStorageKind) {
        if kind == .git {
            locations = RepositoryLocations(dataRepository: gitLocation)
            refresh()
        } else {
            if locations.storageKind == .git {
                gitLocation = locations.dataRepository
            }
            inspections = []
            repositoryReports = []
        }
    }

    func inspection(for kind: LocalRepositoryKind) -> LocalRepositoryInspection? {
        inspections.first { $0.kind == kind }
    }

    func pathBinding(for kind: LocalRepositoryKind) -> Binding<String> {
        Binding(
            get: { self.locations.dataRepository },
            set: { path in
                self.setPath(path, for: kind, refresh: false)
            },
        )
    }

    func setPath(_ path: String, for kind: LocalRepositoryKind) {
        setPath(path, for: kind, refresh: true)
    }

    func refresh() {
        runInspection(showProgress: true)
    }

    func prepareCloudFolder() {
        guard !isWorking else { return }
        isWorking = true
        let folder = cloudFolder
        let environment = environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try RepositorySetupService(environment: environment).prepareCloudFolder(folder, home: home) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isWorking = false
                switch result {
                case let .success(locations): self.locations = locations; self.refresh()
                case let .failure(error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func recoveryPlan() -> RepositoryRecoveryPlan? {
        RepositorySetupService(environment: environment).recoveryPlan(for: .syncData, locations: locations)
    }

    func cloneMissingRepositories() {
        guard canClone else { return }
        let remote = remoteURL
        runClone(
            title: "Cloning mac-sync-data",
            detail: "Downloading the private snapshot repository into \(locations.dataRepository)",
        ) { service, locations in
            service.cloneMissing(locations, remoteURL: remote)
        }
    }

    func backUpAndClone(_ plan: RepositoryRecoveryPlan) {
        guard canClone else { return }
        let remote = remoteURL
        runClone(
            title: "Backing up and cloning mac-sync-data",
            detail: "Moving the legacy folder aside, then cloning a fresh repository",
        ) { service, locations in
            service.backUpAndClone(plan, locations: locations, remoteURL: remote)
        }
    }

    func checkRepositoryAccess() {
        guard hasAllRepositories, !isCheckingRepositoryAccess else { return }
        isCheckingRepositoryAccess = true
        let locations = locations
        let environment = environment
        repositoryReports = RepositorySetupService(environment: environment).checkingRepositoryReports(for: inspections)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reports = RepositorySetupService(environment: environment).checkRepositoryAccess(for: locations)
            DispatchQueue.main.async {
                self?.inspections = reports.map(\.repository)
                self?.repositoryReports = reports
                self?.isCheckingRepositoryAccess = false
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func setPath(_ path: String, for _: LocalRepositoryKind, refresh: Bool) {
        locations = RepositoryLocations(dataRepository: path.trimmingCharacters(in: .whitespacesAndNewlines), storageKind: storageKind,
                                        cloudFolder: storageKind == .cloudFolder ? cloudFolder : nil)
        messages = []
        repositoryReports = []
        activeProgress = nil
        if refresh {
            runInspection(showProgress: false)
        }
    }

    private func runClone(
        title: String,
        detail: String,
        _ operation: @escaping @Sendable (RepositorySetupService, RepositoryLocations) -> RepositoryCloneResult,
    ) {
        guard !isWorking else { return }
        isWorking = true
        activeProgress = SetupProgress(title: title, detail: detail, startedAt: Date())
        let locations = locations
        let environment = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let service = RepositorySetupService(environment: environment)
            let result = operation(service, locations)
            DispatchQueue.main.async {
                self?.inspections = result.inspections
                self?.repositoryReports = service.initialRepositoryReports(for: result.inspections)
                self?.messages = result.messages
                self?.isWorking = false
                self?.activeProgress = nil
            }
        }
    }

    private func runInspection(showProgress: Bool) {
        guard !isWorking else { return }
        isWorking = showProgress
        activeProgress = nil
        let locations = locations
        let environment = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let service = RepositorySetupService(environment: environment)
            let inspections = service.inspect(locations)
            let reports = service.initialRepositoryReports(for: inspections)
            DispatchQueue.main.async {
                self?.inspections = inspections
                self?.repositoryReports = reports
                self?.isWorking = false
            }
        }
    }
}
