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
        !machine.isEmpty && machine.range(of: #"[^A-Za-z0-9._-]"#, options: .regularExpression) == nil
    }

    public static func safeGitHubRepositoryRelativePath(_ rel: String) -> Bool {
        if rel.isEmpty || rel == "." || rel == ".." || rel.hasPrefix("/") || rel.hasPrefix("../")
            || rel.contains("/../") || rel.hasSuffix("/..") || rel.contains("//")
            || rel.contains("\t") || rel.contains("\n") {
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
              !owner.isEmpty, !repo.isEmpty else {
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
        capture: Bool = true
    ) -> CommandResult {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
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
        process.waitUntilExit()

        if capture {
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(
                status: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
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
