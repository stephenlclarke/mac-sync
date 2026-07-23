import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SyncStore
    @State private var selection: NavigationItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "rectangle.3.group.fill")
                        .tag(NavigationItem.dashboard)
                    Label("This Mac", systemImage: "laptopcomputer")
                        .tag(NavigationItem.thisMac)
                    Label("Sync Selection", systemImage: "checklist")
                        .tag(NavigationItem.selection)
                    Label("Sync History", systemImage: "clock.arrow.circlepath")
                        .tag(NavigationItem.history)
                    HStack {
                        Label("Manual Triage", systemImage: "exclamationmark.bubble")
                        Spacer()
                        if store.openIssueCount > 0 {
                            Text("\(store.openIssueCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red, in: Capsule())
                        }
                    }
                    .tag(NavigationItem.triage)
                }

                Section("Other Macs") {
                    ForEach(store.overview.peerMachines) { machine in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.name)
                            Text("\(machine.fileCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(NavigationItem.machine(machine.name))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("xyzzy.tools")
        } detail: {
            detail
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.reload()
        }
        .onAppear {
            applyRequestedNavigation()
        }
        .onChange(of: store.requestedNavigation) { _ in
            applyRequestedNavigation()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.tint)
                    Text("Mac Sync")
                        .fontWeight(.semibold)
                    Text("xyzzy.tools")
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if store.isRunning {
                    Button("Stop") {
                        store.stopSync()
                    }
                    .tint(.red)
                } else {
                    Menu {
                        Button("Sync This Mac") {
                            store.syncSelection()
                        }
                        Button("Preview Sync") {
                            store.previewSync()
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Button {
                    store.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Mac Sync", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: {
                if !$0 {
                    store.dismissError()
                }
            }
        )) {
            Button("OK") {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $store.isSetupSheetPresented) {
            SetupWizardView(store: store)
                .frame(minWidth: 760, idealWidth: 900, maxWidth: 980)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:
            DashboardView(store: store) {
                selection = .triage
            }
        case .thisMac:
            if let machine = store.overview.currentMachine {
                MachineDetailView(machine: machine, isCurrentMachine: true, store: store)
            } else {
                EmptyMachineView(configuration: store.overview.configuration)
            }
        case .selection:
            SelectionEditorView(store: store)
        case .history:
            SyncHistoryView(store: store)
        case .triage:
            SyncIssuesView(store: store)
        case let .machine(name):
            if let machine = store.overview.peerMachines.first(where: { $0.name == name }) {
                MachineDetailView(machine: machine, isCurrentMachine: false, store: store)
            } else {
                UnavailableSnapshotView(
                    title: "Machine snapshot unavailable",
                    message: "Refresh the snapshot list or choose another Mac."
                )
            }
        }
    }

    private func applyRequestedNavigation() {
        guard let requested = store.requestedNavigation else { return }
        selection = requested
        store.consumeNavigationRequest()
    }
}

private struct EmptyMachineView: View {
    let configuration: SyncConfiguration

    var body: some View {
        UnavailableSnapshotView(
            title: "No local snapshot yet",
            message: "Save your selection and run a sync to create \(configuration.machineName)'s first snapshot."
        )
    }
}

private struct UnavailableSnapshotView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
