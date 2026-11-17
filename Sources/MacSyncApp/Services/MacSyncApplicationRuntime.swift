import AppKit
import Darwin
import Foundation
import MacSyncCore

@MainActor
final class MacSyncApplicationRuntime {
    static let shared = MacSyncApplicationRuntime()
    let environment: [String: String]
    let distribution: MacSyncDistribution
    private(set) var fileAccess: MacSyncFileAccess?
    private(set) var preparationError: String?

    private init() {
        distribution = .current
        guard distribution == .appStore else {
            environment = ProcessInfo.processInfo.environment
            fileAccess = nil
            preparationError = nil
            return
        }
        let container = NSHomeDirectory()
        let userHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? container
        environment = MacSyncStoreRuntime.environment(ProcessInfo.processInfo.environment, bundle: Bundle.main.bundleURL, containerHome: container, sourceHome: userHome)
        do {
            try FileManager.default.createDirectory(atPath: environment["TMPDIR"]!, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = URL(fileURLWithPath: environment["MAC_SYNC_PRIVATE_SUPPORT"]!).appendingPathComponent("folder-access.json")
            let access = try MacSyncFileAccess(file: file)
            access.restore()
            fileAccess = access
            let missing = MacSyncStoreRuntime.missingTools(bundle: Bundle.main.bundleURL)
            preparationError = missing.isEmpty ? nil : "This app package is incomplete (missing bundled tools: \(missing.joined(separator: ", "))). Reinstall it from the App Store."
        } catch {
            fileAccess = nil
            preparationError = "Saved folder access could not be loaded. \(error.localizedDescription)"
        }
    }

    func remember(_ url: URL) throws {
        guard distribution == .appStore else { return }
        guard let fileAccess else { throw BackupStorageError.unavailable(preparationError ?? "Folder access is unavailable.") }
        try fileAccess.remember(url)
    }

    func resetFolderAccess() throws {
        guard distribution == .appStore else { return }
        _ = try ManagedAgentService(environment: environment).configure(schedule: nil)
        let file = URL(fileURLWithPath: environment["MAC_SYNC_PRIVATE_SUPPORT"]!).appendingPathComponent("folder-access.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("[]".utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        fileAccess?.stop()
        fileAccess = try MacSyncFileAccess(file: file)
        let missing = MacSyncStoreRuntime.missingTools(bundle: Bundle.main.bundleURL)
        preparationError = missing.isEmpty ? nil : "Reinstall Mac Sync: bundled runtime tools are missing."
    }

    func accessProblem(paths: [String]) -> String? {
        guard distribution == .appStore else { return nil }
        if let preparationError {
            return preparationError
        }
        guard let fileAccess else { return "Choose your sync folders again in Settings." }
        let container = NSHomeDirectory()
        let missing = paths.filter { !BackupDestinationSettings.isInside($0, directory: container) && !fileAccess.covers($0) }
        guard !missing.isEmpty else { return nil }
        return "Folder access needs approval. Use Settings → Folder access to choose these folders again: " + missing.joined(separator: ", ")
    }

    func authorize(_ urls: [URL]) throws {
        guard distribution == .appStore else { return }
        for url in urls {
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url : url.deletingLastPathComponent()
            if BackupDestinationSettings.isInside(directory.path, directory: NSHomeDirectory()) || fileAccess?.covers(directory.path) == true {
                continue
            }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.directoryURL = directory
            panel.prompt = "Allow Access"
            panel.message = "Choose the containing folder for \(url.path). Folder access supports atomic saves and background change detection. Granting access does not add files to sync or transfer other files."
            guard panel.runModal() == .OK, let folder = panel.url else {
                throw BackupStorageError.unavailable("Folder access was not granted. No files were changed.")
            }
            guard BackupDestinationSettings.isInside(url.path, directory: folder.path) else {
                throw BackupStorageError.unavailable("Choose a folder that contains \(url.path).")
            }
            try remember(folder)
        }
    }

    func workerEnvironment() throws -> (values: [String: String], manifest: URL?) {
        guard distribution == .appStore else { return (environment, nil) }
        guard let fileAccess else { throw BackupStorageError.unavailable(preparationError ?? "Folder permissions are unavailable.") }
        let support = URL(fileURLWithPath: environment["MAC_SYNC_PRIVATE_SUPPORT"]!)
        let directory = support.appendingPathComponent("access-leases")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let manifest = directory.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).json")
        let roots = fileAccess.activeRoots + [MacSyncAccessRoot(path: NSHomeDirectory(), isDirectory: true)]
        try JSONEncoder().encode(roots).write(to: manifest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
        var values = environment
        values["MAC_SYNC_ACCESS_MANIFEST"] = manifest.path
        values["MAC_SYNC_ACCESS_BOOKMARKS_FILE"] = support.appendingPathComponent("folder-access.json").path
        return (values, manifest)
    }
}
