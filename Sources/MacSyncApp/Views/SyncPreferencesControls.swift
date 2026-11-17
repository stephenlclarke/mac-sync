import AppKit
import MacSyncCore
import SwiftUI

struct SyncPreferencesControls: View {
    @ObservedObject var store: SyncStore
    @State private var preferences = BackupPreferences()
    @State private var showIncoming = false
    @State private var machineIdentifier = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.backupPreferences.pauseReason() ?? "Automatic sync is not paused.").font(.caption)
            HStack {
                Menu("Pause Automatic Sync") {
                    Button("For one hour") { store.pauseBackup(until: Date().addingTimeInterval(3600)) }
                    Button("For 24 hours") { store.pauseBackup(until: Date().addingTimeInterval(86400)) }
                    Button("Until I resume") { store.pauseBackup(indefinitely: true) }
                }
                Button("Resume") { store.pauseBackup() }
            }
            Toggle("Wait for external power", isOn: $preferences.waitForACPower)
            Toggle("Avoid metered or constrained Git connections", isOn: $preferences.avoidExpensiveNetworks)
            Toggle("Allow automatic sync in Low Power Mode", isOn: $preferences.allowLowPowerMode)
            Picker("Incoming files", selection: $preferences.incomingPolicy) {
                ForEach(IncomingSyncPolicy.allCases) { policy in Text(policy.title).tag(policy) }
            }
            Button("Incoming Changes (\(store.incomingChanges.count)\(store.incomingChanges.count == 100 ? "+" : ""))…") { showIncoming = true }
                .disabled(!store.isSetupComplete)
            Text("Conflicts and deletions always require review. Automatic incoming sync covers regular selected paths under your home folder. Absolute paths and encrypted secrets require manual recovery.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("This Mac identifier", text: $machineIdentifier)
                Button("Change Identifier") { store.setMachineIdentifier(machineIdentifier) }.disabled(store.isRunning)
            }
            Text("Use a different identifier on each Mac. Changing it starts a separate snapshot and keeps the old one.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Save Sync Preferences") { store.savePreferences(preferences) }
            Text("Pausing affects scheduled sync, not Sync Now. Memory and thermal safeguards remain active. Network controls apply to Mac Sync's Git transfers; a cloud provider controls its own uploader.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { preferences = store.backupPreferences; machineIdentifier = store.overview.configuration.machineName }
        .onChange(of: store.backupPreferences) { preferences = $0 }
        .sheet(isPresented: $showIncoming) { IncomingChangesView(store: store) }
    }
}

struct RecoverySettingsControls: View {
    @ObservedObject var store: SyncStore
    @State private var showVersions = false
    @State private var exportURL: URL?
    @State private var confirmExport = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Versions, Undo & Test Recovery…") { showVersions = true }
                .disabled(!store.isSetupComplete || store.isRunning)
            DisclosureGroup("Keep access to encrypted files") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Regular selected files are not automatically encrypted. A private repository or cloud folder is not end-to-end encryption. Use Encrypted Secrets for sensitive files.")
                    Text("Keep a recovery key offline, separate from your synced data. Losing every trusted key means losing access to encrypted archives.")
                    HStack {
                        Button("Test Encryption Access") { store.testEncryptedSecretsAccess() }
                        Button("Export Private Recovery Key…") { chooseExport() }
                    }.disabled(store.isRunning || !store.isSetupComplete)
                    Text("Test Recovery checks copied files and encrypted archive bytes. Test Encryption Access checks the current key separately.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .sheet(isPresented: $showVersions) {
            VersionRecoveryView(store: store, machine: store.overview.configuration.machineName, paths: [])
        }
        .confirmationDialog("Export an unencrypted private recovery key?", isPresented: $confirmExport) {
            Button("Export Private Key", role: .destructive) {
                if let exportURL {
                    store.exportRecoveryKey(to: exportURL)
                }
            }
        } message: { Text("Anyone with this key can open archives encrypted for it. Store it offline, separately from synced folders. Existing files are never overwritten.") }
        .alert("Recovery key", isPresented: Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Choose another export location.") }
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mac-sync-private-recovery-key.txt"
        panel.message = "Choose an offline location, not a synced folder. This exports an unencrypted private key."
        if panel.runModal() == .OK, let url = panel.url {
            guard !FileManager.default.fileExists(atPath: url.path) else { errorMessage = "Choose a new filename. Existing files are never replaced."; return }
            exportURL = url
            confirmExport = true
        }
    }
}
