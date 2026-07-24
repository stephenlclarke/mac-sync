import AppKit
import SwiftUI

struct MachineDetailView: View {
    let machine: MachineSnapshot
    let isCurrentMachine: Bool
    @ObservedObject var store: SyncStore
    @State private var searchText = ""
    @State private var selectedConfiguredPaths = Set<String>()
    @State private var expandedConfiguredPaths = Set<String>()
    @State private var selectedSnapshotPaths = Set<String>()
    @State private var expandedSnapshotPaths = Set<String>()
    @State private var snapshotScrollTarget: String?
    @State private var showRestoreSheet = false
    @State private var restorePaths: [String]?
    @State private var showEncryptedSecretsSheet = false
    @State private var previewRequest: SnapshotFilePreviewRequest?
    @State private var fileActionError: String?
    @State private var archiveRemovalRequest: ConfiguredPath?

    private var visibleSnapshotNodes: [SnapshotContentNode] {
        guard !searchText.isEmpty else { return flattenedSnapshotNodes }
        return flattenedSnapshotNodes.filter {
            $0.file.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var snapshotTree: [SnapshotContentNode] {
        SnapshotContentsTree.nodes(for: machine.files)
    }

    private var flattenedSnapshotNodes: [SnapshotContentNode] {
        flattenedNodes(in: snapshotTree)
    }

    private var configuredPathTree: [PathOutlineNode] {
        PathOutlineTree.nodes(for: machine.configuredPaths.map {
            PathOutlineItem(path: $0.path, kind: snapshotKind(for: $0))
        })
    }

    private var configuredPathsByPath: [String: ConfiguredPath] {
        Dictionary(uniqueKeysWithValues: machine.configuredPaths.map { ($0.path, $0) })
    }

    private var snapshotFileInspector: SnapshotFileInspector {
        SnapshotFileInspector(dataRepository: store.overview.configuration.dataRepository)
    }

    private var snapshotFilesByPath: [String: SnapshotFile] {
        Dictionary(uniqueKeysWithValues: flattenedSnapshotNodes.map { ($0.id, $0.file) })
    }

    private var selectedSnapshotFiles: [SnapshotFile] {
        selectedSnapshotPaths.compactMap { snapshotFilesByPath[$0] }.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private var selectedSnapshotFile: SnapshotFile? {
        selectedSnapshotFiles.count == 1 ? selectedSnapshotFiles[0] : nil
    }

    private var selectedSnapshotRestorePaths: [String] {
        SnapshotContentsTree.restorePaths(for: selectedSnapshotFiles.map(\.displayPath))
    }

    private var selectedConfiguredRoot: ConfiguredPath? {
        guard selectedConfiguredPaths.count == 1,
              let path = selectedConfiguredPaths.first
        else {
            return nil
        }
        return configuredPathsByPath[path]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                configuredPaths
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                files
                    .frame(minWidth: 440)
            }
        }
        .sheet(isPresented: $showRestoreSheet, onDismiss: {
            restorePaths = nil
        }) {
            RestoreSheet(
                machine: machine,
                store: store,
                isPresented: $showRestoreSheet,
                initialPaths: restorePaths
            )
        }
        .sheet(isPresented: $showEncryptedSecretsSheet) {
            EncryptedSecretsSheet(machine: machine, store: store, isPresented: $showEncryptedSecretsSheet)
        }
        .sheet(item: $previewRequest) { request in
            SnapshotFilePreviewSheet(
                machineName: machine.name,
                file: request.file,
                displaysTextPreview: request.mode == .preview,
                inspector: snapshotFileInspector,
                revealInFinder: { revealInFinder(request.file) }
            )
        }
        .alert("Unable to show file", isPresented: Binding(
            get: { fileActionError != nil },
            set: { isPresented in
                if !isPresented {
                    fileActionError = nil
                }
            }
        )) {
            Button("OK") {
                fileActionError = nil
            }
        } message: {
            Text(fileActionError ?? "The archived snapshot file could not be opened.")
        }
        .alert("Remove archived root?", isPresented: Binding(
            get: { archiveRemovalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    archiveRemovalRequest = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                archiveRemovalRequest = nil
            }
            Button("Remove Root and Archive", role: .destructive) {
                if let root = archiveRemovalRequest {
                    store.removeArchivedConfiguredRoot(root.path)
                }
                archiveRemovalRequest = nil
            }
        } message: {
            if let root = archiveRemovalRequest {
                Text("This removes “\(root.path)” from Sync Selection and deletes its archived copy. The original file or folder on this Mac is not changed. The deletion is included in the next sync.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isCurrentMachine ? "laptopcomputer" : "laptopcomputer.and.iphone")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(machine.computerName ?? machine.name)
                    .font(.title2.bold())
                Text(machine.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(metadataDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrentMachine {
                Button("Sync This Mac") {
                    store.syncSelection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRunning)
            } else {
                Menu {
                    Button("Preview Copy") {
                        store.previewRestore(from: machine.name)
                    }
                    Button("Copy to This Mac...") {
                        restorePaths = nil
                        showRestoreSheet = true
                    }
                } label: {
                    Label("Copy to This Mac", systemImage: "arrow.down.to.line.compact")
                }
                .disabled(store.isRunning)
            }
            if machine.hasEncryptedSecrets {
                Button("View Encrypted Secrets…") {
                    showEncryptedSecretsSheet = true
                }
                .disabled(store.isRunning)
            }
        }
        .padding(20)
    }

    private var configuredPaths: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Configured roots")
                        .font(.headline)
                    Text("Click a root to reveal it in Snapshot contents, or expand folders to inspect selected paths.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                configuredBrowserActions
                if let root = selectedRemovableConfiguredRoot {
                    Button("Remove Root…", role: .destructive) {
                        archiveRemovalRequest = root
                    }
                    .controlSize(.small)
                    .disabled(!canRemoveArchivedRoot(root))
                    .help(archiveRemovalHelp(for: root))
                }
            }
            .padding()

            List(selection: $selectedConfiguredPaths) {
                PathOutlineRows(
                    nodes: configuredPathTree,
                    expandedPaths: $expandedConfiguredPaths,
                    row: configuredPathRow
                )
            }
            .listStyle(.inset)
            .onChange(of: selectedConfiguredPaths) { paths in
                guard paths.count == 1, let path = paths.first else { return }
                revealSnapshotItem(forConfiguredPath: path)
            }
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Snapshot contents")
                        .font(.headline)
                    Text(snapshotBrowserDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                snapshotBrowserActions
                if machine.hasEncryptedSecrets {
                    Button {
                        showEncryptedSecretsSheet = true
                    } label: {
                        Label("Encrypted secrets", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding()

            ScrollViewReader { proxy in
                List(selection: $selectedSnapshotPaths) {
                    if searchText.isEmpty {
                        SnapshotTreeRows(
                            nodes: snapshotTree,
                            expandedPaths: $expandedSnapshotPaths,
                            row: snapshotContentRow
                        )
                    } else {
                        ForEach(visibleSnapshotNodes) { node in
                            snapshotContentRow(node)
                                .tag(node.id)
                                .id(node.id)
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Filter snapshot files")
                .onChange(of: snapshotScrollTarget) { path in
                    guard let path else { return }
                    withAnimation {
                        proxy.scrollTo(path, anchor: .center)
                    }
                }
            }
        }
    }

    private var configuredBrowserActions: some View {
        Menu {
            Button("Expand All") {
                expandedConfiguredPaths = Set(PathOutlineTree.paths(in: configuredPathTree))
            }
            Button("Collapse All") {
                expandedConfiguredPaths.removeAll()
            }
            if let root = selectedConfiguredRoot {
                Divider()
                Button("Copy Path") {
                    copyPath(root.path)
                }
                if let file = snapshotFile(forConfiguredPath: root.path) {
                    Button("Show Archived Copy in Finder") {
                        revealInFinder(file)
                    }
                }
            }
        } label: {
            Label("Configured roots actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Expand, collapse, copy, or reveal configured roots")
    }

    private var snapshotBrowserDescription: String {
        let archiveSummary = "\(machine.fileCount) files, \(SyncFormatting.bytes(machine.totalByteCount)). Secret archive entries are available separately with a trusted Keychain identity."
        guard !isCurrentMachine else { return archiveSummary }
        return "\(archiveSummary) Select files or folders, then choose Copy to This Mac; the source archive is unchanged."
    }

    private var snapshotBrowserActions: some View {
        Menu {
            Section("Selected items") {
                Button("Preview") {
                    guard let file = selectedSnapshotFile else { return }
                    presentPreview(for: file)
                }
                .disabled(selectedSnapshotFile?.kind != .file)

                Button("Show File Info") {
                    guard let file = selectedSnapshotFile else { return }
                    presentFileInformation(for: file)
                }
                .disabled(selectedSnapshotFile?.kind != .file)

                Button("Copy Path") {
                    copyPaths(selectedSnapshotFiles.map(\.displayPath))
                }
                .disabled(selectedSnapshotFiles.isEmpty)

                Button("Show in Finder") {
                    revealInFinder(selectedSnapshotFiles)
                }
                .disabled(selectedSnapshotFiles.isEmpty)

                if !isCurrentMachine {
                    Divider()
                    Button("Preview Copy to This Mac") {
                        store.previewRestore(from: machine.name, paths: selectedSnapshotRestorePaths)
                    }
                    .disabled(selectedSnapshotRestorePaths.isEmpty || store.isRunning)

                    Button("Copy to This Mac…") {
                        restorePaths = selectedSnapshotRestorePaths
                        showRestoreSheet = true
                    }
                    .disabled(selectedSnapshotRestorePaths.isEmpty || store.isRunning)
                }
            }

            Divider()
            Button("Expand All Folders") {
                expandedSnapshotPaths = Set(
                    flattenedSnapshotNodes
                        .filter { $0.file.kind == .folder }
                        .map(\.id)
                )
            }
            Button("Collapse All Folders") {
                expandedSnapshotPaths.removeAll()
            }
        } label: {
            Label("Snapshot actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Preview, copy, reveal, or organise the snapshot browser")
    }

    private func snapshotContentRow(_ node: SnapshotContentNode) -> some View {
        snapshotContentRow(node.file, title: node.title, folderContents: node.contents)
    }

    @ViewBuilder
    private func snapshotContentRow(
        _ file: SnapshotFile,
        title: String? = nil,
        folderContents: SnapshotFolderContents? = nil
    ) -> some View {
        if file.kind == .file {
            snapshotContentRowLayout(file, title: title, folderContents: folderContents)
                .contentShape(Rectangle())
                .onTapGesture {
                    presentPreview(for: file)
                }
                .contextMenu {
                    Button("Preview") {
                        presentPreview(for: file)
                    }
                    Button("Show File Info") {
                        presentFileInformation(for: file)
                    }
                    Divider()
                    Button("Copy Path") {
                        copyPath(file.displayPath)
                    }
                    Button("Show in Finder") {
                        revealInFinder(file)
                    }
                    snapshotRestoreMenu(for: file)
                    archiveRemovalMenu(for: file)
                }
                .help("Click to preview; Control-click for more actions")
        } else {
            snapshotContentRowLayout(file, title: title, folderContents: folderContents)
                .contextMenu {
                    Button("Copy Path") {
                        copyPath(file.displayPath)
                    }
                    Button("Show in Finder") {
                        revealInFinder(file)
                    }
                    snapshotRestoreMenu(for: file)
                    archiveRemovalMenu(for: file)
                }
        }
    }

    private func snapshotContentRowLayout(
        _ file: SnapshotFile,
        title: String? = nil,
        folderContents: SnapshotFolderContents? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title ?? file.displayPath)
                .textSelection(.enabled)
            Spacer()
            if file.kind == .file {
                Text(SyncFormatting.bytes(file.byteCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            } else if let folderContents {
                Text(folderContentsDescription(folderContents))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 130, alignment: .trailing)
            }
            Text(SyncFormatting.date(file.modifiedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func presentPreview(for file: SnapshotFile) {
        previewRequest = SnapshotFilePreviewRequest(file: file, mode: .preview)
    }

    private func presentFileInformation(for file: SnapshotFile) {
        previewRequest = SnapshotFilePreviewRequest(file: file, mode: .information)
    }

    private func revealInFinder(_ file: SnapshotFile) {
        revealInFinder([file])
    }

    private func revealInFinder(_ files: [SnapshotFile]) {
        do {
            let urls = try files.map {
                try snapshotFileInspector.fileURL(machineName: machine.name, file: $0)
            }
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } catch {
            fileActionError = error.localizedDescription
        }
    }

    private func copyPath(_ path: String) {
        copyPaths([path])
    }

    private func copyPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    private func snapshotFile(forConfiguredPath path: String) -> SnapshotFile? {
        snapshotFilesByPath[snapshotDisplayPath(forConfiguredPath: path)]
    }

    @ViewBuilder
    private func snapshotRestoreMenu(for file: SnapshotFile) -> some View {
        if !isCurrentMachine {
            Divider()
            Button("Preview Copy to This Mac") {
                store.previewRestore(
                    from: machine.name,
                    paths: SnapshotContentsTree.restorePaths(for: [file.displayPath])
                )
            }
            .disabled(store.isRunning)
            Button("Copy to This Mac…") {
                restorePaths = SnapshotContentsTree.restorePaths(for: [file.displayPath])
                showRestoreSheet = true
            }
            .disabled(store.isRunning)
        }
    }

    private func revealSnapshotItem(forConfiguredPath path: String) {
        let snapshotPath = snapshotDisplayPath(forConfiguredPath: path)
        guard flattenedSnapshotNodes.contains(where: { $0.id == snapshotPath }) else {
            return
        }

        searchText = ""
        expandedSnapshotPaths.formUnion(SnapshotContentsTree.ancestorPaths(for: snapshotPath))
        selectedSnapshotPaths = [snapshotPath]
        snapshotScrollTarget = snapshotPath
    }

    private func snapshotDisplayPath(forConfiguredPath path: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("~/") {
            return path
        }
        return "~/\(path)"
    }

    private func flattenedNodes(in nodes: [SnapshotContentNode]) -> [SnapshotContentNode] {
        nodes.flatMap { node in
            [node] + flattenedNodes(in: node.children ?? [])
        }
    }

    private func folderContentsDescription(_ contents: SnapshotFolderContents) -> String {
        let files = "\(contents.fileCount) file\(contents.fileCount == 1 ? "" : "s")"
        let folders = "\(contents.folderCount) folder\(contents.folderCount == 1 ? "" : "s")"
        return "\(files) · \(folders)"
    }

    @ViewBuilder
    private func configuredPathRow(_ node: PathOutlineNode) -> some View {
        if let path = configuredPathsByPath[node.path] {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: image(for: path))
                    .foregroundStyle(colour(for: path))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .lineLimit(1)
                    Text(detail(for: path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if path.isDynamic {
                    Text("auto")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .contextMenu {
                Button("Copy Path") {
                    copyPath(path.path)
                }
                if let file = snapshotFile(forConfiguredPath: path.path) {
                    Button("Show Archived Copy in Finder") {
                        revealInFinder(file)
                    }
                }
                if canRemoveArchivedRoot(path) {
                    Divider()
                    Button("Remove Root and Archive…", role: .destructive) {
                        archiveRemovalRequest = path
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .lineLimit(1)
                    Text("Folder containing selected paths")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private var metadataDescription: String {
        [machine.operatingSystem, machine.architecture]
            .compactMap(\.self)
            .joined(separator: " · ")
            .ifEmpty("Last updated \(SyncFormatting.date(machine.modifiedAt))")
    }

    private func image(for path: ConfiguredPath) -> String {
        switch path.snapshotState {
        case let .present(kind, _, _):
            kind.systemImage
        case .missing:
            "questionmark.folder"
        }
    }

    private func snapshotKind(for path: ConfiguredPath) -> SnapshotFile.Kind {
        switch path.snapshotState {
        case let .present(kind, _, _):
            kind
        case .missing:
            .file
        }
    }

    private func colour(for path: ConfiguredPath) -> Color {
        switch path.snapshotState {
        case .present:
            .secondary
        case .missing:
            .orange
        }
    }

    private func detail(for path: ConfiguredPath) -> String {
        switch path.snapshotState {
        case let .present(_, fileCount, byteCount):
            "\(fileCount) file\(fileCount == 1 ? "" : "s") · \(SyncFormatting.bytes(byteCount))"
        case .missing:
            "Not present in this snapshot"
        }
    }

    private var selectedRemovableConfiguredRoot: ConfiguredPath? {
        guard let root = selectedConfiguredRoot,
              !root.isDynamic
        else {
            return nil
        }
        return root
    }

    private func removableConfiguredRoot(for file: SnapshotFile) -> ConfiguredPath? {
        guard isCurrentMachine else {
            return nil
        }
        return machine.configuredPaths.first {
            !$0.isDynamic && snapshotDisplayPath(forConfiguredPath: $0.path) == file.displayPath
        }
    }

    @ViewBuilder
    private func archiveRemovalMenu(for file: SnapshotFile) -> some View {
        if let root = removableConfiguredRoot(for: file) {
            Divider()
            Button("Remove Root and Archive…", role: .destructive) {
                archiveRemovalRequest = root
            }
            .disabled(!canRemoveArchivedRoot(root))
        }
    }

    private func canRemoveArchivedRoot(_ root: ConfiguredPath) -> Bool {
        isCurrentMachine && !root.isDynamic && !store.isRunning && !store.hasUnsavedSelection
    }

    private func archiveRemovalHelp(for root: ConfiguredPath) -> String {
        if store.hasUnsavedSelection {
            return "Save or discard Sync Selection changes before removing \(root.path)."
        }
        return "Remove this configured root and its archived copy."
    }
}

private struct SnapshotFilePreviewRequest: Identifiable {
    enum Mode: String {
        case preview
        case information
    }

    let file: SnapshotFile
    let mode: Mode

    var id: String {
        "\(file.id)-\(mode.rawValue)"
    }
}

private struct SnapshotTreeRows<Row: View>: View {
    let nodes: [SnapshotContentNode]
    @Binding var expandedPaths: Set<String>
    let row: (SnapshotContentNode) -> Row

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansionBinding(for: node.id)) {
                    SnapshotTreeRows(nodes: children, expandedPaths: $expandedPaths, row: row)
                } label: {
                    row(node)
                }
                .tag(node.id)
                .id(node.id)
            } else {
                row(node)
                    .tag(node.id)
                    .id(node.id)
            }
        }
    }

    private func expansionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(path) },
            set: { isExpanded in
                if isExpanded {
                    expandedPaths.insert(path)
                } else {
                    expandedPaths.remove(path)
                }
            }
        )
    }
}

private struct PathOutlineRows<Row: View>: View {
    let nodes: [PathOutlineNode]
    @Binding var expandedPaths: Set<String>
    let row: (PathOutlineNode) -> Row

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansionBinding(for: node.id)) {
                    PathOutlineRows(nodes: children, expandedPaths: $expandedPaths, row: row)
                } label: {
                    row(node)
                }
                .tag(node.id)
            } else {
                row(node)
                    .tag(node.id)
            }
        }
    }

    private func expansionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(path) },
            set: { isExpanded in
                if isExpanded {
                    expandedPaths.insert(path)
                } else {
                    expandedPaths.remove(path)
                }
            }
        )
    }
}

private struct EncryptedSecretsSheet: View {
    let machine: MachineSnapshot
    @ObservedObject var store: SyncStore
    @Binding var isPresented: Bool
    @State private var showAccessSetupConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Encrypted secrets for \(machine.name)", systemImage: "lock.fill")
                .font(.title2.bold())
            Text("Mac Sync uses this Mac's Keychain age identity to list archive entries. File contents are never displayed or written by this view.")
                .foregroundStyle(.secondary)

            GroupBox("Archive entries") {
                archiveContents
                    .frame(minHeight: 180, maxHeight: 340)
            }

            Text("To restore selected secrets, use mac-sync secrets restore --from \(machine.name) in Terminal. Restoring is intentionally separate from viewing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Close") {
                    isPresented = false
                }
                Spacer()
                Button("Refresh") {
                    store.inspectEncryptedSecrets(from: machine.name)
                }
                .disabled(store.isLoadingEncryptedSecrets(for: machine.name))
            }
        }
        .padding(24)
        .frame(width: 620)
        .confirmationDialog(
            "Publish this Mac's encrypted-secrets access?",
            isPresented: $showAccessSetupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Set Up and Publish Access") {
                store.prepareEncryptedSecretsAccess()
            }
        } message: {
            Text("Mac Sync will create or reuse this Mac's Keychain identity, then publish only its public recipient to mac-sync-data with Git. It will not decrypt, replace, or expose this archive. Afterwards, run Sync Now on a Mac that can already open the archive to re-encrypt it for this Mac.")
        }
        .task {
            if store.encryptedSecrets(for: machine.name) == nil {
                store.inspectEncryptedSecrets(from: machine.name)
            }
        }
    }

    @ViewBuilder
    private var archiveContents: some View {
        if store.activeAction == .preparingEncryptedSecretsAccess {
            HStack(spacing: 10) {
                ProgressView()
                Text("Publishing this Mac's public recipient…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.isLoadingEncryptedSecrets(for: machine.name) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Unlocking archive entries with Keychain…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.encryptedSecretsError(for: machine.name) {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if let recovery = store.encryptedSecretsRecoverySuggestion(for: machine.name) {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if store.canPrepareEncryptedSecretsAccess(for: machine.name) {
                    Button("Set Up This Mac's Access…") {
                        showAccessSetupConfirmation = true
                    }
                    .disabled(store.isRunning)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let entries = store.encryptedSecrets(for: machine.name) {
            if entries.isEmpty {
                archiveEmptyState(
                    title: "No entries",
                    systemImage: "lock.slash",
                    detail: "This archive did not contain any viewable paths."
                )
            } else {
                List(entries, id: \.self) { entry in
                    Label(entry, systemImage: entry.hasSuffix("/") ? "folder" : "doc")
                        .textSelection(.enabled)
                }
                .listStyle(.inset)
            }
        } else {
            archiveEmptyState(
                title: "Ready to inspect",
                systemImage: "lock",
                detail: "Select Refresh to unlock and list this archive."
            )
        }
    }

    private func archiveEmptyState(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct RestoreSheet: View {
    let machine: MachineSnapshot
    @ObservedObject var store: SyncStore
    @Binding var isPresented: Bool
    let availablePaths: [String]
    @State private var restoreSelectedPaths = false
    @State private var selectedPaths: Set<String>
    @State private var showConflictDecision = false

    init(
        machine: MachineSnapshot,
        store: SyncStore,
        isPresented: Binding<Bool>,
        initialPaths: [String]? = nil
    ) {
        self.machine = machine
        self.store = store
        _isPresented = isPresented
        let configuredPaths = machine.configuredPaths.map(\.path)
        let selectedPaths = initialPaths ?? configuredPaths
        availablePaths = Array(Set(configuredPaths + selectedPaths)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        _restoreSelectedPaths = State(initialValue: initialPaths != nil)
        _selectedPaths = State(initialValue: Set(selectedPaths))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(sheetTitle, systemImage: "arrow.down.to.line.compact")
                .font(.title2.bold())
            Text(sheetExplanation)
                .foregroundStyle(.secondary)
            Toggle("Copy specific paths only", isOn: $restoreSelectedPaths)
            if restoreSelectedPaths {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Source snapshot paths")
                            .font(.headline)
                        Spacer()
                        Button("Select All") {
                            selectedPaths = Set(availablePaths)
                        }
                        .buttonStyle(.borderless)
                        Button("Clear") {
                            selectedPaths.removeAll()
                        }
                        .buttonStyle(.borderless)
                    }
                    List(availablePaths, id: \.self, selection: $selectedPaths) { path in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path)
                            Text(pathDetail(for: path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 190)
                    Text("A selected copy transfers only these paths and intentionally skips package, editor, repository, and secrets restore steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if machine.hasEncryptedSecrets {
                Label("The encrypted secrets archive remains opt-in and is not copied by this action.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Preview Copy") {
                    store.previewRestore(from: machine.name, paths: restorePaths)
                    isPresented = false
                }
                .disabled(restoreSelectedPaths && selectedPaths.isEmpty)
                Button("Copy…") {
                    showConflictDecision = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(restoreSelectedPaths && selectedPaths.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .confirmationDialog(
            "How should existing local files be handled?",
            isPresented: $showConflictDecision,
            titleVisibility: .visible
        ) {
            Button("Keep Existing Local Files") {
                copy(force: false)
            }
            Button("Replace with \(machine.name) Snapshot", role: .destructive) {
                copy(force: true)
            }
            Button("Cancel", role: .cancel) {
                showConflictDecision = false
            }
        } message: {
            Text(conflictDecisionExplanation)
        }
    }

    private var restorePaths: [String]? {
        restoreSelectedPaths ? selectedPaths.sorted() : nil
    }

    private var sheetTitle: String {
        isCurrentMachineSnapshot ? "Restore archived copy" : "Copy from \(machine.name)"
    }

    private var sheetExplanation: String {
        if isCurrentMachineSnapshot {
            return "This restores selected files from this Mac's local archive to your home folder. Existing local files stay in place unless you explicitly choose to replace them."
        }
        return "This copies the selected machine snapshot from mac-sync-data into your home folder. This Mac remains the source of truth, so you will choose how to handle any existing local files before copying."
    }

    private var isCurrentMachineSnapshot: Bool {
        machine.name == store.overview.configuration.machineName
    }

    private func pathDetail(for path: String) -> String {
        guard let configuredPath = machine.configuredPaths.first(where: { $0.path == path }) else {
            return "Selected from snapshot contents"
        }
        return configuredPath.isDynamic ? "Auto-discovered path" : "Saved sync selection"
    }

    private var conflictDecisionExplanation: String {
        let itemDescription = restoreSelectedPaths ? "the selected paths" : "this snapshot"
        return "This is a manual copy of \(itemDescription) from \(machine.name). Keep Existing Local Files preserves this Mac's copies and adds only missing files. Replace with Snapshot overwrites existing files and resolves file or folder conflicts in favour of \(machine.name)."
    }

    private func copy(force: Bool) {
        store.restore(from: machine.name, force: force, paths: restorePaths)
        isPresented = false
    }
}

private extension String {
    func ifEmpty(_ fallback: @autoclosure () -> String) -> String {
        isEmpty ? fallback() : self
    }
}
