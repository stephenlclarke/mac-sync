import Foundation
import LocalAuthentication
import Security

struct MacSyncKeychainBackend {
    let copyMatching: ([CFString: Any]) -> (status: OSStatus, item: Any?)
    let update: ([CFString: Any], [CFString: Any]) -> OSStatus
    let add: ([CFString: Any]) -> OSStatus

    static var live: MacSyncKeychainBackend {
        MacSyncKeychainBackend(
            copyMatching: { query in
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                return (status, item)
            },
            update: { query, attributes in
                SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            },
            add: { query in
                // The age identity must be available to a scheduled sync after the
                // first unlock. This device-only item deliberately has no per-use
                // authentication prompt; adding one would make unattended sync
                // impossible. The app never logs or exports the identity.
                SecItemAdd(query as CFDictionary, nil) // NOSONAR
            },
        )
    }
}

public enum MacSyncKeychainIdentityAvailability: Equatable, Sendable {
    case available
    case missing
    case interactionRequired
    case unavailable(status: OSStatus)
}

public struct MacSyncKeychainIdentityLookup: Equatable, Sendable {
    public let availability: MacSyncKeychainIdentityAvailability
    public let identity: String?

    public init(
        availability: MacSyncKeychainIdentityAvailability,
        identity: String? = nil,
    ) {
        self.availability = availability
        self.identity = identity
    }
}

/// Reads and stores the age identity without invoking the `security` command.
/// Scheduled runs explicitly disallow authentication UI so a locked Keychain
/// becomes a typed, recoverable condition instead of a false "missing" result.
public enum MacSyncKeychain {
    public static func identity(
        service: String,
        account: String,
        allowInteraction: Bool,
    ) -> MacSyncKeychainIdentityLookup {
        identity(
            service: service,
            account: account,
            allowInteraction: allowInteraction,
            backend: .live,
        )
    }

    static func identity(
        service: String,
        account: String,
        allowInteraction: Bool,
        backend: MacSyncKeychainBackend,
    ) -> MacSyncKeychainIdentityLookup {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        context.localizedReason = "Mac Sync needs its age identity to update encrypted secrets."
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
            kSecUseAuthenticationContext: context,
        ]

        let (status, item) = backend.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let identity = String(data: data, encoding: .utf8),
                  !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return MacSyncKeychainIdentityLookup(availability: .unavailable(status: errSecDecode))
            }
            return MacSyncKeychainIdentityLookup(availability: .available, identity: identity)
        case errSecItemNotFound:
            return MacSyncKeychainIdentityLookup(availability: .missing)
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return MacSyncKeychainIdentityLookup(availability: .interactionRequired)
        default:
            return MacSyncKeychainIdentityLookup(availability: .unavailable(status: status))
        }
    }

    public static func storeIdentity(
        _ identity: String,
        service: String,
        account: String,
    ) -> OSStatus {
        storeIdentity(
            identity,
            service: service,
            account: account,
            backend: .live,
        )
    }

    static func storeIdentity(
        _ identity: String,
        service: String,
        account: String,
        backend: MacSyncKeychainBackend,
    ) -> OSStatus {
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(identity.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = backend.update(match, attributes)
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }
        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var item = match
        attributes.forEach { item[$0.key] = $0.value }
        return backend.add(item)
    }
}
