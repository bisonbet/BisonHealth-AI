import XCTest
import UIKit
@testable import HealthApp

@MainActor
final class DocumentProcessingIntegrationTests: XCTestCase {

    func testProcessingQueueItemSortsByPriority() {
        let low = ProcessingQueueItem(
            document: makeDocument(named: "low.pdf"),
            priority: .low,
            addedAt: Date()
        )
        let urgent = ProcessingQueueItem(
            document: makeDocument(named: "urgent.pdf"),
            priority: .urgent,
            addedAt: Date()
        )
        let normal = ProcessingQueueItem(
            document: makeDocument(named: "normal.pdf"),
            priority: .normal,
            addedAt: Date()
        )

        let sorted: [ProcessingQueueItem] = [low, urgent, normal]
            .sorted { $0.priority.rawValue > $1.priority.rawValue }

        XCTAssertEqual(sorted.map { $0.priority }, [.urgent, .normal, .low])
    }

    func testMedicalDocumentCategoryMetadataForLabReports() {
        let document = makeDocument(named: "lab.pdf", category: .labReport)

        XCTAssertEqual(document.documentCategory, .labReport)
        XCTAssertEqual(document.documentCategory.displayName, "Lab Report")
        XCTAssertTrue(document.documentCategory.expectedSections.contains("Test Results"))
    }

    func testDocumentSectionRoundTripsThroughJSON() throws {
        let section = DocumentSection(
            sectionType: "Impression",
            content: "No acute findings.",
            confidence: 0.98,
            metadata: ["source": "test"]
        )

        let encoded = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(DocumentSection.self, from: encoded)

        XCTAssertEqual(decoded.id, section.id)
        XCTAssertEqual(decoded.sectionType, "Impression")
        XCTAssertEqual(decoded.content, "No acute findings.")
        XCTAssertEqual(decoded.confidence, 0.98)
        XCTAssertEqual(decoded.metadata["source"], "test")
    }

    func testMedicalDocumentCapturesCurrentDocumentState() {
        let document = makeDocument(named: "blood-lab.pdf", category: .labReport)

        XCTAssertEqual(document.fileName, "blood-lab.pdf")
        XCTAssertEqual(document.fileType, .pdf)
        XCTAssertEqual(document.processingStatus, .pending)
        XCTAssertEqual(document.documentCategory, .labReport)
    }

    func testFakeLabPDFImportAndExtractionProducesBloodTestOrReview() async throws {
        let harness = try makeRegressionHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let sourceURL = harness.rootURL.appendingPathComponent("fake-lab-report.pdf")
        let pdfData = makeLabReportPDFData()
        try pdfData.write(to: sourceURL)

        let importer = DocumentImporter(
            fileSystemManager: harness.fileSystemManager,
            databaseManager: harness.databaseManager
        )
        var document = try await importer.importDocument(from: sourceURL)
        document.documentCategory = .labReport
        document.includeInAIContext = true
        try await harness.databaseManager.saveDocument(document)

        let processor = DocumentProcessor(
            databaseManager: harness.databaseManager,
            fileSystemManager: harness.fileSystemManager,
            healthDataManager: harness.healthDataManager,
            settingsManager: harness.settingsManager
        )
        let result = try await processor.processDocumentAndExtractHealthDataForTesting(document)

        XCTAssertTrue(result.processed.extractedText.localizedCaseInsensitiveContains("Glucose"))
        XCTAssertGreaterThan(result.processed.confidence, 0)

        let bloodTests = result.extractedData.compactMap { try? $0.decode(as: BloodTestResult.self) }
        let bloodTest = try XCTUnwrap(bloodTests.first)
        let acceptedNames = Set(bloodTest.results.map(\.name))
        let reviewGroups = (processor.pendingImportReview?.importGroups ?? [])
            + (processor.pendingImportReview?.autoAcceptedGroups ?? [])
        let surfacedNames = acceptedNames.union(reviewGroups.map(\.standardTestName))
        XCTAssertTrue(
            surfacedNames.contains("Glucose"),
            "Expected Glucose in accepted results or review groups, got \(surfacedNames)"
        )
        XCTAssertTrue(
            surfacedNames.contains { $0.localizedCaseInsensitiveContains("Cholesterol") },
            "Expected a Cholesterol result in accepted results or review groups, got \(surfacedNames)"
        )

        if bloodTest.metadata?["pending_review"] == "true" {
            XCTAssertNotNil(processor.pendingImportReview)
            XCTAssertFalse(processor.pendingImportReview?.importGroups.isEmpty ?? true)
        } else {
            try await harness.healthDataManager.linkExtractedDataToDocument(document.id, extractedData: result.extractedData)
            let savedBloodTests = try await harness.databaseManager.fetchBloodTestResults()
            XCTAssertTrue(savedBloodTests.contains { $0.results.contains { $0.name == "Glucose" } })
        }
    }

    private func makeDocument(
        named fileName: String,
        category: DocumentCategory = .other
    ) -> MedicalDocument {
        MedicalDocument(
            fileName: fileName,
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/\(fileName)"),
            documentCategory: category
        )
    }

    private struct RegressionHarness {
        let rootURL: URL
        let databaseManager: DatabaseManager
        let fileSystemManager: FileSystemManager
        let healthDataManager: HealthDataManager
        let settingsManager: SettingsManager
    }

    private func makeRegressionHarness() throws -> RegressionHarness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BisonHealthDocumentRegression-\(UUID().uuidString)", isDirectory: true)
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
            settingsManager: settingsManager
        )
    }

    private func makeLabReportPDFData() -> Data {
        let text = """
        Bison Diagnostics
        Collection Date: 2026-01-15
        Patient: Test Patient
        Ordering Physician: Dr. Ada Test

        CHEMISTRY
        Glucose\t98\tmg/dL\t70-100
        BUN\t15\tmg/dL\t7-20
        Creatinine\t0.9\tmg/dL\t0.6-1.2
        Total Cholesterol\t220\tmg/dL\t<200\tH

        CBC
        Hemoglobin\t13.5\tg/dL\t12.0-16.0
        WBC\t6.1\tK/uL\t4.0-11.0
        """

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            text.draw(
                in: pageRect.insetBy(dx: 48, dy: 48),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
            )
        }
    }
}
