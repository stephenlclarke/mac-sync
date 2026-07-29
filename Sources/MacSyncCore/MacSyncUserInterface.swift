import Foundation

public enum MacSyncUserInterfaceError: LocalizedError {
    case notInstalled
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Mac Sync UI is not installed."
        case let .launchFailed(message):
            "Mac Sync UI could not be opened: \(message)"
        }
    }
}

public enum MacSyncUserInterface {
    /// Resolve a complete app bundle rather than a bare executable so macOS can
    /// activate an existing instance through Launch Services.
    public static func applicationURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
    ) -> URL? {
        applicationURL(
            candidates: [
                environment["MAC_SYNC_APPLICATION"],
                "/opt/homebrew/opt/mac-sync-current/MacSync.app",
                "/usr/local/opt/mac-sync-current/MacSync.app",
                "/opt/homebrew/opt/mac-sync/MacSync.app",
                "/usr/local/opt/mac-sync/MacSync.app",
            ],
            fileManager: fileManager,
        )
    }

    static func applicationURL(candidates: [String?], fileManager: FileManager) -> URL? {
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

    public static func versionDescription(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String {
        versionDescription(applicationURL: applicationURL(environment: environment))
    }

    static func versionDescription(applicationURL: URL?) -> String {
        guard let applicationURL,
              let bundle = Bundle(url: applicationURL),
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty
        else {
            return "mac-sync development build"
        }

        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty
        else {
            return "mac-sync \(version)"
        }
        return "mac-sync \(version) (\(build))"
    }

    public static func open(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        try open(
            applicationURL: applicationURL(environment: environment),
            launcher: launch,
        )
    }

    static func open(
        applicationURL: URL?,
        launcher: (URL) throws -> Int32,
    ) throws {
        guard let applicationURL else {
            throw MacSyncUserInterfaceError.notInstalled
        }

        let terminationStatus: Int32
        do {
            terminationStatus = try launcher(applicationURL)
        } catch let error as MacSyncUserInterfaceError {
            throw error
        } catch {
            throw MacSyncUserInterfaceError.launchFailed(error.localizedDescription)
        }
        guard terminationStatus == 0 else {
            throw MacSyncUserInterfaceError.launchFailed("open exited with status \(terminationStatus)")
        }
    }

    private static func launch(_ applicationURL: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [applicationURL.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
