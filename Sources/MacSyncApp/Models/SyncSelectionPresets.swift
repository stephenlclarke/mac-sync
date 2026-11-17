import Foundation

enum SyncSelectionPreset: String, CaseIterable, Identifiable {
    case shell, terminal, editor, git
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .shell: "Shell settings"
        case .terminal: "Terminal settings"
        case .editor: "Editor settings"
        case .git: "Git settings"
        }
    }

    var paths: [String] {
        switch self {
        case .shell: [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".config/fish/config.fish", ".config/fish/functions"]
        case .terminal: [".config/ghostty/config", ".wezterm.lua", ".config/alacritty/alacritty.toml", ".config/kitty/kitty.conf"]
        case .editor: ["Library/Application Support/Code/User/settings.json", "Library/Application Support/Code/User/keybindings.json", "Library/Application Support/Code/User/snippets"]
        case .git: [".gitconfig", ".config/git/config", ".config/git/ignore"]
        }
    }

    func existingPaths(home: String) -> [String] {
        paths.filter { FileManager.default.fileExists(atPath: "\(home)/\($0)") }
    }
}

struct SyncSelectionWarning: Identifiable, Equatable, Sendable {
    let path: String
    let reason: String
    var id: String {
        path
    }
}

enum SyncSelectionSafety {
    static func warnings(paths: [String], home: String) -> [SyncSelectionWarning] {
        paths.compactMap { path in
            if Task.isCancelled {
                return nil
            }
            if let reason = pathWarning(path) {
                return SyncSelectionWarning(path: path, reason: reason)
            }
            let absolute = path.hasPrefix("/") ? path : "\(home)/\(path)"
            guard let values = try? URL(fileURLWithPath: absolute).resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
                  let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: absolute)) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 32 * 1024), !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
            let patterns = [#"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"#,
                            #"AGE-SECRET-KEY-"#,
                            #"(?i)(api[_-]?key|access[_-]?token|password|client[_-]?secret)["'\s]*[:=][\s"']*[^\s"'${}]{6,}"#]
            guard patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) else { return nil }
            return SyncSelectionWarning(path: path, reason: "The first 32 KiB may contain a credential. Review it locally before publishing; use encrypted transfer for sensitive files.")
        }
    }

    static func pathWarning(_ path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        let sensitive = Set([".ssh", ".gnupg", ".aws", ".kube", ".password-store", ".netrc", ".npmrc", ".pypirc", ".git-credentials"])
        if !sensitive.isDisjoint(with: components) || components.last == ".env" || components.last?.hasPrefix(".env.") == true
            || path.hasSuffix(".docker/config.json")
        {
            return "This path commonly contains credentials. Ordinary sync is not end-to-end encrypted. Use Encrypted Secrets or remove it from the selection."
        }
        return nil
    }
}
