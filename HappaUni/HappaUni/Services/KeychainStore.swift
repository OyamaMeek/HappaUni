import Foundation
import Security

struct KeychainStore {
    let service = "com.happanetwork.HappaUni"

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        SecItemDelete(query(for: key) as CFDictionary)
        let status = SecItemAdd(query(for: key, data: data) as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func value(for key: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(for: key) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError.unhandled(status) }
        return value
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandled(status) }
    }

    private func query(for key: String, data: Data? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key]
        if let data { query[kSecValueData] = data }
        else { query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne }
        return query
    }

    enum KeychainError: LocalizedError { case unhandled(OSStatus)
        var errorDescription: String? { "钥匙串操作失败。" }
    }
}
