import Foundation
import Security

/// Thin generic-password Keychain wrapper.
///
///   * `set` is non-destructive: tries `SecItemUpdate` first and only falls
///     back to `SecItemAdd` if the item doesn't yet exist. Avoids the
///     delete-then-add window where the credential briefly vanishes.
///   * Items use `kSecAttrSynchronizable=false` (local only) and
///     `kSecAttrAccessibleAfterFirstUnlock` so the menu-bar agent can read
///     post-reboot without unlock. macOS doesn't enforce per-app Keychain
///     ACLs without explicit access groups, but on a properly Developer-ID
///     signed build the entry is at minimum scoped by the application label
///     stored alongside.
enum Keychain {
    private static let service = "app.scrobblr.Scrobblr"

    static func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainError(status: updateStatus)
        }
        var add = query
        for (k, v) in attrs { add[k] = v }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    struct KeychainError: Error { let status: OSStatus }
}
