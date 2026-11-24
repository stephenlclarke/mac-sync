import SwiftUI

/// Native confirmations are outside the model/executor capability boundary.
@MainActor
struct LocalRepairAssistantView: View {
    @ObservedObject var store: SyncStore
    @StateObject private var repairs = LocalRepairController()
    @StateObject private var diagnosis = LocalDiagnosisController()
    @Environment(\.dismiss) private var dismiss
    @State private var approval: Approval?
    @State private var review: Review?
    @State private var actionError: String?
    @State private var approvingSync = false
    @State private var syncTask: Task<Void, Never>?

    private enum Review: String, Identifiable {
        case files, settings
        var id: String { rawValue }
    }
    private enum ApprovalKind { case sync, files, settings }
    private struct Approval {
        let kind: ApprovalKind
        let scope: String
        let detail: String
    }

    private var busy: Bool {
        repairs.isRunning || diagnosis.isRunning || approvingSync
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Local Repair Assistant", systemImage: "sparkles").font(.title2.bold())
            Text(
                """
                Safe operational repairs run automatically when you open this assistant. \
                AI stays on this Mac, with no cloud fallback or model tools.
                """
            )
            Text(
                """
                Allowed: refresh status in app memory, reconnect a read-only status observer, and clear a busy \
                indicator after its process has finished. No files, schedules, credentials or security settings \
                are changed automatically.
                """
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Operational checks") {
                        VStack(alignment: .leading, spacing: 9) {
                            if repairs.isRunning {
                                ProgressView("Checking local app state…")
                            }
                            ForEach(Array(repairs.receipts.enumerated()), id: \.offset) { _, receipt in Text(receipt) }
                            if let message = repairs.message {
                                Text(message)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }
                    if diagnosis.isRunning {
                        ProgressView("Preparing a read-only diagnosis…")
                    }
                    if let message = diagnosis.message {
                        Text(message)
                    }
                    if let facts = diagnosis.evidence {
                        GroupBox(findingsTitle) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(diagnosis.orderedFindings ?? facts.findings) { finding in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(finding.title).font(.headline)
                                        Text(finding.detail)
                                    }
                                }
                                Text(facts.advice.summary).font(.headline)
                                ForEach(facts.advice.steps) { step in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(step.title).font(.headline)
                                        Text(step.detail)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                        }
                    }
                    GroupBox("Your approval is required") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                """
                                The AI cannot approve a sync, choose a file version, delete a file, resolve a conflict \
                                or change access. These controls are separate from automatic repairs.
                                """
                            )
                            Button("Review Files and Conflicts…") { request(.files) }
                            Button("Review Credentials and Security in Settings…") { request(.settings) }
                            Button("Request a Sync…") { request(.sync) }
                                .disabled(store.isRunning || !store.isSetupComplete)
                            Text(
                                """
                                Opening a review does not approve any file or setting change. Each decision remains \
                                yours. A sync can upload and replace non-conflicting selected files.
                                """
                            )
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                    }.disabled(busy)
                    if let actionError {
                        Text(actionError).foregroundStyle(.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            HStack {
                Text(
                    """
                    On demand only. No background AI. Receipts stay in memory. \
                    macOS 26 and a prepared Apple Intelligence model are needed for AI.
                    """
                )
                .font(.callout)
                Spacer()
                if busy {
                    Button("Stop") { stop() }
                }
                Button("Check Again") { start() }.disabled(busy)
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 700, idealWidth: 800, minHeight: 580, idealHeight: 760)
        .onAppear { start() }
        .onDisappear { stop() }
        .confirmationDialog(
            "Approve this action?",
            isPresented: Binding(get: { approval != nil }, set: {
                if !$0 {
                    approval = nil
                }
            })
        ) {
            Button(approval?.kind == .sync ? "Approve Sync" : "Open Manual Review") { confirm() }
            Button("Cancel", role: .cancel) { approval = nil }
        } message: { Text(approval?.detail ?? "") }
        .sheet(item: $review) { item in
            if item == .files {
                IncomingChangesView(store: store, allowsSync: false)
            } else {
                VStack(alignment: .trailing) {
                    Button("Done") { review = nil }.keyboardShortcut(.cancelAction).padding()
                    SettingsView(store: store)
                }.frame(minWidth: 760, minHeight: 580)
            }
        }
    }

    private func start() {
        actionError = nil
        repairs.start(runtime: store) { diagnosis.start(overview: store.overview) }
    }

    private var findingsTitle: String {
        diagnosis.usedModel ? "On-device diagnosis · verified findings" : "Verified local records"
    }

    private func stop() {
        repairs.cancel()
        diagnosis.cancel()
        syncTask?.cancel()
    }

    private func request(_ kind: ApprovalKind) {
        let detail = switch kind {
        case .sync:
            """
            Sync selected files for \(store.overview.configuration.machineName)? \
            Workspace: \(store.overview.configuration.dataRepository). \
            Destination: \(syncDestination). \
            This saves your selection, uploads files and can replace non-conflicting selected files on this Mac. \
            Conflicts and incoming deletions still require review. \
            Selected paths: \(store.selectedPaths.joined(separator: ", ")).
            """
        case .files:
            """
            Open the manual file review? No version is selected by the AI. Overwrites, deletions and conflict \
            decisions require your separate per-file confirmation. This review cannot start a sync; \
            use Request a Sync separately.
            """
        case .settings:
            """
            Open Settings for manual review? The AI will not test or change credentials, remote access, \
            permissions, security settings or the sync schedule. Any changes must be made by you.
            """
        }
        approval = Approval(kind: kind, scope: store.localRepairScope, detail: detail)
    }

    private func confirm() {
        guard let approved = approval else { return }
        approval = nil
        guard approved.scope == store.localRepairScope else {
            actionError = LocalRepairError.changedScope.localizedDescription
            return
        }
        switch approved.kind {
        case .files: review = .files
        case .settings: review = .settings
        case .sync:
            approvingSync = true
            syncTask = Task {
                defer { approvingSync = false; syncTask = nil }
                do { try await store.approveAssistantSync(scope: approved.scope) } catch {
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private var syncDestination: String {
        store.overview.configuration.cloudFolder ?? store.repositoryInspections.first?.remoteURL ?? "local only"
    }
}
