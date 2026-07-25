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

    /// Prefer Homebrew's stable opt prefix so launch-at-login registration
    /// survives formula upgrades that replace the versioned Cellar directory.
    static func scheduledApplicationURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
    ) -> URL? {
        applicationURL(
            candidates: [
                environment["MAC_SYNC_APPLICATION"],
                "/opt/homebrew/opt/mac-sync/MacSync.app",
                "/usr/local/opt/mac-sync/MacSync.app",
                bundleURL.path,
            ],
            fileManager: fileManager,
        )
    }

    private static func executableURL(candidates: [String?]) -> URL? {
        candidates
            .compactMap(\.self)
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func applicationURL(candidates: [String?], fileManager: FileManager) -> URL? {
        candidates
            .compactMap(\.self)
            .map(URL.init(fileURLWithPath:))
            .first { candidate in
                candidate.pathExtension == "app"
                    && fileManager.isExecutableFile(
                        atPath: candidate.appendingPathComponent("Contents/MacOS/MacSync").path,
                    )
            }
    }
}
