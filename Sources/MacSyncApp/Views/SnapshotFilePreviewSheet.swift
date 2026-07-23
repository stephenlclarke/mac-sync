import SwiftUI

struct SnapshotFilePreviewSheet: View {
    let machineName: String
    let file: SnapshotFile
    let displaysTextPreview: Bool
    let inspector: SnapshotFileInspector
    let revealInFinder: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inspection: SnapshotFileInspection?
    @State private var inspectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: titleImage)
                .font(.title2.bold())
            Text(file.displayPath)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let inspection {
                fileInformation(inspection)
                preview(inspection)
            } else if let inspectionError {
                unavailableState(
                    title: "Preview unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    detail: inspectionError
                )
            } else {
                ProgressView("Loading snapshot file…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Show in Finder") {
                    revealInFinder()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 430, idealHeight: 560)
        .task(id: file.id) {
            loadInspection()
        }
    }

    private var title: String {
        if inspection?.isBinary == true || !displaysTextPreview {
            return "File information"
        }
        return "File preview"
    }

    private var titleImage: String {
        inspection?.isBinary == true ? "doc.badge.gearshape" : "doc.text"
    }

    private func fileInformation(_ inspection: SnapshotFileInspection) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            informationRow("Machine", machineName)
            informationRow("Size", SyncFormatting.bytes(inspection.byteCount))
            informationRow("Modified", SyncFormatting.date(inspection.modifiedAt))
            informationRow("Type", inspection.contentTypeIdentifier ?? "Unknown")
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func preview(_ inspection: SnapshotFileInspection) -> some View {
        if displaysTextPreview, case let .text(text, isTruncated) = inspection.content {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isTruncated ? "Text preview (first 96 KB)" : "Text preview")
                        .font(.headline)
                    Spacer()
                    if isTruncated {
                        Text("Truncated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if inspection.isBinary {
            unavailableState(
                title: "Binary file",
                systemImage: "doc.badge.gearshape",
                detail: "Binary contents are not displayed. The file information above describes the archived snapshot copy."
            )
        } else {
            unavailableState(
                title: "File information",
                systemImage: "doc.text",
                detail: "Choose Preview from the context menu to read this text file."
            )
        }
    }

    private func unavailableState(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 10) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func informationRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func loadInspection() {
        do {
            inspection = try inspector.inspect(machineName: machineName, file: file)
            inspectionError = nil
        } catch {
            inspection = nil
            inspectionError = error.localizedDescription
        }
    }
}
