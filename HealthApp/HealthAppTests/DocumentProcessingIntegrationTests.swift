import XCTest
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
}
