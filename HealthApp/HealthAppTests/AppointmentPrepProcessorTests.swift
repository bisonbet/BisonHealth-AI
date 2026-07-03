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

@MainActor
final class AppointmentPrepManagerRegressionTests: XCTestCase {

    func testGenerateWithScriptedProviderPersistsCompleteSections() async throws {
        let harness = try makeRegressionHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        harness.scriptedProvider.reset(responses: [
            .success("TIMELINE:\n- Symptoms started Monday.\n- Worse after meals."),
            .success("1. What could be causing this?\n2. Which labs should we repeat?"),
            .success("- Bring recent lab results.\n- Ask about medication effects.")
        ])

        let manager = AppointmentPrepManager(
            databaseManager: harness.databaseManager,
            healthDataManager: harness.healthDataManager,
            settingsManager: harness.settingsManager
        )

        let input = AppointmentPrep(
            title: "GI Visit",
            providerName: "Dr. Test",
            symptoms: "I have had abdominal discomfort for the last three days",
            notes: "Worse after dinner",
            medications: "Atorvastatin 20 mg daily",
            includedHealthDataTypes: [.personalInfo]
        )

        let generated = await manager.generate(for: input)

        XCTAssertEqual(generated.status, .complete)
        XCTAssertEqual(manager.generationStage, .done)
        XCTAssertTrue(generated.timeline.contains("Symptoms started Monday."))
        XCTAssertFalse(generated.timeline.hasPrefix("TIMELINE"))
        XCTAssertTrue(generated.questions.contains("Which labs should we repeat?"))
        XCTAssertTrue(generated.relevantInfo.hasSuffix(AppointmentPrepPrompts.disclaimerSuffix))
        XCTAssertEqual(harness.scriptedProvider.requests.count, 3)
        XCTAssertTrue(harness.scriptedProvider.requests.allSatisfy { $0.message.contains(AppointmentPrepPrompts.systemPrompt) })

        let savedPreps = try await harness.databaseManager.fetchAppointmentPreps()
        XCTAssertTrue(savedPreps.contains { $0.id == generated.id && $0.status == .complete })
    }

    func testGenerateClearsStaleSectionsAndPreservesPartialOutputOnFailure() async throws {
        let harness = try makeRegressionHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        harness.scriptedProvider.reset(responses: [
            .success("- New timeline from this run."),
            .failure(RegressionTestError.intentionalFailure)
        ])

        let manager = AppointmentPrepManager(
            databaseManager: harness.databaseManager,
            healthDataManager: harness.healthDataManager,
            settingsManager: harness.settingsManager
        )

        let input = AppointmentPrep(
            title: "Follow-up Visit",
            symptoms: "I have had headaches and dizziness for several days",
            notes: "Stale notes should not matter",
            medications: "Atorvastatin 20 mg daily",
            timeline: "- Old timeline should be replaced.",
            questions: "Old questions should be cleared.",
            relevantInfo: "Old relevant info should be cleared.",
            includedHealthDataTypes: [.personalInfo],
            status: .complete
        )

        let generated = await manager.generate(for: input)

        XCTAssertEqual(generated.status, .complete)
        XCTAssertTrue(generated.timeline.contains("New timeline from this run."))
        XCTAssertFalse(generated.timeline.contains("Old timeline"))
        XCTAssertTrue(generated.questions.isEmpty)
        XCTAssertTrue(generated.relevantInfo.isEmpty)
        XCTAssertNotNil(manager.errorMessage)

        let savedPreps = try await harness.databaseManager.fetchAppointmentPreps()
        let saved = try XCTUnwrap(savedPreps.first { $0.id == generated.id })
        XCTAssertTrue(saved.timeline.contains("New timeline from this run."))
        XCTAssertTrue(saved.questions.isEmpty)
        XCTAssertTrue(saved.relevantInfo.isEmpty)
    }

    private enum RegressionTestError: LocalizedError {
        case intentionalFailure

        var errorDescription: String? {
            "Intentional scripted failure"
        }
    }

    private struct RegressionHarness {
        let rootURL: URL
        let databaseManager: DatabaseManager
        let fileSystemManager: FileSystemManager
        let healthDataManager: HealthDataManager
        let settingsManager: SettingsManager
        let scriptedProvider: ScriptedAIProvider
    }

    private func makeRegressionHarness() throws -> RegressionHarness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BisonHealthPrepRegression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let databaseManager = try DatabaseManager(
            databaseURL: rootURL.appendingPathComponent("Database/health_data.sqlite")
        )
        let fileSystemManager = try FileSystemManager(
            baseDirectory: rootURL.appendingPathComponent("Files/HealthApp", isDirectory: true)
        )
        let healthDataManager = HealthDataManager(
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager,
            automaticallyLoad: false
        )
        let settingsManager = SettingsManager()
        let scriptedProvider = ScriptedAIProvider()
        settingsManager.setAIClientOverrideForTesting(scriptedProvider)

        return RegressionHarness(
            rootURL: rootURL,
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager,
            healthDataManager: healthDataManager,
            settingsManager: settingsManager,
            scriptedProvider: scriptedProvider
        )
    }
}
