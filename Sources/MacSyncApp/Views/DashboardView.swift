import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: SyncStore
    let openManualTriage: () -> Void
    @State private var localChangesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your sync control room")
                        .font(.largeTitle.bold())
                    Text("Inspect the snapshot for this Mac, browse other Macs, and safely publish or copy selected files.")
                        .foregroundStyle(.secondary)
                }

                statusCard

                if store.openIssueCount > 0 {
                    manualTriageCard
                }

                if shouldShowActivityCard {
                    activityCard
                }

                HStack(alignment: .top, spacing: 14) {
                    MetricCard(
                        title: "This Mac",
                        value: store.overview.configuration.machineName,
                        detail: "\(store.overview.currentMachine?.fileCount ?? 0) snapshot files",
                        systemImage: "laptopcomputer"
                    )
                    MetricCard(
                        title: "Other Macs",
                        value: "\(store.overview.peerMachines.count)",
                        detail: "available snapshots",
                        systemImage: "network"
                    )
                    MetricCard(
                        title: "Sync selection",
                        value: "\(store.selectedPaths.count)",
                        detail: store.hasUnsavedSelection ? "unsaved changes" : "saved paths",
                        systemImage: "checklist"
                    )
                    MetricCard(
                        title: "Sync history",
                        value: "\(store.overview.history.count)",
                        detail: "completed local runs",
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                if !store.overview.peerMachines.isEmpty {
                    GroupBox("Available machine snapshots") {
                        VStack(spacing: 0) {
                            ForEach(store.overview.peerMachines) { machine in
                                HStack {
                                    Image(systemName: "laptopcomputer")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(machine.computerName ?? machine.name)
                                        Text("\(machine.fileCount) files · \(SyncFormatting.bytes(machine.totalByteCount)) · \(SyncFormatting.date(machine.modifiedAt))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if machine.hasEncryptedSecrets {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.secondary)
                                            .help("An encrypted secrets archive is available.")
                                    }
                                }
                                .padding(.vertical, 7)
                                if machine.id != store.overview.peerMachines.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                if store.isRunning || !store.commandOutput.isEmpty {
                    GroupBox("Live command activity") {
                        LiveCommandActivityView(
                            output: store.commandOutput,
                            isRunning: store.isRunning
                        )
                    }
                }

            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var statusCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: store.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : store.overview.status.result.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(statusColour)

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.activeAction?.title ?? store.overview.status.result.title)
                        .font(.title3.weight(.semibold))
                    Text(statusDetail)
                        .foregroundStyle(.secondary)
                    if let finishedAt = store.overview.status.finishedAt {
                        Text("Last finished \(finishedAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if store.isRunning {
                    Button("Stop Sync", role: .destructive) {
                        store.stopSync()
                    }
                } else {
                    Button("Sync Now") {
                        store.syncSelection()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(4)
        } label: {
            Text("Sync status")
        }
    }

    private var activityCard: some View {
        GroupBox("Latest warnings and errors") {
            if visibleStatusWarnings.isEmpty, visibleStatusErrors.isEmpty {
                Text("No recorded warnings or errors from the last sync.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleStatusErrors, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    ForEach(visibleStatusWarnings, id: \.self) { message in
                        if isCurrentMachineLocalChangesWarning(message) {
                            localChangesWarning
                        } else {
                            Label(message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private var manualTriageCard: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(store.openIssueCount) issue\(store.openIssueCount == 1 ? "" : "s") need manual triage")
                        .fontWeight(.semibold)
                    Text("Syncs continue in the background. Review, acknowledge, or resolve these items when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Issues") {
                    openManualTriage()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(4)
        } label: {
            Text("Manual triage")
        }
    }

    @ViewBuilder
    private var localChangesWarning: some View {
        let status = store.overview.status
        if localChangesWarningIsResolved, status.recordedLocalChanges.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Label("Resolved: this Mac's snapshot is currently clean", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(historicalWarningDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            DisclosureGroup(isExpanded: $localChangesExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !status.recordedLocalChanges.isEmpty {
                        localChangesList(
                            title: "Changes recorded when the pull was skipped",
                            changes: status.recordedLocalChanges
                        )
                    }

                    if let currentChanges = status.currentLocalChanges {
                        if currentChanges.isEmpty {
                            Text(historicalWarningDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if !status.recordedLocalChanges.isEmpty {
                                Divider()
                            }
                            localChangesList(
                                title: "Changes still present now",
                                changes: currentChanges
                            )
                            Text("The next sync will publish this Mac's selected files but will keep the pre-sync pull paused until these changes are committed or reverted.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Mac Sync cannot inspect the current snapshot. Use Refresh after the mac-sync-data checkout is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 4)
            } label: {
                Label(localChangesWarningTitle, systemImage: "exclamationmark.circle")
                    .foregroundStyle(localChangesWarningIsResolved ? .green : .orange)
            }
            .tint(localChangesWarningIsResolved ? .green : .orange)
        }
    }

    private func localChangesList(title: String, changes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(changes, id: \.self) { change in
                Text(change)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var localChangesWarningTitle: String {
        if localChangesWarningIsResolved {
            return "Resolved: this Mac's snapshot is currently clean"
        }
        let count = store.overview.status.currentLocalChanges?.count
            ?? store.overview.status.recordedLocalChanges.count
        return count == 0
            ? "Git pull was skipped; snapshot state needs checking"
            : "Git pull was skipped; \(count) local snapshot \(count == 1 ? "change" : "changes") need attention"
    }

    private var localChangesWarningIsResolved: Bool {
        store.overview.status.currentLocalChanges?.isEmpty == true
    }

    private var historicalWarningDetail: String {
        if let finishedAt = store.overview.status.finishedAt {
            return "The pre-sync pull was skipped at \(finishedAt), but those changes are no longer present. The next sync will pull normally."
        }
        return "The pre-sync pull was skipped during the last recorded sync, but those changes are no longer present. The next sync will pull normally."
    }

    private func isCurrentMachineLocalChangesWarning(_ message: String) -> Bool {
        message.contains("current machine snapshot has local changes")
    }

    private var visibleStatusErrors: [String] {
        store.overview.status.errors.filter { !hasOpenManualTriageIssue(for: $0) }
    }

    private var visibleStatusWarnings: [String] {
        store.overview.status.warnings.filter { !hasOpenManualTriageIssue(for: $0) }
    }

    private var shouldShowActivityCard: Bool {
        store.openIssueCount == 0 || !visibleStatusErrors.isEmpty || !visibleStatusWarnings.isEmpty
    }

    private func hasOpenManualTriageIssue(for message: String) -> Bool {
        store.syncIssues.contains {
            $0.requiresManualIntervention && $0.message == message
        }
    }

    private var statusDetail: String {
        if store.isRunning {
            return "The app is monitoring a live mac-sync process."
        }
        if let count = store.overview.status.updatedFileCount {
            return "\(count) files updated in \(SyncFormatting.duration(store.overview.status.durationSeconds))."
        }
        return "No completed sync has been recorded on this Mac yet."
    }

    private var statusColour: Color {
        if store.isRunning {
            return .blue
        }
        switch store.overview.status.result {
        case .success:
            return .green
        case .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
