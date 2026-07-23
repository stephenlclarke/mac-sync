import MacSyncCore
import SwiftUI

struct SyncHistoryView: View {
    @ObservedObject var store: SyncStore
    @State private var selectedRecordID: String?
    @State private var filter: HistoryFilter = .all

    private var selectedRecord: SyncHistoryRecord? {
        if let selectedRecordID,
           let selected = store.overview.history.first(where: { $0.id == selectedRecordID })
        {
            return selected
        }
        return store.overview.history.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sync history")
                        .font(.headline)
                    Text("Completed uploads and downloads recorded on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                if store.overview.history.isEmpty {
                    historyEmptyState(
                        title: "No sync history yet",
                        systemImage: "clock.arrow.circlepath",
                        detail: "Run a sync or restore to create the first local record."
                    )
                } else {
                    List(store.overview.history, selection: $selectedRecordID) { record in
                        historyRow(record)
                            .tag(record.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 290, idealWidth: 340, maxWidth: 420)

            if let selectedRecord {
                recordDetail(selectedRecord)
                    .frame(minWidth: 520)
            } else {
                historyEmptyState(
                    title: "No sync history yet",
                    systemImage: "clock.arrow.circlepath",
                    detail: "Completed syncs and restores will appear here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func historyRow(_ record: SyncHistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: actionImage(for: record))
                .foregroundStyle(resultColour(for: record))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(actionTitle(for: record))
                    .fontWeight(.medium)
                Text("\(record.entries.count) file event\(record.entries.count == 1 ? "" : "s") · \(record.finishedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func recordDetail(_ record: SyncHistoryRecord) -> some View {
        let entries = filteredEntries(for: record)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Label(actionTitle(for: record), systemImage: actionImage(for: record))
                        .font(.title2.bold())
                        .foregroundStyle(resultColour(for: record))
                    Spacer()
                    Text(record.result == .success ? "Completed" : "Failed")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(resultColour(for: record).opacity(0.14), in: Capsule())
                }
                Text("Started \(record.startedAt) · finished \(record.finishedAt) · \(SyncFormatting.duration(record.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sourceMachine = record.sourceMachine {
                    Text("Source snapshot: \(sourceMachine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                transferSummary(record)
            }
            .padding(20)

            Picker("Show", selection: $filter) {
                ForEach(HistoryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if entries.isEmpty {
                historyEmptyState(
                    title: "No \(filter.title.lowercased()) events",
                    systemImage: filter.systemImage,
                    detail: "This run did not record any matching file events."
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    transferRow(entry)
                }
                .listStyle(.inset)
            }
        }
    }

    private func historyEmptyState(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func transferSummary(_ record: SyncHistoryRecord) -> some View {
        HStack(spacing: 10) {
            summaryCount("Uploads", count: transferCount(record, direction: .upload), image: "arrow.up.circle")
            summaryCount("Downloads", count: transferCount(record, direction: .download), image: "arrow.down.circle")
            summaryCount("New", count: outcomeCount(record, outcome: .new), image: "plus.circle")
            summaryCount("Updated", count: outcomeCount(record, outcome: .updated), image: "arrow.triangle.2.circlepath")
            summaryCount("Skipped", count: outcomeCount(record, outcome: .skipped), image: "forward.end")
        }
    }

    private func summaryCount(_ title: String, count: Int, image: String) -> some View {
        Label("\(count) \(title.lowercased())", systemImage: image)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func transferRow(_ entry: SyncHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entryImage(for: entry))
                .foregroundStyle(entryColour(for: entry))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.path)
                    .textSelection(.enabled)
                Text("\(entry.direction.rawValue.capitalized) · \(entry.outcome.rawValue.capitalized)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entryColour(for: entry))
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.source) → \(entry.destination)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func actionTitle(for record: SyncHistoryRecord) -> String {
        switch record.action {
        case .sync:
            "Published this Mac"
        case .restore:
            "Restored to this Mac"
        }
    }

    private func actionImage(for record: SyncHistoryRecord) -> String {
        switch record.action {
        case .sync:
            "arrow.up.circle.fill"
        case .restore:
            "arrow.down.circle.fill"
        }
    }

    private func resultColour(for record: SyncHistoryRecord) -> Color {
        record.result == .success ? .green : .red
    }

    private func transferCount(_ record: SyncHistoryRecord, direction: SyncHistoryTransferDirection) -> Int {
        record.entries.filter { $0.direction == direction }.count
    }

    private func outcomeCount(_ record: SyncHistoryRecord, outcome: SyncHistoryTransferOutcome) -> Int {
        record.entries.filter { $0.outcome == outcome }.count
    }

    private func filteredEntries(for record: SyncHistoryRecord) -> [SyncHistoryEntry] {
        switch filter {
        case .all:
            record.entries
        case .uploads:
            record.entries.filter { $0.direction == .upload }
        case .downloads:
            record.entries.filter { $0.direction == .download }
        case .new:
            record.entries.filter { $0.outcome == .new }
        case .updated:
            record.entries.filter { $0.outcome == .updated }
        case .skipped:
            record.entries.filter { $0.outcome == .skipped }
        }
    }

    private func entryImage(for entry: SyncHistoryEntry) -> String {
        switch entry.outcome {
        case .new:
            "plus.circle.fill"
        case .updated:
            "arrow.triangle.2.circlepath.circle.fill"
        case .removed:
            "minus.circle.fill"
        case .skipped:
            "forward.end.circle"
        }
    }

    private func entryColour(for entry: SyncHistoryEntry) -> Color {
        switch entry.outcome {
        case .new:
            .green
        case .updated:
            .blue
        case .removed:
            .orange
        case .skipped:
            .secondary
        }
    }
}

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case uploads
    case downloads
    case new
    case updated
    case skipped

    var id: String {
        rawValue
    }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .all:
            "tray.full"
        case .uploads:
            "arrow.up.circle"
        case .downloads:
            "arrow.down.circle"
        case .new:
            "plus.circle"
        case .updated:
            "arrow.triangle.2.circlepath"
        case .skipped:
            "forward.end"
        }
    }
}
