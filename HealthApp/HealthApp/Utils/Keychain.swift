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
    // encrypted database *is* included in device backups, so the key is stored
    // synchronizable and travels through the user's iCloud Keychain. That is a deliberate
    // trade and the privacy policy states it.
    //
    // Each key is filed under its data store's ID (see `DataKeyResolver`). The builds
    // from 2026-10-23 used one synchronizable account for every device, and iCloud
    // Keychain then delivered one device's key to another. That account and the older
    // device-only one are now only ever read, never written or deleted: either may be
    // the sole copy of the key some existing data needs.
    //
    // Everything else this class holds (API keys, model preferences) stays device-only.

    /// Synchronizable items cannot use a `ThisDeviceOnly` protection class.
    /// `AfterFirstUnlock` still requires the device to have been unlocked once since boot.
    private static var encryptionKeyAccessibility: CFString { kSecAttrAccessibleAfterFirstUnlock }

    private func encryptionKeyAccount(forStore storeID: String) -> String {
        "\(encryptionKeyAccount).\(storeID)"
    }

    private func readKeyData(account: String, synchronizable: Bool) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    /// Rejects anything that is not a 256-bit key rather than handing it to AES-GCM.
    private func validatedKey(_ keyData: Data?) throws -> SymmetricKey? {
        guard let keyData else { return nil }
        guard keyData.count == 32 else { throw KeychainError.invalidData }
        return SymmetricKey(data: keyData)
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

// MARK: - Data Key Storage
extension Keychain: EncryptionKeyStoring {
    func encryptionKey(forStore storeID: String) throws -> SymmetricKey? {
        try validatedKey(readKeyData(account: encryptionKeyAccount(forStore: storeID), synchronizable: true))
    }

    func storeEncryptionKey(_ key: SymmetricKey, forStore storeID: String) throws {
        try write(
            data: key.withUnsafeBytes { Data($0) },
            account: encryptionKeyAccount(forStore: storeID),
            accessibility: Self.encryptionKeyAccessibility,
            synchronizable: true
        )
    }

    /// These are separate namespaces: a query that does not name `kSecAttrSynchronizable`
    /// matches only non-synchronizable items.
    ///
    /// A slot holding something other than a 256-bit key is skipped, not thrown: it can open
    /// nothing, and failing here would block the other slot's key from opening the data.
    func legacyEncryptionKeys() throws -> [LegacyEncryptionKey] {
        let slots: [(synchronizable: Bool, source: LegacyEncryptionKey.Source)] = [
            (false, .deviceOnly),
            (true, .sharedSynchronizable)
        ]
        return try slots.compactMap { slot in
            guard let keyData = try readKeyData(account: encryptionKeyAccount, synchronizable: slot.synchronizable),
                  keyData.count == 32 else { return nil }
            return LegacyEncryptionKey(key: SymmetricKey(data: keyData), source: slot.source)
        }
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