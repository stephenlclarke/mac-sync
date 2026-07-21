import Foundation

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

public struct CommandResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String

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
        capture: Bool = true,
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
                stderr: String(decoding: captured.stderr, as: UTF8.self),
            )
        }
        return CommandResult(status: process.terminationStatus, stdout: "", stderr: "")
    }

    public func shell(
        _ script: String,
        workingDirectory: String? = nil,
        extraEnvironment: [String: String] = [:],
        capture: Bool = true,
    ) -> CommandResult {
        run(
            "/bin/bash",
            ["-c", script],
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment,
            capture: capture,
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
