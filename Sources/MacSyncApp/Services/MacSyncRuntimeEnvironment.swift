import Foundation

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
