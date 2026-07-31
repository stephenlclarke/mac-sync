import SwiftUI

struct SyncIssuesView: View {
    @ObservedObject var store: SyncStore
    @State private var filter: SyncIssueFilter = .open
    @State private var selectedIssueID: String?
    @State private var triageNote = ""

    private var filteredIssues: [SyncIssue] {
        switch filter {
        case .open:
            store.syncIssues.filter(\.requiresManualIntervention)
        case .all:
            store.syncIssues
        }
    }

    private var selectedIssue: SyncIssue? {
        if let selectedIssueID,
           let issue = filteredIssues.first(where: { $0.id == selectedIssueID })
        {
            return issue
        }
        return filteredIssues.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sync health")
                        .font(.headline)
                    Text("Active conditions are checked again automatically. Recovered events remain in All.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Picker("Show", selection: $filter) {
                    ForEach(SyncIssueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 10)

                if filteredIssues.isEmpty {
                    emptyState
                } else {
                    List(filteredIssues, selection: $selectedIssueID) { issue in
                        issueRow(issue)
                            .tag(issue.id)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 430)

            if let selectedIssue {
                issueDetail(selectedIssue)
                    .frame(minWidth: 540)
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectFirstIssueIfNeeded()
        }
        .onChange(of: selectedIssueID) { _ in
            loadSelectedIssueNote()
        }
        .onChange(of: store.syncIssues) { _ in
            selectFirstIssueIfNeeded()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: filter == .open ? "checkmark.circle" : "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(filter == .open ? "No active conditions need attention" : "No recorded sync conditions")
                .font(.headline)
            Text(filter == .open
                ? "GitHub and encrypted-secrets checks currently pass, or active conditions have been acknowledged."
                : "Warnings and errors from completed syncs will remain here as history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func issueRow(_ issue: SyncIssue) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: issue.isActive ? issue.severity.systemImage : issue.dispositionSystemImage)
                .foregroundStyle(issue.isActive ? severityColour(issue.severity) : .green)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.message)
                    .lineLimit(2)
                Text(issue.occurrenceCount == 1
                    ? "\(issue.source) · \(issue.recordedAt)"
                    : "\(issue.occurrenceCount) occurrences · latest \(issue.recordedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(issue.dispositionTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dispositionColour(for: issue))
            }
        }
        .padding(.vertical, 3)
    }

    private func issueDetail(_ issue: SyncIssue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Label(issue.severity.title, systemImage: issue.severity.systemImage)
                        .font(.title2.bold())
                        .foregroundStyle(severityColour(issue.severity))
                    Spacer()
                    Label(issue.dispositionTitle, systemImage: issue.dispositionSystemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(dispositionColour(for: issue))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(dispositionColour(for: issue).opacity(0.14), in: Capsule())
                }

                Text(issue.message)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                LabeledContent("Recorded") {
                    Text(issue.recordedAt)
                        .textSelection(.enabled)
                }
                if issue.occurrenceCount > 1 {
                    LabeledContent("First recorded") {
                        Text(issue.firstRecordedAt)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Occurrences") {
                        Text("\(issue.occurrenceCount)")
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("Source") {
                    Text(issue.source)
                        .textSelection(.enabled)
                }

                GroupBox("Recommended next action") {
                    Text(issue.recommendedAction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                if issue.isActive, !issue.recoveryActions.isEmpty {
                    GroupBox("Recovery actions") {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                recoveryButtons(for: issue)
                            }
                            VStack(alignment: .leading) {
                                recoveryButtons(for: issue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !issue.isActive {
                    GroupBox("Current health") {
                        Label(
                            "This condition is no longer present. The occurrence is retained as sync history.",
                            systemImage: "checkmark.circle.fill",
                        )
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let detail = issue.detail {
                    GroupBox("Relevant details") {
                        Text(detail)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                if issue.isActive {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Triage note")
                            .font(.headline)
                        TextEditor(text: $triageNote)
                            .font(.body)
                            .frame(minHeight: 100)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary)
                            }
                        HStack {
                            if let updatedAt = issue.updatedAt {
                                Text("Last triaged \(SyncFormatting.date(updatedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Save Note") {
                                store.updateIssue(issue, disposition: issue.disposition, note: triageNote)
                            }
                            .disabled(triageNote == issue.note)
                        }
                    }
                    HStack {
                        switch issue.disposition {
                        case .open:
                            Button("Acknowledge") {
                                store.updateIssue(issue, disposition: .acknowledged, note: triageNote)
                            }
                            .help("Keep this issue in the record and clear its Dock badge count.")
                            Button("Resolve") {
                                store.updateIssue(issue, disposition: .resolved, note: triageNote)
                            }
                        case .acknowledged, .resolved:
                            Button("Reopen") {
                                store.updateIssue(issue, disposition: .open, note: triageNote)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func recoveryButtons(for issue: SyncIssue) -> some View {
        ForEach(Array(issue.recoveryActions.enumerated()), id: \.element.id) { index, action in
            if index == 0 {
                recoveryButton(action)
                    .buttonStyle(.borderedProminent)
            } else {
                recoveryButton(action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func recoveryButton(_ action: SyncIssueRecoveryAction) -> some View {
        Button {
            store.performRecoveryAction(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .disabled(store.isRunning || store.isCheckingGitHubAccess)
    }

    private func selectFirstIssueIfNeeded() {
        guard !filteredIssues.isEmpty else {
            selectedIssueID = nil
            triageNote = ""
            return
        }
        if let selectedIssueID,
           filteredIssues.contains(where: { $0.id == selectedIssueID })
        {
            loadSelectedIssueNote()
            return
        }
        selectedIssueID = filteredIssues.first?.id
        loadSelectedIssueNote()
    }

    private func loadSelectedIssueNote() {
        triageNote = selectedIssue?.note ?? ""
    }

    private func severityColour(_ severity: SyncIssueSeverity) -> Color {
        severity == .error ? .red : .orange
    }

    private func dispositionColour(_ disposition: SyncIssueDisposition) -> Color {
        switch disposition {
        case .open:
            .red
        case .acknowledged:
            .blue
        case .resolved:
            .green
        }
    }

    private func dispositionColour(for issue: SyncIssue) -> Color {
        issue.isActive ? dispositionColour(issue.disposition) : .green
    }
}

private enum SyncIssueFilter: String, CaseIterable, Identifiable {
    case open
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .open:
            "Needs attention"
        case .all:
            "All"
        }
    }
}
