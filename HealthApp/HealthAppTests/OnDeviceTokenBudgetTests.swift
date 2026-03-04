import XCTest
@testable import HealthApp

final class OnDeviceTokenBudgetTests: XCTestCase {

    func testOversizedInputKeepsCurrentQuestionAndCompactsOlderContent() {
        var history: [ChatMessage] = []
        for index in 0..<30 {
            history.append(
                ChatMessage(
                    content: String(repeating: "turn-\(index) detail ", count: 120),
                    role: index.isMultiple(of: 2) ? .user : .assistant
                )
            )
        }

        let oversizedContext = """
        {
          "timestamp": "2026-02-21T09:56:00Z",
          "medical_documents": [
            {
              "priority": 1,
              "content": "\(String(repeating: "long-doc ", count: 2000))"
            },
            {
              "priority": 0,
              "sections": [
                {"type": "findings", "content": "\(String(repeating: "section-text ", count: 1500))"}
              ]
            }
          ]
        }
        """

        let question = "What is my current blood pressure trend?"
        let result = OnDevicePromptBuilder.build(
            request: OnDevicePromptBuilder.Request(
                healthContext: oversizedContext,
                conversationHistory: history,
                userMessage: question,
                maxInputTokens: 450
            ),
            tokenCounter: { max(1, $0.count / 4) }
        )

        XCTAssertTrue(result.prompt.contains(question))
        XCTAssertGreaterThan(result.trimmedHistoryCount + result.shortenedHistoryMessageCount + result.trimmedDocumentCount + result.contextTailTrimmedBytes, 0)
        XCTAssertNotEqual(result.fitStatus, .inputTooLargeAfterCompaction)
    }
}
