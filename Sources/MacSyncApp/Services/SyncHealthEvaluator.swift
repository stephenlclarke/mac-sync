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
    typealias EncryptedSecretsVerificationLookup = (_ overview: SyncOverview) -> Bool

    private let environment: [String: String]
    private let runner: any SyncHealthCommandRunning
    private let encryptedSecretsVerificationLookup: EncryptedSecretsVerificationLookup

    init(
        environment: [String: String],
        runner: (any SyncHealthCommandRunning)? = nil,
        encryptedSecretsVerificationLookup: EncryptedSecretsVerificationLookup? = nil,
    ) {
        self.environment = environment
        self.runner = runner ?? SystemSyncHealthCommandRunner(
            runner: ProcessRunner(environment: environment),
        )
        self.encryptedSecretsVerificationLookup = encryptedSecretsVerificationLookup ?? { overview in
            SyncHealthVerificationStore(configuration: overview.configuration)
                .encryptedSecretsWereVerified(for: overview)
        }
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
                .compactMap(SyncHealthMessage.conditionCode),
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
                let branch = runner.run(
                    "git",
                    ["-C", overview.configuration.dataRepository, "symbolic-ref", "--quiet", "HEAD"],
                )
                let reference = branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if branch.status == 0, reference.hasPrefix("refs/heads/"), reference.count > "refs/heads/".count {
                    active.remove(.remoteConfigurationMissing)
                }
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

        if active.contains(.encryptedSecretsIdentityMissing), keychainIdentityMetadataExists() {
            active.remove(.encryptedSecretsIdentityMissing)
        }
        if encryptedSecretsVerificationLookup(overview) {
            active.subtract([
                .encryptedSecretsIdentityMissing,
                .encryptedSecretsIdentityUnavailable,
                .encryptedSecretsIdentityUntrusted,
                .encryptedSecretsSnapshotSkipped,
            ])
        }
    }

    /// `SecItemCopyMatching` can present authentication UI for a legacy Login
    /// Keychain ACL even when it requests only a persistent reference. The
    /// `security` command's default find mode returns item metadata and does
    /// not request password data; never add its `-g` or `-w` flags here.
    private func keychainIdentityMetadataExists() -> Bool {
        let account = environment["MAC_SYNC_KEYCHAIN_ACCOUNT"]
            ?? environment["USER"]
            ?? NSUserName()
        let service = environment["MAC_SYNC_KEYCHAIN_SERVICE"] ?? "mac-sync age identity"
        return runner.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", service, "-a", account],
        ).status == 0
    }
}
