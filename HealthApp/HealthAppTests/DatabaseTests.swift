import XCTest
import SQLite3
@testable import HealthApp

@MainActor
final class DatabaseTests: XCTestCase {

    func testDatabaseManagerInitializes() throws {
        let databaseManager = try DatabaseManager()
        XCTAssertNotNil(databaseManager)
    }

    func testPersonalHealthInfoRoundTripsThroughJSON() throws {
        let original = PersonalHealthInfo(
            name: "Test User",
            dateOfBirth: Date(timeIntervalSince1970: 1_700_000_000),
            gender: .male,
            bloodType: .oPositive
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersonalHealthInfo.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Test User")
        XCTAssertEqual(decoded.gender, .male)
        XCTAssertEqual(decoded.bloodType, .oPositive)
    }

    func testMedicalDocumentRoundTripsThroughJSON() throws {
        let original = MedicalDocument(
            fileName: "lab.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/lab.pdf"),
            processingStatus: .completed,
            documentCategory: .labReport,
            extractedText: "Glucose 95",
            fileSize: 2048,
            tags: ["lab"]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MedicalDocument.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.fileName, "lab.pdf")
        XCTAssertEqual(decoded.fileType, .pdf)
        XCTAssertEqual(decoded.processingStatus, .completed)
        XCTAssertEqual(decoded.documentCategory, .labReport)
        XCTAssertEqual(decoded.tags, ["lab"])
    }

    func testChatConversationMessageCountsUpdate() {
        var conversation = ChatConversation(title: "Test")
        conversation.addMessage(ChatMessage(content: "Hello", role: .user))
        conversation.addMessage(ChatMessage(content: "Hi", role: .assistant))

        XCTAssertEqual(conversation.messageCount, 2)
        XCTAssertEqual(conversation.userMessageCount, 1)
        XCTAssertEqual(conversation.assistantMessageCount, 1)
        XCTAssertTrue(conversation.hasMessages)
    }
}

// MARK: - Schema Migration
//
// The first tests in this project to open a database that already exists.
//
// Every prior test builds a fresh database, so the whole migration path — eleven steps,
// run against real user data on upgrade — had no automated coverage at all, and the
// project's own guidance calls migrations the one change that must never lose data
// (CLAUDE.md). Items still open in the review (a durable review queue, scrubbing
// plaintext metadata) each need a new schema version, so this harness exists to make
// those changes verifiable rather than hopeful.
//
// The fixture is built by letting DatabaseManager create the real current schema and then
// *downgrading* that file: re-adding the column v12 drops and winding the stored version
// back. That keeps the fixture honest — it is the shipping schema, not a hand-copied
// approximation that drifts the moment someone edits a table.
@MainActor
final class DatabaseMigrationTests: XCTestCase {

    private let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
    private var databaseURL: URL { directory.appendingPathComponent("health_data.sqlite") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Raw SQLite helpers (the test target does not link SQLite.swift)

    private func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK else {
            throw MigrationFixtureError.open(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_close(handle) }

        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw MigrationFixtureError.exec(sql, detail)
        }
    }

    private func scalar(_ sql: String) throws -> Int? {
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK else {
            throw MigrationFixtureError.open(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MigrationFixtureError.exec(sql, String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : nil
    }

    private enum MigrationFixtureError: Error {
        case open(String)
        case exec(String, String)
    }

    private func storedVersion() throws -> Int? {
        try scalar("SELECT MAX(version) FROM database_version")
    }

    private func documentsHasColumn(_ name: String) throws -> Bool {
        (try scalar("SELECT COUNT(*) FROM pragma_table_info('documents') WHERE name = '\(name)'") ?? 0) > 0
    }

    // MARK: Tests

    func testUpgradingFromVersion11PreservesDocuments() async throws {
        // Build a real v12 database and store a document through the app's own API, so the
        // row is exactly what a user would have rather than a hand-written INSERT.
        let document = MedicalDocument(
            fileName: "lab-report.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/lab-report.pdf"),
            processingStatus: .completed,
            documentCategory: .labReport,
            extractedText: "Glucose 95 mg/dL",
            fileSize: 2048,
            tags: ["lab"]
        )

        do {
            let manager = try DatabaseManager(databaseURL: databaseURL)
            try await manager.saveMedicalDocument(document)
        }

        // Wind the file back to v11: restore the column v12 drops, and the version row.
        try execute("ALTER TABLE documents ADD COLUMN raw_docling_output BLOB")
        try execute("DELETE FROM database_version")
        try execute("INSERT INTO database_version (version, created_at) VALUES (11, 0)")

        XCTAssertEqual(try storedVersion(), 11, "Precondition: the fixture must look like v11")
        XCTAssertTrue(try documentsHasColumn("raw_docling_output"), "Precondition: the legacy column must be present")

        // Opening it runs the migration.
        let migrated = try DatabaseManager(databaseURL: databaseURL)

        XCTAssertEqual(try storedVersion(), 12, "The stored version must advance")
        XCTAssertFalse(try documentsHasColumn("raw_docling_output"), "v12 drops the legacy column")

        let recovered = try await migrated.fetchMedicalDocument(id: document.id)
        XCTAssertNotNil(recovered, "The document must survive the migration")
        XCTAssertEqual(recovered?.fileName, "lab-report.pdf")
        XCTAssertEqual(recovered?.extractedText, "Glucose 95 mg/dL")
        XCTAssertEqual(recovered?.documentCategory, .labReport)
    }

    func testOpeningAFutureVersionIsRefusedRatherThanCrashing() throws {
        do {
            _ = try DatabaseManager(databaseURL: databaseURL)
        }

        try execute("DELETE FROM database_version")
        try execute("INSERT INTO database_version (version, created_at) VALUES (99, 0)")

        // Running an older build against a migrated database must fail cleanly: the app
        // shows DatabaseUnavailableView rather than trapping (CLAUDE.md).
        XCTAssertThrowsError(try DatabaseManager(databaseURL: databaseURL)) { error in
            guard case DatabaseError.incompatibleVersion = error else {
                return XCTFail("Expected incompatibleVersion, got \(error)")
            }
        }
    }
}
