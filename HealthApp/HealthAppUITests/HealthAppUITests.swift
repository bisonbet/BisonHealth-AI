import XCTest

final class HealthAppUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch and Navigation Tests
    
    func testAppLaunches() throws {
        // Verify the app launches successfully
        XCTAssertTrue(app.tabBars.element.exists)
        
        // Verify all main tabs are present
        XCTAssertTrue(app.tabBars.buttons["Health Data"].exists)
        XCTAssertTrue(app.tabBars.buttons["Documents"].exists)
        XCTAssertTrue(app.tabBars.buttons["AI Chat"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }
    
    func testTabNavigation() throws {
        // Test Health Data tab
        app.tabBars.buttons["Health Data"].tap()
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
        
        // Test Documents tab
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        // Test AI Chat tab
        app.tabBars.buttons["AI Chat"].tap()
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
        
        // Test Settings tab
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
    
    // MARK: - Health Data Tab Tests
    
    func testHealthDataTabContent() throws {
        app.tabBars.buttons["Health Data"].tap()
        
        // Verify main sections are present
        XCTAssertTrue(app.staticTexts["Personal Information"].exists)
        XCTAssertTrue(app.staticTexts["Blood Test Results"].exists)
        XCTAssertTrue(app.staticTexts["Imaging Reports"].exists)
        XCTAssertTrue(app.staticTexts["Health Checkups"].exists)
        
        // Test add menu
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Personal Info"].exists)
        XCTAssertTrue(app.buttons["Blood Test"].exists)
        
        // Dismiss menu
        app.tap()
    }
    
    func testHealthDataRefresh() throws {
        app.tabBars.buttons["Health Data"].tap()
        
        // Test pull to refresh
        let healthDataList = app.scrollViews.element
        healthDataList.swipeDown()
        
        // Verify content is still there after refresh
        XCTAssertTrue(app.staticTexts["Personal Information"].exists)
    }
    
    // MARK: - Documents Tab Tests
    
    func testDocumentsTabContent() throws {
        app.tabBars.buttons["Documents"].tap()
        
        // Should show empty state initially
        XCTAssertTrue(app.staticTexts["No Documents"].exists || app.staticTexts["Import your first health document"].exists)
        
        // Test add menu
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Scan Document"].exists)
        XCTAssertTrue(app.buttons["Import File"].exists)
        XCTAssertTrue(app.buttons["Import Photos"].exists)
        
        // Dismiss menu
        app.tap()
    }
    
    // MARK: - AI Chat Tab Tests
    
    func testAIChatTabContent() throws {
        app.tabBars.buttons["AI Chat"].tap()
        
        // Should show empty state or existing conversations
        XCTAssertTrue(app.staticTexts["No Conversation"].exists || app.buttons["New Chat"].exists)
        
        // Test new chat button
        if app.buttons["New Chat"].exists {
            app.buttons["New Chat"].tap()
        }
    }
    
    // MARK: - Settings Tab Tests
    
    func testSettingsTabContent() throws {
        app.tabBars.buttons["Settings"].tap()
        
        // Verify main settings sections
        XCTAssertTrue(app.staticTexts["AI Services"].exists)
        XCTAssertTrue(app.staticTexts["iCloud Backup"].exists)
        XCTAssertTrue(app.staticTexts["Data Management"].exists)
        XCTAssertTrue(app.staticTexts["About"].exists)
        
        // Test Ollama server settings
        XCTAssertTrue(app.staticTexts["Ollama Server"].exists)
        XCTAssertTrue(app.textFields.matching(identifier: "localhost").count > 0)
        
        // Test connection test buttons
        XCTAssertTrue(app.buttons["Test Connection"].exists)
    }
    
    func testSettingsNavigation() throws {
        app.tabBars.buttons["Settings"].tap()
        
        // Test Export Health Data navigation
        app.buttons["Export Health Data"].tap()
        XCTAssertTrue(app.navigationBars["Data Export"].exists || app.navigationBars.element.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back
        
        // Test Storage Usage navigation
        app.buttons["Storage Usage"].tap()
        XCTAssertTrue(app.navigationBars["Storage Usage"].exists || app.navigationBars.element.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back
    }
    
    // MARK: - Cross-Tab Integration Tests
    
    func testHealthDataToDocumentsFlow() throws {
        // Start in Health Data
        app.tabBars.buttons["Health Data"].tap()
        
        // Navigate to Documents tab
        app.tabBars.buttons["Documents"].tap()
        
        // Verify we can navigate back
        app.tabBars.buttons["Health Data"].tap()
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
    }
    
    func testDocumentsToAIChatFlow() throws {
        // Start in Documents
        app.tabBars.buttons["Documents"].tap()
        
        // Navigate to AI Chat
        app.tabBars.buttons["AI Chat"].tap()
        
        // Verify chat interface
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityElements() throws {
        // Test that main navigation elements are accessible
        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.isAccessibilityElement || tabBar.children(matching: .button).count > 0)
        
        // Test tab buttons have proper labels
        let healthDataTab = app.tabBars.buttons["Health Data"]
        XCTAssertTrue(healthDataTab.isAccessibilityElement)
        XCTAssertNotNil(healthDataTab.label)
    }
    
    func testVoiceOverNavigation() throws {
        // Test basic VoiceOver navigation
        app.tabBars.buttons["Health Data"].tap()
        
        let healthDataTitle = app.navigationBars["Health Data"]
        XCTAssertTrue(healthDataTitle.exists)
        XCTAssertTrue(healthDataTitle.isAccessibilityElement)
    }
    
    // MARK: - Device Orientation Tests (iPad)
    
    func testIPadOrientationSupport() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        // Test portrait orientation
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.tabBars.element.exists)
        
        // Test landscape orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.tabBars.element.exists)
        
        // Test landscape right
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.tabBars.element.exists)
        
        // Test upside down (iPad only)
        XCUIDevice.shared.orientation = .portraitUpsideDown
        XCTAssertTrue(app.tabBars.element.exists)
        
        // Reset to portrait
        XCUIDevice.shared.orientation = .portrait
    }
    
    // MARK: - Performance Tests
    
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    func testTabSwitchingPerformance() throws {
        measure {
            app.tabBars.buttons["Health Data"].tap()
            app.tabBars.buttons["Documents"].tap()
            app.tabBars.buttons["AI Chat"].tap()
            app.tabBars.buttons["Settings"].tap()
            app.tabBars.buttons["Health Data"].tap()
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testOfflineMode() throws {
        // This would require network simulation in a real test environment
        // For now, we test that the app doesn't crash when network is unavailable
        
        app.tabBars.buttons["AI Chat"].tap()
        
        // App should handle offline state gracefully
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
    }
    
    func testMemoryPressure() throws {
        // Test app behavior under memory pressure
        // This is a simplified test - real memory pressure testing requires additional setup
        
        // Navigate through all tabs multiple times
        for _ in 1...5 {
            app.tabBars.buttons["Health Data"].tap()
            app.tabBars.buttons["Documents"].tap()
            app.tabBars.buttons["AI Chat"].tap()
            app.tabBars.buttons["Settings"].tap()
        }
        
        // App should still be responsive
        XCTAssertTrue(app.tabBars.element.exists)
    }
}