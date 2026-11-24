import SwiftUI

struct SyncSelectionWarningsView: View {
    let warnings: [SyncSelectionWarning]
    @State private var isExpanded: Bool

    init(warnings: [SyncSelectionWarning], initiallyExpanded: Bool = false) {
        self.warnings = warnings
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(warnings) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(warning.path)
                                .font(.body.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                            Text(warning.reason)
                        }
                    }
                    Text("Warnings are advisory, not a complete secrets scan. Removing a file now does not remove copies from older Git or cloud versions; rotate exposed credentials.")
                }
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
        } label: {
            Label("Review \(warnings.count) possible credential risks before syncing", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
        }
    }
}
