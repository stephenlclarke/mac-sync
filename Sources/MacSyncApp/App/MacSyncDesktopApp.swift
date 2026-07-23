import AppKit
import SwiftUI

final class MacSyncAppDelegate: NSObject, NSApplicationDelegate {
    private static let aboutCredits = """
    Licensed under the GNU Affero General Public License v3.0 or later
    (AGPL-3.0-or-later).

    This program is provided without warranty.
    """

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: Self.aboutCredits),
        ])
    }
}

@main
struct MacSyncDesktopApp: App {
    @NSApplicationDelegateAdaptor(MacSyncAppDelegate.self) private var appDelegate
    @StateObject private var store = SyncStore()

    var body: some Scene {
        WindowGroup("Mac Sync", id: "main") {
            Group {
                if store.isSetupComplete {
                    ContentView(store: store)
                } else {
                    SetupWizardView(store: store)
                }
            }
        }
        .defaultSize(width: 1180, height: 680)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mac Sync") {
                    appDelegate.showAboutPanel()
                }
            }

            CommandMenu("Sync") {
                Button("Sync This Mac") {
                    store.syncSelection()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isRunning || !store.isSetupComplete)

                Button("Save Sync Selection") {
                    store.saveSelection()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!store.isSetupComplete)

                Divider()

                Button("Refresh Status") {
                    store.reload()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Set Up Repositories…") {
                    store.requestSetup()
                }
            }
        }

        MenuBarExtra {
            MenuBarStatusView(store: store)
        } label: {
            Image(systemName: menuBarImage)
        }

        Settings {
            SettingsView(store: store)
        }
    }

    private var menuBarImage: String {
        if store.isRunning {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return store.overview.status.result.systemImage
    }
}
