import XCTest
@testable import HealthApp

@MainActor
final class AIChatManagerTests: XCTestCase {

    func testProviderContextLimitsAreAvailableForSupportedProviders() {
        XCTAssertGreaterThan(AIProviderContextLimits.limit(for: .onDeviceLLM), 0)
        XCTAssertEqual(AIProviderContextLimits.limit(for: .bedrock), 200_000)
        XCTAssertGreaterThan(AIProviderContextLimits.limit(for: .openAICompatible), 0)
    }

    func testConversationContextBuilderReturnsTrimmedHistoryMetadata() {
        let result = ConversationContextBuilder.buildContext(
            currentMessage: "What changed?",
            healthContext: #"{"bloodPressure":"120/80"}"#,
            conversationHistory: [
                ChatMessage(content: "Earlier question", role: .user),
                ChatMessage(content: "Earlier answer", role: .assistant)
            ],
            systemPrompt: "You are a helpful clinician.",
            provider: .openAICompatible
        )

        XCTAssertTrue(result.includesHealthContext)
        XCTAssertGreaterThanOrEqual(result.conversationHistory.count, 0)
        XCTAssertGreaterThan(result.estimatedTokens, 0)
    }

    func testScriptedDoctorConversationReceivesSelectedHealthContext() async throws {
        let harness = try makeRegressionHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        try await seedHealthContext(in: harness)

        let chatManager = AIChatManager(
            healthDataManager: harness.healthDataManager,
            databaseManager: harness.databaseManager,
            settingsManager: harness.settingsManager,
            automaticallyLoadConversations: false,
            automaticallyUpdateContextOnSelection: false
        )
        chatManager.isOffline = false
        chatManager.isConnected = true
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])

        _ = try await chatManager.startNewConversation(title: "Scripted Doctor")
        try await chatManager.sendMessage("What should I ask my doctor about these labs?", useStreaming: false)

        let conversation = try XCTUnwrap(chatManager.currentConversation)
        XCTAssertTrue(conversation.messages.contains { $0.role == .user && $0.content.contains("these labs") })
        XCTAssertTrue(conversation.messages.contains { $0.role == .assistant && $0.content.contains("SCRIPTED_DOCTOR_REPLY") })

        let chatRequest = try XCTUnwrap(harness.scriptedProvider.requests.first { $0.message.contains("these labs") })
        XCTAssertTrue(chatRequest.context.contains("System:"))
        XCTAssertTrue(chatRequest.context.contains("personal_info"))
        XCTAssertTrue(chatRequest.context.contains("blood_tests"))
        XCTAssertTrue(chatRequest.context.contains("Glucose"))
        XCTAssertFalse(chatRequest.context.contains("simulatorNotSupported"))
    }

    func testContextSelectionIncludesOnlyRequestedDataTypes() async throws {
        let harness = try makeRegressionHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        try await seedHealthContext(in: harness)

        let chatManager = AIChatManager(
            healthDataManager: harness.healthDataManager,
            databaseManager: harness.databaseManager,
            settingsManager: harness.settingsManager,
            automaticallyLoadConversations: false,
            automaticallyUpdateContextOnSelection: false
        )

        chatManager.selectHealthDataForContext([.personalInfo], personalInfoCategories: [.basicInfo])
        let personalContext = await chatManager.buildHealthDataContextForTesting()
        XCTAssertTrue(personalContext.contains("personal_info"))
        XCTAssertTrue(personalContext.contains("Atorvastatin"))
        XCTAssertFalse(personalContext.contains("blood_tests"))
        XCTAssertFalse(personalContext.contains("medical_documents"))

        chatManager.selectHealthDataForContext([.bloodTest], personalInfoCategories: [])
        let labContext = await chatManager.buildHealthDataContextForTesting()
        XCTAssertTrue(labContext.contains("blood_tests"))
        XCTAssertTrue(labContext.contains("medical_documents"))
        XCTAssertTrue(labContext.contains("Glucose"))
        XCTAssertTrue(labContext.contains("ui-test-lab-report.pdf"))
        XCTAssertFalse(labContext.contains("personal_info"))
        XCTAssertFalse(labContext.contains("Atorvastatin"))
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
            .appendingPathComponent("BisonHealthChatRegression-\(UUID().uuidString)", isDirectory: true)
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
        scriptedProvider.reset()
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

    private func seedHealthContext(in harness: RegressionHarness) async throws {
        let personalInfo = PersonalHealthInfo(
            name: "Test Patient",
            dateOfBirth: ISO8601DateFormatter().date(from: "1980-01-01T12:00:00Z"),
            gender: .other,
            allergies: ["Penicillin"],
            medications: [
                Medication(
                    name: "Atorvastatin",
                    dosage: Dosage(value: 20, unit: .mg),
                    frequency: .daily,
                    prescribedBy: "Dr. Ada Test"
                )
            ]
        )
        try await harness.healthDataManager.savePersonalInfo(personalInfo)

        let document = MedicalDocument(
            fileName: "ui-test-lab-report.pdf",
            fileType: .pdf,
            filePath: harness.rootURL.appendingPathComponent("ui-test-lab-report.pdf"),
            processingStatus: .completed,
            documentDate: ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"),
            providerName: "Bison Diagnostics",
            providerType: .laboratory,
            documentCategory: .labReport,
            extractedText: "Glucose 98 mg/dL\nTotal Cholesterol 220 mg/dL",
            includeInAIContext: true,
            contextPriority: 5,
            fileSize: 2048,
            tags: ["unit-test"]
        )
        try await harness.databaseManager.saveMedicalDocument(document)

        let bloodTest = BloodTestResult(
            testDate: ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z") ?? Date(),
            laboratoryName: "Bison Diagnostics",
            orderingPhysician: "Dr. Ada Test",
            results: [
                BloodTestItem(name: "Glucose", value: "98", unit: "mg/dL", referenceRange: "70-100"),
                BloodTestItem(name: "Total Cholesterol", value: "220", unit: "mg/dL", referenceRange: "<200", isAbnormal: true)
            ],
            includeInAIContext: true,
            metadata: ["source_document_id": document.id.uuidString]
        )
        try await harness.healthDataManager.addBloodTest(bloodTest)
        await harness.healthDataManager.loadHealthData()
    }
}
