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
            "--disable-mlx-preload",
            // See HealthAppUITestCase: the simulator's saved provider may ask for cloud consent.
            "-hasAcknowledgedCloudProcessing", "YES"
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

    /// Edit, select a document, and Batch must appear. Regression for PR #59: `DocumentsView`
    /// sits outside its own split view, so reading edit mode from the environment saw a
    /// different value from the one the Edit button changed, and Batch never showed.
    func testSelectingDocumentInEditModeOffersBatch() throws {
        navigateToDocuments()

        let seededDocument = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ui-test-lab-report.pdf"))
            .firstMatch
        XCTAssertTrue(seededDocument.waitForExistence(timeout: 10), "Seeded lab report should be listed")

        let editButton = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Edit", "Edit Documents"]))
            .firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit should be in the Documents toolbar")
        editButton.tap()

        seededDocument.tap()

        XCTAssertTrue(
            app.buttons
                .matching(NSPredicate(format: "label IN %@", ["Batch", "Batch Process"]))
                .firstMatch
                .waitForExistence(timeout: 5),
            "Selecting a document in edit mode should offer Batch"
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
            // `.firstMatch`: on iPad in portrait the top tab bar and the closed sidebar
            // both expose a "Health" button.
            let healthSidebarButton = app.buttons["Health"].firstMatch
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

        let chatSidebarButton = app.buttons["AI Chat"].firstMatch
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
            let newConversationButton = app.buttons["chat.newConversation"]
            XCTAssertTrue(newConversationButton.waitForExistence(timeout: 5), "New Chat should be in the toolbar")
            newConversationButton.tap()
        }

        XCTAssertTrue(
            app.textFields["chat.messageInput"].waitForExistence(timeout: 5),
            "Message input should appear after starting conversation"
        )
    }
}
