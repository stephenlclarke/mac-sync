import Foundation
import MacSyncCore

struct SyncHealthVerificationStore {
    private struct Record: Codable {
        let encryptedSecretsStatusFinishedAt: String
    }

    private let storageURL: URL
    private let fileManager: FileManager

    init(configuration: SyncConfiguration, fileManager: FileManager = .default) {
        storageURL = URL(fileURLWithPath: configuration.statusDirectory)
            .appendingPathComponent("health-verifications")
            .appendingPathComponent("\(configuration.machineName).json")
        self.fileManager = fileManager
    }

    func encryptedSecretsWereVerified(for overview: SyncOverview) -> Bool {
        guard let finishedAt = overview.status.finishedAt,
              let data = try? Data(contentsOf: storageURL),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else {
            return false
        }
        return record.encryptedSecretsStatusFinishedAt == finishedAt
    }

    func markEncryptedSecretsVerified(for overview: SyncOverview) throws {
        guard let finishedAt = overview.status.finishedAt else { return }
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(
            Record(encryptedSecretsStatusFinishedAt: finishedAt),
        ).write(to: storageURL, options: .atomic)
    }
}
