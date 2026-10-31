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

    func storeEncryptionKey(_ key: SymmetricKey, forStore storeID: String) throws {
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
