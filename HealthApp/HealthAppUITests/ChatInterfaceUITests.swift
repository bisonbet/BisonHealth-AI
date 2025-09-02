import XCTest

final class ChatInterfaceUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic Chat Interface Tests
    
    func testChatTabExists() throws {
        let chatTab = app.tabBars.buttons["AI Chat"]
        XCTAssertTrue(chatTab.exists, "Chat tab should exist")
        
        chatTab.tap()
        XCTAssertTrue(chatTab.isSelected, "Chat tab should be selected after tapping")
    }
    
    func testEmptyStateDisplayed() throws {
        navigateToChatTab()
        
        let emptyStateTitle = app.staticTexts["Bison Health AI"]
        XCTAssertTrue(emptyStateTitle.exists, "Empty state title should be displayed")
        
        let startButton = app.buttons["Start New Conversation"]
        XCTAssertTrue(startButton.exists, "Start new conversation button should exist")
    }
    
    func testStartNewConversation() throws {
        navigateToChatTab()
        
        let startButton = app.buttons["Start New Conversation"]
        startButton.tap()
        
        // Should navigate to chat interface
        let messageInput = app.textFields["Type your message..."]
        XCTAssertTrue(messageInput.waitForExistence(timeout: 2), "Message input should appear after starting conversation")
    }
    
    // MARK: - Message Input Tests
    
    func testMessageInputFunctionality() throws {
        startNewConversationAndWait()
        
        let messageInput = app.textFields["Type your message..."]
        XCTAssertTrue(messageInput.exists, "Message input should exist")
        
        // Test typing
        messageInput.tap()
        messageInput.typeText("Hello, this is a test message")
        
        let sendButton = app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch
        XCTAssertTrue(sendButton.exists, "Send button should exist")
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled with text")
    }
    
    func testSendButtonDisabledWhenEmpty() throws {
        startNewConversationAndWait()
        
        let sendButton = app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled when message is empty")
    }
    
    func testMessageSending() throws {
        startNewConversationAndWait()
        
        let messageInput = app.textFields["Type your message..."]
        messageInput.tap()
        messageInput.typeText("Test message")
        
        let sendButton = app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch
        sendButton.tap()
        
        // Message should appear in chat
        let sentMessage = app.staticTexts["Test message"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 2), "Sent message should appear in chat")
    }
    
    // MARK: - iPad Specific Tests
    
    func testIPadSplitViewLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        navigateToChatTab()
        
        // Check for sidebar
        let conversationsTitle = app.staticTexts["Conversations"]
        XCTAssertTrue(conversationsTitle.exists, "Conversations sidebar should exist on iPad")
        
        // Check for new conversation button in sidebar
        let newConversationButton = app.buttons.matching(identifier: "plus").firstMatch
        XCTAssertTrue(newConversationButton.exists, "New conversation button should exist in sidebar")
    }
    
    func testIPadKeyboardShortcuts() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        navigateToChatTab()
        
        // Test Cmd+N for new conversation
        app.typeKey("n", modifierFlags: .command)
        
        let messageInput = app.textFields["Type your message..."]
        XCTAssertTrue(messageInput.waitForExistence(timeout: 2), "New conversation should start with Cmd+N")
    }
    
    func testIPadContextSelector() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        startNewConversationAndWait()
        
        // Test Cmd+K for context selector
        app.typeKey("k", modifierFlags: .command)
        
        let contextTitle = app.staticTexts["Health Data Context"]
        XCTAssertTrue(contextTitle.waitForExistence(timeout: 2), "Context selector should open with Cmd+K")
    }
    
    // MARK: - Conversation Management Tests
    
    func testConversationsList() throws {
        navigateToChatTab()
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // On iPad, conversations are in sidebar
            let conversationsTitle = app.staticTexts["Conversations"]
            XCTAssertTrue(conversationsTitle.exists, "Conversations should be visible in sidebar")
        } else {
            // On iPhone, need to tap conversations button
            let conversationsButton = app.buttons["Conversations"]
            if conversationsButton.exists {
                conversationsButton.tap()
                
                let conversationsTitle = app.staticTexts["Conversations"]
                XCTAssertTrue(conversationsTitle.waitForExistence(timeout: 2), "Conversations list should open")
            }
        }
    }
    
    func testConversationSearch() throws {
        navigateToChatTab()
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Search in sidebar
            let searchField = app.textFields["Search conversations..."]
            if searchField.exists {
                searchField.tap()
                searchField.typeText("test")
                
                // Should filter conversations
                XCTAssertTrue(searchField.value as? String == "test", "Search field should contain typed text")
            }
        } else {
            // Open conversations list first
            let conversationsButton = app.buttons["Conversations"]
            if conversationsButton.exists {
                conversationsButton.tap()
                
                let searchField = app.textFields["Search conversations..."]
                XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field should exist in conversations list")
            }
        }
    }
    
    // MARK: - Context Management Tests
    
    func testHealthDataContextSelector() throws {
        startNewConversationAndWait()
        
        let contextButton = app.buttons["Context"]
        if contextButton.exists {
            contextButton.tap()
            
            let contextTitle = app.staticTexts["Health Data Context"]
            XCTAssertTrue(contextTitle.waitForExistence(timeout: 2), "Context selector should open")
            
            // Test selecting a data type
            let personalInfoButton = app.buttons.containing(.staticText, identifier: "Personal Information").firstMatch
            if personalInfoButton.exists {
                personalInfoButton.tap()
                
                // Save changes
                let saveButton = app.buttons["Save"]
                saveButton.tap()
            }
        }
    }
    
    func testContextIndicatorOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        startNewConversationAndWait()
        
        // Set some context first
        app.typeKey("k", modifierFlags: .command)
        
        let personalInfoCard = app.buttons.containing(.staticText, identifier: "Personal Information").firstMatch
        if personalInfoCard.exists {
            personalInfoCard.tap()
            
            let saveButton = app.buttons["Save"]
            saveButton.tap()
            
            // Context indicator should appear
            let contextIndicator = app.staticTexts["Context:"]
            XCTAssertTrue(contextIndicator.waitForExistence(timeout: 2), "Context indicator should appear on iPad")
        }
    }
    
    // MARK: - Connection Status Tests
    
    func testOfflineIndicator() throws {
        // This test would require mocking network conditions
        // For now, we'll just check that the connection status banner can appear
        startNewConversationAndWait()
        
        // The connection status banner should not be visible when connected
        let offlineBanner = app.staticTexts["Offline"]
        XCTAssertFalse(offlineBanner.exists, "Offline banner should not be visible when connected")
    }
    
    // MARK: - Text Selection and Copy Tests
    
    func testMessageTextSelection() throws {
        startNewConversationAndWait()
        
        // Send a message first
        let messageInput = app.textFields["Type your message..."]
        messageInput.tap()
        messageInput.typeText("This is a test message for selection")
        
        let sendButton = app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch
        sendButton.tap()
        
        // Wait for message to appear
        let sentMessage = app.staticTexts["This is a test message for selection"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 2), "Message should appear")
        
        // Long press to show context menu (text selection)
        sentMessage.press(forDuration: 1.0)
        
        let copyButton = app.buttons["Copy Message"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 1), "Copy button should appear in context menu")
    }
    
    // MARK: - Orientation Tests (iPad)
    
    func testIPadOrientationChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        navigateToChatTab()
        
        // Test portrait
        XCUIDevice.shared.orientation = .portrait
        
        let conversationsTitle = app.staticTexts["Conversations"]
        XCTAssertTrue(conversationsTitle.waitForExistence(timeout: 2), "Conversations should be visible in portrait")
        
        // Test landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        
        // Should still show split view in landscape
        XCTAssertTrue(conversationsTitle.exists, "Conversations should still be visible in landscape")
        
        // Reset orientation
        XCUIDevice.shared.orientation = .portrait
    }
    
    // MARK: - Helper Methods
    
    private func navigateToChatTab() {
        let chatTab = app.tabBars.buttons["AI Chat"]
        chatTab.tap()
    }
    
    private func startNewConversationAndWait() {
        navigateToChatTab()
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // On iPad, use the + button in sidebar
            let newConversationButton = app.buttons.matching(identifier: "plus").firstMatch
            if newConversationButton.exists {
                newConversationButton.tap()
            }
        } else {
            // On iPhone, use the start button or new chat button
            let startButton = app.buttons["Start New Conversation"]
            if startButton.exists {
                startButton.tap()
            } else {
                let newChatButton = app.buttons["New Chat"]
                if newChatButton.exists {
                    newChatButton.tap()
                }
            }
        }
        
        // Wait for message input to appear
        let messageInput = app.textFields["Type your message..."]
        XCTAssertTrue(messageInput.waitForExistence(timeout: 3), "Message input should appear after starting conversation")
    }
}

// MARK: - Performance Tests

extension ChatInterfaceUITests {
    
    func testChatScrollingPerformance() throws {
        startNewConversationAndWait()
        
        // Send multiple messages to test scrolling
        let messageInput = app.textFields["Type your message..."]
        let sendButton = app.buttons.matching(identifier: "arrow.up.circle.fill").firstMatch
        
        for i in 1...10 {
            messageInput.tap()
            messageInput.clearAndEnterText("Test message \(i)")
            sendButton.tap()
            
            // Wait a bit between messages
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Test scrolling performance
        let messagesArea = app.scrollViews.firstMatch
        
        measure {
            messagesArea.swipeUp()
            messagesArea.swipeDown()
        }
    }
    
    func testContextSelectorPerformance() throws {
        startNewConversationAndWait()
        
        measure {
            let contextButton = app.buttons["Context"]
            if contextButton.exists {
                contextButton.tap()
                
                let contextTitle = app.staticTexts["Health Data Context"]
                _ = contextTitle.waitForExistence(timeout: 2)
                
                let cancelButton = app.buttons["Cancel"]
                cancelButton.tap()
            }
        }
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear and enter text into a non-string value")
            return
        }
        
        self.tap()
        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }
}