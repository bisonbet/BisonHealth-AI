import XCTest
@testable import HealthApp

// MARK: - Appointment Prep Processor Tests
/// Verifies the Swift port of the Python `medical-appt-prep` processor logic.
final class AppointmentPrepProcessorTests: XCTestCase {

    // MARK: - Validation

    func testValidateInputs_EmptySymptoms_ReturnsError() {
        let errors = AppointmentPrepProcessor.validateInputs(symptoms: "")
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains { $0.localizedCaseInsensitiveContains("describe your symptoms") })
    }

    func testValidateInputs_ShortSymptoms_ReturnsTooShortError() {
        let errors = AppointmentPrepProcessor.validateInputs(symptoms: "headache") // < 10 chars
        XCTAssertTrue(errors.contains { $0.localizedCaseInsensitiveContains("too short") })
    }

    func testValidateInputs_ValidSymptoms_ReturnsNoErrors() {
        let errors = AppointmentPrepProcessor.validateInputs(symptoms: "I have had a headache for three days")
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateInputs_OverlongField_ReturnsLengthError() {
        let longNotes = String(repeating: "a", count: AppointmentPrepProcessor.maxFieldLength + 1)
        let errors = AppointmentPrepProcessor.validateInputs(
            symptoms: "Valid symptom description here",
            notes: longNotes
        )
        XCTAssertTrue(errors.contains { $0.localizedCaseInsensitiveContains("maximum length") })
    }

    // MARK: - parseOutput

    func testParseOutput_Empty_ReturnsFallback() {
        XCTAssertEqual(AppointmentPrepProcessor.parseOutput("   \n  "), AppointmentPrepProcessor.noOutputFallback)
    }

    func testParseOutput_CollapsesBlankLines() {
        let result = AppointmentPrepProcessor.parseOutput("line a\n\n\n\n\nline b")
        XCTAssertEqual(result, "line a\n\nline b")
    }

    // MARK: - cleanSectionOutput

    func testCleanSectionOutput_StripsThinkBlock() {
        let raw = "<think>internal reasoning here</think>- Bullet one.\n- Bullet two."
        let cleaned = AppointmentPrepProcessor.cleanSectionOutput(raw)
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("internal reasoning"))
        XCTAssertTrue(cleaned.hasPrefix("- Bullet one."))
    }

    func testCleanSectionOutput_RemovesSectionHeaderPrefix() {
        let raw = "TIMELINE:\n- A symptom started Monday.\n- Worse at night."
        let cleaned = AppointmentPrepProcessor.cleanSectionOutput(raw)
        XCTAssertFalse(cleaned.hasPrefix("TIMELINE"))
        XCTAssertTrue(cleaned.hasPrefix("- A symptom started Monday."))
    }

    func testCleanSectionOutput_AppendsRequiredSuffix() {
        let raw = "- Stay hydrated.\n- Track your symptoms."
        let suffix = "This is informational only and not a substitute for professional medical advice."
        let cleaned = AppointmentPrepProcessor.cleanSectionOutput(raw, requiredSuffix: suffix)
        XCTAssertTrue(cleaned.hasSuffix(suffix))
    }

    func testCleanSectionOutput_DoesNotDuplicateExistingSuffix() {
        let suffix = "This is informational only and not a substitute for professional medical advice."
        let raw = "- Stay hydrated.\n\(suffix)"
        let cleaned = AppointmentPrepProcessor.cleanSectionOutput(raw, requiredSuffix: suffix)
        // The suffix should appear exactly once.
        let occurrences = cleaned.components(separatedBy: suffix).count - 1
        XCTAssertEqual(occurrences, 1)
    }

    // MARK: - limitListItems

    func testLimitListItems_CapsToMax() {
        let raw = "- 1 item.\n- 2 item.\n- 3 item.\n- 4 item.\n- 5 item.\n- 6 item."
        let limited = AppointmentPrepProcessor.limitListItems(raw, maxItems: 4)
        let lineCount = limited.components(separatedBy: "\n").count
        XCTAssertEqual(lineCount, 4)
        XCTAssertTrue(limited.hasSuffix("- 4 item."))
    }

    func testLimitListItems_NumberedItems() {
        let raw = "1. First question?\n2. Second question?\n3. Third question?"
        let limited = AppointmentPrepProcessor.limitListItems(raw, maxItems: 2)
        XCTAssertEqual(limited.components(separatedBy: "\n").count, 2)
    }
}
