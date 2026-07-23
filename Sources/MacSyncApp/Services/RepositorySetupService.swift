import Foundation
import MacSyncCore

struct GitCommandResult: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String

    var output: String {
        stdout + stderr
    }
}

protocol GitCommandRunning {
    func run(
        arguments: [String],
        workingDirectory: String?,
        extraEnvironment: [String: String]
    ) -> GitCommandResult
}

struct SystemGitCommandRunner: GitCommandRunning {
    let environment: [String: String]

    func run(
        arguments: [String],
        workingDirectory: String?,
        extraEnvironment: [String: String]
    ) -> GitCommandResult {
        let result = ProcessRunner(environment: environment).run(
            "git",
            arguments,
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment
        )
        return GitCommandResult(status: result.status, stdout: result.stdout, stderr: result.stderr)
    }
}

struct RepositoryCloneResult: Equatable {
    let inspections: [LocalRepositoryInspection]
    let messages: [String]

    var succeeded: Bool {
        inspections.allSatisfy(\.isReady) && messages.allSatisfy { !$0.hasPrefix("Unable") }
    }
}

struct RepositorySetupService {
    private let fileManager: FileManager
    private let runner: any GitCommandRunning

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        runner: (any GitCommandRunning)? = nil
    ) {
        self.fileManager = fileManager
        self.runner = runner ?? SystemGitCommandRunner(environment: environment)
    }

    func inspect(_ locations: RepositoryLocations) -> [LocalRepositoryInspection] {
        LocalRepositoryKind.allCases.map { kind in
            inspect(kind, at: path(for: kind, locations: locations))
        }
    }

    func cloneMissing(_ locations: RepositoryLocations) -> RepositoryCloneResult {
        var messages: [String] = []

        for kind in LocalRepositoryKind.allCases {
            let path = path(for: kind, locations: locations)
            if inspect(kind, at: path).isReady {
                continue
            }
            guard cloneDestinationIsSafe(path) else {
                messages.append("Unable to clone \(kind.shortTitle): choose an empty folder, a different location, or back up this legacy folder first.")
                break
            }

            let destination = URL(fileURLWithPath: path)
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                messages.append("Unable to create the folder for \(kind.shortTitle): \(error.localizedDescription)")
                break
            }

            let result = git(["clone", "--origin", "origin", kind.cloneURL, path])
            if result.status == 0 {
                messages.append("Cloned \(kind.shortTitle).")
            } else {
                messages.append("Unable to clone \(kind.shortTitle): \(safeMessage(from: result, fallback: "Git clone failed."))")
                break
            }
        }

        return RepositoryCloneResult(inspections: inspect(locations), messages: messages)
    }

    func recoveryPlan(for kind: LocalRepositoryKind, locations: RepositoryLocations) -> RepositoryRecoveryPlan? {
        let originalPath = path(for: kind, locations: locations)
        guard inspect(kind, at: originalPath).state == .notGitRepository,
              isDirectory(originalPath),
              !((try? fileManager.contentsOfDirectory(atPath: originalPath)) ?? []).isEmpty
        else {
            return nil
        }
        var backupPath = "\(originalPath).before-mac-sync"
        var suffix = 2
        while fileManager.fileExists(atPath: backupPath) {
            backupPath = "\(originalPath).before-mac-sync-\(suffix)"
            suffix += 1
        }
        return RepositoryRecoveryPlan(kind: kind, originalPath: originalPath, backupPath: backupPath)
    }

    func backUpAndClone(_ plan: RepositoryRecoveryPlan, locations: RepositoryLocations) -> RepositoryCloneResult {
        let expectedPath = path(for: plan.kind, locations: locations)
        guard plan.originalPath == expectedPath,
              !fileManager.fileExists(atPath: plan.backupPath),
              inspect(plan.kind, at: plan.originalPath).state == .notGitRepository
        else {
            return RepositoryCloneResult(
                inspections: inspect(locations),
                messages: ["Unable to repair \(plan.kind.shortTitle): the selected folder changed. Refresh and try again."]
            )
        }

        do {
            try fileManager.moveItem(atPath: plan.originalPath, toPath: plan.backupPath)
        } catch {
            return RepositoryCloneResult(
                inspections: inspect(locations),
                messages: ["Unable to back up \(plan.kind.shortTitle): \(error.localizedDescription)"]
            )
        }

        let clone = git(["clone", "--origin", "origin", plan.kind.cloneURL, plan.originalPath])
        guard clone.status == 0 else {
            try? fileManager.removeItem(atPath: plan.originalPath)
            do {
                try fileManager.moveItem(atPath: plan.backupPath, toPath: plan.originalPath)
                return RepositoryCloneResult(
                    inspections: inspect(locations),
                    messages: ["Unable to clone \(plan.kind.shortTitle); the original folder was restored. \(safeMessage(from: clone, fallback: "Git clone failed."))"]
                )
            } catch {
                return RepositoryCloneResult(
                    inspections: inspect(locations),
                    messages: ["Unable to clone \(plan.kind.shortTitle). Your original folder is safe at \(plan.backupPath). \(safeMessage(from: clone, fallback: "Git clone failed."))"]
                )
            }
        }
        return RepositoryCloneResult(
            inspections: inspect(locations),
            messages: ["Backed up \(plan.kind.shortTitle) to \(plan.backupPath) and cloned a fresh repository."]
        )
    }

    func initialGitHubReports(for inspections: [LocalRepositoryInspection]) -> [GitHubConnectionReport] {
        inspections.map { inspection in
            switch inspection.state {
            case .missing:
                GitHubConnectionReport(
                    repository: inspection,
                    state: .failed,
                    detail: "Choose or clone this repository before checking GitHub access."
                )
            case .notGitRepository:
                GitHubConnectionReport(
                    repository: inspection,
                    state: .failed,
                    detail: "This folder is not a Git checkout accepted by mac-sync."
                )
            case .ready where !inspection.hasOrigin:
                GitHubConnectionReport(
                    repository: inspection,
                    state: .noOrigin,
                    detail: "No origin remote is configured. Sync stays local until you add one."
                )
            case .ready:
                GitHubConnectionReport(
                    repository: inspection,
                    state: .notChecked,
                    detail: "GitHub access has not been checked in this app session."
                )
            }
        }
    }

    func checkingGitHubReports(for inspections: [LocalRepositoryInspection]) -> [GitHubConnectionReport] {
        inspections.map { inspection in
            GitHubConnectionReport(
                repository: inspection,
                state: inspection.isReady && inspection.hasOrigin ? .checking : initialGitHubReports(for: [inspection])[0].state,
                detail: inspection.isReady && inspection.hasOrigin
                    ? "Checking GitHub without prompting for credentials…"
                    : initialGitHubReports(for: [inspection])[0].detail
            )
        }
    }

    func checkGitHubAccess(for locations: RepositoryLocations) -> [GitHubConnectionReport] {
        inspect(locations).map(checkGitHubAccess)
    }

    private func checkGitHubAccess(_ inspection: LocalRepositoryInspection) -> GitHubConnectionReport {
        guard inspection.isReady else {
            return initialGitHubReports(for: [inspection])[0]
        }
        guard inspection.hasOrigin else {
            return initialGitHubReports(for: [inspection])[0]
        }

        let origin = git(["remote", "get-url", "origin"], in: inspection.path)
        guard origin.status == 0 else {
            return GitHubConnectionReport(
                repository: inspection,
                state: .noOrigin,
                detail: "No origin remote is configured. Sync stays local until you add one."
            )
        }
        guard MacSyncPaths.normalizeGitHubRemoteURL(origin.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            return GitHubConnectionReport(
                repository: inspection,
                state: .notGitHubRemote,
                detail: "The origin remote is not hosted on github.com."
            )
        }

        let readCheck = git(["ls-remote", "origin"], in: inspection.path)
        guard readCheck.status == 0 else {
            return GitHubConnectionReport(
                repository: inspection,
                state: accessFailureState(for: readCheck, requiresWrite: false),
                detail: safeMessage(from: readCheck, fallback: "Git could not read this GitHub remote.")
            )
        }

        let localHead = git(["rev-parse", "--verify", "HEAD"], in: inspection.path)
        guard localHead.status == 0 else {
            return GitHubConnectionReport(
                repository: inspection,
                state: .readAccessReady,
                detail: "Git can read this empty data repository. Your first sync will create and push the initial snapshot."
            )
        }

        guard let branch = inspection.branch, !branch.isEmpty else {
            return GitHubConnectionReport(
                repository: inspection,
                state: .writeAccessDenied,
                detail: "Git can read this repository, but this checkout is detached and cannot push a sync."
            )
        }

        let pushCheck = git(["push", "--dry-run", "--porcelain", "origin", "HEAD:refs/heads/\(branch)"], in: inspection.path)
        guard pushCheck.status == 0 else {
            return GitHubConnectionReport(
                repository: inspection,
                state: accessFailureState(for: pushCheck, requiresWrite: true),
                detail: safeMessage(from: pushCheck, fallback: "Git could not verify write access to this GitHub repository.")
            )
        }
        return GitHubConnectionReport(
            repository: inspection,
            state: .syncAccessReady,
            detail: "Git can read and dry-run push to this repository without prompting for credentials."
        )
    }

    private func inspect(_ kind: LocalRepositoryKind, at path: String) -> LocalRepositoryInspection {
        guard fileManager.fileExists(atPath: path) else {
            return LocalRepositoryInspection(kind: kind, path: path, state: .missing, hasOrigin: false, remoteURL: nil, branch: nil)
        }
        guard isDirectory(path), isDirectory("\(path)/.git") else {
            return LocalRepositoryInspection(kind: kind, path: path, state: .notGitRepository, hasOrigin: false, remoteURL: nil, branch: nil)
        }

        let remote = git(["remote", "get-url", "origin"], in: path)
        let rawRemote = remote.status == 0 ? remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let branch = git(["branch", "--show-current"], in: path)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalRepositoryInspection(
            kind: kind,
            path: path,
            state: .ready,
            hasOrigin: !rawRemote.isEmpty,
            remoteURL: MacSyncPaths.normalizeGitHubRemoteURL(rawRemote),
            branch: branch.isEmpty ? nil : branch
        )
    }

    private func path(for _: LocalRepositoryKind, locations: RepositoryLocations) -> String {
        locations.dataRepository
    }

    private func cloneDestinationIsSafe(_ path: String) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return true }
        guard isDirectory(path) else { return false }
        return ((try? fileManager.contentsOfDirectory(atPath: path)) ?? []).isEmpty
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func git(_ arguments: [String], in directory: String? = nil) -> GitCommandResult {
        runner.run(
            arguments: arguments,
            workingDirectory: directory,
            extraEnvironment: [
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/usr/bin/false",
                "GCM_INTERACTIVE": "never",
                "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10",
            ]
        )
    }

    private func accessFailureState(for result: GitCommandResult, requiresWrite: Bool) -> GitHubAccessState {
        let output = result.output.lowercased()
        if output.contains("authentication failed")
            || output.contains("permission denied")
            || output.contains("publickey")
            || output.contains("could not read username")
            || output.contains("repository not found")
        {
            return .authenticationRequired
        }
        if output.contains("could not resolve host") || output.contains("timed out") || output.contains("network is unreachable") {
            return .unavailable
        }
        return requiresWrite ? .writeAccessDenied : .failed
    }

    private func safeMessage(from result: GitCommandResult, fallback: String) -> String {
        let lines = result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let output = lines.first(where: isActionableGitDiagnostic)
            ?? lines.first
            ?? fallback
        return redactCredentials(in: output)
    }

    private func isActionableGitDiagnostic(_ line: String) -> Bool {
        let value = line.lowercased()
        return value.contains("fatal:")
            || value.contains("error:")
            || value.hasPrefix("remote:")
            || value.contains("authentication")
            || value.contains("permission denied")
    }

    private func redactCredentials(in value: String) -> String {
        value.replacingOccurrences(
            of: #"https?://[^/@[:space:]]+@"#,
            with: "https://***@",
            options: .regularExpression
        )
    }
}
