import MacSyncCore

enum SyncHealthActivity: Equatable {
    case checking
    case active
    case recovered

    static func resolve(
        conditionCode: SyncHealthConditionCode?,
        recordedAsActive: Bool = true,
        activeConditionCodes: Set<SyncHealthConditionCode>?,
    ) -> SyncHealthActivity {
        guard recordedAsActive else { return .recovered }
        guard let conditionCode else { return .active }
        guard let activeConditionCodes else { return .checking }
        return activeConditionCodes.contains(conditionCode) ? .active : .recovered
    }
}

enum SyncHealthMessage {
    static func conditionCode(for message: String) -> SyncHealthConditionCode? {
        if isLocalChangesWarning(message) {
            return .remoteRefreshBlockedByLocalChanges
        }
        if message.contains("could not pull machines repo") {
            return .remoteRefreshFailed
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
        if message.contains("encrypted-secrets tools are unavailable")
            || message.contains("age, age-keygen, gzip, or gtar not found")
        {
            return .encryptedSecretsRuntimeUnavailable
        }
        if message.contains("encrypted secrets snapshot cannot be decrypted") {
            return .encryptedSecretsSnapshotSkipped
        }
        return nil
    }

    static func isLocalChangesWarning(_ message: String) -> Bool {
        message.contains("current machine snapshot has local changes")
            || message.contains("local repo has local changes")
    }
}
