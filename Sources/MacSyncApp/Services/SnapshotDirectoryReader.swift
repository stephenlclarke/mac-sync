import Foundation
import MacSyncCore

struct SnapshotDirectoryPage: Sendable {
    let files: [SnapshotFile]
    let hasNext: Bool
}

struct SnapshotDirectoryReader: Sendable {
    let dataRepository: String

    func page(machine: String, directory: String, offset: Int = 0, limit: Int = 100) throws -> SnapshotDirectoryPage {
        guard MacSyncPaths.safeMachineName(machine), directory.hasPrefix("~/") || directory.hasPrefix("/") else {
            throw SnapshotFileInspectionError.invalidSnapshotPath
        }
        let home = directory.hasPrefix("~/")
        let relative = String(directory.dropFirst(home ? 2 : 1)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard relative.isEmpty || relative.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SnapshotFileInspectionError.invalidSnapshotPath
        }
        let root = URL(fileURLWithPath: dataRepository).appendingPathComponent("machines/\(machine)/\(home ? "home" : "absolute")")
        let folder = relative.isEmpty ? root : root.appendingPathComponent(relative)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let repository = URL(fileURLWithPath: dataRepository).resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedRoot.hasPrefix(repository + "/machines/") else { throw SnapshotFileInspectionError.outsideSnapshot }
        guard resolvedFolder == resolvedRoot || resolvedFolder.hasPrefix(resolvedRoot + "/") else {
            throw SnapshotFileInspectionError.outsideSnapshot
        }
        guard FileManager.default.fileExists(atPath: folder.path) else { return SnapshotDirectoryPage(files: [], hasNext: false) }
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                              includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                                                              options: [.skipsSubdirectoryDescendants]) else { throw SnapshotFileInspectionError.missingFile }
        var files: [SnapshotFile] = []
        var index = 0
        let pageSize = min(200, max(1, limit))
        for case let url as URL in enumerator {
            if Task.isCancelled {
                throw CancellationError()
            }
            defer { index += 1 }
            if index < max(0, offset) {
                continue
            }
            if files.count == pageSize {
                return SnapshotDirectoryPage(files: files, hasNext: true)
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            let prefix = directory.hasSuffix("/") ? directory : directory + "/"
            files.append(SnapshotFile(displayPath: prefix + url.lastPathComponent,
                                      kind: values.isDirectory == true && values.isSymbolicLink != true ? .folder : .file,
                                      byteCount: values.fileSize ?? 0, modifiedAt: values.contentModificationDate))
        }
        return SnapshotDirectoryPage(files: files, hasNext: false)
    }
}
