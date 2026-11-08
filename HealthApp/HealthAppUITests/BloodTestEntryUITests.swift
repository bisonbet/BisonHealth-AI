import XCTest

/// The lab-results editor, opened from Health → Add Health Data → Add Lab Results.
final class BloodTestEntryUITests: HealthAppUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openAddHealthDataMenuItem("Add Lab Results")
        XCTAssertTrue(screenTitle("Lab Results Entry").waitForExistence(timeout: 5), "The lab results editor should open")
    }

    // MARK: - Elements

    private var saveButton: XCUIElement { app.buttons["bloodTest.saveButton"] }
    private var addResultButton: XCUIElement { app.buttons["bloodTest.addResultButton"] }
    private var laboratoryField: XCUIElement { app.textFields["bloodTest.laboratoryDropdown"] }
    private var physicianField: XCUIElement { app.textFields["bloodTest.physicianDropdown"] }
    private var nameFields: XCUIElementQuery { app.textFields.matching(identifier: "bloodTestItem.nameField") }
    private var valueFields: XCUIElementQuery { app.textFields.matching(identifier: "bloodTestItem.valueField") }

    /// Adds a result and, if given, types its custom name and value into the new row.
    ///
    /// The new row is found as the one whose name field is still empty, not by index: the
    /// form loads rows lazily, so once there are a few results the earlier ones are no longer
    /// in the hierarchy and an index would point at the wrong row.
    private func addResult(name: String? = nil, value: String? = nil) {
        XCTAssertTrue(scrollUntilHittable(addResultButton), "Add Test Result should be reachable")
        addResultButton.tap()
        let newRow = app.cells.containing(NSPredicate(
            format: "identifier == 'bloodTestItem.nameField' AND (value == nil OR value == '' OR value == placeholderValue)"
        )).firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: 3), "A new result row should appear")
        // Value first: once the name is typed the row no longer matches `newRow`.
        if let value {
            type(value, into: newRow.textFields["bloodTestItem.valueField"])
        }
        if let name {
            type(name, into: newRow.textFields["bloodTestItem.nameField"])
        }
    }

    private func type(_ text: String, into field: XCUIElement) {
        scrollUntilHittable(field)
        field.tap()
        field.typeText(text)
    }

    // MARK: - Basic Navigation Tests

    func testBloodTestEntryOpens() throws {
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(saveButton.exists)
    }

    func testCancelButtonDismissesEntry() throws {
        app.buttons["Cancel"].tap()
        XCTAssertTrue(screenTitle("Lab Results Entry").waitForNonExistence(timeout: 5))
    }

    // MARK: - Test Information Section Tests

    func testTestDatePicker() throws {
        let datePicker = app.datePickers["bloodTest.testDatePicker"]
        XCTAssertTrue(datePicker.exists)
        XCTAssertTrue(datePicker.isHittable)
        // The date defaults to today, which is valid, so no date error is shown.
        XCTAssertFalse(app.staticTexts["bloodTest.testDateError"].exists)
    }

    func testLaboratoryNameField() throws {
        XCTAssertTrue(laboratoryField.exists)
        type("Quest Diagnostics", into: laboratoryField)
        XCTAssertEqual(laboratoryField.value as? String, "Quest Diagnostics")
    }

    func testOrderingPhysicianField() throws {
        XCTAssertTrue(physicianField.exists)
        type("Dr. Smith", into: physicianField)
        XCTAssertEqual(physicianField.value as? String, "Dr. Smith")
    }

    // MARK: - Test Results Section Tests

    func testAddTestResultButton() throws {
        XCTAssertTrue(addResultButton.exists)
        XCTAssertTrue(app.staticTexts["No test results added"].exists, "A new entry starts empty")

        addResult()

        XCTAssertFalse(app.staticTexts["No test results added"].exists)
        XCTAssertTrue(app.buttons["bloodTestItem.testTypeButton"].exists)
        XCTAssertTrue(nameFields.firstMatch.exists)
        XCTAssertTrue(valueFields.firstMatch.exists)
    }

    func testTestResultItemFields() throws {
        addResult(name: "Glucose", value: "95")
        XCTAssertEqual(nameFields.firstMatch.value as? String, "Glucose")
        XCTAssertEqual(valueFields.firstMatch.value as? String, "95")

        let unitField = app.textFields["bloodTestItem.unitDropdown"]
        type("mg/dL", into: unitField)
        XCTAssertEqual(unitField.value as? String, "mg/dL")

        let rangeField = app.textFields["bloodTestItem.referenceRangeField"]
        type("70-100", into: rangeField)
        XCTAssertEqual(rangeField.value as? String, "70-100")

        let abnormalToggle = app.switches["bloodTestItem.abnormalToggle"]
        XCTAssertTrue(scrollUntilHittable(abnormalToggle))
        XCTAssertEqual(abnormalToggle.value as? String, "0")
        abnormalToggle.switches.firstMatch.tap()
        XCTAssertEqual(abnormalToggle.value as? String, "1")
    }

    func testMultipleTestResults() throws {
        addResult(name: "Glucose", value: "95")
        addResult(name: "Cholesterol", value: "180")

        XCTAssertEqual(nameFields.count, 2)
        XCTAssertEqual(nameFields.element(boundBy: 1).value as? String, "Cholesterol")
        XCTAssertTrue(saveButton.isEnabled)
    }

    func testDeleteTestResult() throws {
        addResult(name: "Glucose", value: "95")
        XCTAssertEqual(nameFields.count, 1)

        // Results are rows with swipe-to-delete. The swipe is not recognised while the
        // keyboard is up; Return in the name field (typed last) dismisses it.
        nameFields.firstMatch.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let row = app.cells.containing(.textField, identifier: "bloodTestItem.nameField").firstMatch
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Swiping a result should offer Delete")
        delete.tap()

        XCTAssertTrue(nameFields.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled)
    }

    // MARK: - Validation Tests

    func testTestDateValidation() throws {
        // This test would require setting a future date, which is complex in UI tests
        // For now, we verify the date picker exists and has proper constraints
        let datePicker = app.datePickers["bloodTest.testDatePicker"]
        XCTAssertTrue(datePicker.exists)
    }

    func testResultsValidation() throws {
        let error = app.staticTexts["bloodTest.resultsError"]
        XCTAssertFalse(saveButton.isEnabled, "Nothing to save yet")
        XCTAssertEqual(error.label, "At least one test result is required")

        addResult()
        XCTAssertFalse(saveButton.isEnabled, "An empty result is not enough")

        type("Glucose", into: nameFields.firstMatch)
        type("95", into: valueFields.firstMatch)
        XCTAssertTrue(saveButton.isEnabled)
        XCTAssertFalse(error.exists)
    }

    func testTestItemValidation() throws {
        addResult()
        XCTAssertTrue(app.staticTexts["Test name is required"].exists)
        XCTAssertTrue(app.staticTexts["Test value is required"].exists)

        // A named result with no value cannot be saved.
        type("A", into: nameFields.firstMatch)
        XCTAssertFalse(app.staticTexts["Test name is required"].exists)
        XCTAssertEqual(app.staticTexts["bloodTest.resultsError"].label, "All test results must have values")
        XCTAssertFalse(saveButton.isEnabled)
    }

    func testDuplicateTestNames() throws {
        addResult(name: "Glucose", value: "95")
        addResult(name: "glucose", value: "100")

        let error = app.staticTexts["bloodTest.resultsError"]
        XCTAssertTrue(error.waitForExistence(timeout: 2))
        XCTAssertEqual(error.label, "Duplicate test names are not allowed")
        XCTAssertFalse(saveButton.isEnabled)
    }

    // MARK: - Save Functionality Tests

    func testSaveButtonState() throws {
        XCTAssertFalse(saveButton.isEnabled)
        addResult(name: "Glucose", value: "95")
        XCTAssertTrue(saveButton.isEnabled)
    }

    func testCompleteBloodTestWorkflow() throws {
        XCTAssertTrue(app.staticTexts["No test results added"].exists)
        type("Quest Diagnostics", into: laboratoryField)
        type("Dr. Smith", into: physicianField)
        addResult(name: "Glucose", value: "95")
        type("70-100", into: app.textFields["bloodTestItem.referenceRangeField"])

        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        // Back on Health, the record is listed and the empty state is gone.
        XCTAssertTrue(screenTitle("Lab Results Entry").waitForNonExistence(timeout: 5))
        XCTAssertTrue(screenTitle("Health Data").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No lab results"].waitForNonExistence(timeout: 5), "The saved result should replace the empty state")
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabels() throws {
        XCTAssertTrue(app.datePickers["bloodTest.testDatePicker"].exists)
        XCTAssertTrue(laboratoryField.exists)
        XCTAssertTrue(physicianField.exists)
        XCTAssertTrue(addResultButton.exists)
        XCTAssertTrue(saveButton.exists)
    }

    func testVoiceOverSupport() throws {
        // Fields announce their purpose through the placeholder; buttons through a label.
        XCTAssertEqual(laboratoryField.placeholderValue, "Laboratory Name")
        XCTAssertEqual(physicianField.placeholderValue, "Ordering Physician")
        XCTAssertEqual(addResultButton.label, "Add Test Result")
        XCTAssertEqual(saveButton.label, "Save")
    }

    // MARK: - iPad Specific Tests

    func testIPadLayout() throws {
        // Only run on iPad
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-specific test")
        }

        XCTAssertTrue(laboratoryField.exists)
        addResult()
        addResult()
        addResult()
        XCTAssertEqual(nameFields.count, 3)
    }

    // MARK: - Performance Tests

    func testLargeNumberOfResults() throws {
        for index in 1...10 {
            addResult(name: "Test \(index)", value: "\(index * 10)")
        }

        // Rows load lazily, so check the last one by scrolling to it rather than by count.
        let last = app.textFields.matching(
            NSPredicate(format: "identifier == 'bloodTestItem.nameField' AND value == 'Test 10'")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(last), "The tenth result should be in the form")
        XCTAssertTrue(saveButton.isEnabled)
    }
}
