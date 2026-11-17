import Foundation

/// A credential-free Git endpoint. Provider-specific APIs are not needed for
/// clone/fetch/push; authentication stays with Git's SSH/credential helpers.
public struct GitRemote: Equatable, Sendable {
    public let host: String
    public let path: String
    public let user: String?
    public let isSSH: Bool
    public let port: Int?

    public init?(_ raw: String) {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace || $0.isNewline }), !raw.contains("\0") else { return nil }
        let url: URLComponents?
        if !raw.contains("://"), let colon = raw.firstIndex(of: ":") {
            let authority = String(raw[..<colon])
            url = URLComponents(string: "ssh://\(authority)/\(raw[raw.index(after: colon)...])")
        } else {
            url = URLComponents(string: raw)
        }
        guard let url, let scheme = url.scheme?.lowercased(), ["https", "ssh"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              host.range(of: #"[^a-z0-9.-]"#, options: .regularExpression) == nil,
              !host.hasPrefix("-"), !host.hasPrefix("."), !host.hasSuffix("."),
              url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1 ... 65535).contains($0) }) ?? true
        else { return nil }
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix("-") }),
              path.range(of: #"[^A-Za-z0-9_./-]"#, options: .regularExpression) == nil,
              url.user?.range(of: #"[^A-Za-z0-9_.@-]"#, options: .regularExpression) == nil
        else { return nil }
        self.host = host
        self.path = path
        user = url.user
        isSSH = scheme == "ssh"
        port = url.port
    }

    public var cloneURL: String {
        var url = URLComponents()
        url.scheme = isSSH ? "ssh" : "https"
        url.host = host
        url.user = user
        url.port = port
        url.path = "/\(path).git"
        return url.string!
    }

    public var displayURL: String {
        "https://\(host)/\(path).git"
    }

    public var sshURL: String {
        if isSSH {
            return cloneURL
        }
        return "git@\(host):\(path).git"
    }
}

public enum GitHostingProvider: String, CaseIterable, Identifiable, Sendable {
    case github, gitlab, bitbucket, other
    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .bitbucket: "Bitbucket"
        case .other: "Other Git server"
        }
    }

    public var creationURL: URL? {
        switch self {
        case .github: URL(string: "https://github.com/new?name=mac-sync-data&visibility=private")
        case .gitlab: URL(string: "https://gitlab.com/projects/new#blank_project")
        case .bitbucket: URL(string: "https://bitbucket.org/repo/create")
        case .other: nil
        }
    }

    public var instructionsURL: URL {
        switch self {
        case .github: URL(string: "https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository")!
        case .gitlab: URL(string: "https://docs.gitlab.com/user/project/")!
        case .bitbucket: URL(string: "https://support.atlassian.com/bitbucket-cloud/docs/create-a-repository-in-bitbucket-cloud/")!
        case .other: URL(string: "https://git-scm.com/book/en/v2/Git-Basics-Working-with-Remotes")!
        }
    }
}
