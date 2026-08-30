import XCTest
import PDFKit
import SQLite
@testable import HealthApp

/// Regression tests for the pre-beta review fixes: streaming lifecycle, SSE
/// parsing, PHI encryption at rest, reprocess idempotency, context trimming,
/// the import-review queue, and the PDF exporter.
@MainActor
final class PreBetaRegressionTests: XCTestCase {

    // MARK: - Harness

    private struct Harness {
        let rootURL: URL
        let databaseManager: DatabaseManager
        let fileSystemManager: FileSystemManager
        let healthDataManager: HealthDataManager
        let settingsManager: SettingsManager
        let scriptedProvider: ScriptedAIProvider
    }

    private func makeHarness() throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BisonHealthPreBeta-\(UUID().uuidString)", isDirectory: true)
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

        return Harness(
            rootURL: rootURL,
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager,
            healthDataManager: healthDataManager,
            settingsManager: settingsManager,
            scriptedProvider: scriptedProvider
        )
    }

    // MARK: - SSE parsing (streaming reply corruption fix)

    func testSSEDataPayloadParsing() {
        // Standard form
        XCTAssertEqual(OpenAICompatibleClient.sseDataPayload(forLine: "data: {\"x\":1}"), "{\"x\":1}")
        // Spec-legal form without the trailing space (previously dropped the whole chunk)
        XCTAssertEqual(OpenAICompatibleClient.sseDataPayload(forLine: "data:{\"x\":1}"), "{\"x\":1}")
        // CRLF is tolerated by trimming
        XCTAssertEqual(OpenAICompatibleClient.sseDataPayload(forLine: "data: [DONE]\r"), "[DONE]")
        // Non-data lines are ignored
        XCTAssertNil(OpenAICompatibleClient.sseDataPayload(forLine: ": keep-alive comment"))
        XCTAssertNil(OpenAICompatibleClient.sseDataPayload(forLine: "event: ping"))
        XCTAssertNil(OpenAICompatibleClient.sseDataPayload(forLine: ""))
        XCTAssertNil(OpenAICompatibleClient.sseDataPayload(forLine: "   "))
    }

    // MARK: - Conversation persistence

    func testConversationPersonalInfoCategoriesPersistRoundTrip() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        guard let excludedCategory = PersonalInfoCategory.allCases.first else {
            return XCTFail("PersonalInfoCategory has no cases")
        }

        var conversation = ChatConversation(title: "Privacy Test")
        conversation.includedPersonalInfoCategories = Set(PersonalInfoCategory.allCases).subtracting([excludedCategory])
        try await harness.databaseManager.saveConversation(conversation)

        let fetched = try await harness.databaseManager.fetchConversations()
        guard let restored = fetched.first(where: { $0.id == conversation.id }) else {
            return XCTFail("Conversation not found after save")
        }

        XCTAssertFalse(restored.includedPersonalInfoCategories.contains(excludedCategory),
                       "Privacy opt-out must survive save/load — previously the column was never persisted and the decoder defaulted to ALL categories")
        XCTAssertEqual(restored.includedPersonalInfoCategories, conversation.includedPersonalInfoCategories)
    }

    func testChatTitleEncryptedAtRest() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let conversation = ChatConversation(title: "My Hemoglobin Results Discussion")
        try await harness.databaseManager.saveConversation(conversation)

        let row = try harness.databaseManager.db?.pluck(
            harness.databaseManager.chatConversationsTable
                .filter(harness.databaseManager.conversationId == conversation.id.uuidString)
        )
        guard let rawTitle = row?[harness.databaseManager.conversationTitle] else {
            return XCTFail("Raw conversation row missing")
        }
        XCTAssertNotEqual(rawTitle, "My Hemoglobin Results Discussion",
                           "Conversation titles are PHI (AI-derived from health messages) and must not sit in the SQLite file as plaintext")

        // And the model layer still decrypts correctly
        let fetched = try await harness.databaseManager.fetchConversations()
        XCTAssertEqual(fetched.first(where: { $0.id == conversation.id })?.title,
                       "My Hemoglobin Results Discussion")
    }

    // MARK: - Documents PHI encryption

    func testMedicalDocumentPHIEncryptedAtRestAndRoundTrips() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let document = MedicalDocument(
            fileName: "Private Lab Report.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/private.pdf"),
            processingStatus: .completed,
            documentDate: Date(timeIntervalSince1970: 1_700_000_000),
            providerName: "Bison Diagnostics",
            documentCategory: .labReport,
            extractedText: "Hemoglobin 13.5 g/dL — Glucose 95 mg/dL",
            fileSize: 2048,
            tags: ["lab"],
            notes: "Patient notes with details"
        )
        try await harness.databaseManager.saveMedicalDocument(document)

        let row = try harness.databaseManager.db?.pluck(
            harness.databaseManager.documentsTable
                .filter(harness.databaseManager.documentId == document.id.uuidString)
        )
        XCTAssertNotNil(row, "Raw document row missing")

        let rawFileName = row?[harness.databaseManager.documentFileName]
        let rawNotes = row?[harness.databaseManager.documentNotes]
        let rawExtractedText = row?[harness.databaseManager.documentExtractedText]
        let rawProviderName = row?[harness.databaseManager.documentProviderName]

        XCTAssertNotEqual(rawFileName, "Private Lab Report.pdf", "file_name must be encrypted at rest")
        XCTAssertNotEqual(rawNotes, "Patient notes with details", "notes must be encrypted at rest")
        XCTAssertNotEqual(rawExtractedText, "Hemoglobin 13.5 g/dL — Glucose 95 mg/dL", "extracted_text must be encrypted at rest")
        XCTAssertNotEqual(rawProviderName, "Bison Diagnostics", "provider_name must be encrypted at rest")

        // Round-trip through the decrypting row builder
        let fetched = try await harness.databaseManager.fetchMedicalDocument(id: document.id)
        XCTAssertEqual(fetched?.fileName, "Private Lab Report.pdf")
        XCTAssertEqual(fetched?.notes, "Patient notes with details")
        XCTAssertEqual(fetched?.extractedText, "Hemoglobin 13.5 g/dL — Glucose 95 mg/dL")
        XCTAssertEqual(fetched?.providerName, "Bison Diagnostics")
    }

    // MARK: - Reprocess idempotency

    func testLinkExtractedDataIsIdempotentForSameDocument() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let documentId = UUID()

        let bloodTest = BloodTestResult(
            testDate: Date(timeIntervalSince1970: 1_700_000_000),
            laboratoryName: "Bison Diagnostics",
            results: [BloodTestItem(name: "Hemoglobin", value: "13.5", unit: "g/dL")],
            metadata: ["source_document_id": documentId.uuidString]
        )

        // First link imports the blood test.
        try await harness.healthDataManager.linkExtractedDataToDocument(
            documentId,
            extractedData: [AnyHealthData(bloodTest)]
        )
        XCTAssertEqual(harness.healthDataManager.bloodTests.count, 1)

        // Second link (reprocess of the same document) must be a no-op, not a
        // document-failing error and not a duplicate import.
        try await harness.healthDataManager.linkExtractedDataToDocument(
            documentId,
            extractedData: [AnyHealthData(bloodTest)]
        )
        XCTAssertEqual(harness.healthDataManager.bloodTests.count, 1,
                       "Reprocessing a document must not duplicate its blood test")
    }

    // MARK: - Context trimming

    func testContextBuilderKeepsContiguousHistorySuffix() {
        let tiny1 = ChatMessage(content: "first", role: .user)
        let huge = ChatMessage(content: String(repeating: "x", count: 400_000), role: .assistant)
        let tiny2 = ChatMessage(content: "last", role: .user)

        let result = ConversationContextBuilder.buildContext(
            currentMessage: "question",
            healthContext: "",
            conversationHistory: [tiny1, huge, tiny2],
            systemPrompt: "",
            provider: .onDeviceLLM
        )

        let included = result.conversationHistory
        XCTAssertTrue(included.contains(where: { $0.id == tiny2.id }), "The newest message must always be kept")

        // Whatever is kept must be a contiguous suffix of the original history:
        // skipping a newer message while keeping older ones gives the model a
        // history with a hole in the middle.
        let inputIds = [tiny1.id, huge.id, tiny2.id]
        let includedIds = included.map(\.id)
        if let firstIncluded = includedIds.first, let start = inputIds.firstIndex(of: firstIncluded) {
            XCTAssertEqual(includedIds, Array(inputIds[start...]),
                           "Included history must be a contiguous suffix; got \(includedIds) within \(inputIds)")
        }
    }

    // MARK: - Response cleaner

    func testResponseCleanerPreservesMarkdownIndentation() {
        let input = "Intro line\n\n    indented code block line\n\n- list item"
        let cleaned = AIResponseCleaner.cleanConversational(input)
        XCTAssertTrue(cleaned.contains("\n    indented code block line"),
                      "Leading indentation is markdown structure and must survive cleaning. Got: \(cleaned)")
    }

    // MARK: - PDF export

    func testPDFExportContainsRealContent() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        var conversation = ChatConversation(title: "Lab Results Discussion")
        conversation.addMessage(ChatMessage(content: "What is my hemoglobin?", role: .user))
        conversation.addMessage(ChatMessage(content: "13.5 g/dL", role: .assistant))
        try await harness.databaseManager.saveConversation(conversation)

        let exporter = DocumentExporter(
            fileSystemManager: harness.fileSystemManager,
            databaseManager: harness.databaseManager
        )
        let url = try await exporter.exportHealthReportAsPDF()

        let data = try Data(contentsOf: url)
        let pdf = PDFDocument(data: data)
        XCTAssertNotNil(pdf, "Exported file must be a valid PDF")
        XCTAssertGreaterThanOrEqual(pdf?.pageCount ?? 0, 1, "Report must have at least one page (previously all pages were blank)")

        let text = (0..<(pdf?.pageCount ?? 0)).compactMap { pdf?.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Health Data Report"), "Title must be rendered. Got: \(text.prefix(200))")
        XCTAssertTrue(text.contains("Lab Results Discussion"),
                      "Chat conversation summary must be rendered (previously pages were empty)")
    }

    // MARK: - Import review queue

    func testPendingImportReviewQueueSemantics() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let processor = DocumentProcessor(
            databaseManager: harness.databaseManager,
            fileSystemManager: harness.fileSystemManager,
            healthDataManager: harness.healthDataManager,
            settingsManager: harness.settingsManager
        )

        func makeReview(docId: UUID) -> PendingImportReview {
            PendingImportReview(
                documentId: docId,
                documentName: "Doc \(docId.uuidString.prefix(4))",
                importGroups: [],
                bloodTestResult: BloodTestResult(
                    testDate: Date(),
                    results: [BloodTestItem(name: "Hemoglobin", value: "13.5")]
                )
            )
        }

        let docA = UUID(), docB = UUID()

        // First review presents immediately; a concurrent second review queues
        // instead of overwriting (which previously lost doc A's review).
        processor.enqueueImportReview(makeReview(docId: docA))
        XCTAssertEqual(processor.pendingImportReview?.documentId, docA)
        processor.enqueueImportReview(makeReview(docId: docB))
        XCTAssertEqual(processor.pendingImportReview?.documentId, docA,
                       "Second concurrent review must queue, not overwrite")

        // Completing A promotes B.
        processor.finishPendingImportReview()
        XCTAssertEqual(processor.pendingImportReview?.documentId, docB)

        // Discard only affects the matching document.
        processor.discardPendingImportReview(for: docA)
        XCTAssertEqual(processor.pendingImportReview?.documentId, docB)
        processor.discardPendingImportReview(for: docB)
        XCTAssertNil(processor.pendingImportReview)

        // With no queue behind it, finishing clears the slot.
        processor.enqueueImportReview(makeReview(docId: docA))
        processor.finishPendingImportReview()
        XCTAssertNil(processor.pendingImportReview)
    }

    // MARK: - Retry path

    func testRetryFailedMessageResolvesCurrentStateFromConversation() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        harness.scriptedProvider.reset(responses: [.success("13.5 g/dL — normal range")])

        // A user message that FAILED: the alert's retry closure captures the
        // original (pre-failure) struct, so the manager must re-resolve the
        // current state from the conversation before checking canRetry.
        let userMessage = ChatMessage(content: "What is my hemoglobin?", role: .user, isError: true, status: .failed)

        var conversation = ChatConversation(title: "Retry Test")
        conversation.addMessage(userMessage)
        try await harness.databaseManager.saveConversation(conversation)

        let chatManager = AIChatManager(
            healthDataManager: harness.healthDataManager,
            databaseManager: harness.databaseManager,
            settingsManager: harness.settingsManager,
            automaticallyLoadConversations: false
        )
        // Load explicitly — init's automatic load races in a detached Task.
        await chatManager.loadConversations()

        // The pre-failure snapshot (status nil, isError false) that the error
        // alert captures. Before the fix this made retry a silent no-op.
        let staleSnapshot = ChatMessage(id: userMessage.id, content: userMessage.content, role: .user)
        XCTAssertFalse(staleSnapshot.canRetry)

        await chatManager.retryFailedMessage(staleSnapshot, conversationId: conversation.id)

        let updated = chatManager.conversations.first(where: { $0.id == conversation.id })
        XCTAssertTrue(
            updated?.messages.contains(where: { $0.role == .assistant && !$0.content.isEmpty }) == true,
            "Retry must actually send using the conversation's current message state, not the stale snapshot"
        )
    }

    // MARK: - Review selection propagation (P0 fix)

    func testReviewSelectionPropagation() {
        let picked = BloodTestImportCandidate(testName: "Hemoglobin", value: "13.5", isAbnormal: true, originalTestName: "HGB")
        let other = BloodTestImportCandidate(testName: "Hemoglobin", value: "10.1", isAbnormal: true, originalTestName: "Hgb")
        let defaultPick = BloodTestImportCandidate(testName: "Glucose", value: "95", originalTestName: "GLU")
        let glucoseAlt = BloodTestImportCandidate(testName: "Glucose", value: "99", originalTestName: "GLUCOSE")

        // Abnormal group: no recommended default — the user MUST pick.
        let abnormalGroup = BloodTestImportGroup(
            standardTestName: "Hemoglobin",
            standardKey: "hemoglobin",
            candidates: [picked, other]
        )
        XCTAssertNil(abnormalGroup.selectedCandidateId)

        // Recommended group: the reconciler pre-selected a default the user can override.
        let recommendedGroup = BloodTestImportGroup(
            standardTestName: "Glucose",
            standardKey: "glucose",
            candidates: [defaultPick, glucoseAlt],
            selectedCandidateId: defaultPick.id
        )

        let ignoredGroup = BloodTestImportGroup(
            standardTestName: "WBC",
            standardKey: "wbc",
            candidates: [BloodTestImportCandidate(testName: "WBC", value: "6.0", originalTestName: "WBC")]
        )

        let resolved = BloodTestImportReviewView.resolvedGroups(
            importGroups: [abnormalGroup, recommendedGroup, ignoredGroup],
            demotedGroups: [],
            autoAcceptedGroups: [],
            selectedIds: [abnormalGroup.id: picked.id, recommendedGroup.id: glucoseAlt.id],
            ignoredGroupIds: [ignoredGroup.id]
        )

        // The user's explicit pick must land (historically discarded via a no-op Binding).
        XCTAssertEqual(resolved.first(where: { $0.id == abnormalGroup.id })?.selectedCandidateId, picked.id)
        // The user's override of a recommended default must win.
        XCTAssertEqual(resolved.first(where: { $0.id == recommendedGroup.id })?.selectedCandidateId, glucoseAlt.id)
        // "Don't import" must clear the selection.
        XCTAssertNil(resolved.first(where: { $0.id == ignoredGroup.id })?.selectedCandidateId)
        // Ordering preserved: reviewed groups stay in presentation order.
        XCTAssertEqual(resolved.map(\.id), [abnormalGroup.id, recommendedGroup.id, ignoredGroup.id])
    }
}
