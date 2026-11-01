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
    /// A failure is kept too: `DatabaseManager` and `FileSystemManager` each ask, and a
    /// store that could not be resolved once will not resolve on a second scan this launch.
    private static var resolved: Swift.Result<SymmetricKey, Error>?

    static func current() throws -> SymmetricKey {
        if let resolved { return try resolved.get() }
        let result = Swift.Result { try DataKeyResolver.forDefaultStore().resolve() }
        resolved = result
        return try result.get()
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
    /// The stored data could not be read to tell which key it needs.
    case dataStoreUnreadable

    var errorDescription: String? {
        switch self {
        case .dataStoreUnreadable:
            return "Your health data could not be read to check its encryption key. Restart your device, then reopen the app."
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

    /// The schema version from which a column holds only ciphertext. Below it the column
    /// can hold legacy plaintext, which can look like Base64 or, in a BLOB, like anything
    /// at all, so a value no key opens proves nothing there. At or above it, such a value
    /// is data sealed with a key that is not here. Columns not listed were encrypted from
    /// the moment they existed (`pending_import_reviews` in v13, `failure_reason` in v15).
    private static let ciphertextOnlySinceVersion: [String: Int] = [
        "chat_conversations.title": 11,
        "documents.file_name": 11,
        "documents.notes": 11,
        "documents.provider_name": 11,
        "documents.extracted_text": 11,
        "documents.extracted_data": 11,
        "documents.extracted_sections": 11,
        "documents.tags": 14
    ]

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
        let storeID = try readStoreID()

        if let storeID, let key = try keychain.encryptionKey(forStore: storeID) {
            log.database("Using encryption key for data store \(storeID.prefix(8)) (fingerprint: \(Self.fingerprint(key)))")
            if isReconciliationPending {
                // Values no key opened at binding: see whether their key has arrived since.
                // The key is already filed, so an unreadable Keychain or store only postpones
                // this: the marker stays and the next launch tries again.
                let legacy = (try? keychain.legacyEncryptionKeys().map(\.key)) ?? []
                let keys = Self.distinct([key] + legacy) { $0 }
                if let samples = try? collectSamples(candidates: keys),
                   reconcile(samples, selected: 0, keys: keys) {
                    clearReconciliationPending()
                }
            }
            return key
        }

        // No ID yet (an upgrade from a build that kept no ID), or an ID whose key has not
        // reached this device. Decide by what the stored data can be opened with.
        let candidates = try Self.distinct(keychain.legacyEncryptionKeys(), by: \.key)
        let samples = try collectSamples(candidates: candidates.map(\.key))

        guard !samples.isEmpty else {
            // Nothing is encrypted yet, so any key is correct. A new one, rather than a
            // legacy key that may belong to another device.
            let key = SymmetricKey(size: .bits256)
            try bind(key, to: storeID ?? UUID().uuidString, reconciliationPending: false)
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

        // A store with an ID was bound once, so its own key exists, if only in iCloud Keychain
        // not yet synced here. Values no legacy key opens may need exactly that key, and
        // binding a legacy one under the ID would overwrite its only copy. Wait for it.
        let unopened = samples.count { $0.opener == nil }
        if storeID != nil && unopened > 0 {
            log.database("Data store key has not reached this device and \(unopened) encrypted value(s) need a key other than the legacy ones; waiting for it", level: .critical)
            throw DataKeyError.noKeyOpensExistingData
        }

        let key = candidates[best].key
        log.database("Selected \(candidates[best].source) key (fingerprint: \(Self.fingerprint(key))): opens \(scores[best]) of \(samples.count) encrypted value(s)")

        // Filed under the store ID whatever happens next: the legacy slot it came from may
        // be overwritten by another device, and everything written from now on uses it.
        let complete = reconcile(samples, selected: best, keys: candidates.map(\.key))
        try bind(key, to: storeID ?? UUID().uuidString, reconciliationPending: !complete)
        return key
    }

    /// Re-encrypts with the selected key every value another key opens.
    /// - Returns: whether nothing is left to do. False when a re-encryption failed, or when
    ///   some value opens with no key here (its key may still be syncing).
    private func reconcile(_ samples: [Sample], selected: Int, keys: [SymmetricKey]) -> Bool {
        let foreign = samples.filter { $0.opener != nil && $0.opener != selected }
        if !foreign.isEmpty {
            do {
                // Personal info under more than one key means the app made a stand-in while
                // the original would not decrypt. Only rows a key here opens can be restored.
                let personalInfo = samples.filter { Self.isPersonalInfo($0.location) && $0.opener != nil }
                let restorable = Set(personalInfo.compactMap(\.opener)).count > 1 ? personalInfo : []
                try reencrypt(foreign, to: keys[selected], candidates: keys, restoringPersonalInfoFrom: restorable)
            } catch {
                log.error("Re-encrypting values sealed with another key failed: \(error.localizedDescription)", error: error, category: .database)
                return false
            }
        }

        let unopened = samples.count { $0.opener == nil }
        if unopened > 0 {
            log.database("\(unopened) encrypted value(s) open with no available key; will look again next launch", level: .warning)
        }
        return unopened == 0
    }

    /// Files the key under the store ID, then records the ID. In that order: an ID written
    /// first and a Keychain write that then failed would point at a key that is not there.
    /// A pending reconciliation is marked before either, so a bound store cannot lose it.
    private func bind(_ key: SymmetricKey, to storeID: String, reconciliationPending: Bool) throws {
        try FileManager.default.createDirectory(
            at: identityURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if reconciliationPending {
            try Data().write(to: reconciliationPendingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try keychain.storeEncryptionKey(key, forStore: storeID)
        try Data(storeID.utf8).write(to: identityURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if !reconciliationPending {
            clearReconciliationPending()
        }
    }

    /// Present while some stored value opened with no available key. A bound store only
    /// samples its data again while this exists.
    private var reconciliationPendingURL: URL { identityURL.appendingPathExtension("pending") }

    private var isReconciliationPending: Bool {
        FileManager.default.fileExists(atPath: reconciliationPendingURL.path)
    }

    private func clearReconciliationPending() {
        try? FileManager.default.removeItem(at: reconciliationPendingURL)
    }

    /// The store's ID, or nil when no ID has been recorded. An ID file that exists but
    /// cannot be read throws: taken as "no ID", it would be overwritten with a new one and
    /// the store's own key would never be looked up again.
    private func readStoreID() throws -> String? {
        guard FileManager.default.fileExists(atPath: identityURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: identityURL)
        } catch {
            log.error("Could not read the data store ID: \(error.localizedDescription)", error: error, category: .database)
            throw DataKeyError.dataStoreUnreadable
        }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              UUID(uuidString: text) != nil else {
            // Not an ID this code wrote; there is no account name to recover from it.
            log.database("Ignoring a malformed data store ID file", level: .warning)
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

    /// Every encrypted value in the store, and which candidate opens it.
    ///
    /// Fails rather than skips when the store cannot be read: an unreadable store would
    /// otherwise look empty, and an empty store is the one case that mints a key.
    private func collectSamples(candidates: [SymmetricKey]) throws -> [Sample] {
        var samples: [Sample] = []

        do {
            for databaseURL in databaseURLs where FileManager.default.fileExists(atPath: databaseURL.path) {
                let db = try Connection(databaseURL.path, readonly: true)
                let columns = try Self.columnsByTable(db)
                // No version table means a schema older than any encryption migration.
                let schemaVersion = columns["database_version"] == nil
                    ? 0
                    : Int((try db.scalar("SELECT MAX(version) FROM database_version") as? Int64) ?? 0)

                // A missing table or column means an older schema; there is nothing to check.
                for (table, column) in Self.encryptedColumns where columns[table]?.contains(column) == true {
                    let holdsOnlyCiphertext = schemaVersion >= Self.ciphertextOnlySinceVersion["\(table).\(column)", default: 0]
                    let recordType = table == "health_data" ? ", type" : ""
                    let rows = try db.prepare("SELECT rowid, \(column)\(recordType) FROM \(table) WHERE \(column) IS NOT NULL")
                    while let row = try rows.failableNext() {
                        guard let rowID = row[0] as? Int64,
                              let (sealed, isText) = Self.sealedBytes(row[1]) else { continue }
                        let location = Location.cell(
                            database: databaseURL, table: table, column: column, rowID: rowID,
                            isText: isText, recordType: row.count > 2 ? row[2] as? String : nil
                        )
                        let opener = Self.opener(of: sealed, among: candidates)
                        // A value no key opens counts only where it cannot be legacy plaintext.
                        if opener != nil || holdsOnlyCiphertext && sealed.count >= Self.minimumSealedLength {
                            samples.append(Sample(location: location, opener: opener))
                        }
                    }
                }
            }

            for directory in fileDirectories where FileManager.default.fileExists(atPath: directory.path) {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                for url in files {
                    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    // A file counts only when some key opens it. Legacy plaintext documents can
                    // be any image type the importer accepts, so a file no key opens proves
                    // nothing; its `documents` row, encrypted since v11, is the evidence.
                    if let opener = Self.opener(of: try Data(contentsOf: url), among: candidates) {
                        samples.append(Sample(location: .file(url), opener: opener))
                    }
                }
            }
        } catch {
            log.error("Could not read the data store to check its encryption key: \(error.localizedDescription)", error: error, category: .database)
            throw DataKeyError.dataStoreUnreadable
        }

        return samples
    }

    /// Each table's column names. A table that is not there is simply absent.
    private static func columnsByTable(_ db: Connection) throws -> [String: Set<String>] {
        var columns: [String: Set<String>] = [:]
        let rows = try db.prepare("""
            SELECT m.name, p.name FROM sqlite_master AS m, pragma_table_info(m.name) AS p
            WHERE m.type = 'table'
            """)
        while let row = try rows.failableNext() {
            guard let table = row[0] as? String, let column = row[1] as? String else { continue }
            columns[table, default: []].insert(column)
        }
        return columns
    }

    // MARK: Re-encryption

    /// - Parameter restoringPersonalInfoFrom: Personal info records, all openable, among which
    ///   the original is to be put back in front. Empty when there is nothing to restore.
    private func reencrypt(
        _ samples: [Sample],
        to key: SymmetricKey,
        candidates: [SymmetricKey],
        restoringPersonalInfoFrom personalInfo: [Sample]
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
                // Only openable rows are candidates: promoting one no key opens would make the
                // app read an undecryptable profile and create yet another stand-in.
                let rowIDs = personalInfo.compactMap { sample -> Int64? in
                    guard case .cell(databaseURL, _, _, let rowID, _, _) = sample.location else { return nil }
                    return rowID
                }
                if !rowIDs.isEmpty {
                    let candidateRows = rowIDs.map(String.init).joined(separator: ",")
                    try db.run("""
                        UPDATE health_data
                        SET updated_at = (SELECT MAX(updated_at) FROM health_data WHERE type = 'personal_info') + 1
                        WHERE rowid = (SELECT rowid FROM health_data WHERE rowid IN (\(candidateRows))
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

    /// The items in order, without any whose key an earlier item already holds.
    private static func distinct<T>(_ items: [T], by key: (T) -> SymmetricKey) -> [T] {
        var seen: [SymmetricKey] = []
        return items.filter { item in
            guard !seen.contains(where: { sameKey($0, key(item)) }) else { return false }
            seen.append(key(item))
            return true
        }
    }

    private static func sameKey(_ lhs: SymmetricKey, _ rhs: SymmetricKey) -> Bool {
        lhs.withUnsafeBytes { Data($0) } == rhs.withUnsafeBytes { Data($0) }
    }

    static func fingerprint(_ key: SymmetricKey) -> String {
        let hash = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        return hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
