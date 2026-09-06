import Foundation
import Security

/// Minimal Keychain read/write for the two small pieces of session state
/// worth persisting across launches: the refresh token and the email it
/// belongs to. Deliberately narrow — this is not a general-purpose Keychain
/// wrapper, just enough for UserSession's silent-restore flow.
///
/// Uses kSecClassGenericPassword with a fixed service name; the account
/// name distinguishes the two stored items (refreshToken vs email).
enum KeychainStore {
    private static let service = "com.crowdshield.session"

    enum Key: String {
        case refreshToken
        case email
    }

    static func set(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first — SecItemAdd fails with
        // errSecDuplicateItem if one already exists, and SecItemUpdate
        // requires a separate query/attributes split that's more code for
        // no real benefit at this scale (single small values, infrequent
        // writes on sign-in only).
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            // Available as soon as the device is unlocked once after boot,
            // and not synced to iCloud Keychain — appropriate for a
            // short-lived session credential rather than a long-term secret.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() {
        delete(.refreshToken)
        delete(.email)
    }
}
