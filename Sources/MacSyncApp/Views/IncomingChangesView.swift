import MacSyncCore
import SwiftUI

struct IncomingChangesView: View {
    @ObservedObject var store: SyncStore
    var allowsSync = true
    @Environment(\.dismiss) private var dismiss
    @State private var changes: [IncomingSyncChange] = []
    @State private var offset = 0
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var confirmation: IncomingSyncChange?
    @State private var choice = "--keep-local"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Incoming Changes").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Non-conflicting files can sync automatically. Conflicts and deletions wait here. Only paths selected on this Mac are eligible. Older Macs without version tracking require a manual copy from their snapshot.")
                .font(.caption).foregroundStyle(.secondary)
            if loading {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange)
            }
            if changes.isEmpty, !loading {
                Text("No incoming changes need review.").padding(.vertical)
            }
            List(changes) { change in
                VStack(alignment: .leading, spacing: 6) {
                    Text(change.path).font(.headline).textSelection(.enabled)
                    Text("From \(change.machine) · \(change.reason)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Keep This Mac") { confirm(change, "--keep-local") }
                        if !change.deletion {
                            Button("Keep Both") { confirm(change, "--keep-both") }
                        }
                        Button(change.deletion ? "Delete Local File…" : "Use Incoming Version…", role: .destructive) { confirm(change, "--use-incoming") }
                    }.disabled(store.isRunning || loading)
                }.padding(.vertical, 5)
            }
            HStack {
                Button("Previous") { offset = max(0, offset - 100) }.disabled(offset == 0 || loading)
                Text("Page \(offset / 100 + 1)").font(.caption)
                Button("Next") { offset += 100 }.disabled(changes.count < 100 || loading)
                Spacer()
                if allowsSync {
                    Button("Check for Changes") { store.syncSelection() }.disabled(store.isRunning)
                }
            }
            Text("Applying an incoming version saves a local Undo copy first. Keep Both leaves your file in place and creates a named copy beside it. Sync again to send your decision to the other Macs.")
                .font(.caption).foregroundStyle(.secondary)
            if !store.commandOutput.isEmpty {
                ScrollView { Text(store.commandOutput).font(.caption.monospaced()).textSelection(.enabled) }.frame(height: 100)
            }
        }.padding(20).frame(minWidth: 820, minHeight: 560)
            .task(id: "\(offset)-\(store.isRunning)") {
                guard !store.isRunning else { return }
                loading = true
                do { changes = try await store.loadIncomingChanges(offset: offset); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
                loading = false
            }
            .confirmationDialog("Resolve \(confirmation?.path ?? "this change")?", isPresented: Binding(get: { confirmation != nil }, set: {
                if !$0 {
                    confirmation = nil
                }
            })) {
                Button(choice == "--use-incoming" ? "Apply Incoming Change" : choice == "--keep-both" ? "Keep Both Copies" : "Keep This Mac", role: choice == "--use-incoming" ? .destructive : nil) {
                    if let confirmation {
                        store.resolveIncoming(confirmation, choice: choice)
                    }
                    confirmation = nil
                }
            } message: { Text(confirmation?.deletion == true && choice == "--use-incoming" ? "This explicitly deletes the local file. A local Undo copy is saved first." : "Use Incoming Version replaces your current file. Keep This Mac records your local version as the chosen result. Your decision is shared on the next sync.") }
    }

    private func confirm(_ change: IncomingSyncChange, _ choice: String) {
        self.choice = choice; confirmation = change
    }
}
