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
    private func write(
        data: Data,
        account: String,
        accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        synchronizable: Bool = false
    ) throws {
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        // `identityQuery` doubles as the add-query below, so it must already carry the
        // synchronizable flag: an item added without it lands in the device-only
        // namespace and a synchronizable lookup will never see it.

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
    //
    // The database key is the one secret that has to survive a device restore. The
    // encrypted database *is* included in device backups while the key, stored
    // `ThisDeviceOnly`, was not — so restoring to a new device produced a database
    // nothing could read, and the caller's response to a missing key is to mint a new
    // one over it. The key is therefore stored synchronizable, which means it travels
    // through the user's iCloud Keychain. That is a deliberate trade and the privacy
    // policy states it.
    //
    // Everything else this class holds (API keys, model preferences) stays device-only.

    /// Synchronizable items cannot use a `ThisDeviceOnly` protection class.
    /// `AfterFirstUnlock` still requires the device to have been unlocked once since boot.
    private static var encryptionKeyAccessibility: CFString { kSecAttrAccessibleAfterFirstUnlock }

    func storeEncryptionKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try write(
            data: keyData,
            account: encryptionKeyAccount,
            accessibility: Self.encryptionKeyAccessibility,
            synchronizable: true
        )
    }

    func getEncryptionKey() throws -> SymmetricKey? {
        // Look in the synchronizable namespace first — that is where new keys live.
        if let keyData = try readEncryptionKeyData(synchronizable: true) {
            return SymmetricKey(data: keyData)
        }

        // Then the device-only namespace, where every key written by an earlier build
        // lives. These are separate namespaces: a query that does not name
        // `kSecAttrSynchronizable` matches only non-synchronizable items, so skipping
        // this lookup would make an ordinary upgrade look like a missing key — and a
        // missing key is what makes the caller overwrite an existing database.
        guard let legacyKeyData = try readEncryptionKeyData(synchronizable: false) else {
            return nil
        }

        migrateLegacyKeyToSynchronizable(legacyKeyData)
        return SymmetricKey(data: legacyKeyData)
    }

    /// Copies a device-only key into the synchronizable namespace so it can survive a
    /// restore. Best-effort by design: if any step fails the device-only copy is left
    /// exactly where it is, because losing it is unrecoverable and failing to sync it is
    /// merely the situation we were already in.
    private func migrateLegacyKeyToSynchronizable(_ keyData: Data) {
        do {
            try write(
                data: keyData,
                account: encryptionKeyAccount,
                accessibility: Self.encryptionKeyAccessibility,
                synchronizable: true
            )
            // Only remove the old copy once the new one reads back identically.
            guard let verified = try readEncryptionKeyData(synchronizable: true), verified == keyData else {
                return
            }
            try deleteEncryptionKey(synchronizable: false)
        } catch {
            // Deliberately swallowed: the app still has a working key either way.
            return
        }
    }

    private func readEncryptionKeyData(synchronizable: Bool) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecAttrSynchronizable as String: synchronizable,
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

        return keyData
    }

    /// Removes the key from BOTH namespaces. A reset that cleared only one would leave a
    /// key behind that a later launch would match against a freshly created database.
    func deleteEncryptionKey() throws {
        try deleteEncryptionKey(synchronizable: true)
        try deleteEncryptionKey(synchronizable: false)
    }

    private func deleteEncryptionKey(synchronizable: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecAttrSynchronizable as String: synchronizable
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