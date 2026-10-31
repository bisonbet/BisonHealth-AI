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
            CREATE TABLE health_data (id TEXT PRIMARY KEY, type TEXT, encrypted_data BLOB, updated_at INTEGER);
            CREATE TABLE documents (id TEXT PRIMARY KEY, file_name TEXT, tags TEXT);
            """)
        return db
    }

    private func insertHealthData(_ db: Connection, id: String, type: String, sealed: Data) throws {
        try db.run("INSERT INTO health_data (id, type, encrypted_data, updated_at) VALUES (?, ?, ?, 0)",
                   id, type, Blob(bytes: [UInt8](sealed)))
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
        try insertHealthData(db, id: "profile", type: "personal_info", sealed: seal("own profile", with: own))
        for index in 0..<3 {
            try insertHealthData(db, id: "lab\(index)", type: "blood_test", sealed: seal("lab \(index)", with: own))
        }
        // Written during the broken session.
        try insertHealthData(db, id: "profile-dup", type: "personal_info", sealed: seal("health sync only", with: foreign))
        try insertHealthData(db, id: "lab-new", type: "blood_test", sealed: seal("new lab", with: foreign))
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
        XCTAssertNil(try storedBlob(db, id: "profile-dup"),
                     "The stand-in profile would otherwise sort ahead of the user's own record")

        let tags = try XCTUnwrap(try db.scalar("SELECT tags FROM documents WHERE id = 'd'") as? String)
        XCTAssertEqual(open(try XCTUnwrap(Data(base64Encoded: tags)), with: own), "[\"lipids\"]")
        XCTAssertEqual(open(try Data(contentsOf: fileURL), with: own), "pdf bytes")

        XCTAssertNotNil(keychain.sharedSynchronizable, "Another device may still need the shared key")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("health_data.sqlite.backup.rekey-") }
        XCTAssertEqual(backups.count, 1)
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
