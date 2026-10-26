import SwiftUI

struct SnapshotDirectoryBrowser<Row: View>: View {
    let machineName: String
    let dataRepository: String
    @Binding var directory: String
    @Binding var selectedPaths: Set<String>
    @Binding var pageFiles: [SnapshotFile]
    let row: (SnapshotFile) -> Row
    @State private var offset = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Home") { directory = "~/" }
                Button("Absolute paths") { directory = "/" }
                Button("Up") { directory = parent }
                    .disabled(directory == "~/" || directory == "/")
                Text(directory).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                }
            }.padding(.horizontal)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.orange).font(.caption)
            }
            List(selection: $selectedPaths) {
                ForEach(pageFiles) { file in
                    row(file).tag(file.id)
                        .onTapGesture(count: 2) {
                            if file.kind == .folder {
                                directory = file.displayPath + "/"
                            }
                        }
                }
            }.listStyle(.inset)
            HStack {
                Button("Previous") { offset = max(0, offset - 100) }.disabled(offset == 0 || loading)
                Text("Items \(pageFiles.isEmpty ? 0 : offset + 1)–\(offset + pageFiles.count) · Double-click a folder to open it")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Next") { offset += 100 }.disabled(!hasNext || loading)
            }.padding(.bottom, 8)
        }
        .task(id: "\(machineName):\(directory):\(offset)") { await load() }
        .onChange(of: directory) { _ in offset = 0; selectedPaths = [] }
    }

    private var parent: String {
        let home = directory.hasPrefix("~/")
        let pieces = directory.dropFirst(home ? 2 : 1).split(separator: "/").dropLast()
        return (home ? "~/" : "/") + pieces.joined(separator: "/") + (pieces.isEmpty ? "" : "/")
    }

    private func load() async {
        loading = true
        let reader = SnapshotDirectoryReader(dataRepository: dataRepository)
        let machine = machineName
        let path = directory
        let pageOffset = offset
        let request = Task.detached(priority: .utility) { Result { try reader.page(machine: machine, directory: path, offset: pageOffset) } }
        let result = await withTaskCancellationHandler(operation: { await request.value }, onCancel: { request.cancel() })
        guard !Task.isCancelled, path == directory, pageOffset == offset else { return }
        loading = false
        switch result {
        case let .success(page): pageFiles = page.files; hasNext = page.hasNext; errorMessage = nil
        case let .failure(error): pageFiles = []; hasNext = false; errorMessage = error.localizedDescription
        }
    }
}
