import MacSyncCore
import SwiftUI

struct GitCredentialsView: View {
    let remote: String
    @State private var username = ""
    @State private var token = ""
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HTTPS access is saved in this app's Keychain access, not copied from Homebrew. Use a token limited to this private repository, with read/write access. Your provider may call it an app password or API token. It is used only for the selected host.")
                .font(.callout)
            TextField("Git username", text: $username)
            SecureField("Repository access token", text: $token)
            Button(saving ? "Saving…" : "Save HTTPS Access in Keychain") { save() }
                .disabled(saving || username.isEmpty || token.isEmpty)
            if let message {
                Text(message).font(.callout)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func save() {
        let username = username
        let secret = token
        let remote = remote
        token = ""
        saving = true
        let environment = MacSyncApplicationRuntime.shared.environment
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try GitCredentialService(environment: environment).save(remote: remote, username: username, token: secret) }
            DispatchQueue.main.async {
                saving = false
                switch result {
                case .success: message = "Saved in Keychain. Test Repository Access to confirm the token's permissions."
                case let .failure(error): message = error.localizedDescription
                }
            }
        }
    }
}
