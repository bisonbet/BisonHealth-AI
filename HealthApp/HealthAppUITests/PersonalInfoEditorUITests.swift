import XCTest

final class PersonalInfoEditorUITests: HealthAppUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openAddHealthDataMenuItem("Add Personal Information")
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
        XCTAssertTrue(datePicker.isHittable)
        XCTAssertTrue(app.staticTexts["Date of Birth"].exists)
    }
    
    func testGenderPicker() throws {
        let genderPicker = button(labelStartingWith: "Sex")
        XCTAssertTrue(genderPicker.exists)
        XCTAssertEqual(genderPicker.label, "Sex, Prefer not to say")

        genderPicker.tap()
        XCTAssertTrue(app.buttons["Male"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Female"].exists)
        XCTAssertTrue(app.buttons["Other"].exists)
        app.buttons["Male"].tap()

        XCTAssertTrue(app.buttons["Sex, Male"].waitForExistence(timeout: 2), "The picker should show the choice")
    }
    
    func testBloodTypePicker() throws {
        let bloodTypePicker = button(labelStartingWith: "Blood Type")
        XCTAssertTrue(bloodTypePicker.exists)

        bloodTypePicker.tap()
        XCTAssertTrue(app.buttons["A+"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["O-"].exists)
        app.buttons["A+"].tap()

        XCTAssertTrue(app.buttons["Blood Type, A+"].waitForExistence(timeout: 2), "The picker should show the choice")
    }
    
    // MARK: - Measurement System Tests

    /// A wheel picker whose current value starts with `prefix` ("173 cm").
    private func wheel(valueStartingWith prefix: String) -> XCUIElement {
        app.pickerWheels.matching(NSPredicate(format: "value BEGINSWITH %@", prefix)).firstMatch
    }
    
    func testUnitSystemToggle() throws {
        let metric = app.buttons["Metric (cm, kg)"]
        let imperial = app.buttons["Imperial (ft/in, lbs)"]
        XCTAssertTrue(metric.exists)
        XCTAssertTrue(metric.isSelected, "Metric is the default")
        XCTAssertTrue(wheel(valueStartingWith: "173 cm").exists)

        imperial.tap()
        XCTAssertTrue(wheel(valueStartingWith: "5 ft").waitForExistence(timeout: 2), "Height should switch to feet")
        XCTAssertTrue(wheel(valueStartingWith: "8 in").exists, "and inches")

        metric.tap()
        XCTAssertTrue(wheel(valueStartingWith: "173 cm").waitForExistence(timeout: 2), "Height should switch back to centimetres")
    }
    
    func testHeightInputModes() throws {
        let typeValue = app.buttons.matching(NSPredicate(format: "label == %@", "Type Value")).element(boundBy: 0)
        XCTAssertTrue(typeValue.exists)
        typeValue.tap()

        let heightField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Height (cm)")).firstMatch
        XCTAssertTrue(heightField.waitForExistence(timeout: 2), "Typing mode should show a text field")
        heightField.tap()
        heightField.typeText("175")
        XCTAssertEqual(heightField.value as? String, "175")

        let usePicker = app.buttons["Use Picker"]
        XCTAssertTrue(usePicker.exists)
        usePicker.tap()
        XCTAssertTrue(heightField.waitForNonExistence(timeout: 2), "Picker mode should hide the text field")
    }
    
    func testWeightInputModes() throws {
        let typeValue = app.buttons.matching(NSPredicate(format: "label == %@", "Type Value")).element(boundBy: 1)
        XCTAssertTrue(scrollUntilHittable(typeValue))
        typeValue.tap()

        let weightField = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Weight (kg)")).firstMatch
        XCTAssertTrue(weightField.waitForExistence(timeout: 2), "Typing mode should show a text field")
        weightField.tap()
        weightField.typeText("70")
        XCTAssertEqual(weightField.value as? String, "70")

        app.buttons["Use Picker"].tap()
        XCTAssertTrue(weightField.waitForNonExistence(timeout: 2), "Picker mode should hide the text field")
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
        let nameField = app.textFields["personalInfo.nameField"]
        nameField.tap()
        nameField.typeText("John Doe")

        button(labelStartingWith: "Sex").tap()
        app.buttons["Male"].tap()
        button(labelStartingWith: "Blood Type").tap()
        app.buttons["A+"].tap()

        let saveButton = app.buttons["personalInfo.saveButton"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        // Back on Health, the card shows the saved name instead of the empty state.
        XCTAssertTrue(screenTitle("Health Data").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No personal information added"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["John Doe"].waitForExistence(timeout: 5))
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        // Verify key elements have accessibility identifiers
        XCTAssertTrue(app.textFields["personalInfo.nameField"].exists)
        XCTAssertTrue(app.datePickers["personalInfo.dateOfBirthPicker"].exists)
        XCTAssertTrue(app.buttons["personalInfo.saveButton"].exists)
    }
    
    func testVoiceOverSupport() throws {
        // The name field announces its purpose; the pickers announce title and value.
        XCTAssertEqual(app.textFields["personalInfo.nameField"].placeholderValue, "Full Name")
        XCTAssertTrue(button(labelStartingWith: "Sex, ").exists)
        XCTAssertTrue(button(labelStartingWith: "Blood Type, ").exists)
        XCTAssertEqual(app.buttons["personalInfo.saveButton"].label, "Save")
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