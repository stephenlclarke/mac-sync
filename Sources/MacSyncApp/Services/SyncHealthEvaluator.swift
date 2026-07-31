import Foundation
import MacSyncCore

protocol SyncHealthCommandRunning {
    func run(_ executable: String, _ arguments: [String]) -> CommandResult
    func commandExists(_ command: String) -> Bool
}

struct SystemSyncHealthCommandRunner: SyncHealthCommandRunning {
    let runner: ProcessRunner

    func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        runner.run(executable, arguments)
    }

    func commandExists(_ command: String) -> Bool {
        runner.commandExists(command)
    }
}

struct SyncHealthEvaluator {
    typealias KeychainLookup = (
        _ service: String,
        _ account: String,
    ) -> MacSyncKeychainIdentityLookup

    private let environment: [String: String]
    private let runner: any SyncHealthCommandRunning
    private let keychainLookup: KeychainLookup
    private let fileManager: FileManager

    init(
        environment: [String: String],
        runner: (any SyncHealthCommandRunning)? = nil,
        keychainLookup: KeychainLookup? = nil,
        fileManager: FileManager = .default,
    ) {
        self.environment = environment
        self.runner = runner ?? SystemSyncHealthCommandRunner(
            runner: ProcessRunner(environment: environment),
        )
        self.keychainLookup = keychainLookup ?? { service, account in
            MacSyncKeychain.identity(
                service: service,
                account: account,
                allowInteraction: false,
            )
        }
        self.fileManager = fileManager
    }

    func activeConditionCodes(in overview: SyncOverview) -> Set<SyncHealthConditionCode> {
        var active = recordedConditionCodes(in: overview)
        guard !active.isEmpty else { return [] }

        reconcileRemoteConditions(&active, overview: overview)
        reconcileEncryptedSecretsConditions(&active, overview: overview)
        return active
    }

    private func recordedConditionCodes(
        in overview: SyncOverview,
    ) -> Set<SyncHealthConditionCode> {
        if !overview.status.conditions.isEmpty {
            return Set(overview.status.conditions.map(\.code))
        }
        if let latest = overview.history.first,
           let conditions = latest.conditions,
           !conditions.isEmpty
        {
            return Set(conditions.map(\.code))
        }
        return Set(
            (overview.status.warnings + overview.status.errors)
                .compactMap(Self.legacyConditionCode),
        )
    }

    private func reconcileRemoteConditions(
        _ active: inout Set<SyncHealthConditionCode>,
        overview: SyncOverview,
    ) {
        let remoteCodes: Set<SyncHealthConditionCode> = [
            .remoteAuthenticationFailed,
            .remoteRefreshFailed,
            .remoteUnavailable,
        ]
        if !active.isDisjoint(with: remoteCodes),
           remoteIsReachable(repository: overview.configuration.dataRepository)
        {
            active.subtract(remoteCodes)
        }

        if active.contains(.remoteRefreshBlockedByLocalChanges),
           overview.status.currentLocalChanges?.isEmpty == true
        {
            active.remove(.remoteRefreshBlockedByLocalChanges)
        }

        if active.contains(.remoteConfigurationMissing) {
            let remote = runner.run(
                "git",
                ["-C", overview.configuration.dataRepository, "remote", "get-url", "origin"],
            )
            if remote.status == 0, !remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                active.remove(.remoteConfigurationMissing)
            }
        }
    }

    private func remoteIsReachable(repository: String) -> Bool {
        let configured = runner.run("git", ["-C", repository, "ls-remote", "origin", "HEAD"])
        if configured.status == 0 {
            return true
        }
        let remote = runner.run("git", ["-C", repository, "remote", "get-url", "origin"])
        guard remote.status == 0,
              let sshRemote = MacSyncPaths.githubSSHRemoteURL(
                  remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              )
        else {
            return false
        }
        return runner.run("git", ["ls-remote", sshRemote, "HEAD"]).status == 0
    }

    private func reconcileEncryptedSecretsConditions(
        _ active: inout Set<SyncHealthConditionCode>,
        overview: SyncOverview,
    ) {
        let runtimeCommands = ["age", "age-keygen", "gzip", "gtar"]
        let runtimeAvailable = runtimeCommands.allSatisfy(runner.commandExists)
        if runtimeAvailable {
            active.remove(.encryptedSecretsRuntimeUnavailable)
        }

        let account = environment["MAC_SYNC_KEYCHAIN_ACCOUNT"]
            ?? environment["USER"]
            ?? NSUserName()
        let service = environment["MAC_SYNC_KEYCHAIN_SERVICE"] ?? "mac-sync age identity"
        let lookup = keychainLookup(service, account)
        guard lookup.availability == .available, let identity = lookup.identity else {
            return
        }
        active.remove(.encryptedSecretsIdentityMissing)
        active.remove(.encryptedSecretsIdentityUnavailable)
        guard runtimeAvailable else { return }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("mac-sync-health-\(UUID().uuidString)")
        let identityURL = temporaryDirectory.appendingPathComponent("identity.txt")
        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true,
            )
            defer { try? fileManager.removeItem(at: temporaryDirectory) }
            guard fileManager.createFile(
                atPath: identityURL.path,
                contents: Data(identity.utf8),
                attributes: [.posixPermissions: NSNumber(value: 0o600)],
            ) else {
                return
            }
        } catch {
            return
        }

        let recipient = runner.run("age-keygen", ["-y", identityURL.path])
        let recipientsFile = "\(overview.configuration.dataRepository)/machines/_shared/config/age-recipients.txt"
        if recipient.status == 0,
           readConfigLines(recipientsFile).contains(
               recipient.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
           )
        {
            active.remove(.encryptedSecretsIdentityUntrusted)
        }

        let archive = "\(overview.configuration.dataRepository)/machines/\(overview.configuration.machineName)/secrets/secrets.tar.gz.age"
        guard fileManager.fileExists(atPath: archive) else {
            active.remove(.encryptedSecretsSnapshotSkipped)
            return
        }
        let decrypt = runner.run(
            "/bin/sh",
            [
                "-c",
                "age -d -i \(ShellQuoter.quote(identityURL.path)) \(ShellQuoter.quote(archive)) > /dev/null",
            ],
        )
        if decrypt.status == 0 {
            active.remove(.encryptedSecretsSnapshotSkipped)
        }
    }

    private func readConfigLines(_ path: String) -> Set<String> {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return Set(text.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value.hasPrefix("#") ? nil : value
        })
    }

    private static func legacyConditionCode(_ message: String) -> SyncHealthConditionCode? {
        if message.contains("could not pull machines repo") {
            return .remoteRefreshFailed
        }
        if message.contains("current machine snapshot has local changes")
            || message.contains("local repo has local changes")
        {
            return .remoteRefreshBlockedByLocalChanges
        }
        if message.contains("missing local Keychain age identity")
            || message.contains("no local Keychain age identity")
        {
            return .encryptedSecretsIdentityMissing
        }
        if message.contains("Keychain age identity requires user interaction")
            || message.contains("Keychain age identity is unavailable")
        {
            return .encryptedSecretsIdentityUnavailable
        }
        if message.contains("encrypted secrets snapshot cannot be decrypted") {
            return .encryptedSecretsSnapshotSkipped
        }
        if message.contains("age, age-keygen, gzip, or gtar not found")
            || message.contains("encrypted-secrets tools are unavailable")
        {
            return .encryptedSecretsRuntimeUnavailable
        }
        return nil
    }
}
