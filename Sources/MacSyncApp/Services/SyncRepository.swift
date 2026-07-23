import Darwin
import Foundation
import MacSyncCore

enum SyncArchiveRemovalError: LocalizedError {
    case notConfiguredRoot(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case let .notConfiguredRoot(path):
            "Only a saved configured root can be removed from this Mac's archive: \(path)"
        case let .unsafePath(path):
            "This archive path is not safe to remove: \(path)"
        }
    }
}

struct SyncRepository {
    private let environment: [String: String]
    private let fileManager: FileManager
    private let machineName: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        let resolvedEnvironment = MacSyncUserConfiguration.resolvedEnvironment(environment)
        self.environment = resolvedEnvironment
        self.fileManager = fileManager
        machineName = Self.resolveMachineName(environment: resolvedEnvironment)
    }

    func load() -> SyncOverview {
        let configuration = configuration()
        let currentStatus = readStatus(configuration: configuration)
        let history = readHistory(configuration: configuration)
        let processID = activeSyncProcessID(machine: configuration.machineName)
        let snapshots = machineSnapshots(configuration: configuration)
        let currentMachine = snapshots.first { $0.name == configuration.machineName }
        let peerMachines = snapshots.filter { $0.name != configuration.machineName }

        return SyncOverview(
            configuration: configuration,
            status: currentStatus,
            history: history,
            currentMachine: currentMachine,
            peerMachines: peerMachines,
            localSyncProcessID: processID,
            isLocalSyncActive: processID != nil
        )
    }

    func configuredPaths() -> [String] {
        readPathList(configuration().pathsFile)
    }

    func saveConfiguredPaths(_ paths: [String]) throws {
        let cleanPaths = orderedUnique(paths.map(normalizePath))
        for path in cleanPaths where !MacSyncPaths.safeSyncPath(path) {
            throw SyncConfigurationError.invalidPath(path)
        }
        try writeConfiguredPaths(cleanPaths)
    }

    /// Removes a regular configured root and its local snapshot copy. The
    /// caller is responsible for confirming this destructive action in the UI.
    func removeArchivedConfiguredPath(_ path: String) throws {
        let configuration = configuration()
        let cleanPath = normalizePath(path)
        guard MacSyncPaths.safeSyncPath(cleanPath) else {
            throw SyncArchiveRemovalError.unsafePath(cleanPath)
        }
        let currentPaths = readPathList(configuration.pathsFile)
        guard currentPaths.contains(cleanPath) else {
            throw SyncArchiveRemovalError.notConfiguredRoot(cleanPath)
        }

        let pathsFile = URL(fileURLWithPath: configuration.pathsFile)
        let previousConfiguration = try Data(contentsOf: pathsFile)
        let archiveURL = try archiveURL(forConfiguredPath: cleanPath, configuration: configuration)
        let remainingPaths = currentPaths.filter { $0 != cleanPath }

        try writeConfiguredPaths(remainingPaths)
        do {
            if fileManager.fileExists(atPath: archiveURL.path) {
                try fileManager.removeItem(at: archiveURL)
            }
        } catch {
            try? previousConfiguration.write(to: pathsFile, options: .atomic)
            throw error
        }
    }

    /// Carries a pre-app configuration forward once, without overwriting a
    /// machine's checked-in configuration. Public age recipients belong in the
    /// shared registry so every trusted Mac can decrypt future snapshots.
    func seedMachineConfigurationIfNeeded() throws {
        let configuration = configuration()
        let target = URL(fileURLWithPath: configuration.pathsFile)
        let legacyRoot = URL(fileURLWithPath: configuration.homeDirectory)
            .appendingPathComponent("github/mac-sync/config")
        let legacyPaths = legacyRoot.appendingPathComponent("sync-paths.txt")

        if !fileManager.fileExists(atPath: target.path), fileManager.fileExists(atPath: legacyPaths.path) {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyPaths, to: target)
            for fileName in ["excludes.txt", "secret-paths.txt"] {
                let source = legacyRoot.appendingPathComponent(fileName)
                let destination = target.deletingLastPathComponent().appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: source, to: destination)
                }
            }
        }

        let recipients = legacyRoot.appendingPathComponent("age-recipients.txt")
        let sharedRecipients = URL(fileURLWithPath: configuration.dataRepository)
            .appendingPathComponent("machines/_shared/config/age-recipients.txt")
        if fileManager.fileExists(atPath: recipients.path), !fileManager.fileExists(atPath: sharedRecipients.path) {
            try fileManager.createDirectory(at: sharedRecipients.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: recipients, to: sharedRecipients)
        }
    }

    func pathForUserSelection(_ url: URL) -> String {
        let absolutePath = url.standardizedFileURL.path
        let home = configuration().homeDirectory
        if absolutePath == home {
            return absolutePath
        }
        let homePrefix = home.hasSuffix("/") ? home : "\(home)/"
        if absolutePath.hasPrefix(homePrefix) {
            return String(absolutePath.dropFirst(homePrefix.count))
        }
        return absolutePath
    }

    func configuration() -> SyncConfiguration {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let dataRepository = environment["MAC_SYNC_MACHINES_REPO"] ?? "\(home)/github/mac-sync-data"
        let statusDirectory = environment["MAC_SYNC_STATUS_DIR"] ?? "\(home)/Library/Application Support/mac-sync/status"
        let pathsFile = environment["MAC_SYNC_PATHS_FILE"]
            ?? "\(dataRepository)/machines/\(machineName)/config/sync-paths.txt"

        return SyncConfiguration(
            homeDirectory: home,
            dataRepository: dataRepository,
            statusDirectory: statusDirectory,
            machineName: machineName,
            pathsFile: pathsFile
        )
    }

    private func writeConfiguredPaths(_ cleanPaths: [String]) throws {
        let configuration = configuration()
        if readPathList(configuration.pathsFile) == cleanPaths {
            return
        }
        let header = existingHeader(in: configuration.pathsFile)
        let heading = (header.isEmpty
            ? [
                "# Paths are relative to $HOME unless they start with /.",
                "# Managed by Mac Sync. Select files and folders in the app to update this list.",
            ]
            : header).joined(separator: "\n")
        let output = cleanPaths.isEmpty
            ? "\(heading)\n"
            : "\(heading)\n\(cleanPaths.joined(separator: "\n"))\n"
        let url = URL(fileURLWithPath: configuration.pathsFile)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func archiveURL(
        forConfiguredPath path: String,
        configuration: SyncConfiguration
    ) throws -> URL {
        let machineRoot = URL(fileURLWithPath: configuration.dataRepository)
            .appendingPathComponent("machines")
            .appendingPathComponent(configuration.machineName)
        let archiveRoot: URL
        let relativePath: String
        if path.hasPrefix("/") {
            archiveRoot = machineRoot.appendingPathComponent("absolute")
            relativePath = String(path.drop(while: { $0 == "/" }))
        } else {
            archiveRoot = machineRoot.appendingPathComponent("home")
            relativePath = path
        }

        let standardRoot = archiveRoot.standardizedFileURL
        let archiveURL = standardRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard archiveURL.path.hasPrefix("\(standardRoot.path)/") else {
            throw SyncArchiveRemovalError.unsafePath(path)
        }
        return archiveURL
    }

    private static func resolveMachineName(environment: [String: String]) -> String {
        if let configured = environment["MAC_SYNC_MACHINE"], !configured.isEmpty {
            return normalizeMachineName(configured)
        }
        let runner = ProcessRunner(environment: environment)
        let localHostName = runner.run("scutil", ["--get", "LocalHostName"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !localHostName.isEmpty {
            return normalizeMachineName(localHostName)
        }
        return normalizeMachineName(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    private static func normalizeMachineName(_ name: String) -> String {
        let lower = name.lowercased()
        let replaced = lower.replacingOccurrences(
            of: #"[^a-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func readStatus(configuration: SyncConfiguration) -> SyncStatus {
        let prefix = "\(configuration.statusDirectory)/\(configuration.machineName)"
        let values = keyValueFile("\(prefix).env")
        guard !values.isEmpty else { return .empty }

        let result: SyncResult = switch values["result"] {
        case "success":
            .success
        case "failed":
            .failed
        default:
            .unknown
        }

        return SyncStatus(
            result: result,
            startedAt: values["started_at"],
            finishedAt: values["finished_at"],
            durationSeconds: Int(values["duration_seconds"] ?? ""),
            updatedFileCount: Int(values["updated_file_count"] ?? ""),
            updatedByteCount: Int(values["updated_byte_count"] ?? ""),
            storageFileCount: Int(values["storage_file_count"] ?? ""),
            storageByteCount: Int(values["storage_byte_count"] ?? ""),
            warningCount: Int(values["warning_count"] ?? "") ?? 0,
            errorCount: Int(values["error_count"] ?? "") ?? 0,
            lastCommit: values["last_commit"],
            remoteRepository: values["remote_repo"],
            warnings: readLines("\(prefix).warnings.log"),
            errors: readLines("\(prefix).errors.log")
        )
    }

    private func readHistory(configuration: SyncConfiguration) -> [SyncHistoryRecord] {
        let directory = URL(fileURLWithPath: configuration.statusDirectory)
            .appendingPathComponent("history")
            .appendingPathComponent(configuration.machineName)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SyncHistoryRecord.self, from: data)
            }
    }

    private func activeSyncProcessID(machine: String) -> Int32? {
        let temporaryDirectory = environment["TMPDIR"] ?? "/tmp"
        let lockFile = "\(temporaryDirectory)/mac-sync-\(machine).lock/pid"
        guard let processID = Int32(readText(lockFile).trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(processID, 0) == 0
        else {
            return nil
        }
        return processID
    }

    private func machineSnapshots(configuration: SyncConfiguration) -> [MachineSnapshot] {
        let root = URL(fileURLWithPath: configuration.dataRepository).appendingPathComponent("machines")
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return names
            // _shared holds repository-wide configuration such as age
            // recipients. It is not a machine and must never appear as one.
            .filter { $0 != "_shared" }
            .filter(MacSyncPaths.safeMachineName)
            .filter { isDirectory(root.appendingPathComponent($0).path) }
            .map { snapshot(named: $0, root: root) }
    }

    private func snapshot(
        named name: String,
        root: URL
    ) -> MachineSnapshot {
        let machineRoot = root.appendingPathComponent(name)
        let metadata = machineMetadata(machineRoot.appendingPathComponent("MACHINE.md").path)
        let configured = readPathList(machineRoot.appendingPathComponent("config/sync-paths.txt").path)
        let dynamic = readPathList(machineRoot.appendingPathComponent("dynamic-sync-paths.txt").path)
        let pathStates = orderedUnique(configured + dynamic).map { path in
            configuredPath(
                path,
                isDynamic: !configured.contains(path),
                machineRoot: machineRoot
            )
        }
        let files = snapshotFiles(machineRoot: machineRoot)
        let latestFileDate = files.compactMap(\.modifiedAt).max()
        let metadataDate = modificationDate(machineRoot.appendingPathComponent("MACHINE.md").path)

        return MachineSnapshot(
            name: name,
            computerName: metadata["ComputerName"],
            operatingSystem: metadata["OS"],
            architecture: metadata["Architecture"],
            modifiedAt: [latestFileDate, metadataDate].compactMap(\.self).max(),
            files: files,
            configuredPaths: pathStates,
            hasEncryptedSecrets: fileManager.fileExists(
                atPath: machineRoot.appendingPathComponent("secrets/secrets.tar.gz.age").path
            ),
            packageCount: readPathList(machineRoot.appendingPathComponent("homebrew/formulae.txt").path).count
                + readPathList(machineRoot.appendingPathComponent("homebrew/casks.txt").path).count,
            editorExtensionCount: readPathList(
                machineRoot.appendingPathComponent("editor/vscode-extensions.txt").path
            ).count,
            repositoryCount: readPathList(
                machineRoot.appendingPathComponent("github-repositories/repositories.txt").path
            ).count
        )
    }

    private func configuredPath(
        _ path: String,
        isDynamic: Bool,
        machineRoot: URL
    ) -> ConfiguredPath {
        let snapshotPath: URL = if path.hasPrefix("/") {
            machineRoot
                .appendingPathComponent("absolute")
                .appendingPathComponent(String(path.drop(while: { $0 == "/" })))
        } else {
            machineRoot
                .appendingPathComponent("home")
                .appendingPathComponent(path)
        }
        guard fileManager.fileExists(atPath: snapshotPath.path) else {
            return ConfiguredPath(path: path, isDynamic: isDynamic, snapshotState: .missing)
        }

        let directory = isDirectory(snapshotPath.path)
        return ConfiguredPath(
            path: path,
            isDynamic: isDynamic,
            snapshotState: .present(
                directory ? .folder : .file,
                directory ? recursiveFileCount(snapshotPath) : 1,
                directory ? recursiveByteCount(snapshotPath) : fileSize(snapshotPath.path)
            )
        )
    }

    private func snapshotFiles(machineRoot: URL) -> [SnapshotFile] {
        let sections = ["home", "absolute"]
        var files: [SnapshotFile] = []
        for section in sections {
            let sectionRoot = machineRoot.appendingPathComponent(section)
            guard fileManager.fileExists(atPath: sectionRoot.path) else { continue }
            if let enumerator = fileManager.enumerator(atPath: sectionRoot.path) {
                for case let relative as String in enumerator {
                    let url = sectionRoot.appendingPathComponent(relative)
                    files.append(
                        SnapshotFile(
                            displayPath: section == "home" ? "~/\(relative)" : "/\(relative)",
                            kind: isDirectory(url.path) ? .folder : .file,
                            byteCount: fileSize(url.path),
                            modifiedAt: modificationDate(url.path)
                        )
                    )
                }
            }
        }
        return files.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private func machineMetadata(_ path: String) -> [String: String] {
        let quote = Character("\u{0060}")
        let marker = ": \(quote)"
        return readLines(path).reduce(into: [:]) { values, line in
            guard line.hasPrefix("- "),
                  let separator = line.range(of: marker),
                  line.last == quote
            else {
                return
            }
            let key = String(line.dropFirst(2)[..<separator.lowerBound])
            let valueStart = separator.upperBound
            values[key] = String(line[valueStart ..< line.index(before: line.endIndex)])
        }
    }

    private func keyValueFile(_ path: String) -> [String: String] {
        readLines(path).reduce(into: [:]) { values, line in
            guard let separator = line.firstIndex(of: "=") else { return }
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
    }

    private func readPathList(_ path: String) -> [String] {
        readLines(path).filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func existingHeader(in path: String) -> [String] {
        readText(path)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .prefix { $0.isEmpty || $0.hasPrefix("#") }
            .filter { !$0.isEmpty }
    }

    private func readLines(_ path: String) -> [String] {
        readText(path)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func readText(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func normalizePath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func orderedUnique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func recursiveFileCount(_ root: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return 0
        }
        return enumerator.compactMap { $0 as? URL }.filter { !isDirectory($0.path) }.count
    }

    private func recursiveByteCount(_ root: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        ) else {
            return 0
        }
        return enumerator.compactMap { $0 as? URL }.reduce(0) { total, url in
            guard !isDirectory(url.path) else { return total }
            return total + fileSize(url.path)
        }
    }

    private func fileSize(_ path: String) -> Int {
        ((try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber) ?? 0).intValue
    }

    private func modificationDate(_ path: String) -> Date? {
        try? fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
