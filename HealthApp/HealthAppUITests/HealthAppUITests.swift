import XCTest

final class HealthAppUITests: HealthAppUITestCase {

    // MARK: - App Launch and Navigation Tests
    
    func testAppLaunches() throws {
        // Every top-level section is reachable: tabs on iPhone, the sidebar on iPad.
        for section in ["Health", "Prep", "AI Chat", "Settings"] {
            XCTAssertTrue(sectionButton(section).waitForExistence(timeout: 5), "\(section) should be reachable")
        }
        XCTAssertTrue(screenTitle("Health Data").exists, "The app should open on Health")
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

        for section in ["Personal Information", "Lab Results", "Imaging Reports"] {
            XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 5), "\(section) should be on Health")
        }

        let addMenu = app.buttons["Add Health Data"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        XCTAssertTrue(app.buttons["Add Personal Information"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Add Lab Results"].exists)
    }
    
    func testHealthDataRefresh() throws {
        navigateToHealth()
        XCTAssertTrue(app.staticTexts["Personal Information"].waitForExistence(timeout: 5))

        // Pull to refresh reloads the records; the content must still be there after.
        let records = app.collectionViews.firstMatch
        XCTAssertTrue(records.exists)
        records.swipeDown()
        XCTAssertTrue(app.staticTexts["Personal Information"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lab Results"].exists)
    }
    
    // MARK: - Documents Tab Tests
    
    func testDocumentsTabContent() throws {
        navigateToDocuments()

        // A reset store has no documents, so the empty state offers the import routes.
        XCTAssertTrue(app.staticTexts["No Documents"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(labelStartingWith: "Import File").exists)
        XCTAssertTrue(button(labelStartingWith: "Import Photos").exists)
        XCTAssertTrue(app.buttons["Add Document"].exists, "The Add Document menu should be in the toolbar")
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

        XCTAssertTrue(app.staticTexts["AI Provider"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(labelStartingWith: "AI Provider").exists, "The provider picker should show the current provider")
        XCTAssertTrue(scrollUntilHittable(app.staticTexts["Data Management"]), "Data Management should be in Settings")
        XCTAssertTrue(scrollUntilHittable(app.staticTexts["About"]), "About should be in Settings")
    }
    
    func testSettingsNavigation() throws {
        navigateToSettings()

        for destination in ["Export Health Data", "Storage Usage"] {
            let link = app.buttons[destination]
            XCTAssertTrue(scrollUntilHittable(link), "\(destination) should be in Settings")
            link.tap()
            XCTAssertTrue(screenTitle(destination).waitForExistence(timeout: 5), "\(destination) should open")

            let back = backButton(to: "Settings")
            XCTAssertTrue(back.waitForExistence(timeout: 5), "Back to Settings should exist")
            back.tap()
            XCTAssertTrue(screenTitle("Settings").waitForExistence(timeout: 5))
        }
    }
    
    // MARK: - Cross-Tab Integration Tests
    
    func testHealthDataToDocumentsFlow() throws {
        navigateToDocuments()
        XCTAssertTrue(screenTitle("Documents").waitForExistence(timeout: 5))

        // The segment switches back to the records without leaving Health.
        let records = app.buttons["Records"]
        XCTAssertTrue(records.exists)
        records.tap()
        XCTAssertTrue(screenTitle("Health Data").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Personal Information"].exists)
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
        // Navigation controls carry the visible name as their label, so VoiceOver reads it.
        for section in ["Health", "AI Chat", "Settings"] {
            let control = sectionButton(section)
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertEqual(control.label, section)
            XCTAssertTrue(control.isHittable, "\(section) should be reachable by touch")
        }
    }
    
    func testVoiceOverNavigation() throws {
        navigateToHealth()
        XCTAssertTrue(screenTitle("Health Data").waitForExistence(timeout: 5))

        // Icon-only and segmented controls must still speak a name.
        let addMenu = app.buttons["Add Health Data"]
        XCTAssertTrue(addMenu.exists, "The plus button should be labelled for VoiceOver")
        let segments = app.buttons.matching(identifier: "health.segment")
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments["Records"].exists)
        XCTAssertTrue(segments["Documents"].exists)
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
        XCTAssertTrue(sectionButton("Health").exists)
    }

}
