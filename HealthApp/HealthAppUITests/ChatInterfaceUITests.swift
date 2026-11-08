import XCTest

final class ChatInterfaceUITests: HealthAppUITestCase {

    override var launchArguments: [String] {
        guard name.contains("testScriptedDoctorReplyAppearsAfterSendingMessage") else {
            return super.launchArguments
        }
        return super.launchArguments + ["--seed-lab-report"]
    }

    // MARK: - Basic Chat Interface Tests
    
    func testChatTabExists() throws {
        let chatTab = sectionButton("AI Chat")
        XCTAssertTrue(chatTab.waitForExistence(timeout: 5), "Chat tab should exist")
        
        chatTab.tap()
        XCTAssertTrue(chatTab.isSelected, "Chat tab should be selected after tapping")
    }
    
    func testEmptyStateDisplayed() throws {
        navigateToChat()
        
        let emptyStateTitle = app.staticTexts["Bison Health AI"]
        XCTAssertTrue(emptyStateTitle.exists, "Empty state title should be displayed")
        
        let startButton = app.buttons["Start New Conversation"].firstMatch
        XCTAssertTrue(startButton.exists, "Start new conversation button should exist")
    }
    
    func testStartNewConversation() throws {
        navigateToChat()
        
        let startButton = app.buttons["Start New Conversation"].firstMatch
        startButton.tap()
        
        // Should navigate to chat interface
        let messageInput = app.textFields["Type your message..."]
        XCTAssertTrue(messageInput.waitForExistence(timeout: 2), "Message input should appear after starting conversation")
    }
    
    // MARK: - Message Input Tests
    
    func testMessageInputFunctionality() throws {
        startNewConversationAndWait()

        messageInput.tap()
        messageInput.typeText("Hello, this is a test message")
        XCTAssertEqual(messageInput.value as? String, "Hello, this is a test message")

        XCTAssertTrue(sendButton.exists, "Send button should exist")
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled with text")
    }
    
    func testSendButtonDisabledWhenEmpty() throws {
        startNewConversationAndWait()

        XCTAssertTrue(sendButton.exists)
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled when message is empty")

        // Whitespace alone is not a message.
        messageInput.tap()
        messageInput.typeText("   ")
        XCTAssertFalse(sendButton.isEnabled, "Send button should stay disabled for whitespace")
    }
    
    func testMessageSending() throws {
        startNewConversationAndWait()
        send("Test message")

        XCTAssertTrue(app.staticTexts["Test message"].waitForExistence(timeout: 5), "Sent message should appear in chat")
        XCTAssertEqual(messageInput.value as? String ?? "", messageInput.placeholderValue ?? "", "The input should clear after sending")
    }

    func testScriptedDoctorReplyAppearsAfterSendingMessage() throws {
        startNewConversationAndWait()

        let messageInput = app.textFields["chat.messageInput"]
        messageInput.tap()
        messageInput.typeText("What should I ask my doctor about my lab report?")

        let sendButton = app.buttons["chat.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3), "Send button should be available")
        sendButton.tap()

        XCTAssertTrue(
            app.staticTexts["What should I ask my doctor about my lab report?"].waitForExistence(timeout: 5),
            "User message should appear in the chat transcript"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "SCRIPTED_DOCTOR_REPLY")).firstMatch.waitForExistence(timeout: 10),
            "Scripted AI doctor reply should appear without a live provider"
        )
    }
    
    // MARK: - iPad Specific Tests
    
    func testIPadSplitViewLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        navigateToChat()
        
        // Check for sidebar
        let conversationsTitle = app.staticTexts["Conversations"]
        XCTAssertTrue(conversationsTitle.exists, "Conversations sidebar should exist on iPad")
        
        // Check for new conversation button in sidebar
        let newConversationButton = app.buttons["chat.sidebar.newConversation"]
        XCTAssertTrue(newConversationButton.exists, "New conversation button should exist in sidebar")
    }
    
    func testIPadKeyboardShortcuts() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        // Key commands reach the app once something in it has focus; a started conversation
        // focuses the message input.
        startNewConversationAndWait()
        let conversations = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New Conversation,'"))
        XCTAssertEqual(conversations.count, 1)

        // Cmd+N is New Chat's shortcut.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            conversations.element(boundBy: 1).waitForExistence(timeout: 8),
            "Cmd+N should start a second conversation"
        )
    }
    
    func testIPadContextSelector() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }

        startNewConversationAndWait()

        // Cmd+Shift+H opens the conversation's health data context.
        app.typeKey("h", modifierFlags: [.command, .shift])
        XCTAssertTrue(screenTitle("AI Context").waitForExistence(timeout: 3), "Context selector should open with Cmd+Shift+H")
    }
    
    // MARK: - Conversation Management Tests
    
    func testConversationsList() throws {
        navigateToChat()
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // On iPad, conversations are in sidebar
            let conversationsTitle = app.staticTexts["Conversations"]
            XCTAssertTrue(conversationsTitle.exists, "Conversations should be visible in sidebar")
        } else {
            // On iPhone the list is the split view's sidebar, reached with Back.
            let backToConversations = backButton(to: "Conversations")
            XCTAssertTrue(backToConversations.waitForExistence(timeout: 2), "Back to Conversations should exist")
            backToConversations.tap()

            let searchField = app.textFields["Search conversations..."]
            XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Conversations list should open")
        }
    }
    
    func testConversationSearch() throws {
        navigateToChat()
        
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
            // Open conversations list first: it is the split view's sidebar, reached with Back.
            let backToConversations = backButton(to: "Conversations")
            XCTAssertTrue(backToConversations.waitForExistence(timeout: 2), "Back to Conversations should exist")
            backToConversations.tap()

            let searchField = app.textFields["Search conversations..."]
            XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field should exist in conversations list")
        }
    }
    
    // MARK: - Context Management Tests
    
    func testHealthDataContextSelector() throws {
        startNewConversationAndWait()
        
        let contextButton = app.buttons["Context"]
        if contextButton.exists {
            contextButton.tap()
            
            let contextTitle = app.staticTexts["AI Context"]
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
        send("This is a test message for selection")

        let sentMessage = app.staticTexts["This is a test message for selection"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 5), "Message should appear")

        // A long press opens the message's context menu.
        sentMessage.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Copy Message"].waitForExistence(timeout: 3), "Copy should be in the context menu")
    }
    
    // MARK: - Orientation Tests (iPad)
    
    func testIPadOrientationChanges() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This test is only for iPad")
        }
        
        navigateToChat()
        
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

    private var messageInput: XCUIElement { app.textFields["chat.messageInput"] }
    private var sendButton: XCUIElement { app.buttons["chat.sendButton"] }

    private func send(_ text: String) {
        messageInput.tap()
        messageInput.typeText(text)
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()
    }

    private func startNewConversationAndWait() {
        navigateToChat()
        
        // The chat column's New Chat toolbar item exists at every width; the empty
        // state's button is the more natural tap when it is showing.
        let startButton = app.buttons["Start New Conversation"].firstMatch
        if startButton.exists {
            startButton.tap()
        } else {
            let newChatButton = app.buttons["chat.newConversation"]
            XCTAssertTrue(newChatButton.waitForExistence(timeout: 2), "New Chat should be in the toolbar")
            newChatButton.tap()
        }
        
        // Wait for message input to appear
        let messageInputByIdentifier = app.textFields["chat.messageInput"]
        let messageInput: XCUIElement
        if messageInputByIdentifier.waitForExistence(timeout: 2) {
            messageInput = messageInputByIdentifier
        } else {
            messageInput = app.textFields["Type your message..."]
        }
        XCTAssertTrue(messageInput.waitForExistence(timeout: 3), "Message input should appear after starting conversation")
    }
}

// MARK: - Performance Tests

extension ChatInterfaceUITests {
    
    func testChatScrollingPerformance() throws {
        startNewConversationAndWait()

        // Enough scripted exchanges to make the transcript scroll.
        for index in 1...5 {
            send("Test message \(index)")
            XCTAssertTrue(app.staticTexts["Test message \(index)"].waitForExistence(timeout: 10))
            XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        }

        let messagesArea = app.scrollViews.firstMatch
        XCTAssertTrue(messagesArea.exists)
        measure {
            messagesArea.swipeDown()
            messagesArea.swipeUp()
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
