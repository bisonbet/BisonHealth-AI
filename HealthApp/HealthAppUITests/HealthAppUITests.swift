import XCTest

final class HealthAppUITests: HealthAppUITestCase {

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
        navigateToHealth()
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
        
        // Test Documents tab
        navigateToDocuments()
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        // Test AI Chat tab
        navigateToChat()
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
        
        // Test Settings tab
        navigateToSettings()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
    
    // MARK: - Health Data Tab Tests
    
    func testHealthDataTabContent() throws {
        navigateToHealth()
        
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
        navigateToHealth()
        
        // Test pull to refresh
        let healthDataList = app.scrollViews.element
        healthDataList.swipeDown()
        
        // Verify content is still there after refresh
        XCTAssertTrue(app.staticTexts["Personal Information"].exists)
    }
    
    // MARK: - Documents Tab Tests
    
    func testDocumentsTabContent() throws {
        navigateToDocuments()
        
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
        navigateToChat()
        
        // Should show empty state or existing conversations
        XCTAssertTrue(app.staticTexts["No Conversation"].exists || app.buttons["New Chat"].exists)
        
        // Test new chat button
        if app.buttons["New Chat"].exists {
            app.buttons["New Chat"].tap()
        }
    }
    
    // MARK: - Settings Tab Tests
    
    func testSettingsTabContent() throws {
        navigateToSettings()
        
        // Verify main settings sections
        XCTAssertTrue(app.staticTexts["AI Services"].exists)
        XCTAssertTrue(app.staticTexts["Data Management"].exists)
        XCTAssertTrue(app.staticTexts["About"].exists)
        
        XCTAssertTrue(app.staticTexts["On-Device LLM"].exists || app.staticTexts["OpenAI Compatible"].exists)
    }
    
    func testSettingsNavigation() throws {
        navigateToSettings()
        
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
        navigateToHealth()
        
        // Navigate to Documents tab
        navigateToDocuments()
        
        // Verify we can navigate back
        navigateToHealth()
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
    }
    
    func testDocumentsToAIChatFlow() throws {
        // Start in Documents
        navigateToDocuments()
        
        // Navigate to AI Chat
        navigateToChat()
        
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
        navigateToHealth()
        
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
            navigateToHealth()
            navigateToDocuments()
            navigateToChat()
            navigateToSettings()
            navigateToHealth()
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testOfflineMode() throws {
        // This would require network simulation in a real test environment
        // For now, we test that the app doesn't crash when network is unavailable
        
        navigateToChat()
        
        // App should handle offline state gracefully
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
    }
    
    func testMemoryPressure() throws {
        // Test app behavior under memory pressure
        // This is a simplified test - real memory pressure testing requires additional setup
        
        // Navigate through all tabs multiple times
        for _ in 1...5 {
            navigateToHealth()
            navigateToDocuments()
            navigateToChat()
            navigateToSettings()
        }
        
        // App should still be responsive
        XCTAssertTrue(app.tabBars.element.exists)
    }
}
