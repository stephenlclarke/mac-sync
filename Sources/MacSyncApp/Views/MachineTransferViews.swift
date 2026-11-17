import AppKit
import MacSyncCore
import SwiftUI

struct SendMachineFilesView: View {
    @ObservedObject var store: SyncStore
    let machine: String
    let files: [URL]
    let replacementPath: String?
    @State var destinationFolder: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(replacementPath == nil ? "Send files to \(machine)" : "Replace a file on \(machine)").font(.title2.bold())
            Text("Files are queued in this Mac's storage area. The receiving Mac applies selected, non-conflicting files on its next sync. Conflicts and unselected paths wait in its Inbox. Your original files stay unchanged.")
            if let replacementPath {
                Text("Replace: ~/\(replacementPath)").font(.headline).textSelection(.enabled)
            } else {
                TextField("Destination folder under the other Mac's home folder", text: $destinationFolder)
            }
            ForEach(files, id: \.path) { Text($0.lastPathComponent).font(.caption).lineLimit(1) }
            Text("Regular sync storage is not end-to-end encrypted. Do not send private keys or credentials this way. Only regular files are accepted; send folders as an archive or select their files.")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(replacementPath == nil ? "Send Files" : "Queue Replacement", role: replacementPath == nil ? nil : .destructive) {
                    let folder = destinationFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let paths = files.map { replacementPath ?? (folder.isEmpty ? $0.lastPathComponent : folder + "/" + $0.lastPathComponent) }
                    store.sendFiles(files, to: machine, paths: paths)
                    dismiss()
                }.disabled(files.isEmpty || files.count > 100 || store.isRunning || !validDestination)
            }
        }.padding(20).frame(width: 620)
    }

    private var validDestination: Bool {
        if let replacementPath {
            return MacSyncPaths.safeSyncPath(replacementPath) && !replacementPath.hasPrefix("/")
        }
        return destinationFolder.isEmpty || (!destinationFolder.hasPrefix("/") && MacSyncPaths.safeSyncPath(destinationFolder))
    }
}

struct MachineInboxView: View {
    @ObservedObject var store: SyncStore
    let machine: String
    let isCurrent: Bool
    @State private var items: [(MachineFileDelivery, MachineDeliveryReceipt?)] = []
    @State private var offset = 0
    @State private var errorMessage: String?
    @State private var selected: MachineFileDelivery?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Inbox — \(machine)").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Each Mac owns its snapshot. Files sent by other Macs wait here until applied. Receipts show the last published decision, not whether the other Mac is online.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange)
            }
            if items.isEmpty {
                Text("No files have been sent to this Mac.")
            }
            List(items, id: \.0.id) { record, receipt in
                VStack(alignment: .leading, spacing: 6) {
                    Text("~/\(record.path)").font(.headline).textSelection(.enabled)
                    Text("From \(record.sender) · \(record.createdAt.formatted()) · \(receipt?.state ?? "pending")").font(.caption)
                    if let receipt {
                        Text(receipt.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if isCurrent, receipt?.state != "applied", receipt?.state != "keptLocal" {
                        HStack {
                            Button("Apply to This Mac…", role: .destructive) { selected = record }
                            Button("Keep This Mac") { store.resolveDelivery(record, apply: false) }
                        }.disabled(store.isRunning)
                    }
                }.padding(.vertical, 5)
            }
            HStack {
                Button("Previous") { offset = max(0, offset - 100) }.disabled(offset == 0)
                Text("Page \(offset / 100 + 1)").font(.caption)
                Button("Next") { offset += 100 }.disabled(items.count < 100)
                Spacer()
                Button("Sync Now") { store.syncSelection() }.disabled(store.isRunning)
            }
            Text("Apply explicitly replaces the named local file and saves an Undo copy first. It does not add the path to Sync Selection. Unselected files are copied once only; add them to Sync Selection if you want future changes to sync.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 780, minHeight: 520)
            .task(id: "\(offset)-\(store.isRunning)") {
                guard !store.isRunning else { return }
                do { items = try await store.loadDeliveries(target: machine, offset: offset); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            }
            .confirmationDialog("Replace ~/\(selected?.path ?? "this file")?", isPresented: Binding(get: { selected != nil }, set: {
                if !$0 {
                    selected = nil
                }
            })) {
                Button("Apply and Replace Local File", role: .destructive) {
                    if let selected {
                        store.resolveDelivery(selected, apply: true)
                    }; selected = nil
                }
            } message: { Text("This replaces local edits with the sent file. An Undo copy is saved first. Sync afterwards to publish the result.") }
    }
}
