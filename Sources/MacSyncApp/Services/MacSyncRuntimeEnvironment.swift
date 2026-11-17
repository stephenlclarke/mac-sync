import Darwin
import Foundation
import MacSyncCore

enum MacSyncRuntimeEnvironment {
    private static let requiredCommandDirectories = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func prepared(_ environment: [String: String]) -> [String: String] {
        if MacSyncDistribution.current == .appStore, MacSyncDistribution(environment: environment) != .appStore {
            let container = NSHomeDirectory()
            let sourceHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? container
            return MacSyncStoreRuntime.environment(environment, bundle: Bundle.main.bundleURL, containerHome: container, sourceHome: sourceHome)
        }
        if MacSyncDistribution(environment: environment) == .appStore {
            return environment
        }
        var environment = environment
        let currentPaths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let path = (requiredCommandDirectories + currentPaths)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        environment["PATH"] = path
        return environment
    }
}
