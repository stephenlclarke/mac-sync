import Foundation

enum MacSyncCommandLocator {
    static func executableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        executableURL(candidates: [
            environment["MAC_SYNC_EXECUTABLE"],
            Bundle.main.url(forResource: "mac-sync", withExtension: nil)?.path,
            "/opt/homebrew/bin/mac-sync",
            "/usr/local/bin/mac-sync",
        ])
    }

    /// Prefer Homebrew's stable opt prefix for the launchd job so a formula
    /// upgrade does not leave the schedule pointing at a replaced app bundle.
    static func scheduledExecutableURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        executableURL(candidates: [
            environment["MAC_SYNC_EXECUTABLE"],
            "/opt/homebrew/opt/mac-sync/bin/mac-sync",
            "/usr/local/opt/mac-sync/bin/mac-sync",
            Bundle.main.url(forResource: "mac-sync", withExtension: nil)?.path,
            "/opt/homebrew/bin/mac-sync",
            "/usr/local/bin/mac-sync",
        ])
    }

    private static func executableURL(candidates: [String?]) -> URL? {
        return candidates
            .compactMap(\.self)
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
