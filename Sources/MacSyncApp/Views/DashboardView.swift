import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: SyncStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your sync control room")
                        .font(.largeTitle.bold())
                    Text("Inspect the snapshot for this Mac, browse other Macs, and safely publish or restore selected files.")
                        .foregroundStyle(.secondary)
                }

                statusCard

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

                activityCard
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
            if store.overview.status.warnings.isEmpty, store.overview.status.errors.isEmpty {
                Text("No recorded warnings or errors from the last sync.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.overview.status.errors, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    ForEach(store.overview.status.warnings, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
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
