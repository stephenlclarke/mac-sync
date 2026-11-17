import AppKit
import MacSyncCore
import SwiftUI

struct InstallationIdentityImportView: View {
    @ObservedObject var store: SyncStore
    @State private var stoppedPreviousInstallation = false
    @State private var message: String?

    var body: some View {
        DisclosureGroup("Moving from another Mac Sync edition on this Mac?") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before the first sync, keep the same destination and This Mac identifier. Import this Mac's previous device-id file from its Status records folder. Never import another computer's identity. History and Undo stay in the old installation; Git/cloud version history stays at the shared destination. Encryption keys and credentials need separate setup.")
                Toggle("I stopped automatic sync and quit the previous installation on this Mac", isOn: $stoppedPreviousInstallation)
                Button("Import This Mac's Previous Identity…") { importIdentity() }
                    .disabled(!stoppedPreviousInstallation || store.isRunning || store.syncScheduleStatus.schedule != nil)
                if let message {
                    Text(message).font(.callout)
                }
            }
            .padding(.top, 6)
        }
    }

    private func importIdentity() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.message = "Choose device-id from the previous installation's Status records folder on THIS Mac. Do not choose a file from a different computer or a shared snapshot."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            try InstallationIdentity.importIdentity(from: file, statusDirectory: URL(fileURLWithPath: store.overview.configuration.statusDirectory))
            message = "Identity imported. Keep the previous edition stopped. Review folder access and credentials before enabling automatic sync in this edition."
        } catch { message = error.localizedDescription }
    }
}
