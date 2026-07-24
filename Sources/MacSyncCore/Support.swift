import Foundation

/// A completed local publish or restore operation. The CLI stores these
/// records in the local status directory; they deliberately never contain
/// decrypted secret contents.
public enum SyncHistoryAction: String, Codable, Hashable, Sendable {
    case sync
    case restore
}

public enum SyncHistoryResult: String, Codable, Hashable, Sendable {
    case success
    case failed
}

public enum SyncHistoryTransferDirection: String, Codable, Hashable, Sendable {
    case upload
    case download
}

public enum SyncHistoryTransferOutcome: String, Codable, Hashable, Sendable {
    case new
    case updated
    case removed
    case skipped
}

public struct SyncHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let direction: SyncHistoryTransferDirection
    public let outcome: SyncHistoryTransferOutcome
    public let path: String
    public let source: String
    public let destination: String
    public let detail: String?

    public init(
        id: String = UUID().uuidString,
        direction: SyncHistoryTransferDirection,
        outcome: SyncHistoryTransferOutcome,
        path: String,
        source: String,
        destination: String,
        detail: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.outcome = outcome
        self.path = path
        self.source = source
        self.destination = destination
        self.detail = detail
    }
}

public struct SyncHistoryTiming: Codable, Hashable, Sendable {
    public let startedAt: String
    public let finishedAt: String
    public let durationSeconds: Int

    public init(startedAt: String, finishedAt: String, durationSeconds: Int) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
    }
}

public struct SyncHistoryDiagnostics: Codable, Hashable, Sendable {
    public let warningCount: Int
    public let errorCount: Int
    public let warnings: [String]
    public let errors: [String]

    public init(
        warningCount: Int,
        errorCount: Int,
        warnings: [String],
        errors: [String]
    ) {
        self.warningCount = warningCount
        self.errorCount = errorCount
        self.warnings = warnings
        self.errors = errors
    }
}

public struct SyncHistoryRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let action: SyncHistoryAction
    public let sourceMachine: String?
    public let result: SyncHistoryResult
    public let startedAt: String
    public let finishedAt: String
    public let durationSeconds: Int
    public let warningCount: Int
    public let errorCount: Int
    public let entries: [SyncHistoryEntry]
    public let warnings: [String]
    public let errors: [String]

    public init(
        id: String = UUID().uuidString,
        action: SyncHistoryAction,
        sourceMachine: String? = nil,
        result: SyncHistoryResult,
        timing: SyncHistoryTiming,
        entries: [SyncHistoryEntry],
        diagnostics: SyncHistoryDiagnostics
    ) {
        self.id = id
        self.action = action
        self.sourceMachine = sourceMachine
        self.result = result
        startedAt = timing.startedAt
        finishedAt = timing.finishedAt
        durationSeconds = timing.durationSeconds
        warningCount = diagnostics.warningCount
        errorCount = diagnostics.errorCount
        self.entries = entries
        warnings = diagnostics.warnings
        errors = diagnostics.errors
    }
}

public enum ShellQuoter {
    public static func quote(_ value: String) -> String {
        if value.isEmpty || value.range(of: #"[^A-Za-z0-9_./:@%+=,-]"#, options: .regularExpression) != nil {
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return value
    }
}

public enum MacSyncPaths {
    public static func safeMachineName(_ machine: String) -> Bool {
        !machine.isEmpty
            && machine != "."
            && machine != ".."
            && !machine.hasPrefix("-")
            && machine.range(of: #"[^A-Za-z0-9._-]"#, options: .regularExpression) == nil
    }

    public static func safeSyncPath(_ path: String) -> Bool {
        if path.isEmpty || path == "." || path == "/" || path.contains("\n") || path.contains("\r") {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: true).allSatisfy { part in
            part != "." && part != ".."
        }
    }

    public static func selectedMachineName(input: String, available: [String]) -> String? {
        let selection = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(selection), available.indices.contains(index - 1) {
            return available[index - 1]
        }
        let matches = available.filter { $0.caseInsensitiveCompare(selection) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func safeGitHubRepositoryRelativePath(_ rel: String) -> Bool {
        if rel.isEmpty || rel == "." || rel == ".." || rel.hasPrefix("/") || rel.hasPrefix("../")
            || rel.contains("/../") || rel.hasSuffix("/..") || rel.contains("//")
            || rel.contains("\t") || rel.contains("\n")
        {
            return false
        }
        return rel.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && !part.hasPrefix("-")
        }
    }

    public static func normalizeGitHubRemoteURL(_ rawURL: String) -> String? {
        var url = rawURL.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if let hash = url.firstIndex(of: "#") {
            url = String(url[..<hash])
        }
        if let query = url.firstIndex(of: "?") {
            url = String(url[..<query])
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }

        let prefixes = [
            "git@github.com:",
            "git@ssh.github.com:",
            "ssh://git@github.com/",
            "ssh://git@ssh.github.com:443/",
            "https://github.com/",
            "http://github.com/",
            "git://github.com/",
        ]
        var path: String?
        for prefix in prefixes where url.hasPrefix(prefix) {
            path = String(url.dropFirst(prefix.count))
            break
        }
        if path == nil, url.hasPrefix("https://"), let range = url.range(of: "@github.com/") {
            path = String(url[range.upperBound...])
        }
        if path == nil, url.hasPrefix("http://"), let range = url.range(of: "@github.com/") {
            path = String(url[range.upperBound...])
        }
        guard var repoPath = path else { return nil }
        while repoPath.hasSuffix("/") {
            repoPath.removeLast()
        }
        if repoPath.hasSuffix(".git") {
            repoPath.removeLast(4)
        }
        guard !repoPath.isEmpty, !repoPath.contains("//") else { return nil }
        let parts = repoPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        let repo = String(parts[1])
        guard owner.range(of: #"[^A-Za-z0-9_.-]"#, options: .regularExpression) == nil,
              repo.range(of: #"[^A-Za-z0-9_.-]"#, options: .regularExpression) == nil,
              !owner.isEmpty, !repo.isEmpty
        else {
            return nil
        }
        return "https://github.com/\(owner)/\(repo).git"
    }
}

public enum MacSyncUserConfiguration {
    private static let managedKeys = [
        "MAC_SYNC_DATA_REPOSITORY",
    ]

    public static func configurationFilePath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return environment["MAC_SYNC_APP_CONFIG"] ?? "\(home)/Library/Application Support/mac-sync/config.env"
    }

    public static func resolvedEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let filePath = configurationFilePath(environment: environment)
        let stored = values(in: filePath)
        var resolved = stored
        if let dataRepository = stored["MAC_SYNC_DATA_REPOSITORY"] {
            resolved["MAC_SYNC_MACHINES_REPO"] = dataRepository
        }
        return resolved.merging(environment) { _, directValue in directValue }
    }

    public static func saveDataRepository(
        _ dataRepository: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        guard !dataRepository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !dataRepository.contains("\n"),
              !dataRepository.contains("\r")
        else {
            throw MacSyncUserConfigurationError.invalidRepositoryLocation
        }

        let filePath = configurationFilePath(environment: environment)
        let output = [
            "# Managed by Mac Sync. Data repository only; credentials remain in Git/Keychain.",
            "MAC_SYNC_DATA_REPOSITORY=\(dataRepository)",
            "",
        ].joined(separator: "\n")
        let url = URL(fileURLWithPath: filePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: filePath)
    }

    private static func values(in path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }
        return text.split(separator: "\n").reduce(into: [:]) { values, line in
            guard let separator = line.firstIndex(of: "=") else { return }
            let key = String(line[..<separator])
            let valueStart: Substring.Index = line.index(after: separator)
            let value = String(line[valueStart...])
            guard managedKeys.contains(key), !value.isEmpty, !value.contains("\r") else { return }
            values[key] = value
        }
    }
}

public enum MacSyncUserConfigurationError: LocalizedError {
    case invalidRepositoryLocation

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryLocation:
            "Repository locations must not be empty or contain new lines."
        }
    }
}

public struct CommandResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        stdout + stderr
    }
}

public struct ProcessRunner {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(
        _ executable: String,
        _ arguments: [String] = [],
        workingDirectory: String? = nil,
        extraEnvironment: [String: String] = [:],
        capture: Bool = true
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = environment.merging(extraEnvironment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        if capture {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        }

        do {
            try process.run()
        } catch {
            return CommandResult(status: 127, stdout: "", stderr: "\(error)\n")
        }

        let output = ProcessOutputCapture()
        let reads = DispatchGroup()
        if capture {
            reads.enter()
            DispatchQueue.global(qos: .utility).async {
                output.storeStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                reads.leave()
            }
            reads.enter()
            DispatchQueue.global(qos: .utility).async {
                output.storeStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                reads.leave()
            }
        }
        process.waitUntilExit()

        if capture {
            reads.wait()
            let captured = output.snapshot()
            return CommandResult(
                status: process.terminationStatus,
                stdout: String(decoding: captured.stdout, as: UTF8.self),
                stderr: String(decoding: captured.stderr, as: UTF8.self)
            )
        }
        return CommandResult(status: process.terminationStatus, stdout: "", stderr: "")
    }

    public func shell(
        _ script: String,
        workingDirectory: String? = nil,
        extraEnvironment: [String: String] = [:],
        capture: Bool = true
    ) -> CommandResult {
        run(
            "/bin/bash",
            ["-c", script],
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment,
            capture: capture
        )
    }

    public func commandExists(_ command: String) -> Bool {
        shell("command -v \(ShellQuoter.quote(command)) >/dev/null 2>&1").status == 0
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func storeStdout(_ data: Data) {
        lock.lock()
        stdout = data
        lock.unlock()
    }

    func storeStderr(_ data: Data) {
        lock.lock()
        stderr = data
        lock.unlock()
    }

    func snapshot() -> (stdout: Data, stderr: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr)
    }
}
