import SwiftUI

@MainActor
struct LocalDiagnosisView: View {
    let overview: SyncOverview
    @StateObject private var controller: LocalDiagnosisController
    @Environment(\.dismiss) private var dismiss

    init(overview: SyncOverview, controller: LocalDiagnosisController = LocalDiagnosisController()) {
        self.overview = overview
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("On-device diagnosis", systemImage: "sparkles")
                .font(.title2.bold())
            Text(
                """
                Runs only on this Mac using Apple's on-device model. No cloud fallback, file contents, \
                credentials, raw logs or file paths. It cannot sync, change settings, acknowledge warnings \
                or resolve conflicts.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(
                """
                The AI organises verified findings. Counts and explanations come from Mac Sync's records, \
                not generated prose. An inconsistent answer is discarded.
                """
            )
            .font(.callout)

            if controller.isRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading local records and preparing the diagnosis…")
                    Spacer()
                    Button("Cancel") { controller.cancel() }
                }
            }
            if let message = controller.message {
                Label(message, systemImage: "info.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let capturedAt = controller.capturedAt {
                        Text(
                            """
                            Review queue read \(SyncFormatting.date(capturedAt)). \
                            Last recorded run: \(controller.recordedRunFinishedAt ?? "not available").
                            """
                        )
                        .font(.callout)
                        Text(
                            "This is a saved reading, not a live connection test. Generate again after another sync."
                        )
                        .font(.callout)
                    }
                    if let facts = controller.evidence {
                        GroupBox(findingsTitle) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(controller.orderedFindings ?? facts.findings) { finding in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(finding.title).font(.headline)
                                        Text(finding.detail)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(5)
                            .textSelection(.enabled)
                        }
                    }
                    if controller.evidence != nil {
                        GroupBox("What remains unknown") {
                            Text(
                                """
                                These records do not establish who edited a file or when. A generic path/link \
                                warning does not identify the precise failed safety check. Unknown information \
                                is not treated as the cause of the warning.
                                """
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(
                    """
                    Apple Intelligence and macOS 26 or later are required. macOS may need an initial \
                    model download; prepared models work offline. This feature never disconnects your network.
                    """
                )
                .font(.callout)
                Spacer()
                Button("Try Again") { controller.start(overview: overview) }
                    .disabled(controller.isRunning)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 650, idealWidth: 760, minHeight: 540, idealHeight: 700)
        .onAppear { controller.start(overview: overview) }
        .onDisappear { controller.cancel() }
    }

    private var findingsTitle: String {
        controller.orderedFindings == nil
            ? "Verified records (not an AI diagnosis)"
            : "On-device diagnosis · verified findings"
    }
}
