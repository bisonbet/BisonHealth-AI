import XCTest
import CryptoKit
import SQLite
@testable import HealthApp

/// Keychain stand-in: per-store keys plus the two legacy slots, all in memory.
private final class InMemoryKeyStore: EncryptionKeyStoring {
    var storeKeys: [String: SymmetricKey] = [:]
    var deviceOnly: SymmetricKey?
    var sharedSynchronizable: SymmetricKey?

    func encryptionKey(forStore storeID: String) throws -> SymmetricKey? { storeKeys[storeID] }

    /// Called as each key is filed, to observe what the store held at that moment.
    var onStore: (() -> Void)?

    func storeEncryptionKey(_ key: SymmetricKey, forStore storeID: String) throws {
        onStore?()
        storeKeys[storeID] = key
    }

    func legacyEncryptionKeys() throws -> [LegacyEncryptionKey] {
        [
            deviceOnly.map { LegacyEncryptionKey(key: $0, source: .deviceOnly) },
            sharedSynchronizable.map { LegacyEncryptionKey(key: $0, source: .sharedSynchronizable) }
        ].compactMap { $0 }
    }
}

@MainActor
final class DataKeyResolverTests: XCTestCase {
    // XCTest makes a new instance per test, so each test gets its own of both.
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let keychain = InMemoryKeyStore()

    private var databaseURL: URL { directory.appendingPathComponent("health_data.sqlite") }
    private var identityURL: URL { directory.appendingPathComponent("data-store-id") }
    private var filesURL: URL { directory.appendingPathComponent("Imported") }

    override func setUp() async throws {
        try await super.setUp()
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func makeResolver() -> DataKeyResolver {
        DataKeyResolver(
            keychain: keychain,
            identityURL: identityURL,
            databaseURLs: [databaseURL],
            fileDirectories: [filesURL]
        )
    }

    private func seal(_ text: String, with key: SymmetricKey) throws -> Data {
        try XCTUnwrap(AES.GCM.seal(Data(text.utf8), using: key).combined)
    }

    private func open(_ sealed: Data, with key: SymmetricKey) -> String? {
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// Just the encrypted columns the resolver reads, in their real storage formats.
    private func makeDatabase() throws -> Connection {
        let db = try Connection(databaseURL.path)
        try db.execute("""
            CREATE TABLE health_data (id TEXT PRIMARY KEY, type TEXT, encrypted_data BLOB, created_at INTEGER, updated_at INTEGER);
            CREATE TABLE documents (id TEXT PRIMARY KEY, file_name TEXT, tags TEXT, extracted_data BLOB);
            CREATE TABLE chat_conversations (id TEXT PRIMARY KEY, title TEXT);
            """)
        return db
    }

    /// `time` is both created and updated: a later record was made later.
    private func insertHealthData(_ db: Connection, id: String, type: String, sealed: Data, time: Int64 = 0) throws {
        try db.run("INSERT INTO health_data (id, type, encrypted_data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                   id, type, Blob(bytes: [UInt8](sealed)), time, time)
    }

    /// The id of the personal info record the app reads: the most recently updated.
    private func visiblePersonalInfo(_ db: Connection) throws -> String? {
        try db.scalar("SELECT id FROM health_data WHERE type = 'personal_info' ORDER BY updated_at DESC LIMIT 1") as? String
    }

    private func storedBlob(_ db: Connection, id: String) throws -> Data? {
        (try db.scalar("SELECT encrypted_data FROM health_data WHERE id = ?", id) as? Blob).map { Data($0.bytes) }
    }

    // MARK: - Tests

    func testFreshInstallCreatesAndKeepsOneKey() throws {
        let first = try makeResolver().resolve()
        let second = try makeResolver().resolve()

        XCTAssertEqual(first.withUnsafeBytes { Data($0) }, second.withUnsafeBytes { Data($0) })
        XCTAssertEqual(keychain.storeKeys.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: identityURL.path))
    }

    func testEmptyStoreDoesNotAdoptAnotherDevicesKey() throws {
        let foreign = SymmetricKey(size: .bits256)
        keychain.sharedSynchronizable = foreign

        let key = try makeResolver().resolve()

        XCTAssertNotEqual(key.withUnsafeBytes { Data($0) }, foreign.withUnsafeBytes { Data($0) })
    }

    func testUpgradeAdoptsTheDeviceOnlyKeyThatOpensTheData() throws {
        let own = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertEqual(keychain.storeKeys.count, 1, "The key is filed under the new store ID")
        XCTAssertNotNil(keychain.deviceOnly, "The legacy copy is never removed")
    }

    /// The failure seen on device: another device's key arrived in the shared synchronizable
    /// slot and was used over the key this device's data was sealed with, and a few values
    /// were then written with it.
    func testForeignSharedKeyIsRejectedAndItsWritesAreReencrypted() throws {
        let own = SymmetricKey(size: .bits256)
        let foreign = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        keychain.sharedSynchronizable = foreign

        let db = try makeDatabase()
        try insertHealthData(db, id: "profile", type: "personal_info", sealed: seal("own profile", with: own), time: 100)
        for index in 0..<3 {
            try insertHealthData(db, id: "lab\(index)", type: "blood_test", sealed: seal("lab \(index)", with: own))
        }
        // Written during the broken session.
        try insertHealthData(db, id: "profile-dup", type: "personal_info", sealed: seal("health sync only", with: foreign), time: 200)
        try insertHealthData(db, id: "lab-new", type: "blood_test", sealed: seal("new lab", with: foreign), time: 200)
        try db.run("INSERT INTO documents (id, file_name, tags) VALUES ('d', ?, ?)",
                   try seal("report.pdf", with: own).base64EncodedString(),
                   try seal("[\"lipids\"]", with: foreign).base64EncodedString())
        let fileURL = filesURL.appendingPathComponent("doc.pdf")
        try seal("pdf bytes", with: foreign).write(to: fileURL)

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "lab-new")), with: own), "new lab")
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "lab0")), with: own), "lab 0")
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "profile")), with: own), "own profile")
        XCTAssertEqual(try visiblePersonalInfo(db), "profile",
                       "The stand-in profile would otherwise sort ahead of the user's own record")
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "profile-dup")), with: own), "health sync only",
                       "Nothing is deleted")

        let tags = try XCTUnwrap(try db.scalar("SELECT tags FROM documents WHERE id = 'd'") as? String)
        XCTAssertEqual(open(try XCTUnwrap(Data(base64Encoded: tags)), with: own), "[\"lipids\"]")
        XCTAssertEqual(open(try Data(contentsOf: fileURL), with: own), "pdf bytes")

        XCTAssertNotNil(keychain.sharedSynchronizable, "Another device may still need the shared key")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("health_data.sqlite.backup.rekey-") }
        XCTAssertEqual(backups.count, 1)
    }

    /// More values were written during the broken session than before it, so the foreign
    /// key wins. The user's original profile must still be kept, and be the one shown.
    func testOriginalProfileSurvivesWhenTheForeignKeyWins() throws {
        let own = SymmetricKey(size: .bits256)
        let foreign = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        keychain.sharedSynchronizable = foreign

        let db = try makeDatabase()
        try insertHealthData(db, id: "profile", type: "personal_info", sealed: seal("own profile", with: own), time: 100)
        try insertHealthData(db, id: "profile-dup", type: "personal_info", sealed: seal("health sync only", with: foreign), time: 200)
        for index in 0..<3 {
            try insertHealthData(db, id: "new\(index)", type: "blood_test", sealed: seal("new \(index)", with: foreign), time: 200)
        }

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, foreign.withUnsafeBytes { Data($0) })
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "profile")), with: foreign), "own profile")
        XCTAssertEqual(try visiblePersonalInfo(db), "profile")
    }

    /// Before v11, titles and extracted data were stored in the clear. "Test" is valid
    /// Base64, and a plaintext BLOB can be any bytes, but neither proves a key is missing:
    /// the v11 migration still has to run on them.
    func testLegacyPlaintextDoesNotCountAsUnreadableData() throws {
        let db = try makeDatabase()
        try db.run("INSERT INTO chat_conversations (id, title) VALUES ('c', 'Test')")
        try db.run("INSERT INTO documents (id, file_name, extracted_data) VALUES ('d', 'Quest lab results', ?)",
                   Blob(bytes: [UInt8]("{\"results\":[{\"name\":\"LDL\",\"value\":120}]}".utf8)))

        XCTAssertNoThrow(try makeResolver().resolve())
        XCTAssertEqual(keychain.storeKeys.count, 1)
    }

    /// A restore whose per-store key has not synced yet, holding only empty conversations.
    /// From v11 their titles are always ciphertext, so they prove a key is missing: minting
    /// one would strand them and file a wrong key under the restored store's ID.
    func testRestoredStoreWithOnlyEncryptedTitlesWaitsForItsKey() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE database_version (version INTEGER PRIMARY KEY, created_at INTEGER)")
        try db.run("INSERT INTO database_version (version, created_at) VALUES (?, 0)", DatabaseManager.currentDatabaseVersion)
        try db.run("INSERT INTO chat_conversations (id, title) VALUES ('c', ?)",
                   try seal("New Conversation", with: SymmetricKey(size: .bits256)).base64EncodedString())
        let storeID = UUID().uuidString
        try Data(storeID.utf8).write(to: identityURL)

        XCTAssertThrowsError(try makeResolver().resolve()) { error in
            guard case DataKeyError.noKeyOpensExistingData = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertNil(keychain.storeKeys[storeID])
    }

    /// A mixed-key store where only one of the keys has reached this device, and that key is
    /// in the shared slot, which another device can overwrite. The key must be filed under
    /// the store at once, and the values it cannot open must still be looked for later.
    func testStoreKeepsItsKeyAndKeepsLookingForValuesNoKeyOpens() throws {
        let own = SymmetricKey(size: .bits256)
        let late = SymmetricKey(size: .bits256)
        keychain.sharedSynchronizable = own

        let db = try makeDatabase()
        for index in 0..<2 {
            try insertHealthData(db, id: "lab\(index)", type: "blood_test", sealed: seal("lab \(index)", with: own))
        }
        try insertHealthData(db, id: "lab-late", type: "blood_test", sealed: seal("late lab", with: late))

        let first = try makeResolver().resolve()
        XCTAssertEqual(first.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertEqual(keychain.storeKeys.count, 1, "Filed under the store before the shared slot can change")

        // Another device overwrites the shared slot, with the key the stranded value needs.
        keychain.sharedSynchronizable = late
        let second = try makeResolver().resolve()

        XCTAssertEqual(second.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "lab-late")), with: own), "late lab")
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.appendingPathExtension("pending").path),
                       "Nothing is left to look for")
    }

    /// A restore whose per-store key has not synced, where a legacy key opens only part of
    /// the data. The rest may need the store's own key, so a legacy key must not replace it.
    func testRestoredStoreWaitsForItsKeyWhenALegacyKeyOpensOnlySomeData() throws {
        let storeKey = SymmetricKey(size: .bits256)
        let legacy = SymmetricKey(size: .bits256)
        keychain.deviceOnly = legacy

        let db = try makeDatabase()
        try insertHealthData(db, id: "old", type: "blood_test", sealed: seal("old lab", with: legacy))
        try insertHealthData(db, id: "new", type: "blood_test", sealed: seal("new lab", with: storeKey))
        let storeID = UUID().uuidString
        try Data(storeID.utf8).write(to: identityURL)

        XCTAssertThrowsError(try makeResolver().resolve()) { error in
            guard case DataKeyError.noKeyOpensExistingData = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertNil(keychain.storeKeys[storeID], "The store's own key slot is not overwritten")

        // The store's key syncs.
        keychain.storeKeys[storeID] = storeKey
        let key = try makeResolver().resolve()
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, storeKey.withUnsafeBytes { Data($0) })
    }

    /// A restored store whose key has not synced and whose database cannot be read. It
    /// must not look empty: an empty store is the one case that mints a key.
    func testUnreadableStoreThrowsInsteadOfLookingEmpty() throws {
        try Data(repeating: 0xAB, count: 4096).write(to: databaseURL)
        let storeID = UUID().uuidString
        try Data(storeID.utf8).write(to: identityURL)

        XCTAssertThrowsError(try makeResolver().resolve()) { error in
            guard case DataKeyError.dataStoreUnreadable = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertTrue(keychain.storeKeys.isEmpty)
    }

    /// A pre-encryption document in a format with no recognised header (GIF here) opens with
    /// no key, but proves nothing: it must neither block resolution nor leave it pending.
    func testLegacyPlaintextFileOfAnyTypeDoesNotCount() throws {
        let own = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))
        try Data("GIF89a".utf8 + [UInt8](repeating: 0x2C, count: 64)).write(to: filesURL.appendingPathComponent("scan.gif"))

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.appendingPathExtension("pending").path))
    }

    /// An ID file that exists but cannot be read must not be taken for "no ID" and replaced.
    func testUnreadableIdentityFileThrowsInsteadOfStartingOver() throws {
        try FileManager.default.createDirectory(at: identityURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try makeResolver().resolve()) { error in
            guard case DataKeyError.dataStoreUnreadable = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertTrue(keychain.storeKeys.isEmpty)
    }

    /// The oldest profile is sealed with a key that is not here. Promoting it would make the
    /// app read a profile it cannot open, so the oldest one that opens is restored instead.
    func testProfileRestoreSkipsAProfileNoKeyOpens() throws {
        let own = SymmetricKey(size: .bits256)
        let foreign = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        keychain.sharedSynchronizable = foreign

        let db = try makeDatabase()
        try insertHealthData(db, id: "lost", type: "personal_info", sealed: seal("unreachable", with: SymmetricKey(size: .bits256)), time: 50)
        try insertHealthData(db, id: "profile", type: "personal_info", sealed: seal("own profile", with: own), time: 100)
        try insertHealthData(db, id: "profile-dup", type: "personal_info", sealed: seal("stand-in", with: foreign), time: 200)
        for index in 0..<2 {
            try insertHealthData(db, id: "lab\(index)", type: "blood_test", sealed: seal("lab \(index)", with: own))
        }

        _ = try makeResolver().resolve()

        XCTAssertEqual(try visiblePersonalInfo(db), "profile")
    }

    private var pendingMarkerExists: Bool {
        FileManager.default.fileExists(atPath: identityURL.appendingPathExtension("pending").path)
    }

    /// A key that never arrives must not cost a full scan on every launch for ever.
    func testStopsLookingForAMissingKeyAfterAFewLaunches() throws {
        let own = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))
        try insertHealthData(db, id: "gone", type: "blood_test", sealed: seal("lost", with: SymmetricKey(size: .bits256)))

        _ = try makeResolver().resolve()
        XCTAssertTrue(pendingMarkerExists)

        for _ in 0..<4 { _ = try makeResolver().resolve() }
        XCTAssertTrue(pendingMarkerExists, "Still looking after four more launches")

        _ = try makeResolver().resolve()
        XCTAssertFalse(pendingMarkerExists, "Gave up on the fifth")
    }

    /// Once the database has nothing left that no key opens, the files are checked too, so a
    /// document left sealed with another key (a file rewrite that failed) is still recovered.
    func testPendingStoreRecoversFilesOnceTheDatabaseIsSettled() throws {
        let own = SymmetricKey(size: .bits256)
        let foreign = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))
        try insertHealthData(db, id: "gone", type: "blood_test", sealed: seal("lost", with: SymmetricKey(size: .bits256)))
        _ = try makeResolver().resolve()

        try db.run("DELETE FROM health_data WHERE id = 'gone'")
        keychain.sharedSynchronizable = foreign
        let fileURL = filesURL.appendingPathComponent("doc.pdf")
        try seal("pdf bytes", with: foreign).write(to: fileURL)

        _ = try makeResolver().resolve()

        XCTAssertEqual(open(try Data(contentsOf: fileURL), with: own), "pdf bytes")
        XCTAssertFalse(pendingMarkerExists)
    }

    /// A restored device shares its store ID, and so its Keychain account, with the device
    /// the backup came from. Whatever it picks must go under a new ID, never that one.
    func testRestoredStoreWithoutItsKeyNeverWritesUnderItsID() throws {
        let storeID = UUID().uuidString
        try Data(storeID.utf8).write(to: identityURL)

        _ = try makeResolver().resolve()

        XCTAssertNil(keychain.storeKeys[storeID], "The original device's account is left alone")
        XCTAssertEqual(keychain.storeKeys.count, 1)
        let newID = try String(contentsOf: identityURL, encoding: .utf8)
        XCTAssertNotEqual(newID, storeID)
    }

    /// The same when a legacy key opens all of a restored store's data.
    func testRestoredStoreAdoptingALegacyKeyFilesItUnderANewID() throws {
        let own = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))
        let storeID = UUID().uuidString
        try Data(storeID.utf8).write(to: identityURL)

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertNil(keychain.storeKeys[storeID])
        XCTAssertEqual(keychain.storeKeys.count, 1)
    }

    /// A file in no recognised format that no key opens may be plaintext or may be sealed with
    /// a key still to come: it keeps recovery pending, but proves nothing about which key.
    func testUnrecognisedFileKeepsRecoveryPendingWithoutBlockingResolution() throws {
        let own = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: own))
        try seal("pdf bytes", with: SymmetricKey(size: .bits256)).write(to: filesURL.appendingPathComponent("doc.pdf"))

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
        XCTAssertTrue(pendingMarkerExists)
    }

    func testUnrecognisedFileAloneIsNotEvidenceOfAMissingKey() throws {
        try seal("pdf bytes", with: SymmetricKey(size: .bits256)).write(to: filesURL.appendingPathComponent("doc.pdf"))

        XCTAssertNoThrow(try makeResolver().resolve())
        XCTAssertEqual(keychain.storeKeys.count, 1)
    }

    /// The key must be filed before any value is rewritten with it, so a crash midway cannot
    /// leave rewritten data whose only key is in the overwritable shared slot.
    func testSelectedKeyIsFiledBeforeAnyValueIsRewritten() throws {
        let own = SymmetricKey(size: .bits256)
        let foreign = SymmetricKey(size: .bits256)
        keychain.deviceOnly = own
        keychain.sharedSynchronizable = foreign
        let db = try makeDatabase()
        for index in 0..<2 {
            try insertHealthData(db, id: "lab\(index)", type: "blood_test", sealed: seal("lab \(index)", with: own))
        }
        try insertHealthData(db, id: "new", type: "blood_test", sealed: seal("new lab", with: foreign))

        var stillForeignWhenFiled: Bool?
        keychain.onStore = { [unowned self] in
            stillForeignWhenFiled = (try? self.storedBlob(db, id: "new")).flatMap { $0 }.flatMap { self.open($0, with: foreign) } != nil
        }
        _ = try makeResolver().resolve()

        XCTAssertEqual(stillForeignWhenFiled, true)
        XCTAssertEqual(open(try XCTUnwrap(storedBlob(db, id: "new")), with: own), "new lab")
        XCTAssertFalse(pendingMarkerExists)
    }

    func testExistingDataWithNoMatchingKeyThrowsAndCreatesNothing() throws {
        keychain.sharedSynchronizable = SymmetricKey(size: .bits256)
        let db = try makeDatabase()
        try insertHealthData(db, id: "a", type: "blood_test", sealed: seal("lab", with: SymmetricKey(size: .bits256)))

        XCTAssertThrowsError(try makeResolver().resolve()) { error in
            guard case DataKeyError.noKeyOpensExistingData = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertTrue(keychain.storeKeys.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: identityURL.path))
    }

    func testBoundStoreUsesItsOwnKeyWhateverTheSharedSlotHolds() throws {
        let own = try makeResolver().resolve()
        keychain.sharedSynchronizable = SymmetricKey(size: .bits256)

        let key = try makeResolver().resolve()

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, own.withUnsafeBytes { Data($0) })
    }
}
