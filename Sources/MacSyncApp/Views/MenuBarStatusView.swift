import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: SyncStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Mac Sync") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        if !store.isSetupComplete {
            Text("Repository setup required")
            Button("Set Up Mac Sync…") {
                store.requestSetup()
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        } else if store.isRunning {
            Text(store.activeAction?.title ?? "Sync active")
            Button("Stop Sync") {
                store.stopSync()
            }
        } else {
            Text(store.overview.status.result.title)
            Button("Sync This Mac") {
                store.syncSelection()
            }
        }

        Button("Refresh Status") {
            store.reload()
        }

        Divider()

        Text("xyzzy.tools")
            .foregroundStyle(.secondary)
        Button("Quit Mac Sync") {
            NSApplication.shared.terminate(nil)
        }
    }
}
