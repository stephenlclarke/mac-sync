import Foundation
@testable import MacSyncApp
import MacSyncCore

func diagnosisStatus(
    conditions: [SyncHealthCondition] = [],
    commands: [SyncCommandDiagnostic]? = nil
) -> SyncStatus {
    .init(
        result: .success,
        startedAt: nil,
        finishedAt: "2026-11-23 14:42:54 GMT",
        durationSeconds: nil,
        updatedFileCount: nil,
        updatedByteCount: nil,
        storageFileCount: nil,
        storageByteCount: nil,
        warningCount: 1,
        errorCount: 0,
        lastCommit: nil,
        remoteRepository: "PRIVATE_VALUE",
        warnings: ["Deletions were not applied automatically. PRIVATE_VALUE"],
        errors: [],
        conditions: conditions,
        commandDiagnostics: commands ?? [.init(
            step: "Publishing the data repository",
            command: "git push",
            attempt: 1,
            exitStatus: 0,
            output: ""
        )],
        recordedLocalChanges: ["PRIVATE_VALUE"],
        currentLocalChanges: nil
    )
}
