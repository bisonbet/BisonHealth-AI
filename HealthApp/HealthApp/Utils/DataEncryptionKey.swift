import Foundation
import CryptoKit
@preconcurrency import SQLite

// MARK: - Data Encryption Key
//
// One key encrypts this device's database and its document files. It lives in the
// Keychain under an account named for a *data store ID*, a UUID kept in a plain file
// beside the database:
//
//   - The ID file is in the device backup with the database, and the key item is
//     synchronizable, so a restore to a new device brings back both halves together.
//   - Every device has its own ID, so two devices on one Apple ID never share a slot.
//
// Builds from 2026-10-23 kept the key in ONE synchronizable slot. iCloud Keychain synced
// that slot between devices whose databases are separate, so one device's key arrived on
// another and was used there over the key its data was actually encrypted with. Every
// existing record failed to decrypt, and records written afterwards were sealed with the
// foreign key. `DataKeyResolver` picks the key by trying it against the stored data, and
// re-encrypts anything a different candidate key can open.

/// The process-wide data key. Both `DatabaseManager` and `FileSystemManager` read it from
/// here, so they cannot end up holding different keys.
@MainActor
enum DataEncryptionKey {
    private static var cached: SymmetricKey?

    static func current() throws -> SymmetricKey {
        if let cached { return cached }
        let key = try DataKeyResolver.forDefaultStore().resolve()
        cached = key
        return key
    }
}

// MARK: - Key Storage

/// A data key from before keys were filed under a data store ID.
struct LegacyEncryptionKey {
    enum Source {
        /// Device-only. Written by builds before 2026-10-23, and so made on this device.
        case deviceOnly
        /// The single synchronizable slot from 2026-10-23. May belong to another device.
        case sharedSynchronizable
    }

    let key: SymmetricKey
    let source: Source
}

/// The Keychain operations the resolver needs. Extracted so the resolver can be tested
/// without touching the real Keychain.
protocol EncryptionKeyStoring {
    func encryptionKey(forStore storeID: String) throws -> SymmetricKey?
    func storeEncryptionKey(_ key: SymmetricKey, forStore storeID: String) throws
    func legacyEncryptionKeys() throws -> [LegacyEncryptionKey]
}

enum DataKeyError: LocalizedError {
    /// Encrypted data exists and none of the keys on this device can open it.
    case noKeyOpensExistingData

    var errorDescription: String? {
        switch self {
        case .noKeyOpensExistingData:
            return "The encryption key for your health data is not available on this device. If you restored from a backup, make sure iCloud Keychain is on and has finished syncing, then reopen the app."
        }
    }
}

// MARK: - Resolver

@MainActor
struct DataKeyResolver {
    let keychain: EncryptionKeyStoring
    /// Plain file holding this data store's ID.
    let identityURL: URL
    /// Databases to examine. The first is the live one; any others are legacy locations
    /// that a later migration moves into place.
    let databaseURLs: [URL]
    /// Directories of encrypted files (imported documents and their thumbnails).
    let fileDirectories: [URL]

    private let log = AppLog.shared

    /// Every column sealed with the data key. BLOB cells hold the AES-GCM combined
    /// representation; TEXT cells hold it as Base64. A column added later that is
    /// encrypted with the data key must be listed here, or a re-key would leave it behind.
    static let encryptedColumns: [(table: String, column: String)] = [
        ("health_data", "encrypted_data"),
        ("appointment_preps", "encrypted_data"),
        ("chat_messages", "content"),
        ("chat_conversations", "title"),
        ("documents", "file_name"),
        ("documents", "notes"),
        ("documents", "tags"),
        ("documents", "provider_name"),
        ("documents", "extracted_text"),
        ("documents", "extracted_data"),
        ("documents", "extracted_sections"),
        ("documents", "failure_reason"),
        ("pending_import_reviews", "payload")
    ]

    /// Columns encrypted since the first schema. Only these can hold a value that proves
    /// the data needs a key nobody has: every other column held plaintext before the
    /// migration that encrypted it (v11, v14, v15), and plaintext can look like Base64 or,
    /// in a BLOB, like anything at all.
    private static let alwaysEncryptedTables: Set<String> = ["health_data", "chat_messages", "appointment_preps"]

    static func forDefaultStore() -> DataKeyResolver {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        let databaseDirectory = applicationSupport?.appendingPathComponent("HealthApp/Database")
            ?? fileManager.temporaryDirectory
        let fileBase = documents?.appendingPathComponent("HealthApp")

        return DataKeyResolver(
            keychain: Keychain(),
            identityURL: databaseDirectory.appendingPathComponent("data-store-id"),
            databaseURLs: [
                databaseDirectory.appendingPathComponent("health_data.sqlite"),
                // Where builds before the move to Application Support kept it.
                fileBase?.appendingPathComponent("Database/health_data.sqlite")
            ].compactMap { $0 },
            fileDirectories: [
                fileBase?.appendingPathComponent("Documents/Imported"),
                fileBase?.appendingPathComponent("Documents/Thumbnails")
            ].compactMap { $0 }
        )
    }

    // MARK: Resolution

    func resolve() throws -> SymmetricKey {
        let storeID = readStoreID()

        if let storeID, let key = try keychain.encryptionKey(forStore: storeID) {
            log.database("Using encryption key for data store \(storeID.prefix(8)) (fingerprint: \(Self.fingerprint(key)))")
            return key
        }

        // No ID yet (an upgrade from a build that kept no ID), or an ID whose key has not
        // reached this device. Decide by what the stored data can be opened with.
        let candidates = try Self.distinct(keychain.legacyEncryptionKeys())
        let samples = collectSamples(candidates: candidates.map(\.key))

        guard !samples.isEmpty else {
            // Nothing is encrypted yet, so any key is correct. A new one, rather than a
            // legacy key that may belong to another device.
            let key = SymmetricKey(size: .bits256)
            try bind(key, to: storeID ?? UUID().uuidString)
            log.database("Created a new encryption key (fingerprint: \(Self.fingerprint(key)))", level: .warning)
            return key
        }

        var scores = Array(repeating: 0, count: candidates.count)
        for sample in samples {
            if let opener = sample.opener { scores[opener] += 1 }
        }

        // Most data opened wins. On a tie, the device-only key: it was made on this device.
        guard let best = candidates.indices.max(by: { lhs, rhs in
            if scores[lhs] != scores[rhs] { return scores[lhs] < scores[rhs] }
            return candidates[lhs].source == .sharedSynchronizable && candidates[rhs].source == .deviceOnly
        }), scores[best] > 0 else {
            // Never mint a key over data that exists: that is what destroys it.
            log.database("\(samples.count) encrypted value(s) exist and none of \(candidates.count) available key(s) opens them", level: .critical)
            throw DataKeyError.noKeyOpensExistingData
        }

        let key = candidates[best].key
        let foreign = samples.filter { $0.opener != nil && $0.opener != best }
        log.database("Selected \(candidates[best].source) key (fingerprint: \(Self.fingerprint(key))): opens \(scores[best]) of \(samples.count) encrypted value(s); \(foreign.count) sealed with another key")

        if !foreign.isEmpty {
            do {
                let personalInfoKeys = Set(samples.filter { Self.isPersonalInfo($0.location) }.compactMap(\.opener))
                try reencrypt(
                    foreign,
                    to: key,
                    candidates: candidates.map(\.key),
                    restoreOriginalPersonalInfo: personalInfoKeys.count > 1
                )
            } catch {
                // Leave the store unbound so the next launch tries again. The selected key
                // still opens most of the data, so the app can run meanwhile.
                log.error("Re-encrypting values sealed with another key failed: \(error.localizedDescription)", error: error, category: .database)
                return key
            }
        }

        try bind(key, to: storeID ?? UUID().uuidString)
        return key
    }

    /// Files the key under the store ID, then records the ID. In that order: an ID written
    /// first and a Keychain write that then failed would point at a key that is not there.
    private func bind(_ key: SymmetricKey, to storeID: String) throws {
        try keychain.storeEncryptionKey(key, forStore: storeID)
        try FileManager.default.createDirectory(
            at: identityURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(storeID.utf8).write(to: identityURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func readStoreID() -> String? {
        guard let data = try? Data(contentsOf: identityURL),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              UUID(uuidString: text) != nil else {
            return nil
        }
        return text
    }

    // MARK: Sampling

    /// Where an encrypted value lives, so it can be rewritten in place.
    enum Location: Equatable {
        case cell(database: URL, table: String, column: String, rowID: Int64, isText: Bool, recordType: String?)
        case file(URL)
    }

    struct Sample {
        let location: Location
        /// Index of the candidate key that opens it, or nil when none does (legacy
        /// plaintext, or a value sealed with a key that is not here).
        let opener: Int?
    }

    private func collectSamples(candidates: [SymmetricKey]) -> [Sample] {
        var samples: [Sample] = []

        for databaseURL in databaseURLs where FileManager.default.fileExists(atPath: databaseURL.path) {
            guard let db = try? Connection(databaseURL.path, readonly: true) else {
                log.database("Could not open \(databaseURL.lastPathComponent) to check its encryption key", level: .warning)
                continue
            }
            for (table, column) in Self.encryptedColumns {
                let recordType = table == "health_data" ? ", type" : ""
                // A missing table or column means an older schema; there is nothing to check.
                guard let rows = try? db.prepare("SELECT rowid, \(column)\(recordType) FROM \(table) WHERE \(column) IS NOT NULL") else {
                    continue
                }
                for row in rows {
                    guard let rowID = row[0] as? Int64,
                          let (sealed, isText) = Self.sealedBytes(row[1]) else { continue }
                    let location = Location.cell(
                        database: databaseURL, table: table, column: column, rowID: rowID,
                        isText: isText, recordType: row.count > 2 ? row[2] as? String : nil
                    )
                    let opener = Self.opener(of: sealed, among: candidates)
                    // A value no key opens counts only where it cannot be legacy plaintext.
                    if opener != nil || Self.alwaysEncryptedTables.contains(table) && sealed.count >= Self.minimumSealedLength {
                        samples.append(Sample(location: location, opener: opener))
                    }
                }
            }
        }

        for directory in fileDirectories {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in files {
                guard let sealed = try? Data(contentsOf: url) else { continue }
                // Plain files left by earlier versions open with no key and do not count.
                let opener = Self.opener(of: sealed, among: candidates)
                if opener != nil || sealed.count >= Self.minimumSealedLength && !Self.isKnownPlaintext(sealed) {
                    samples.append(Sample(location: .file(url), opener: opener))
                }
            }
        }

        return samples
    }

    // MARK: Re-encryption

    /// - Parameter restoreOriginalPersonalInfo: Personal info records exist under more than
    ///   one key, so the app made a second one while the first would not decrypt.
    private func reencrypt(
        _ samples: [Sample],
        to key: SymmetricKey,
        candidates: [SymmetricKey],
        restoreOriginalPersonalInfo: Bool
    ) throws {
        let cells = Dictionary(grouping: samples.compactMap { sample -> (URL, Sample)? in
            if case .cell(let database, _, _, _, _, _) = sample.location { return (database, sample) }
            return nil
        }, by: \.0)

        for (databaseURL, entries) in cells {
            let db = try Connection(databaseURL.path)
            backUp(db, at: databaseURL)

            try db.transaction {
                for (_, sample) in entries {
                    guard case .cell(_, let table, let column, let rowID, let isText, _) = sample.location,
                          let opener = sample.opener else { continue }

                    let stored = try db.scalar("SELECT \(column) FROM \(table) WHERE rowid = ?", rowID)
                    guard let (sealed, _) = Self.sealedBytes(stored) else { continue }
                    let resealed = try Self.reseal(sealed, from: candidates[opener], to: key)
                    let value: Binding = isText ? resealed.base64EncodedString() : Blob(bytes: [UInt8](resealed))
                    try db.run("UPDATE \(table) SET \(column) = ? WHERE rowid = ?", value, rowID)
                }

                // Personal info is read as one record: the most recently updated. The app
                // creates a fresh one when none decrypts, so the stand-in is newer than the
                // user's own and would hide it. Which key won says nothing about which record
                // is the user's, so nothing is deleted: the earliest-created record is moved
                // to the front, and the stand-in stays in the table behind it.
                if restoreOriginalPersonalInfo {
                    try db.run("""
                        UPDATE health_data
                        SET updated_at = (SELECT MAX(updated_at) FROM health_data WHERE type = 'personal_info') + 1
                        WHERE rowid = (SELECT rowid FROM health_data WHERE type = 'personal_info'
                                       ORDER BY created_at ASC, rowid ASC LIMIT 1)
                        """)
                    log.database("Restored the original personal info record ahead of one created while the wrong key was in use", level: .warning)
                }
            }
            log.database("Re-encrypted \(entries.count) value(s) in \(databaseURL.lastPathComponent) with the selected key")
        }

        for sample in samples {
            guard case .file(let url) = sample.location, let opener = sample.opener else { continue }
            let resealed = try Self.reseal(try Data(contentsOf: url), from: candidates[opener], to: key)
            try resealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// A copy of the database before anything in it is rewritten. Named like the migration
    /// backups so that an erase removes it with them.
    private func backUp(_ db: Connection, at databaseURL: URL) {
        let backupURL = URL(fileURLWithPath: databaseURL.path + ".backup.rekey-\(Int(Date().timeIntervalSince1970))")
        do {
            try db.run("VACUUM INTO ?", backupURL.path)
        } catch {
            log.database("Could not back up the database before re-encrypting: \(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: Helpers

    /// Nonce (12) + tag (16): nothing shorter can be an AES-GCM combined value.
    private static let minimumSealedLength = 28

    private static func isPersonalInfo(_ location: Location) -> Bool {
        guard case .cell(_, let table, _, _, _, let recordType) = location else { return false }
        return table == "health_data" && recordType == "personal_info"
    }

    /// The AES-GCM bytes a cell holds, and whether the cell is TEXT (Base64).
    private static func sealedBytes(_ value: Binding?) -> (Data, Bool)? {
        if let blob = value as? Blob {
            return (Data(blob.bytes), false)
        }
        if let text = value as? String, let data = Data(base64Encoded: text) {
            return (data, true)
        }
        return nil
    }

    private static func opener(of sealed: Data, among candidates: [SymmetricKey]) -> Int? {
        guard sealed.count >= minimumSealedLength,
              let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return candidates.firstIndex { (try? AES.GCM.open(box, using: $0)) != nil }
    }

    private static func reseal(_ sealed: Data, from oldKey: SymmetricKey, to newKey: SymmetricKey) throws -> Data {
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: oldKey)
        guard let combined = try AES.GCM.seal(plaintext, using: newKey).combined else {
            throw DatabaseError.encryptionFailed
        }
        return combined
    }

    /// Headers of the formats the app imports (PDF, JPEG, PNG, DOCX as ZIP, HEIC as an ISO
    /// media file): files written before files were encrypted.
    private static func isKnownPlaintext(_ data: Data) -> Bool {
        data.starts(with: [0x25, 0x50, 0x44, 0x46])
            || data.starts(with: [0xFF, 0xD8, 0xFF])
            || data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || data.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || data.dropFirst(4).starts(with: Array("ftyp".utf8))
    }

    private static func distinct(_ keys: [LegacyEncryptionKey]) -> [LegacyEncryptionKey] {
        var seen: [Data] = []
        return keys.filter { candidate in
            let bytes = candidate.key.withUnsafeBytes { Data($0) }
            guard !seen.contains(bytes) else { return false }
            seen.append(bytes)
            return true
        }
    }

    static func fingerprint(_ key: SymmetricKey) -> String {
        let hash = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        return hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
