import Foundation
import MacSyncCore

/// App-owned, advisory text only. There are no commands, callbacks or file APIs.
struct LocalDiagnosisAdvice: Equatable, Sendable {
    let summary: String
    let steps: [LocalDiagnosisFinding]

    init(
        status: SyncStatus,
        storageKind: BackupStorageKind,
        inventory: IncomingReviewInventory?,
        publishExitStatus: Int32?
    ) {
        guard let inventory else {
            summary = "Review counts are unknown, not zero. No file-level repair can be proposed yet."
            steps = [.init(
                id: "inspect_inventory", title: "Read the review inventory first",
                detail: """
                The local review ledger is missing or unreadable. Inspect Incoming Changes and the local \
                records before deciding which files need attention. Do not assume there are no deletions or \
                start a sync to resolve unknown choices.
                """
            )]
            return
        }
        let recordSteps = Self.recordSteps(
            status: status,
            storageKind: storageKind,
            publishExitStatus: publishExitStatus
        )
        if inventory.total == 0 {
            if recordSteps.isEmpty {
                summary = "No repair is indicated by these records. No incoming changes need review."
            } else if recordSteps.map(\.id) == ["provider_upload"] {
                summary = "No incoming changes need review. Provider upload confirmation is separate from a local save."
            } else {
                summary = "No incoming changes need review. The saved records still need attention as described below."
            }
            steps = recordSteps
            return
        }
        summary = "Suggested next steps for \(inventory.total) review items. This is advice only; nothing is applied."
        steps = Self.fileSteps(inventory) + recordSteps + [.init(
            id: "approve_choices", title: "Review and approve each choice",
            detail: """
            You must decide which contents to keep before applying targeted changes in Incoming Changes. \
            Do not use blanket resets, recloning, force-pushing, credential replacement or warning \
            dismissal as a conflict fix. This diagnosis cannot apply any choice.
            """
        ), .init(
            id: "verify_after_approval", title: "Verify after approved changes",
            detail: storageKind == .cloudFolder
                ? """
                Only after you approve and apply the choices, use a separate, later sync to share them. \
                Check remaining review items, the local save, provider upload and the receiving Mac. A local \
                folder save alone does not confirm upload.
                """
                : """
                Only after you approve and apply the choices, use a separate, later sync to share them. \
                Check remaining review items, the publish result and the receiving Mac. Retrying sync now \
                does not choose conflict winners.
                """
        )]
    }

    private static func fileSteps(_ inventory: IncomingReviewInventory) -> [LocalDiagnosisFinding] {
        var steps: [LocalDiagnosisFinding] = [.init(
            id: "preserve_versions", title: "Preserve the available versions first",
            detail: """
            Before any approved replacement or deletion, keep independent copies of the available local \
            and incoming versions on both Macs. An incoming deletion may have no incoming file to copy.
            """
        )]
        if inventory.conflicts > 0 {
            steps.append(.init(
                id: "compare_conflicts", title: "Compare \(inventory.conflicts) file-version conflicts",
                detail: """
                Inspect each pair's contents or diff. Keep This Mac chooses your local copy; Use Incoming \
                Version chooses the other copy. Keep Both preserves separate copies when unsure; it does not \
                merge contents. Neither timestamps nor this diagnosis determine which version is correct. Do \
                not delete a conflict as a shortcut.
                """
            ))
        }
        if inventory.pathOrLink > 0 {
            steps.append(.init(
                id: "inspect_paths", title: "Inspect \(inventory.pathOrLink) path or link review items",
                detail: """
                Check the actual file kind, linked parents, target and selected scope. The precise failed \
                safety check is unknown. Do not blindly follow or remove a link or write outside the \
                selected safe scope. Consider targeted manual copy or recovery only after inspection and \
                preservation.
                """
            ))
        }
        steps.append(deletionStep(inventory.deletions))
        if inventory.reviewPolicy > 0 || inventory.other > 0 {
            steps.append(.init(
                id: "inspect_other_reviews", title: "Inspect other held review items",
                detail: """
                \(inventory.reviewPolicy) items are held by review-only policy and \(inventory.other) have \
                another recorded reason. Read each reason before choosing a version. These counts do not \
                establish an edit conflict or a deletion.
                """
            ))
        }
        return steps
    }

    private static func deletionStep(_ count: Int) -> LocalDiagnosisFinding {
        .init(
            id: "deletion_decisions",
            title: count == 0 ? "No deletion action is needed" : "Review \(count) explicit deletions separately",
            detail: count == 0
                ? """
                There are 0 pending deletions. A path/link item or a generic warning is not a deletion \
                record. Do not delete files to clear this review queue.
                """
                : """
                Each of these entries is explicitly marked as a deletion. Decide separately whether to keep \
                the local file or approve its deletion, after preserving the available copy. Nothing here \
                authorises deletion.
                """
        )
    }

    private static func recordSteps(
        status: SyncStatus, storageKind: BackupStorageKind, publishExitStatus: Int32?
    ) -> [LocalDiagnosisFinding] {
        var steps: [LocalDiagnosisFinding] = []
        if storageKind == .cloudFolder {
            steps.append(.init(
                id: "provider_upload", title: "Cloud upload remains unconfirmed",
                detail: """
                The app can report a local folder save, not the provider's completed upload. If you need \
                confirmation, inspect the cloud provider's status. Unconfirmed upload is not proof of \
                failure and is not a Git repair problem.
                """
            ))
        } else if let publishExitStatus, publishExitStatus != 0 {
            steps.append(.init(
                id: "inspect_publish", title: "Inspect the recorded publish failure",
                detail: """
                The saved Git publish exited with status \(publishExitStatus). Read its specific diagnostic \
                before proposing a targeted remedy. An exit status alone does not prove an authentication or \
                network fault. Diagnosis does not test the connection or retry publication. Verify \
                publication separately after any approved remedy.
                """
            ))
        } else if publishExitStatus == nil {
            steps.append(.init(
                id: "inspect_publish_record", title: "The publish outcome is unknown",
                detail: """
                Read the saved run details before claiming an upload succeeded or failed. Missing \
                publication evidence is not a reason to reset the repository, replace credentials or retry \
                blindly.
                """
            ))
        }
        if status.result != .success || status.errorCount > 0 || !status.conditions.isEmpty {
            steps.append(.init(
                id: "inspect_recorded_health", title: "Read the saved health details",
                detail: """
                The saved run result, errors or recognised health conditions need inspection in Sync Health \
                and Sync History. They are not live checks. Use the recorded cause to choose a targeted next \
                step; do not infer one from missing information or perform a blanket repair.
                """
            ))
        }
        return steps
    }
}
