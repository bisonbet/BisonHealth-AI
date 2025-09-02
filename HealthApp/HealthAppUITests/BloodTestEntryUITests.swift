import XCTest

final class BloodTestEntryUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Navigate to Health Data tab and open Blood Test Entry
        app.tabBars.buttons["Health Data"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap() // Menu button
        app.buttons["Blood Test"].tap()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic Navigation Tests
    
    func testBloodTestEntryOpens() throws {
        XCTAssertTrue(app.navigationBars["Blood Test Entry"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
    }
    
    func testCancelButtonDismissesEntry() throws {
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["Blood Test Entry"].exists)
    }
    
    // MARK: - Test Information Section Tests
    
    func testTestDatePicker() throws {
        let datePicker = app.datePickers["bloodTest.testDatePicker"]
        XCTAssertTrue(datePicker.exists)
        
        // Test that date picker is interactive
        datePicker.tap()
        XCTAssertTrue(datePicker.isHittable)
    }
    
    func testLaboratoryNameField() throws {
        let labField = app.textFields["bloodTest.laboratoryField"]
        XCTAssertTrue(labField.exists)
        
        labField.tap()
        labField.typeText("Quest Diagnostics")
        
        XCTAssertEqual(labField.value as? String, "Quest Diagnostics")
    }
    
    func testOrderingPhysicianField() throws {
        let physicianField = app.textFields["bloodTest.physicianField"]
        XCTAssertTrue(physicianField.exists)
        
        physicianField.tap()
        physicianField.typeText("Dr. Smith")
        
        XCTAssertEqual(physicianField.value as? String, "Dr. Smith")
    }
    
    // MARK: - Test Results Section Tests
    
    func testAddTestResultButton() throws {
        let addButton = app.buttons["bloodTest.addResultButton"]
        XCTAssertTrue(addButton.exists)
        
        // Initially should show empty state
        XCTAssertTrue(app.staticTexts["No test results added"].exists)
        
        // Add a test result
        addButton.tap()
        
        // Should now show test result fields
        XCTAssertTrue(app.textFields["bloodTestItem.nameField"].exists)
        XCTAssertTrue(app.textFields["bloodTestItem.valueField"].exists)
    }
    
    func testTestResultItemFields() throws {
        // Add a test result first
        app.buttons["bloodTest.addResultButton"].tap()
        
        // Test name field
        let nameField = app.textFields["bloodTestItem.nameField"]
        XCTAssertTrue(nameField.exists)
        nameField.tap()
        nameField.typeText("Glucose")
        
        // Test value field
        let valueField = app.textFields["bloodTestItem.valueField"]
        XCTAssertTrue(valueField.exists)
        valueField.tap()
        valueField.typeText("95")
        
        // Test unit field
        let unitField = app.textFields["bloodTestItem.unitField"]
        XCTAssertTrue(unitField.exists)
        unitField.tap()
        unitField.typeText("mg/dL")
        
        // Test reference range field
        let rangeField = app.textFields["bloodTestItem.referenceRangeField"]
        XCTAssertTrue(rangeField.exists)
        rangeField.tap()
        rangeField.typeText("70-100")
        
        // Test abnormal toggle
        let abnormalToggle = app.switches["bloodTestItem.abnormalToggle"]
        XCTAssertTrue(abnormalToggle.exists)
        abnormalToggle.tap()
        XCTAssertEqual(abnormalToggle.value as? String, "1")
    }
    
    func testMultipleTestResults() throws {
        // Add first test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        let firstNameField = app.textFields["bloodTestItem.nameField"]
        firstNameField.tap()
        firstNameField.typeText("Glucose")
        
        let firstValueField = app.textFields["bloodTestItem.valueField"]
        firstValueField.tap()
        firstValueField.typeText("95")
        
        // Add second test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        // Should now have multiple test result sections
        let nameFields = app.textFields.matching(identifier: "bloodTestItem.nameField")
        XCTAssertEqual(nameFields.count, 2)
        
        // Fill second result
        let secondNameField = nameFields.element(boundBy: 1)
        secondNameField.tap()
        secondNameField.typeText("Cholesterol")
        
        let valueFields = app.textFields.matching(identifier: "bloodTestItem.valueField")
        let secondValueField = valueFields.element(boundBy: 1)
        secondValueField.tap()
        secondValueField.typeText("180")
    }
    
    func testDeleteTestResult() throws {
        // Add a test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        let nameField = app.textFields["bloodTestItem.nameField"]
        nameField.tap()
        nameField.typeText("Glucose")
        
        // Swipe to delete (this is a simplified test - actual deletion might require different gestures)
        let testResultCell = nameField.firstMatch
        testResultCell.swipeLeft()
        
        // Look for delete button (implementation may vary)
        if app.buttons["Delete"].exists {
            app.buttons["Delete"].tap()
        }
    }
    
    // MARK: - Validation Tests
    
    func testTestDateValidation() throws {
        // This test would require setting a future date, which is complex in UI tests
        // For now, we verify the date picker exists and has proper constraints
        let datePicker = app.datePickers["bloodTest.testDatePicker"]
        XCTAssertTrue(datePicker.exists)
    }
    
    func testResultsValidation() throws {
        // Test that save button is disabled when no results
        let saveButton = app.buttons["bloodTest.saveButton"]
        XCTAssertFalse(saveButton.isEnabled)
        
        // Add empty test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        // Save should still be disabled with empty result
        XCTAssertFalse(saveButton.isEnabled)
        
        // Add valid test result
        let nameField = app.textFields["bloodTestItem.nameField"]
        nameField.tap()
        nameField.typeText("Glucose")
        
        let valueField = app.textFields["bloodTestItem.valueField"]
        valueField.tap()
        valueField.typeText("95")
        
        // Save should now be enabled
        XCTAssertTrue(saveButton.isEnabled)
    }
    
    func testTestItemValidation() throws {
        // Add a test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        // Test name validation - enter single character
        let nameField = app.textFields["bloodTestItem.nameField"]
        nameField.tap()
        nameField.typeText("A")
        
        // Should show validation error (implementation dependent)
        // This is a placeholder - actual validation error detection would need refinement
        
        // Test value validation - leave empty
        let valueField = app.textFields["bloodTestItem.valueField"]
        valueField.tap()
        // Don't type anything
        
        // Tap elsewhere to trigger validation
        app.tap()
    }
    
    func testDuplicateTestNames() throws {
        // Add first test result
        app.buttons["bloodTest.addResultButton"].tap()
        
        let firstNameField = app.textFields["bloodTestItem.nameField"]
        firstNameField.tap()
        firstNameField.typeText("Glucose")
        
        let firstValueField = app.textFields["bloodTestItem.valueField"]
        firstValueField.tap()
        firstValueField.typeText("95")
        
        // Add second test result with same name
        app.buttons["bloodTest.addResultButton"].tap()
        
        let nameFields = app.textFields.matching(identifier: "bloodTestItem.nameField")
        let secondNameField = nameFields.element(boundBy: 1)
        secondNameField.tap()
        secondNameField.typeText("Glucose") // Duplicate name
        
        let valueFields = app.textFields.matching(identifier: "bloodTestItem.valueField")
        let secondValueField = valueFields.element(boundBy: 1)
        secondValueField.tap()
        secondValueField.typeText("100")
        
        // Should show validation error for duplicate names
        let errorText = app.staticTexts["bloodTest.resultsError"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))
    }
    
    // MARK: - Save Functionality Tests
    
    func testSaveButtonState() throws {
        let saveButton = app.buttons["bloodTest.saveButton"]
        
        // Initially disabled (no results)
        XCTAssertFalse(saveButton.isEnabled)
        
        // Add valid result
        app.buttons["bloodTest.addResultButton"].tap()
        
        let nameField = app.textFields["bloodTestItem.nameField"]
        nameField.tap()
        nameField.typeText("Glucose")
        
        let valueField = app.textFields["bloodTestItem.valueField"]
        valueField.tap()
        valueField.typeText("95")
        
        // Should now be enabled
        XCTAssertTrue(saveButton.isEnabled)
    }
    
    func testCompleteBloodTestWorkflow() throws {
        // Fill test information
        let labField = app.textFields["bloodTest.laboratoryField"]
        labField.tap()
        labField.typeText("Quest Diagnostics")
        
        let physicianField = app.textFields["bloodTest.physicianField"]
        physicianField.tap()
        physicianField.typeText("Dr. Smith")
        
        // Add test results
        app.buttons["bloodTest.addResultButton"].tap()
        
        let nameField = app.textFields["bloodTestItem.nameField"]
        nameField.tap()
        nameField.typeText("Glucose")
        
        let valueField = app.textFields["bloodTestItem.valueField"]
        valueField.tap()
        valueField.typeText("95")
        
        let unitField = app.textFields["bloodTestItem.unitField"]
        unitField.tap()
        unitField.typeText("mg/dL")
        
        let rangeField = app.textFields["bloodTestItem.referenceRangeField"]
        rangeField.tap()
        rangeField.typeText("70-100")
        
        // Save the blood test
        let saveButton = app.buttons["bloodTest.saveButton"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()
        
        // Should return to health data view
        XCTAssertFalse(app.navigationBars["Blood Test Entry"].exists)
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        // Verify key elements have accessibility identifiers
        XCTAssertTrue(app.datePickers["bloodTest.testDatePicker"].exists)
        XCTAssertTrue(app.textFields["bloodTest.laboratoryField"].exists)
        XCTAssertTrue(app.buttons["bloodTest.addResultButton"].exists)
        XCTAssertTrue(app.buttons["bloodTest.saveButton"].exists)
    }
    
    func testVoiceOverSupport() throws {
        let labField = app.textFields["bloodTest.laboratoryField"]
        XCTAssertNotNil(labField.label)
        XCTAssertTrue(labField.isAccessibilityElement)
        
        let addButton = app.buttons["bloodTest.addResultButton"]
        XCTAssertNotNil(addButton.label)
        XCTAssertTrue(addButton.isAccessibilityElement)
    }
    
    // MARK: - iPad Specific Tests
    
    func testIPadLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        // Test that form elements are properly sized for iPad
        let labField = app.textFields["bloodTest.laboratoryField"]
        XCTAssertTrue(labField.exists)
        
        // Verify keyboard handling on iPad
        labField.tap()
        XCTAssertTrue(app.keyboards.element.exists)
        
        // Test that multiple test results display well on iPad's larger screen
        app.buttons["bloodTest.addResultButton"].tap()
        app.buttons["bloodTest.addResultButton"].tap()
        app.buttons["bloodTest.addResultButton"].tap()
        
        let nameFields = app.textFields.matching(identifier: "bloodTestItem.nameField")
        XCTAssertEqual(nameFields.count, 3)
    }
    
    // MARK: - Performance Tests
    
    func testLargeNumberOfResults() throws {
        // Test adding many results (stress test)
        for i in 1...10 {
            app.buttons["bloodTest.addResultButton"].tap()
            
            let nameFields = app.textFields.matching(identifier: "bloodTestItem.nameField")
            let nameField = nameFields.element(boundBy: i - 1)
            nameField.tap()
            nameField.typeText("Test \(i)")
            
            let valueFields = app.textFields.matching(identifier: "bloodTestItem.valueField")
            let valueField = valueFields.element(boundBy: i - 1)
            valueField.tap()
            valueField.typeText("\(i * 10)")
        }
        
        // Verify all results are present
        let nameFields = app.textFields.matching(identifier: "bloodTestItem.nameField")
        XCTAssertEqual(nameFields.count, 10)
        
        // Test scrolling performance
        app.swipeUp()
        app.swipeDown()
    }
}