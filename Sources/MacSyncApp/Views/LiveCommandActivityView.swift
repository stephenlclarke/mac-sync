import SwiftUI

struct LiveCommandActivityView: View {
    let output: String
    let isRunning: Bool

    private var lines: [CommandActivityLine] {
        CommandActivityPresentation.lines(for: output)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            activityLegend

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if lines.isEmpty {
                            Text("A mac-sync process is active. This app will refresh its completion state automatically.")
                                .foregroundStyle(.secondary)
                                .id("activity-empty")
                        } else {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(colour(for: line.tone))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    scrollToLatest(using: proxy)
                }
                .onChange(of: output) { _ in
                    guard isRunning else { return }
                    scrollToLatest(using: proxy)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private var activityLegend: some View {
        HStack(spacing: 12) {
            legend("New", tone: .new)
            legend("Updated", tone: .updated)
            legend("Skipped", tone: .skipped)
            legend("Warning", tone: .warning)
            legend("Error", tone: .error)
        }
        .font(.caption2)
    }

    private func legend(_ title: String, tone: CommandActivityTone) -> some View {
        Label(title, systemImage: "circle.fill")
            .foregroundStyle(colour(for: tone))
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                if let latest = lines.last {
                    proxy.scrollTo(latest.id, anchor: .bottom)
                } else {
                    proxy.scrollTo("activity-empty", anchor: .bottom)
                }
            }
        }
    }

    private func colour(for tone: CommandActivityTone) -> Color {
        switch tone {
        case .normal:
            .primary
        case .pending:
            .blue
        case .success, .new:
            .green
        case .updated:
            .cyan
        case .removed, .warning:
            .orange
        case .skipped:
            .secondary
        case .error:
            .red
        }
    }
}
