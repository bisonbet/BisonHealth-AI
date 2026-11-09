import XCTest

final class DocumentManagementUITests: HealthAppUITestCase {

    override var launchArguments: [String] {
        super.launchArguments + ["--seed-lab-report"]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToDocuments()
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

    func testSeededLabReportAppearsInDocumentsList() throws {
        let seededDocument = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ui-test-lab-report.pdf"))
            .firstMatch
        if !seededDocument.waitForExistence(timeout: 5) {
            app.swipeDown()
        }

        XCTAssertTrue(
            seededDocument.waitForExistence(timeout: 5),
            "Seeded lab report should appear in Documents when UI test launch arguments are enabled"
        )
        XCTAssertTrue(
            (seededDocument.value as? String ?? "").contains("Completed"),
            "Seeded lab report should expose completed processing status"
        )
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
        // This looked for a button labelled "plus", which never existed, so its `if` skipped
        // every assertion. It now has to find the menu.
        let addButton = app.buttons["Add Document"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "The Add Document menu should be in the toolbar")
        addButton.tap()

        XCTAssertTrue(app.buttons["Import File"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Import Photos"].exists)
        #if targetEnvironment(simulator)
        // The app hides scanning where there is no document camera.
        XCTAssertFalse(app.buttons["Scan Document"].exists)
        #else
        XCTAssertTrue(app.buttons["Scan Document"].exists)
        #endif

        // Dismiss menu
        app.tap()
    }
    
    // MARK: - Document List Tests
    
    func testDocumentListView() throws {
        // The seeded report is listed, with its status in the row's value.
        let seededDocument = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ui-test-lab-report.pdf"))
            .firstMatch
        XCTAssertTrue(seededDocument.waitForExistence(timeout: 10), "The documents list should show the seeded report")
        XCTAssertFalse(app.staticTexts["No Documents"].exists)
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
        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "Edit should be offered once there are documents")
        editButton.tap()

        // In edit mode the system's EditButton becomes a checkmark.
        XCTAssertTrue(app.buttons["documents.selectionToggle"].waitForExistence(timeout: 3), "Edit mode should show selection controls")
        let doneButton = app.buttons["checkmark"]
        XCTAssertTrue(doneButton.exists, "Edit mode should offer a way out")
        doneButton.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3), "Done should leave edit mode")
        XCTAssertFalse(app.buttons["documents.selectionToggle"].exists)
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
        
        // One button that names the other mode.
        let toGrid = app.buttons["Grid View"]
        XCTAssertTrue(toGrid.waitForExistence(timeout: 3), "The view mode button should offer the grid first")
        toGrid.tap()

        let toList = app.buttons["List View"]
        XCTAssertTrue(toList.waitForExistence(timeout: 2), "After switching, it should offer the list")
        toList.tap()
    }
    
    // MARK: - Batch Operations Tests
    
    func testBatchSelection() throws {
        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10))
        editButton.tap()

        // Selecting a document offers batch processing.
        let selectionToggle = app.buttons["documents.selectionToggle"]
        XCTAssertTrue(selectionToggle.waitForExistence(timeout: 3), "Edit mode should show a selection control per document")
        selectionToggle.tap()

        let batchButton = app.buttons["Batch Process"]
        XCTAssertTrue(batchButton.waitForExistence(timeout: 3), "Batch should appear once a document is selected")
        batchButton.tap()
        XCTAssertTrue(screenTitle("Batch Processing").waitForExistence(timeout: 5))

        app.buttons["Cancel"].tap()
        XCTAssertTrue(screenTitle("Batch Processing").waitForNonExistence(timeout: 5))
        app.buttons["checkmark"].tap()
    }
    
    // MARK: - Processing Tests
    
    func testProcessAllPendingButton() throws {
        guard !app.staticTexts["No Documents"].exists else {
            throw XCTSkip("No documents available for testing")
        }
        
        // Open add menu
        app.buttons["Add Document"].tap()
        
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
        app.buttons["Add Document"].tap()
        
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
        // The Documents segment and the icon-only toolbar menu both carry spoken names.
        let segment = app.buttons.matching(identifier: "health.segment")["Documents"]
        XCTAssertTrue(segment.exists)
        XCTAssertTrue(segment.isSelected)
        XCTAssertTrue(app.buttons["Add Document"].exists)

        app.buttons["Add Document"].tap()
        XCTAssertEqual(app.buttons["Import File"].label, "Import File")
        XCTAssertEqual(app.buttons["Import Photos"].label, "Import Photos")
    }
    
    func testVoiceOverSupport() throws {
        // The document row reads its name and, as the value, its processing status.
        let seededDocument = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ui-test-lab-report.pdf"))
            .firstMatch
        XCTAssertTrue(seededDocument.waitForExistence(timeout: 10))
        XCTAssertFalse((seededDocument.value as? String ?? "").isEmpty, "The row should announce a status")
        XCTAssertTrue(app.buttons["Edit"].exists, "Edit should be offered with a spoken label")
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
        
        navigateToChat()
        
        // Verify chat interface exists
        XCTAssertTrue(app.navigationBars["BisonHealth AI"].exists)
        
        // Return to documents
        navigateToDocuments()
        XCTAssertTrue(app.navigationBars["Documents"].exists)
    }

}
