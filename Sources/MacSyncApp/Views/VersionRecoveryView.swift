import AppKit
import MacSyncCore
import SwiftUI

struct VersionRecoveryView: View {
    @ObservedObject var store: SyncStore
    let machine: String
    let paths: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [BackupRevision] = []
    @State private var selectedID: String?
    @State private var undoRecords: [UndoRestoreRecord] = []
    @State private var selectedUndo: String?
    @State private var errorMessage: String?
    @State private var loading = false
    @State private var confirmRestore = false
    @State private var confirmUndo = false
    @State private var comparison: FileVersionComparison?
    @State private var offset = 0
    @State private var undoOffset = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Versions & Recovery — \(machine)").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Review an earlier version, copy it to a separate folder, or recover it to this Mac. This does not switch your working Git branch.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.orange)
            }
            if loading {
                ProgressView()
            }
            List(versions, selection: $selectedID) { version in
                HStack {
                    Text(version.createdAt.formatted(date: .abbreviated, time: .standard))
                    Spacer()
                    Text(String(version.id.prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                }.tag(version.id)
            }.frame(minHeight: 140)
            HStack {
                Button("Newer Versions") { offset = max(0, offset - 50) }.disabled(offset == 0 || loading)
                Text("Page \(offset / 50 + 1)").font(.caption)
                Button("Older Versions") { offset += 50 }.disabled(versions.count < 50 || loading)
            }
            Text(paths.isEmpty ? "Actions use the selected version's saved path selection." : "Selected paths: \(paths.joined(separator: ", "))")
                .font(.caption).lineLimit(3)
            HStack {
                Button("Preview changes") {
                    if let selectedID {
                        store.restoreVersion(machine: machine, revision: selectedID, paths: paths, preview: true)
                    }
                }
                Button("Compare file…") { compareFile() }.disabled(paths.count != 1)
                Button("Export to Folder…") { exportVersion() }
                Button("Restore over current files…", role: .destructive) { confirmRestore = true }
            }.disabled(selectedID == nil || store.isRunning || loading)
            HStack {
                Button("Test Recovery") {
                    if let selectedID {
                        store.verifyRecovery(machine: machine, revision: selectedID)
                    }
                }.disabled(selectedID == nil || store.isRunning)
                Text("Copies and hashes files in a temporary folder. It does not replace local files, confirm cloud upload or test decryption keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !undoRecords.isEmpty || undoOffset > 0 {
                Divider()
                HStack {
                    Picker("Pre-restore copies", selection: $selectedUndo) {
                        Text("Choose a restore").tag(String?.none)
                        ForEach(undoRecords) { record in
                            Text("\(record.createdAt.formatted()) · \(record.entries.count) paths").tag(Optional(record.id))
                        }
                    }
                    Button("Preview Undo") {
                        if let selectedUndo {
                            store.undoRestore(id: selectedUndo, preview: true)
                        }
                    }
                    .disabled(selectedUndo == nil)
                    Button("Undo Restore…") { confirmUndo = true }.disabled(selectedUndo == nil)
                }.disabled(store.isRunning)
                HStack {
                    Button("Newer Undo Copies") { undoOffset = max(0, undoOffset - 50) }.disabled(undoOffset == 0 || loading)
                    Button("Older Undo Copies") { undoOffset += 50 }.disabled(undoRecords.count < 50 || loading)
                }
                Text("Undo replaces the current copies, including later edits. Review the preview first. Safety copies are kept locally until you remove them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.commandOutput.isEmpty {
                ScrollView {
                    Text(store.commandOutput).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 130)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 620)
        .task(id: "\(offset)-\(undoOffset)-\(store.isRunning)") {
            if !store.isRunning {
                await load()
            }
        }
        .confirmationDialog("Replace current files with this version?", isPresented: $confirmRestore) {
            Button("Restore Version", role: .destructive) {
                if let selectedID {
                    store.restoreVersion(machine: machine, revision: selectedID, paths: paths, force: true)
                }
            }
        } message: { Text("Current copies will be saved locally for Undo before anything is replaced. Keep an independent backup. Preview or export the version first.") }
        .confirmationDialog("Recover the pre-restore copies?", isPresented: $confirmUndo) {
            Button("Undo Restore", role: .destructive) {
                if let selectedUndo {
                    store.undoRestore(id: selectedUndo, preview: false)
                }
            }
        } message: { Text("This replaces current files and can remove files created by the restore. Later edits can be lost. Review Preview Undo before continuing.") }
        .sheet(item: $comparison) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text(item.path).font(.headline)
                HStack(alignment: .top) {
                    comparisonColumn("Selected version", item.archived)
                    comparisonColumn("Current local file", item.local)
                }
                Button("Done") { comparison = nil }.keyboardShortcut(.defaultAction)
            }.padding(20).frame(minWidth: 900, minHeight: 500)
        }
    }

    private func comparisonColumn(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ScrollView([.vertical, .horizontal]) { Text(text).font(.caption.monospaced()).textSelection(.enabled) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        loading = true
        let service = store.recoveryService
        let machine = machine
        let offset = offset
        let undoOffset = undoOffset
        let result = await Task.detached(priority: .utility) { Result { try (service.revisions(machine: machine, offset: offset), service.undoRecords(offset: undoOffset)) } }.value
        guard !Task.isCancelled else { return }
        loading = false
        switch result {
        case let .success((items, undos)):
            versions = items; undoRecords = undos
            if !undos.contains(where: { $0.id == selectedUndo }) {
                selectedUndo = nil
            }
            if !items.contains(where: { $0.id == selectedID }) {
                selectedID = items.first?.id
            }
        case let .failure(error): errorMessage = error.localizedDescription
        }
    }

    private func exportVersion() {
        guard let selectedID else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Choose an empty folder. Current local files will not be replaced."
        if panel.runModal() == .OK, let url = panel.url {
            store.restoreVersion(machine: machine, revision: selectedID, paths: paths, output: url.path)
        }
    }

    private func compareFile() {
        guard let selectedID, let path = paths.first else { return }
        let service = store.recoveryService
        let machine = machine
        let home = store.overview.configuration.homeDirectory
        loading = true
        Task {
            let result = await Task.detached(priority: .utility) { Result {
                let workspace = try service.workspace(machine: machine, revision: selectedID)
                defer { withExtendedLifetime(workspace) {} }
                let archived = workspace.root.appendingPathComponent("machines/\(machine)/\(path.hasPrefix("/") ? "absolute" : "home")/\(path.drop(while: { $0 == "/" }))")
                guard BackupDestinationSettings.isInside(archived.path, directory: workspace.root.path), MacSyncPaths.safeSyncPath(path) else {
                    throw BackupStorageError.invalidSnapshot
                }
                let local = URL(fileURLWithPath: path.hasPrefix("/") ? path : "\(home)/\(path)")
                return try FileVersionComparison(path: path, archived: FileVersionComparison.read(archived), local: FileVersionComparison.read(local))
            } }.value
            loading = false
            switch result {
            case let .success(item): comparison = item
            case let .failure(error): errorMessage = error.localizedDescription
            }
        }
    }
}

private struct FileVersionComparison: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let archived: String
    let local: String

    static func read(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "File not present" }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return "Choose a regular file, not a folder or symbolic link." }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 96 * 1024) ?? Data()
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return "Binary or non-UTF-8 content is not displayed." }
        return text + ((values.fileSize ?? 0) > data.count ? "\n[Preview truncated at 96 KiB]" : "")
    }
}
