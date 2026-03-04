import XCTest
@testable import HealthApp

@MainActor
final class AIChatManagerReliabilityTests: XCTestCase {
    private var chatManager: AIChatManager!
    private var originalModelPreferences: ModelPreferences!

    override func setUp() async throws {
        try await super.setUp()
        originalModelPreferences = SettingsManager.shared.modelPreferences
        chatManager = AIChatManager(
            healthDataManager: HealthDataManager.shared,
            databaseManager: DatabaseManager.shared
        )
    }

    override func tearDown() async throws {
        SettingsManager.shared.modelPreferences = originalModelPreferences
        chatManager = nil
        try await super.tearDown()
    }

    func testSecondSendIsBlockedWhileMessageInFlight() async {
        chatManager.currentConversation = ChatConversation(title: "In-flight Guard")
        chatManager.isOffline = false
        chatManager.isSendingMessage = true

        do {
            try await chatManager.sendMessage("Should be blocked")
            XCTFail("Expected sendMessage to throw messageInFlight")
        } catch let error as AIChatError {
            if case .messageInFlight = error {
                // expected
            } else {
                XCTFail("Unexpected AIChatError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOnDeviceConversationTitleUsesHeuristicPath() async throws {
        var prefs = SettingsManager.shared.modelPreferences
        prefs.aiProvider = .onDeviceLLM
        SettingsManager.shared.modelPreferences = prefs

        let conversation = ChatConversation(
            title: "New Conversation",
            messages: [
                ChatMessage(content: "What is my current health status and blood pressure?", role: .user),
                ChatMessage(content: "Placeholder response", role: .assistant)
            ]
        )

        let title = try await chatManager.generateConversationTitleForTesting(for: conversation)
        XCTAssertNotEqual(title, "New Conversation")
        XCTAssertFalse(title.isEmpty)
    }
}
