import XCTest
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
