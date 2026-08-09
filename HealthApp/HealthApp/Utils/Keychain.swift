import Foundation
import Security
import CryptoKit

// MARK: - Keychain Storage

/// The generic item operations callers depend on. Extracted so components that
/// persist secrets can be tested without mutating the real login keychain.
protocol KeychainStoring {
    func store(data: Data, for account: String) throws
    func retrieve(for account: String) throws -> Data?
    func delete(for account: String) throws
    func store(string: String, for account: String) throws
    func retrieveString(for account: String) throws -> String?
}

// MARK: - Keychain Helper
class Keychain: KeychainStoring {

    private let service = "com.healthapp.encryption"
    private let encryptionKeyAccount = "health_data_encryption_key"

    // MARK: - Writing

    /// Writes an item, updating in place when it already exists.
    ///
    /// Deliberately not delete-then-add: if the add failed after the delete succeeded,
    /// the previous value would already be destroyed. A failed update leaves the stored
    /// item untouched, so a transient Keychain error cannot lose a key.
    private func write(data: Data, account: String) throws {
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(identityQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.storeFailed(updateStatus)
        }

        var addQuery = identityQuery
        addQuery.merge(attributes) { current, _ in current }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.storeFailed(addStatus)
        }
    }

    // MARK: - Encryption Key Management
    func storeEncryptionKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try write(data: keyData, account: encryptionKeyAccount)
    }
    
    func getEncryptionKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }
        
        guard let keyData = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return SymmetricKey(data: keyData)
    }
    
    func deleteEncryptionKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: encryptionKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Generic Keychain Operations
    func store(data: Data, for account: String) throws {
        try write(data: data, account: account)
    }
    
    func retrieve(for account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }
        
        return result as? Data
    }
    
    func delete(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - String Convenience Methods
    func store(string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try store(data: data, for: account)
    }
    
    func retrieveString(for account: String) throws -> String? {
        guard let data = try retrieve(for: account) else {
            return nil
        }
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
}

// MARK: - Keychain Errors
enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store item in keychain: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve item from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete item from keychain: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}