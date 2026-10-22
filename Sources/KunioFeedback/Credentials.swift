import Foundation
import Security

protocol FeedbackCredentialStore: Sendable {
    func load(account: String) throws -> String?
    func save(_ token: String, account: String) throws
    func remove(account: String) throws
}
struct KeychainCredentialStore: FeedbackCredentialStore {
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.kunio.feedback.participant.v1",
         kSecAttrAccount as String: account]
    }
    func load(account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw KunioFeedbackError.credentialStorage }
        return token
    }
    func save(_ token: String, account: String) throws {
        let request = query(account), data = Data(token.utf8)
        let updated = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KunioFeedbackError.credentialStorage }
        var new = request
        new[kSecValueData as String] = data
        new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw KunioFeedbackError.credentialStorage }
    }
    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KunioFeedbackError.credentialStorage }
    }
}
