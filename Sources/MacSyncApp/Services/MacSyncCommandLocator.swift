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
    static func scheduledExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
    ) -> URL? {
        executableURL(candidates: [
            environment["MAC_SYNC_EXECUTABLE"],
            homebrewOptRoot(for: bundleURL)?.appendingPathComponent("bin/mac-sync").path,
            "/opt/homebrew/opt/mac-sync-current/bin/mac-sync",
            "/usr/local/opt/mac-sync-current/bin/mac-sync",
            "/opt/homebrew/opt/mac-sync/bin/mac-sync",
            "/usr/local/opt/mac-sync/bin/mac-sync",
            Bundle.main.url(forResource: "mac-sync", withExtension: nil)?.path,
            "/opt/homebrew/bin/mac-sync",
            "/usr/local/bin/mac-sync",
        ], fileManager: fileManager)
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
                homebrewOptRoot(for: bundleURL)?.appendingPathComponent("MacSync.app").path,
                "/opt/homebrew/opt/mac-sync-current/MacSync.app",
                "/usr/local/opt/mac-sync-current/MacSync.app",
                "/opt/homebrew/opt/mac-sync/MacSync.app",
                "/usr/local/opt/mac-sync/MacSync.app",
                bundleURL.path,
            ],
            fileManager: fileManager,
        )
    }

    private static func executableURL(
        candidates: [String?],
        fileManager: FileManager = .default,
    ) -> URL? {
        candidates
            .compactMap(\.self)
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
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

    private static func homebrewOptRoot(for bundleURL: URL) -> URL? {
        let resolvedPath = bundleURL.resolvingSymlinksInPath().path
        guard let cellarRange = resolvedPath.range(of: "/Cellar/") else { return nil }
        let formulaPath = resolvedPath[cellarRange.upperBound...]
        guard let formula = formulaPath.split(separator: "/").first,
              formula == "mac-sync" || formula == "mac-sync-current"
        else {
            return nil
        }
        let prefix = String(resolvedPath[..<cellarRange.lowerBound])
        return URL(fileURLWithPath: prefix)
            .appendingPathComponent("opt")
            .appendingPathComponent(String(formula))
    }
}
