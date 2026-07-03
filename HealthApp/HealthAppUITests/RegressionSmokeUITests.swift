import XCTest

final class RegressionSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-test-data",
            "--skip-disclaimer",
            "--seed-lab-report",
            "--scripted-ai-provider",
            "--disable-healthkit-sync",
            "--disable-mlx-preload"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSeededLabReportAppearsInDocumentsList() throws {
        navigateToDocuments()

        let seededDocument = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ui-test-lab-report.pdf"))
            .firstMatch

        XCTAssertTrue(
            seededDocument.waitForExistence(timeout: 10),
            "Seeded lab report should appear in Documents when UI test launch arguments are enabled"
        )
        XCTAssertTrue(
            (seededDocument.value as? String ?? "").contains("Completed"),
            "Seeded lab report should expose completed processing status"
        )
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
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "SCRIPTED_DOCTOR_REPLY"))
                .firstMatch
                .waitForExistence(timeout: 10),
            "Scripted AI doctor reply should appear without a live provider"
        )
    }

    private func navigateToDocuments() {
        let healthTab = app.tabBars.buttons["Health"]
        if healthTab.waitForExistence(timeout: 5) {
            healthTab.tap()
        } else {
            let healthSidebarButton = app.buttons["Health"]
            XCTAssertTrue(healthSidebarButton.waitForExistence(timeout: 5), "Health navigation should be visible")
            healthSidebarButton.tap()
        }

        let documentsSegment = app.buttons["Documents"]
        XCTAssertTrue(documentsSegment.waitForExistence(timeout: 5), "Documents segment should be visible in the Health tab")
        documentsSegment.tap()
    }

    private func navigateToChat() {
        let chatTab = app.tabBars.buttons["AI Chat"]
        if chatTab.waitForExistence(timeout: 5) {
            chatTab.tap()
            return
        }

        let chatSidebarButton = app.buttons["AI Chat"]
        XCTAssertTrue(chatSidebarButton.waitForExistence(timeout: 5), "AI Chat navigation should be visible")
        chatSidebarButton.tap()
    }

    private func startNewConversationAndWait() {
        navigateToChat()

        let startButton = app.buttons
            .matching(NSPredicate(format: "label == %@", "Start New Conversation"))
            .firstMatch
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        } else {
            let newConversationButton = app.buttons.matching(identifier: "plus").firstMatch
            XCTAssertTrue(newConversationButton.waitForExistence(timeout: 5), "New conversation button should be visible")
            newConversationButton.tap()
        }

        XCTAssertTrue(
            app.textFields["chat.messageInput"].waitForExistence(timeout: 5),
            "Message input should appear after starting conversation"
        )
    }
}
