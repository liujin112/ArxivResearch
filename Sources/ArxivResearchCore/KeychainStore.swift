import Foundation
import LocalAuthentication
import Security

public struct KeychainStore {
    public static let accessGroupEnvironmentKey = "ARXIVRESEARCH_KEYCHAIN_ACCESS_GROUP"
    public static let accessGroupInfoKey = "ArxivResearchKeychainAccessGroup"

    public var service: String
    public var accessGroup: String?
    public var migrateLegacyItems: Bool

    public init(
        service: String = "com.arxivresearch.app",
        accessGroup: String? = KeychainStore.configuredAccessGroup,
        migrateLegacyItems: Bool? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.migrateLegacyItems = migrateLegacyItems
            ?? (Bundle.main.bundleIdentifier == "com.arxivresearch.app")
    }

    public static var configuredAccessGroup: String? {
        let environmentValue = ProcessInfo.processInfo.environment[accessGroupEnvironmentKey]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoKey) as? String
        return (environmentValue ?? bundleValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    public func set(_ secret: String, for key: String) throws {
        let data = Data(secret.utf8)
        let query = itemQuery(for: key, scoped: accessGroup != nil)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        if accessGroup != nil {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
    }

    public func get(_ key: String) throws -> String? {
        if let value = try value(for: key, scoped: accessGroup != nil) {
            return value
        }
        guard accessGroup != nil, migrateLegacyItems,
              let legacyValue = try value(for: key, scoped: false) else {
            return nil
        }

        try set(legacyValue, for: key)
        deleteLegacyValueWithoutPrompt(for: key)
        return legacyValue
    }

    public func delete(_ key: String) throws {
        try deleteValue(for: key, scoped: accessGroup != nil)
        if accessGroup != nil, migrateLegacyItems {
            try deleteValue(for: key, scoped: false)
        }
    }

    private func value(for key: String, scoped: Bool) throws -> String? {
        var query = itemQuery(for: key, scoped: scoped)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteValue(for key: String, scoped: Bool) throws {
        let status = SecItemDelete(itemQuery(for: key, scoped: scoped) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func deleteLegacyValueWithoutPrompt(for key: String) {
#if os(macOS)
        var query = itemQuery(for: key, scoped: false)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        _ = SecItemDelete(query as CFDictionary)
#endif
    }

    private func itemQuery(for key: String, scoped: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if scoped, let accessGroup {
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .unhandled(status):
            "Keychain operation failed with status \(status)."
        }
    }
}
