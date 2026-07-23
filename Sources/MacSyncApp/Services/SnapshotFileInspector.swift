import Foundation
import MacSyncCore
import UniformTypeIdentifiers

enum SnapshotFileInspectionError: LocalizedError, Equatable {
    case invalidMachineName
    case invalidSnapshotPath
    case outsideSnapshot
    case missingFile
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .invalidMachineName:
            "This machine name is not safe to inspect."
        case .invalidSnapshotPath:
            "This snapshot path is not safe to inspect."
        case .outsideSnapshot:
            "This snapshot file resolves outside the selected machine archive."
        case .missingFile:
            "This file is no longer available in the selected snapshot."
        case .unsupportedFileType:
            "Only regular files can be previewed."
        }
    }
}

enum SnapshotFileContent: Equatable {
    case text(String, isTruncated: Bool)
    case binary
}

struct SnapshotFileInspection: Equatable {
    let url: URL
    let byteCount: Int
    let modifiedAt: Date?
    let contentTypeIdentifier: String?
    let content: SnapshotFileContent

    var isBinary: Bool {
        if case .binary = content {
            return true
        }
        return false
    }
}

/// Reads a bounded preview from a regular file within one machine snapshot.
/// It never follows a snapshot path outside its machine archive.
struct SnapshotFileInspector {
    static let maximumPreviewByteCount = 96 * 1024

    private let dataRepository: URL
    private let fileManager: FileManager

    init(dataRepository: String, fileManager: FileManager = .default) {
        self.dataRepository = URL(fileURLWithPath: dataRepository)
        self.fileManager = fileManager
    }

    func inspect(machineName: String, file: SnapshotFile) throws -> SnapshotFileInspection {
        guard file.kind == .file else {
            throw SnapshotFileInspectionError.unsupportedFileType
        }

        let url = try fileURL(machineName: machineName, file: file)
        let values = try url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey,
        ])
        guard values.isRegularFile == true else {
            throw SnapshotFileInspectionError.unsupportedFileType
        }

        let byteCount = values.fileSize ?? file.byteCount
        let previewData = try readPreviewData(from: url)
        let isTruncated = byteCount > previewData.count
        let content: SnapshotFileContent = if let text = text(in: previewData) {
            .text(text, isTruncated: isTruncated)
        } else {
            .binary
        }

        return SnapshotFileInspection(
            url: url,
            byteCount: byteCount,
            modifiedAt: values.contentModificationDate,
            contentTypeIdentifier: values.contentType?.identifier,
            content: content
        )
    }

    func fileURL(machineName: String, file: SnapshotFile) throws -> URL {
        guard MacSyncPaths.safeMachineName(machineName) else {
            throw SnapshotFileInspectionError.invalidMachineName
        }
        let location = try snapshotLocation(for: file.displayPath)
        let root = dataRepository
            .appendingPathComponent("machines")
            .appendingPathComponent(machineName)
            .appendingPathComponent(location.section)
        let url = root.appendingPathComponent(location.relativePath)

        guard fileManager.fileExists(atPath: url.path) else {
            throw SnapshotFileInspectionError.missingFile
        }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : "\(resolvedRoot)/"
        guard resolvedURL.hasPrefix(rootPrefix) else {
            throw SnapshotFileInspectionError.outsideSnapshot
        }

        return url
    }

    private func snapshotLocation(for displayPath: String) throws -> (section: String, relativePath: String) {
        let location: (section: String, relativePath: String) = if displayPath.hasPrefix("~/") {
            ("home", String(displayPath.dropFirst(2)))
        } else if displayPath.hasPrefix("/") {
            ("absolute", String(displayPath.dropFirst()))
        } else {
            throw SnapshotFileInspectionError.invalidSnapshotPath
        }

        let components = location.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component != "." && component != ".." && !component.contains("\0")
              })
        else {
            throw SnapshotFileInspectionError.invalidSnapshotPath
        }
        return location
    }

    private func readPreviewData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: Self.maximumPreviewByteCount) ?? Data()
    }

    private func text(in data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        for droppedByteCount in 1 ... min(3, data.count) {
            if let text = String(data: data.dropLast(droppedByteCount), encoding: .utf8) {
                return text
            }
        }
        return nil
    }
}
