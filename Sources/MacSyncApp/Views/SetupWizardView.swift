import AppKit
import MacSyncCore
import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var store: SyncStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SetupWizardModel
    @State private var recoveryPlan: RepositoryRecoveryPlan?

    init(store: SyncStore) {
        self.store = store
        _model = StateObject(wrappedValue: SetupWizardModel(locations: store.repositoryLocations))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Set up Mac Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title.bold())
                Text("One private repository holds every Mac's snapshots and its own Mac Sync configuration. dot-files is not changed.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("1. mac-sync data repository") {
                VStack(alignment: .leading, spacing: 9) {
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
                .padding(.vertical, 2)
            }

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
                            .disabled(model.isWorking || model.hasAllRepositories)
                        }

                        if model.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let message = model.messages.last {
                        Label(message, systemImage: message.hasPrefix("Unable") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(message.hasPrefix("Unable") ? .orange : .secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }

            GroupBox("3. GitHub access") {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Checks read access and a dry-run push without opening a credential prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Button(model.isCheckingGitHubAccess ? "Checking…" : "Test GitHub Access") {
                            model.checkGitHubAccess()
                        }
                        .disabled(!model.hasAllRepositories || model.isWorking || model.isCheckingGitHubAccess)
                    }
                    if let report = model.gitHubReports.first {
                        CompactGitHubConnectionRow(report: report)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(alignment: .bottom) {
                Text("The Homebrew CLI uses this local, credential-free setting. Git credentials remain in Git and Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Finish Setup") {
                    store.completeSetup(with: model.locations)
                    if store.isSetupComplete {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasAllRepositories || model.isWorking)
            }
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 900, maxWidth: 980, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            model.refresh()
        }
        .alert("Mac Sync setup", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: {
                if !$0 {
                    model.dismissError()
                }
            }
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
                }
            ),
            presenting: recoveryPlan
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
            model.setPath(url.standardizedFileURL.path, for: .syncData)
        }
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

private struct CompactGitHubConnectionRow: View {
    let report: GitHubConnectionReport

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
        case .readAccessReady, .notGitHubRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var colour: Color {
        switch report.state {
        case .syncAccessReady:
            .green
        case .checking, .notChecked, .noOrigin:
            .secondary
        case .readAccessReady, .notGitHubRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            .orange
        }
    }
}

struct GitHubConnectionRow: View {
    let report: GitHubConnectionReport

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
        case .notGitHubRemote:
            "Not a GitHub remote"
        case .authenticationRequired:
            "Authentication required"
        case .writeAccessDenied:
            "Write access unavailable"
        case .unavailable:
            "GitHub unavailable"
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
        case .notGitHubRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var colour: Color {
        switch report.state {
        case .readAccessReady, .syncAccessReady:
            .green
        case .notChecked, .checking, .noOrigin:
            .secondary
        case .notGitHubRemote, .authenticationRequired, .writeAccessDenied, .unavailable, .failed:
            .orange
        }
    }
}

@MainActor
final class SetupWizardModel: ObservableObject {
    @Published private(set) var locations: RepositoryLocations
    @Published private(set) var inspections: [LocalRepositoryInspection] = []
    @Published private(set) var gitHubReports: [GitHubConnectionReport] = []
    @Published private(set) var messages: [String] = []
    @Published private(set) var isWorking = false
    @Published private(set) var isCheckingGitHubAccess = false
    @Published private(set) var errorMessage: String?

    private let environment: [String: String]

    init(
        locations: RepositoryLocations,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.locations = locations
        self.environment = MacSyncUserConfiguration.resolvedEnvironment(environment)
    }

    var hasAllRepositories: Bool {
        inspections.count == LocalRepositoryKind.allCases.count && inspections.allSatisfy(\.isReady)
    }

    func inspection(for kind: LocalRepositoryKind) -> LocalRepositoryInspection? {
        inspections.first { $0.kind == kind }
    }

    func pathBinding(for kind: LocalRepositoryKind) -> Binding<String> {
        Binding(
            get: { self.locations.dataRepository },
            set: { path in
                self.setPath(path, for: kind, refresh: false)
            }
        )
    }

    func setPath(_ path: String, for kind: LocalRepositoryKind) {
        setPath(path, for: kind, refresh: true)
    }

    func refresh() {
        runInspection(showProgress: true)
    }

    func recoveryPlan() -> RepositoryRecoveryPlan? {
        RepositorySetupService(environment: environment).recoveryPlan(for: .syncData, locations: locations)
    }

    func cloneMissingRepositories() {
        runClone { service, locations in
            service.cloneMissing(locations)
        }
    }

    func backUpAndClone(_ plan: RepositoryRecoveryPlan) {
        runClone { service, locations in
            service.backUpAndClone(plan, locations: locations)
        }
    }

    func checkGitHubAccess() {
        guard hasAllRepositories, !isCheckingGitHubAccess else { return }
        isCheckingGitHubAccess = true
        let locations = locations
        let environment = environment
        gitHubReports = RepositorySetupService(environment: environment).checkingGitHubReports(for: inspections)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reports = RepositorySetupService(environment: environment).checkGitHubAccess(for: locations)
            DispatchQueue.main.async {
                self?.inspections = reports.map(\.repository)
                self?.gitHubReports = reports
                self?.isCheckingGitHubAccess = false
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func setPath(_ path: String, for _: LocalRepositoryKind, refresh: Bool) {
        locations = RepositoryLocations(dataRepository: path.trimmingCharacters(in: .whitespacesAndNewlines))
        messages = []
        gitHubReports = []
        if refresh {
            runInspection(showProgress: false)
        }
    }

    private func runClone(
        _ operation: @escaping @Sendable (RepositorySetupService, RepositoryLocations) -> RepositoryCloneResult
    ) {
        guard !isWorking else { return }
        isWorking = true
        let locations = locations
        let environment = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let service = RepositorySetupService(environment: environment)
            let result = operation(service, locations)
            DispatchQueue.main.async {
                self?.inspections = result.inspections
                self?.gitHubReports = service.initialGitHubReports(for: result.inspections)
                self?.messages = result.messages
                self?.isWorking = false
            }
        }
    }

    private func runInspection(showProgress: Bool) {
        guard !isWorking else { return }
        isWorking = showProgress
        let locations = locations
        let environment = environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let service = RepositorySetupService(environment: environment)
            let inspections = service.inspect(locations)
            let reports = service.initialGitHubReports(for: inspections)
            DispatchQueue.main.async {
                self?.inspections = inspections
                self?.gitHubReports = reports
                self?.isWorking = false
            }
        }
    }
}
