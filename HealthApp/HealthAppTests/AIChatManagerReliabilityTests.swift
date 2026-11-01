import XCTest
@testable import HealthApp

@MainActor
final class AIChatManagerReliabilityTests: XCTestCase {
    private var chatManager: AIChatManager!
    private var container: TestContainer?
    private var settingsManager: SettingsManager?

    override func setUp() async throws {
        try await super.setUp()
        let container = try TestContainer()
        self.container = container
        let databaseManager = try container.makeDatabaseManager()
        let settingsManager = try makeIsolatedSettingsManager()
        self.settingsManager = settingsManager
        chatManager = AIChatManager(
            healthDataManager: HealthDataManager(
                databaseManager: databaseManager,
                fileSystemManager: try container.makeFileSystemManager(),
                automaticallyLoad: false
            ),
            databaseManager: databaseManager,
            settingsManager: settingsManager,
            // Its unawaited load would read the container tearDown deletes; no test here needs it.
            automaticallyLoadConversations: false
        )
    }

    override func tearDown() async throws {
        chatManager = nil
        settingsManager = nil
        container?.remove()
        container = nil
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
        try XCTUnwrap(settingsManager).modelPreferences.aiProvider = .onDeviceLLM

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
