import XCTest
@testable import HealthApp

final class OnDevicePromptBuilderTests: XCTestCase {

    func testPromptFormatAvoidsLeakyMarkers() {
        let history = [
            ChatMessage(content: "Previous user question", role: .user),
            ChatMessage(content: "Previous assistant answer", role: .assistant)
        ]

        let result = OnDevicePromptBuilder.build(
            request: OnDevicePromptBuilder.Request(
                healthContext: "{\"weight\":\"102.49 kg\"}",
                conversationHistory: history,
                userMessage: "What is my weight in pounds?",
                maxInputTokens: 4096
            ),
            tokenCounter: { max(1, $0.count / 4) }
        )

        XCTAssertFalse(result.prompt.contains("Question:"))
        XCTAssertFalse(result.prompt.contains("Previous conversation:"))
        XCTAssertTrue(result.prompt.contains("<<CURRENT_USER_MESSAGE>>"))
        XCTAssertTrue(result.prompt.contains("Do not echo HEALTH_CONTEXT_JSON"))
    }

    func testNewestUserMessageSurvivesCompaction() {
        let longHistory = (0..<20).map { idx in
            ChatMessage(
                content: String(repeating: "history-\(idx) ", count: 150),
                role: idx.isMultiple(of: 2) ? .user : .assistant
            )
        }

        let newestQuestion = "What is my weight in pounds?"
        let result = OnDevicePromptBuilder.build(
            request: OnDevicePromptBuilder.Request(
                healthContext: String(repeating: "{\"medical_documents\":[{\"content\":\"very long\"}]}", count: 200),
                conversationHistory: longHistory,
                userMessage: newestQuestion,
                maxInputTokens: 300
            ),
            tokenCounter: { max(1, $0.count / 4) }
        )

        XCTAssertTrue(result.prompt.contains(newestQuestion))
        XCTAssertNotEqual(result.fitStatus, .inputTooLargeAfterCompaction)
    }
}
