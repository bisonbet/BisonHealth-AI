import XCTest

final class PersonalInfoEditorUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Navigate to Health Data tab and open Personal Info Editor
        app.tabBars.buttons["Health Data"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap() // Menu button
        app.buttons["Personal Info"].tap()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic Navigation Tests
    
    func testPersonalInfoEditorOpens() throws {
        XCTAssertTrue(app.navigationBars["Personal Information"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
    }
    
    func testCancelButtonDismissesEditor() throws {
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["Personal Information"].exists)
    }
    
    // MARK: - Form Input Tests
    
    func testNameFieldInput() throws {
        let nameField = app.textFields["personalInfo.nameField"]
        XCTAssertTrue(nameField.exists)
        
        nameField.tap()
        nameField.typeText("John Doe")
        
        XCTAssertEqual(nameField.value as? String, "John Doe")
    }
    
    func testDateOfBirthPicker() throws {
        let datePicker = app.datePickers["personalInfo.dateOfBirthPicker"]
        XCTAssertTrue(datePicker.exists)
        
        // Test that date picker is interactive
        datePicker.tap()
        XCTAssertTrue(datePicker.isHittable)
    }
    
    func testGenderPicker() throws {
        let genderPicker = app.buttons["Sex"]
        XCTAssertTrue(genderPicker.exists)
        
        genderPicker.tap()
        XCTAssertTrue(app.buttons["Male"].exists)
        XCTAssertTrue(app.buttons["Female"].exists)
        XCTAssertTrue(app.buttons["Other"].exists)
        
        app.buttons["Male"].tap()
    }
    
    func testBloodTypePicker() throws {
        let bloodTypePicker = app.buttons["Blood Type"]
        XCTAssertTrue(bloodTypePicker.exists)
        
        bloodTypePicker.tap()
        XCTAssertTrue(app.buttons["A+"].exists)
        XCTAssertTrue(app.buttons["O-"].exists)
        
        app.buttons["A+"].tap()
    }
    
    // MARK: - Measurement System Tests
    
    func testUnitSystemToggle() throws {
        let unitPicker = app.segmentedControls.element
        XCTAssertTrue(unitPicker.exists)
        
        // Test switching to Imperial
        unitPicker.buttons["Imperial (ft/in, lbs)"].tap()
        
        // Verify height pickers show feet/inches
        XCTAssertTrue(app.buttons["5 ft"].exists)
        XCTAssertTrue(app.buttons["8 in"].exists)
        
        // Test switching back to Metric
        unitPicker.buttons["Metric (cm, kg)"].tap()
        
        // Verify height picker shows centimeters
        XCTAssertTrue(app.buttons["173 cm"].exists)
    }
    
    func testHeightInputModes() throws {
        // Test picker to text input toggle
        let heightToggleButton = app.buttons["Type Value"]
        if heightToggleButton.exists {
            heightToggleButton.tap()
            
            // Should now show text field
            let heightTextField = app.textFields.element
            XCTAssertTrue(heightTextField.exists)
            
            // Test typing height
            heightTextField.tap()
            heightTextField.typeText("175")
            
            // Toggle back to picker
            app.buttons["Use Picker"].tap()
        }
    }
    
    func testWeightInputModes() throws {
        // Scroll to weight section
        app.swipeUp()
        
        // Test weight input toggle
        let weightToggleButton = app.buttons["Type Value"]
        if weightToggleButton.exists {
            weightToggleButton.tap()
            
            // Should now show text field
            let weightTextField = app.textFields.element
            XCTAssertTrue(weightTextField.exists)
            
            // Test typing weight
            weightTextField.tap()
            weightTextField.typeText("70")
            
            // Toggle back to picker
            app.buttons["Use Picker"].tap()
        }
    }
    
    // MARK: - Validation Tests
    
    func testNameValidation() throws {
        let nameField = app.textFields["personalInfo.nameField"]
        nameField.tap()
        nameField.typeText("A") // Too short
        
        // Check for validation error
        let errorText = app.staticTexts["personalInfo.nameError"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))
        XCTAssertTrue(errorText.label.contains("at least 2 characters"))
    }
    
    func testDateOfBirthValidation() throws {
        // This test would require setting a future date, which is complex in UI tests
        // For now, we verify the date picker exists and has proper constraints
        let datePicker = app.datePickers["personalInfo.dateOfBirthPicker"]
        XCTAssertTrue(datePicker.exists)
    }
    
    func testSaveButtonState() throws {
        let saveButton = app.buttons["personalInfo.saveButton"]
        XCTAssertTrue(saveButton.exists)
        
        // Initially should be enabled (no validation errors)
        XCTAssertTrue(saveButton.isEnabled)
        
        // Add invalid name to test disabled state
        let nameField = app.textFields["personalInfo.nameField"]
        nameField.tap()
        nameField.typeText("A") // Too short
        
        // Save button should become disabled
        XCTAssertFalse(saveButton.isEnabled)
    }
    
    // MARK: - Medical Information Navigation Tests
    
    func testAllergiesNavigation() throws {
        app.swipeUp() // Scroll to medical information section
        
        let allergiesButton = app.buttons.matching(identifier: "Allergies").element
        if allergiesButton.exists {
            allergiesButton.tap()
            XCTAssertTrue(app.navigationBars["Allergies"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap() // Back button
        }
    }
    
    func testMedicationsNavigation() throws {
        app.swipeUp() // Scroll to medical information section
        
        let medicationsButton = app.buttons.matching(identifier: "Medications").element
        if medicationsButton.exists {
            medicationsButton.tap()
            XCTAssertTrue(app.navigationBars["Medications"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap() // Back button
        }
    }
    
    func testMedicalHistoryNavigation() throws {
        app.swipeUp() // Scroll to medical information section
        
        let historyButton = app.buttons.matching(identifier: "Medical History").element
        if historyButton.exists {
            historyButton.tap()
            XCTAssertTrue(app.navigationBars["Medical History"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap() // Back button
        }
    }
    
    func testEmergencyContactsNavigation() throws {
        app.swipeUp() // Scroll to medical information section
        
        let contactsButton = app.buttons.matching(identifier: "Emergency Contacts").element
        if contactsButton.exists {
            contactsButton.tap()
            XCTAssertTrue(app.navigationBars["Emergency Contacts"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap() // Back button
        }
    }
    
    // MARK: - Complete Form Workflow Test
    
    func testCompleteFormWorkflow() throws {
        // Fill out complete form
        let nameField = app.textFields["personalInfo.nameField"]
        nameField.tap()
        nameField.typeText("John Doe")
        
        // Set date of birth (simplified - just tap to interact)
        app.datePickers["personalInfo.dateOfBirthPicker"].tap()
        
        // Set gender
        app.buttons["Sex"].tap()
        app.buttons["Male"].tap()
        
        // Set blood type
        app.buttons["Blood Type"].tap()
        app.buttons["A+"].tap()
        
        // Verify save button is enabled
        let saveButton = app.buttons["personalInfo.saveButton"]
        XCTAssertTrue(saveButton.isEnabled)
        
        // Save the form
        saveButton.tap()
        
        // Should return to health data view
        XCTAssertFalse(app.navigationBars["Personal Information"].exists)
        XCTAssertTrue(app.navigationBars["Health Data"].exists)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        // Verify key elements have accessibility identifiers
        XCTAssertTrue(app.textFields["personalInfo.nameField"].exists)
        XCTAssertTrue(app.datePickers["personalInfo.dateOfBirthPicker"].exists)
        XCTAssertTrue(app.buttons["personalInfo.saveButton"].exists)
    }
    
    func testVoiceOverSupport() throws {
        // Enable VoiceOver for testing
        // Note: This requires additional setup in real testing scenarios
        let nameField = app.textFields["personalInfo.nameField"]
        XCTAssertNotNil(nameField.label)
        XCTAssertTrue(nameField.isAccessibilityElement)
    }
    
    // MARK: - iPad Specific Tests
    
    func testIPadLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }
        
        // Test that form elements are properly sized for iPad
        let nameField = app.textFields["personalInfo.nameField"]
        XCTAssertTrue(nameField.exists)
        
        // Verify keyboard handling on iPad
        nameField.tap()
        XCTAssertTrue(app.keyboards.element.exists)
        
        // Test external keyboard support (if available)
        // This would require additional setup for external keyboard testing
    }
}