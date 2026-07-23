import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectionEditorView: View {
    @ObservedObject var store: SyncStore
    @State private var pathToAdd = ""
    @State private var selectedOutlinePaths = Set<String>()
    @State private var expandedOutlinePaths = Set<String>()
    @State private var isFileDropTargeted = false

    private var selectedPathTree: [PathOutlineNode] {
        PathOutlineTree.nodes(for: store.selectedPaths.map {
            PathOutlineItem(path: $0, kind: localKind(for: $0))
        })
    }

    private var selectedConfiguredPaths: [String] {
        selectedOutlinePaths.filter { store.selectedPaths.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync selection")
                        .font(.largeTitle.bold())
                    Text("A Finder-style list of the files and folders this Mac publishes. Add roots from Finder, organise them here, then save the portable selection.")
                        .foregroundStyle(.secondary)
                    if store.hasUnsavedSelection {
                        Label("You have unsaved selection changes.", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                selectionBrowserActions
            }
            .padding(24)

            Divider()

            List(selection: $selectedOutlinePaths) {
                SelectionOutlineRows(
                    nodes: selectedPathTree,
                    expandedPaths: $expandedOutlinePaths,
                    row: selectionRow
                )
            }
            .listStyle(.inset)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFileDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: $isFileDropTargeted,
                perform: importFileURLs(from:)
            )
            .onDeleteCommand(perform: removeSelectedPaths)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Add Files or Folders...") {
                        choosePaths()
                    }
                    Button("Paste Files") {
                        pasteFiles()
                    }
                    Button("Show in Finder") {
                        revealSelectedPaths()
                    }
                    .disabled(selectedConfiguredPaths.isEmpty)
                    Button("Use Current Saved Selection") {
                        store.discardSelectionChanges()
                        selectedOutlinePaths.removeAll()
                    }
                    .disabled(!store.hasUnsavedSelection)
                    Button("Remove Selected") {
                        removeSelectedPaths()
                    }
                    .disabled(selectedConfiguredPaths.isEmpty)
                    Spacer()
                    Button("Save Selection") {
                        store.saveSelection()
                    }
                    .disabled(!store.hasUnsavedSelection)
                    Button("Save and Sync") {
                        store.syncSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isRunning)
                }

                HStack {
                    TextField("Relative to your home folder, or an absolute path", text: $pathToAdd)
                    Button("Add Path") {
                        store.add(paths: [pathToAdd])
                        pathToAdd = ""
                    }
                    .disabled(pathToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Drop files or folders from Finder into the list, or copy them in Finder and use Paste Files (⌘V). A folder selection includes its contents subject to the existing excludes file. Sync publishes this Mac's snapshot; opening a peer Mac lets you preview or restore that snapshot onto this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .onPasteCommand(of: [UTType.fileURL]) { providers in
            _ = importFileURLs(from: providers)
        }
    }

    private var selectionBrowserActions: some View {
        Menu {
            Button("Expand All Folders") {
                expandedOutlinePaths = Set(PathOutlineTree.paths(in: selectedPathTree))
            }
            Button("Collapse All Folders") {
                expandedOutlinePaths.removeAll()
            }
            Divider()
            Button("Copy Selected Paths") {
                copySelectedPaths()
            }
            .disabled(selectedConfiguredPaths.isEmpty)
            Button("Show Selected in Finder") {
                revealSelectedPaths()
            }
            .disabled(selectedConfiguredPaths.isEmpty)
            Divider()
            Button("Remove Selected", role: .destructive) {
                removeSelectedPaths()
            }
            .disabled(selectedConfiguredPaths.isEmpty)
        } label: {
            Label("Sync selection actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Organise, reveal, copy, or remove selected sync roots")
    }

    private func pathStatus(_ path: String) -> String {
        guard let configuredPath = store.overview.currentMachine?.configuredPaths.first(where: { $0.path == path }) else {
            return "Will be included after the next sync"
        }
        switch configuredPath.snapshotState {
        case let .present(_, fileCount, byteCount):
            return "Current snapshot: \(fileCount) file\(fileCount == 1 ? "" : "s"), \(SyncFormatting.bytes(byteCount))"
        case .missing:
            return "Not in the current snapshot"
        }
    }

    @ViewBuilder
    private func selectionRow(_ node: PathOutlineNode) -> some View {
        if node.isExplicitSelection {
            HStack(spacing: 10) {
                Image(systemName: node.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .textSelection(.enabled)
                    Text(pathStatus(node.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.remove(path: node.path)
                    selectedOutlinePaths.remove(node.path)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from sync selection")
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Copy Path") {
                    copyPaths([node.path])
                }
                Button("Show in Finder") {
                    reveal(paths: [node.path])
                }
                Divider()
                Button("Remove from Sync Selection", role: .destructive) {
                    store.remove(path: node.path)
                    selectedOutlinePaths.remove(node.path)
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                    Text("Folder containing selected paths")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func localKind(for path: String) -> SnapshotFile.Kind {
        let fullPath = path.hasPrefix("/")
            ? path
            : "\(store.overview.configuration.homeDirectory)/\(path)"
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        return .file
    }

    private func removeSelectedPaths() {
        for path in selectedConfiguredPaths {
            store.remove(path: path)
        }
        selectedOutlinePaths.subtract(selectedConfiguredPaths)
    }

    private func revealSelectedPaths() {
        reveal(paths: selectedConfiguredPaths)
    }

    private func reveal(paths: [String]) {
        let urls = paths.map(sourceURL(for:))
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func sourceURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: store.overview.configuration.homeDirectory)
            .appendingPathComponent(path)
    }

    private func copySelectedPaths() {
        copyPaths(selectedConfiguredPaths)
    }

    private func copyPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.sorted().joined(separator: "\n"), forType: .string)
    }

    private func choosePaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Sync"
        if panel.runModal() == .OK {
            store.add(fileURLs: panel.urls)
        }
    }

    private func pasteFiles() {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        store.add(fileURLs: urls)
    }

    private func importFileURLs(from providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else {
            return false
        }

        for provider in fileURLProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else {
                    return
                }
                DispatchQueue.main.async {
                    store.add(fileURLs: [url])
                }
            }
        }
        return true
    }
}

private struct SelectionOutlineRows<Row: View>: View {
    let nodes: [PathOutlineNode]
    @Binding var expandedPaths: Set<String>
    let row: (PathOutlineNode) -> Row

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansionBinding(for: node.id)) {
                    SelectionOutlineRows(nodes: children, expandedPaths: $expandedPaths, row: row)
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
