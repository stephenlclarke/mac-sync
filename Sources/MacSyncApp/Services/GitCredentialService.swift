import Foundation
import MacSyncCore

/// The bundled Git helper owns the credential item. Tokens travel over stdin,
/// never through command arguments, configuration files, logs or Git remotes.
struct GitCredentialService {
    let environment: [String: String]

    func save(remote: String, username: String, token: String) throws {
        let input = try Self.payload(remote: remote, username: username, token: token)
        guard let root = environment["GIT_EXEC_PATH"] else { throw BackupStorageError.invalidDestination }
        let result = ProcessRunner(environment: environment).run(root + "/git-credential-osxkeychain", ["store"],
                                                                 timeout: 60, outputLimit: 1024, input: input)
        guard result.status == 0 else {
            // A credential helper's output is never safe to relay verbatim.
            throw BackupStorageError.unavailable("Keychain access could not be saved (exit \(result.status)). Unlock this Mac's Keychain and try again.")
        }
    }

    static func payload(remote: String, username: String, token: String) throws -> Data {
        guard let remote = GitRemote(remote), !remote.isSSH, remote.user == nil,
              !username.isEmpty, !token.isEmpty, username.utf8.count <= 1024, token.utf8.count <= 32 * 1024,
              !username.contains(where: { $0.isNewline || $0 == "\0" }), !token.contains(where: { $0.isNewline || $0 == "\0" })
        else {
            throw BackupStorageError.unavailable("Enter a credential-free HTTPS repository URL, your Git username and a repository access token without line breaks.")
        }
        let host = remote.host + (remote.port.map { ":\($0)" } ?? "")
        return Data("protocol=https\nhost=\(host)\nusername=\(username)\npassword=\(token)\n\n".utf8)
    }
}
