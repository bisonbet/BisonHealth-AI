import XCTest

final class DocumentManagementUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Navigate to Documents tab
        app.tabBars.buttons["Documents"].tap()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic Navigation Tests
    
    func testDocumentsTabOpens() throws {
        XCTAssertTrue(app.navigationBars["Documents"].exists)
    }
    
    func testEmptyStateDisplayed() throws {
        // If no documents exist, should show empty state
        if app.staticTexts["No Documents"].exists {
            XCTAssertTrue(app.staticTexts["Import your health documents to get started"].exists)
            XCTAssertTrue(app.buttons["Scan Document"].exists)
            XCTAssertTrue(app.buttons["Import File"].exists)
            XCTAssertTrue(app.buttons["Import Photos"].exists)
        }
    }
    
    // MARK: - Document Import Tests
    
    func testScanDocumentButton() throws {
        // Test scan document button in empty state
        if app.buttons["Scan Document"].exists {
            app.buttons["Scan Document"].tap()
            
            // Should open camera interface (VisionKit)
            // Note: Camera testing requires physical device or simulator with camera access
            XCTAssertTrue(app.otherElements["Document Camera"].waitForExistence(timeout: 3) || 
                         app.alerts.element.exists) // Alert if camera not available
        }
    }
    
    func testImportFileButton() throws {
        // Test import file button
        if app.buttons["Import File"].exists {
            app.buttons["Import File"].tap()
            
            // Should open Files app picker
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
        }
    }
    
    func testImportPhotosButton() throws {
        // Test import photos button
        if app.buttons["Import Photos"].exists {
            app.buttons["Import Photos"].tap()
            
            // Should open Photos picker
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
        }
    }
    
    func testAddMenuInToolbar() throws {
        // Test the plus menu in toolbar
        let addButton = app.navigationBars.buttons["plus"]
        if addButton.exists {
            addButton.tap()
            
            XCTAssertTrue(app.buttons["Scan Document"].exists)
            XCTAssertTrue(app.buttons["Import File"].exists)
            XCTAssertTrue(app.buttons["Import Photos"].exists)
            
            // Dismiss menu
            app.tap()
        }
    }
    
    // MARK: - Document List Tests
    
    func testDocumentListView() throws {
        // Skip if no documents exist
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Should show document list
        XCTAssertTrue(app.scrollViews.element.exists || app.tables.element.exists)
    }
    
    func testDocumentRowTap() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Tap first document if available
        let firstDocument = app.cells.firstMatch
        if firstDocument.exists {
            firstDocument.tap()
            
            // Should open document detail view
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 2))
        }
    }
    
    func testEditModeToggle() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Test edit button
        let editButton = app.navigationBars.buttons["Edit"]
        if editButton.exists {
            editButton.tap()
            
            // Should enter edit mode
            XCTAssertTrue(app.navigationBars.buttons["Done"].exists)
            
            // Exit edit mode
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.navigationBars.buttons["Edit"].exists)
        }
    }
    
    // MARK: - Search and Filter Tests
    
    func testSearchFunctionality() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Look for search field
        let searchField = app.textFields["Search documents..."]
        if searchField.exists {
            searchField.tap()
            searchField.typeText("test")
            
            // Should filter results
            XCTAssertEqual(searchField.value as? String, "test")
            
            // Clear search
            if app.buttons["Clear"].exists {
                app.buttons["Clear"].tap()
                XCTAssertTrue(searchField.value as? String == "" || searchField.value == nil)
            }
        }
    }
    
    func testFilterButton() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        let filterButton = app.buttons["Filter"]
        if filterButton.exists {
            filterButton.tap()
            
            // Should open filter view
            XCTAssertTrue(app.navigationBars["Filter & Sort"].waitForExistence(timeout: 2))
            
            // Close filter view
            app.buttons["Done"].tap()
        }
    }
    
    // MARK: - View Mode Tests (iPad)
    
    func testViewModeToggle() throws {
        // Only test on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Look for view mode picker
        let viewModePicker = app.segmentedControls.element
        if viewModePicker.exists {
            // Test grid view
            viewModePicker.buttons.element(boundBy: 1).tap()
            
            // Test list view
            viewModePicker.buttons.element(boundBy: 0).tap()
        }
    }
    
    // MARK: - Batch Operations Tests
    
    func testBatchSelection() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Enter edit mode
        let editButton = app.navigationBars.buttons["Edit"]
        if editButton.exists {
            editButton.tap()
            
            // Select documents
            let firstCell = app.cells.firstMatch
            if firstCell.exists {
                firstCell.tap()
                
                // Should show batch button
                XCTAssertTrue(app.buttons["Batch"].waitForExistence(timeout: 1))
                
                // Test batch processing
                app.buttons["Batch"].tap()
                XCTAssertTrue(app.navigationBars["Batch Processing"].waitForExistence(timeout: 2))
                
                // Close batch processing
                app.buttons["Cancel"].tap()
            }
            
            // Exit edit mode
            app.navigationBars.buttons["Done"].tap()
        }
    }
    
    // MARK: - Processing Tests
    
    func testProcessAllPendingButton() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Open add menu
        app.navigationBars.buttons["plus"].tap()
        
        // Look for process all pending option
        if app.buttons["Process All Pending"].exists {
            app.buttons["Process All Pending"].tap()
            
            // Should start processing (may show progress indicator)
            // This is hard to test without actual documents
        }
        
        // Dismiss menu if still open
        if app.buttons["Process All Pending"].exists {
            app.tap()
        }
    }
    
    func testRetryFailedButton() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Open add menu
        app.navigationBars.buttons["plus"].tap()
        
        // Look for retry failed option
        if app.buttons["Retry Failed"].exists {
            app.buttons["Retry Failed"].tap()
            
            // Should retry failed documents
        }
        
        // Dismiss menu if still open
        if app.buttons["Retry Failed"].exists {
            app.tap()
        }
    }
    
    // MARK: - Pull to Refresh Tests
    
    func testPullToRefresh() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Test pull to refresh
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeDown()
            
            // Should trigger refresh (hard to verify without network activity)
            XCTAssertTrue(scrollView.exists)
        }
    }
    
    // MARK: - Document Detail Tests
    
    func testDocumentDetailView() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Tap first document
        let firstDocument = app.cells.firstMatch
        if firstDocument.exists {
            firstDocument.tap()
            
            // Should open detail view
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 2))
            
            // Test close button
            if app.buttons["Close"].exists {
                app.buttons["Close"].tap()
                XCTAssertTrue(app.navigationBars["Documents"].exists)
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        // Test that key elements have accessibility labels
        XCTAssertTrue(app.tabBars.buttons["Documents"].isAccessibilityElement)
        
        if app.buttons["Scan Document"].exists {
            XCTAssertTrue(app.buttons["Scan Document"].isAccessibilityElement)
            XCTAssertNotNil(app.buttons["Scan Document"].label)
        }
        
        if app.buttons["Import File"].exists {
            XCTAssertTrue(app.buttons["Import File"].isAccessibilityElement)
            XCTAssertNotNil(app.buttons["Import File"].label)
        }
    }
    
    func testVoiceOverSupport() throws {
        // Test VoiceOver navigation
        let documentsTab = app.tabBars.buttons["Documents"]
        XCTAssertTrue(documentsTab.isAccessibilityElement)
        XCTAssertNotNil(documentsTab.label)
        
        // Test document cells if they exist
        if !app.staticTexts["No Documents"].exists {
            let firstCell = app.cells.firstMatch
            if firstCell.exists {
                XCTAssertTrue(firstCell.isAccessibilityElement)
            }
        }
    }
    
    // MARK: - iPad Specific Tests
    
    func testIPadLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        // Test that iPad-specific elements exist
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        // Test orientation changes
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        // Reset orientation
        XCUIDevice.shared.orientation = .portrait
    }
    
    func testKeyboardShortcuts() throws {
        // Only test on iPad with external keyboard
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        // Test Command+N for new document (scan)
        // Note: Keyboard shortcut testing requires special setup
        // This is a placeholder for keyboard shortcut testing
        
        // Test Command+F for filter
        // Test Command+A for select all
        // Test Command+R for refresh
    }
    
    // MARK: - Performance Tests
    
    func testScrollingPerformance() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            measure {
                // Scroll up and down multiple times
                for _ in 0..<5 {
                    scrollView.swipeUp()
                    scrollView.swipeDown()
                }
            }
        }
    }
    
    func testViewModeSwitch() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        let viewModePicker = app.segmentedControls.element
        if viewModePicker.exists {
            measure {
                // Switch between list and grid view multiple times
                for _ in 0..<10 {
                    viewModePicker.buttons.element(boundBy: 1).tap() // Grid
                    viewModePicker.buttons.element(boundBy: 0).tap() // List
                }
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testOfflineMode() throws {
        // Test app behavior when offline
        // This would require network simulation in a real test environment
        
        // Verify that local documents are still accessible
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        
        // Processing should be disabled or show appropriate messaging
        // This is hard to test without actual network control
    }
    
    func testLowStorageScenario() throws {
        // Test app behavior when device storage is low
        // This would require storage simulation
        
        // App should handle storage errors gracefully
        XCTAssertTrue(app.navigationBars["Documents"].exists)
    }
    
    // MARK: - Integration Tests
    
    func testDocumentToHealthDataFlow() throws {
        // Test the flow from document processing to health data extraction
        // This requires actual documents and processing
        
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // This would test:
        // 1. Document import
        // 2. Processing initiation
        // 3. Health data extraction
        // 4. Navigation to health data tab to verify extraction
    }
    
    func testDocumentToChatFlow() throws {
        // Test using processed documents in AI chat
        
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Navigate to chat tab
        app.tabBars.buttons["AI Chat"].tap()
        
        // Verify chat interface exists
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
        
        // Return to documents
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].exists)
    }
}
</content>
</invoke>