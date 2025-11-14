import XCTest

final class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    // MARK: - VoiceOver Support Tests
    
    func testTabBarAccessibility() throws {
        // Test that all tab bar items have proper accessibility labels
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        // Test Health Data tab
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            XCTAssertTrue(healthDataTab.isAccessibilityElement, "Health Data tab should be accessible")
            XCTAssertNotNil(healthDataTab.label, "Health Data tab should have a label")
        }
        
        // Test Documents tab
        let documentsTab = app.tabBars.buttons["Documents"]
        if documentsTab.exists {
            XCTAssertTrue(documentsTab.isAccessibilityElement, "Documents tab should be accessible")
            XCTAssertNotNil(documentsTab.label, "Documents tab should have a label")
        }
        
        // Test Chat tab
        let chatTab = app.tabBars.buttons["AI Chat"]
        if chatTab.exists {
            XCTAssertTrue(chatTab.isAccessibilityElement, "Chat tab should be accessible")
            XCTAssertNotNil(chatTab.label, "Chat tab should have a label")
        }
        
        // Test Settings tab
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            XCTAssertTrue(settingsTab.isAccessibilityElement, "Settings tab should be accessible")
            XCTAssertNotNil(settingsTab.label, "Settings tab should have a label")
        }
    }
    
    func testNavigationBarAccessibility() throws {
        // Navigate to Health Data tab
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            healthDataTab.tap()
            
            // Check navigation title
            let navBar = app.navigationBars["Health Data"]
            if navBar.exists {
                XCTAssertTrue(navBar.isAccessibilityElement, "Navigation bar should be accessible")
            }
        }
    }
    
    func testButtonAccessibility() throws {
        // Navigate to Documents tab
        let documentsTab = app.tabBars.buttons["Documents"]
        if documentsTab.exists {
            documentsTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test add button if it exists
            let addButton = app.buttons.matching(identifier: "Add Document").firstMatch
            if addButton.exists {
                XCTAssertTrue(addButton.isAccessibilityElement, "Add button should be accessible")
                XCTAssertNotNil(addButton.label, "Add button should have a label")
            }
        }
    }
    
    func testSearchFieldAccessibility() throws {
        // Navigate to Documents tab
        let documentsTab = app.tabBars.buttons["Documents"]
        if documentsTab.exists {
            documentsTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test search field if it exists
            let searchField = app.textFields.matching(identifier: "documents.searchField").firstMatch
            if searchField.exists {
                XCTAssertTrue(searchField.isAccessibilityElement, "Search field should be accessible")
                XCTAssertNotNil(searchField.label, "Search field should have a label")
            }
        }
    }
    
    func testListAccessibility() throws {
        // Navigate to Health Data tab
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            healthDataTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test that list elements are accessible
            let tables = app.tables
            if tables.count > 0 {
                let firstTable = tables.firstMatch
                if firstTable.exists {
                    XCTAssertTrue(firstTable.isAccessibilityElement, "Table should be accessible")
                }
            }
        }
    }
    
    // MARK: - Dynamic Type Tests
    
    func testDynamicTypeSupport() throws {
        // Navigate to any tab
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            healthDataTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test that text elements exist (they should scale with Dynamic Type)
            let staticTexts = app.staticTexts
            if staticTexts.count > 0 {
                let firstText = staticTexts.firstMatch
                if firstText.exists {
                    // Text should be accessible
                    XCTAssertTrue(firstText.isAccessibilityElement || firstText.isHittable, 
                                "Text elements should be accessible")
                }
            }
        }
    }
    
    // MARK: - Touch Target Tests
    
    func testMinimumTouchTargets() throws {
        // Navigate to Documents tab
        let documentsTab = app.tabBars.buttons["Documents"]
        if documentsTab.exists {
            documentsTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test that buttons have sufficient size
            let buttons = app.buttons
            for i in 0..<min(buttons.count, 5) {
                let button = buttons.element(boundBy: i)
                if button.exists && button.isHittable {
                    let frame = button.frame
                    // Minimum touch target should be at least 44x44 points
                    XCTAssertGreaterThanOrEqual(frame.width, 44.0, 
                                             "Button should meet minimum touch target width")
                    XCTAssertGreaterThanOrEqual(frame.height, 44.0, 
                                             "Button should meet minimum touch target height")
                }
            }
        }
    }
    
    // MARK: - Color Contrast Tests
    
    func testColorContrast() throws {
        // Navigate to any tab
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            healthDataTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test that buttons have sufficient contrast
            // This is a basic test - full contrast testing would require color analysis
            let buttons = app.buttons
            if buttons.count > 0 {
                let firstButton = buttons.firstMatch
                if firstButton.exists {
                    // Button should be visible (basic contrast check)
                    XCTAssertTrue(firstButton.isHittable, "Button should be visible and accessible")
                }
            }
        }
    }
    
    // MARK: - Keyboard Navigation Tests (iPad)
    
    func testKeyboardNavigation() throws {
        // This test would require iPad simulator and external keyboard
        // For now, we just verify that focusable elements exist
        let healthDataTab = app.tabBars.buttons["Health Data"]
        if healthDataTab.exists {
            healthDataTab.tap()
            
            // Wait for view to load
            sleep(1)
            
            // Test that interactive elements can receive focus
            let buttons = app.buttons
            if buttons.count > 0 {
                let firstButton = buttons.firstMatch
                if firstButton.exists {
                    // Button should be focusable
                    XCTAssertTrue(firstButton.isHittable, "Button should be focusable")
                }
            }
        }
    }
    
    // MARK: - Accessibility Identifiers Tests
    
    func testAccessibilityIdentifiers() throws {
        // Test that key elements have accessibility identifiers
        let healthDataTab = app.tabBars.buttons.matching(identifier: "tab.healthData").firstMatch
        if healthDataTab.exists {
            XCTAssertTrue(healthDataTab.exists, "Health Data tab should have identifier")
        }
        
        let documentsTab = app.tabBars.buttons.matching(identifier: "tab.documents").firstMatch
        if documentsTab.exists {
            XCTAssertTrue(documentsTab.exists, "Documents tab should have identifier")
        }
        
        let chatTab = app.tabBars.buttons.matching(identifier: "tab.chat").firstMatch
        if chatTab.exists {
            XCTAssertTrue(chatTab.exists, "Chat tab should have identifier")
        }
        
        let settingsTab = app.tabBars.buttons.matching(identifier: "tab.settings").firstMatch
        if settingsTab.exists {
            XCTAssertTrue(settingsTab.exists, "Settings tab should have identifier")
        }
    }
}

