import XCTest
@testable import HealthApp

@MainActor
final class AIChatManagerTests: XCTestCase {

    func testProviderContextLimitsAreAvailableForSupportedProviders() {
        XCTAssertGreaterThan(AIProviderContextLimits.limit(for: .onDeviceLLM), 0)
        XCTAssertEqual(AIProviderContextLimits.limit(for: .bedrock), 200_000)
        XCTAssertGreaterThan(AIProviderContextLimits.limit(for: .openAICompatible), 0)
    }

    func testConversationContextBuilderReturnsTrimmedHistoryMetadata() {
        let result = ConversationContextBuilder.buildContext(
            currentMessage: "What changed?",
            healthContext: #"{"bloodPressure":"120/80"}"#,
            conversationHistory: [
                ChatMessage(content: "Earlier question", role: .user),
                ChatMessage(content: "Earlier answer", role: .assistant)
            ],
            systemPrompt: "You are a helpful clinician.",
            provider: .openAICompatible
        )

        XCTAssertTrue(result.includesHealthContext)
        XCTAssertGreaterThanOrEqual(result.conversationHistory.count, 0)
        XCTAssertGreaterThan(result.estimatedTokens, 0)
    }
}
