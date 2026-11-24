import Foundation

/// Channels change packaging and permissions, not snapshot formats.
public enum MacSyncDistribution: String, Codable, Sendable {
    case direct
    case appStore = "app-store"

    public var supportsDeveloperTools: Bool {
        self == .direct
    }

    public static var current: Self {
        Self(rawValue: Bundle.main.object(forInfoDictionaryKey: "MacSyncDistribution") as? String ?? "") ?? .direct
    }

    public init(environment: [String: String]) {
        self = Self(rawValue: environment["MAC_SYNC_DISTRIBUTION"] ?? "") ?? .direct
    }
}

public enum MacSyncStoreRuntime {
    public static let tools = ["mac-sync", "git", "rsync", "age", "age-keygen", "gtar", "git-remote-http", "git-remote-https", "git-credential-osxkeychain"]

    static func localTransfer(arguments: [String], workingDirectory: String?) -> ([String], String?) {
        guard let destination = arguments.last, destination.hasPrefix("/") else { return (arguments, workingDirectory) }
        // Recent rsync securely opens every component of an absolute receiver
        // path. That would require read access to /Users, beyond any folder
        // grant. Start inside the approved target instead; keep rsync's secure
        // resolution enabled and never add --insecure-links.
        let url = URL(fileURLWithPath: destination)
        let directory = destination.hasSuffix("/") ? url : url.deletingLastPathComponent()
        let target = destination.hasSuffix("/") ? "./" : "./" + url.lastPathComponent
        return (Array(arguments.dropLast()) + [target], directory.path)
    }

    public static func environment(_ original: [String: String], bundle: URL, containerHome: String, sourceHome: String) -> [String: String] {
        var values = original
        let discarded = ["BASH_ENV", "ENV", "SSH_ASKPASS", "MAC_SYNC_REPO", "MAC_SYNC_MACHINES_REPO", "MAC_SYNC_DATA_REPOSITORY",
                         "MAC_SYNC_STORAGE_KIND", "MAC_SYNC_CLOUD_FOLDER", "MAC_SYNC_MACHINE", "MAC_SYNC_PATHS_FILE", "MAC_SYNC_EXCLUDES_FILE", "MAC_SYNC_SECRET_PATHS_FILE"]
        for key in Array(values.keys) where key.hasPrefix("DYLD_") || key.hasPrefix("GIT_") || discarded.contains(key) {
            values.removeValue(forKey: key)
        }
        let support = URL(fileURLWithPath: containerHome).appendingPathComponent("Library/Application Support/mac-sync")
        let tools = bundle.appendingPathComponent("Contents/Helpers")
        values["MAC_SYNC_DISTRIBUTION"] = MacSyncDistribution.appStore.rawValue
        values["MAC_SYNC_CONTAINER_HOME"] = containerHome
        values["MAC_SYNC_PRIVATE_SUPPORT"] = support.path
        values["MAC_SYNC_APP_CONFIG"] = support.appendingPathComponent("config.env").path
        values["MAC_SYNC_STATUS_DIR"] = support.appendingPathComponent("status").path
        values["MAC_SYNC_EXECUTABLE"] = tools.appendingPathComponent("mac-sync").path
        values["MAC_SYNC_APPLICATION"] = bundle.path
        values["TMPDIR"] = URL(fileURLWithPath: containerHome).appendingPathComponent("tmp").path
        values["HOME"] = sourceHome
        values = MacSyncUserConfiguration.resolvedEnvironment(values)
        values["MAC_SYNC_MACHINES_REPO"] = values["MAC_SYNC_MACHINES_REPO"] ?? support.appendingPathComponent("workspace").path
        values["PATH"] = tools.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        values["GIT_EXEC_PATH"] = tools.path
        values["GIT_TEMPLATE_DIR"] = bundle.appendingPathComponent("Contents/Resources/Runtime/share/git-core/templates").path
        values["GIT_CONFIG_NOSYSTEM"] = "1"
        values["GIT_CONFIG_GLOBAL"] = support.appendingPathComponent("gitconfig").path
        values["GIT_TERMINAL_PROMPT"] = "0"
        values["GIT_CONFIG_COUNT"] = "5"
        values["GIT_CONFIG_KEY_0"] = "core.hooksPath"
        values["GIT_CONFIG_VALUE_0"] = "/dev/null"
        values["GIT_CONFIG_KEY_1"] = "protocol.ext.allow"
        values["GIT_CONFIG_VALUE_1"] = "never"
        values["GIT_CONFIG_KEY_2"] = "credential.helper"
        values["GIT_CONFIG_VALUE_2"] = ""
        values["GIT_CONFIG_KEY_3"] = "credential.helper"
        values["GIT_CONFIG_VALUE_3"] = "osxkeychain"
        values["GIT_CONFIG_KEY_4"] = "core.fsmonitor"
        values["GIT_CONFIG_VALUE_4"] = "false"
        // SSH key and known-host files require an explicit folder grant.
        values["GIT_SSH_COMMAND"] = "/usr/bin/ssh -F /dev/null -oBatchMode=yes -oStrictHostKeyChecking=yes"
        values["GIT_SSH_VARIANT"] = "ssh"
        for key in ["MAC_SYNC_HOMEBREW", "MAC_SYNC_VSCODE_EXTENSIONS", "MAC_SYNC_GITHUB_REPOS", "MAC_SYNC_DYNAMIC_REFS"] {
            values[key] = "0"
        }
        return values
    }

    public static func missingTools(bundle: URL, fileManager: FileManager = .default) -> [String] {
        let root = bundle.appendingPathComponent("Contents/Helpers")
        return tools.filter {
            let tool = root.appendingPathComponent($0)
            return !fileManager.isExecutableFile(atPath: tool.path) || !tool.resolvingSymlinksInPath().path.hasPrefix(bundle.resolvingSymlinksInPath().path + "/")
        }
    }
}
