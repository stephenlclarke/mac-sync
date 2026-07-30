import AppKit
import Foundation

enum MacSyncDockIconController {
    static let preferenceKey = "showDockIcon"

    static func isVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? false
    }

    static func activationPolicy(isVisible: Bool) -> NSApplication.ActivationPolicy {
        isVisible ? .regular : .accessory
    }

    @MainActor
    @discardableResult
    static func apply(isVisible: Bool, to application: NSApplication = .shared) -> Bool {
        application.setActivationPolicy(activationPolicy(isVisible: isVisible))
    }
}
