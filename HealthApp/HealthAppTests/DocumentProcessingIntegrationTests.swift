import XCTest
import VisionKit
@testable import HealthApp

// MARK: - Document Processing Integration Tests
@MainActor
final class DocumentProcessingIntegrationTests: XCTestCase {
    
    var databaseManager: DatabaseManager!
    var fileSystemManager: FileSystemManager!
    var doclingClient: DoclingClient!
    var healthDataManager: HealthDataManager!
    var documentImporter: DocumentImporter!
    var documentProcessor: DocumentProcessor!
    var documentManager: DocumentManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Set up test dependencies
        databaseManager = try DatabaseManager(inMemory: true)
        fileSystemManager = try FileSystemManager()
        doclingClient = DoclingClient(hostname: "localhost", port: 5001)
        healthDataManager = HealthDataManager(
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager
        )
        documentImporter = DocumentImporter(
            fileSystemManager: fileSystemManager,
            databaseManager: databaseManager
        )
        documentProcessor = DocumentProcessor(
            doclingClient: doclingClient,
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager,
            healthDataManager: healthDataManager
        )
        documentManager = DocumentManager(
            documentImporter: documentImporter,
            documentProcessor: documentProcessor,
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager
        )
    }
    
    override func tearDown() async throws {
        // Clean up test data
        try await databaseManager.clearAllData()
        try await super.tearDown()
    }
    
    // MARK: - Document Import Tests
    func testDocumentImportFromURL() async throws {
        // Create a test PDF file
        let testPDFData = createTestPDFData()
        let testURL = try createTemporaryFile(data: testPDFData, extension: "pdf")
        
        // Import document
        await documentManager.importDocument(from: testURL)
        
        // Verify document was imported
        XCTAssertEqual(documentManager.documents.count, 1)
        
        let importedDocument = documentManager.documents.first!
        XCTAssertEqual(importedDocument.fileType, .pdf)
        XCTAssertEqual(importedDocument.processingStatus, .queued)
        XCTAssertTrue(fileSystemManager.fileExists(at: importedDocument.filePath))
    }
    
    func testBatchDocumentImport() async throws {
        // Create multiple test files
        let testFiles = [
            (createTestPDFData(), "pdf"),
            (createTestImageData(), "jpg"),
            (createTestTextData(), "txt")
        ]
        
        var testURLs: [URL] = []
        for (data, ext) in testFiles {
            let url = try createTemporaryFile(data: data, extension: ext)
            testURLs.append(url)
        }
        
        // Import documents
        await documentManager.importDocuments(from: testURLs)
        
        // Verify documents were imported
        XCTAssertEqual(documentManager.documents.count, 3)
        
        // Verify all documents are queued for processing
        let queuedDocuments = documentManager.documents.filter { $0.processingStatus == .queued }
        XCTAssertEqual(queuedDocuments.count, 3)
    }
    
    func testScannedDocumentImport() async throws {
        // Create a mock scanned document
        let mockScan = createMockDocumentScan()
        
        // Import scanned document
        await documentManager.importScannedDocument(mockScan)
        
        // Verify document was imported
        XCTAssertEqual(documentManager.documents.count, 1)
        
        let importedDocument = documentManager.documents.first!
        XCTAssertEqual(importedDocument.fileType, .pdf)
        XCTAssertTrue(importedDocument.tags.contains("scanned"))
        XCTAssertEqual(importedDocument.processingStatus, .queued)
    }
    
    // MARK: - Document Processing Tests
    func testDocumentProcessingQueue() async throws {
        // Create test documents with different priorities
        let testDocuments = try await createTestDocuments(count: 5)
        
        // Add documents to queue with different priorities
        await documentProcessor.addToQueue(testDocuments[0], priority: .low)
        await documentProcessor.addToQueue(testDocuments[1], priority: .high)
        await documentProcessor.addToQueue(testDocuments[2], priority: .normal)
        await documentProcessor.addToQueue(testDocuments[3], priority: .urgent)
        await documentProcessor.addToQueue(testDocuments[4], priority: .normal)
        
        // Verify queue ordering (urgent -> high -> normal -> low)
        let queueItems = documentProcessor.processingQueue
        XCTAssertEqual(queueItems.count, 5)
        XCTAssertEqual(queueItems[0].priority, .urgent)
        XCTAssertEqual(queueItems[1].priority, .high)
        XCTAssertTrue(queueItems[2].priority == .normal || queueItems[3].priority == .normal)
        XCTAssertEqual(queueItems[4].priority, .low)
    }
    
    func testImmediateDocumentProcessing() async throws {
        // Mock successful Docling response
        mockDoclingSuccess()
        
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        
        // Process document immediately
        let result = try await documentProcessor.processDocumentImmediately(testDocument)
        
        // Verify processing result
        XCTAssertFalse(result.extractedText.isEmpty)
        XCTAssertFalse(result.structuredData.isEmpty)
        XCTAssertGreaterThan(result.confidence, 0.0)
        XCTAssertGreaterThan(result.processingTime, 0.0)
    }
    
    func testDocumentProcessingWithRetry() async throws {
        // Mock Docling failure followed by success
        mockDoclingFailureThenSuccess()
        
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        
        // Add to queue and start processing
        await documentProcessor.addToQueue(testDocument)
        await documentProcessor.startProcessing()
        
        // Wait for processing to complete
        await waitForProcessingCompletion()
        
        // Verify document was eventually processed successfully
        let updatedDocument = try await databaseManager.fetchDocument(id: testDocument.id)
        XCTAssertEqual(updatedDocument?.processingStatus, .completed)
    }
    
    // MARK: - Health Data Extraction Tests
    func testHealthDataExtractionFromProcessedDocument() async throws {
        // Mock Docling response with health data
        mockDoclingWithHealthData()
        
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        
        // Process document
        let result = try await documentProcessor.processDocumentImmediately(testDocument)
        
        // Verify health data extraction
        XCTAssertFalse(result.healthDataItems.isEmpty)
        
        let healthDataItems = result.healthDataItems
        XCTAssertTrue(healthDataItems.contains { $0.type == "Blood Pressure" })
        XCTAssertTrue(healthDataItems.contains { $0.type == "Heart Rate" })
    }
    
    func testPersonalInfoExtractionAndMerging() async throws {
        // Set up existing personal info
        let existingPersonalInfo = PersonalHealthInfo(
            name: "John Doe",
            dateOfBirth: Date(),
            gender: .male
        )
        try await healthDataManager.savePersonalInfo(existingPersonalInfo)
        
        // Mock Docling response with additional personal info
        mockDoclingWithPersonalInfo()
        
        // Create and process test document
        let testDocument = try await createTestDocument(type: .pdf)
        await documentProcessor.addToQueue(testDocument)
        await documentProcessor.startProcessing()
        
        // Wait for processing to complete
        await waitForProcessingCompletion()
        
        // Verify personal info was merged
        await healthDataManager.loadHealthData()
        let updatedPersonalInfo = healthDataManager.personalInfo
        
        XCTAssertNotNil(updatedPersonalInfo)
        XCTAssertEqual(updatedPersonalInfo?.name, "John Doe") // Existing name preserved
        XCTAssertNotNil(updatedPersonalInfo?.height) // New height added
        XCTAssertNotNil(updatedPersonalInfo?.weight) // New weight added
    }
    
    func testBloodTestExtractionAndStorage() async throws {
        // Mock Docling response with blood test data
        mockDoclingWithBloodTestData()
        
        // Create and process test document
        let testDocument = try await createTestDocument(type: .pdf)
        await documentProcessor.addToQueue(testDocument)
        await documentProcessor.startProcessing()
        
        // Wait for processing to complete
        await waitForProcessingCompletion()
        
        // Verify blood test was extracted and stored
        await healthDataManager.loadHealthData()
        XCTAssertEqual(healthDataManager.bloodTests.count, 1)
        
        let bloodTest = healthDataManager.bloodTests.first!
        XCTAssertFalse(bloodTest.results.isEmpty)
        XCTAssertTrue(bloodTest.results.contains { $0.name == "Glucose" })
        XCTAssertTrue(bloodTest.results.contains { $0.name == "Cholesterol" })
    }
    
    // MARK: - Document Management Tests
    func testDocumentSearchAndFiltering() async throws {
        // Create test documents with different properties
        let documents = try await createTestDocumentsWithVariedProperties()
        
        for document in documents {
            await documentManager.documents.append(document)
        }
        
        // Test search functionality
        await documentManager.searchDocuments("blood")
        let searchResults = documentManager.filteredDocuments
        XCTAssertTrue(searchResults.allSatisfy { 
            $0.fileName.localizedCaseInsensitiveContains("blood") ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains("blood") }
        })
        
        // Test status filtering
        documentManager.setStatusFilter(.completed)
        let statusFiltered = documentManager.filteredDocuments
        XCTAssertTrue(statusFiltered.allSatisfy { $0.processingStatus == .completed })
        
        // Test type filtering
        documentManager.setTypeFilter(.pdf)
        let typeFiltered = documentManager.filteredDocuments
        XCTAssertTrue(typeFiltered.allSatisfy { $0.fileType == .pdf })
    }
    
    func testDocumentTagManagement() async throws {
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        await documentManager.documents.append(testDocument)
        
        // Add tags
        await documentManager.addTagToDocument(testDocument.id, tag: "important")
        await documentManager.addTagToDocument(testDocument.id, tag: "lab-result")
        
        // Verify tags were added
        let updatedDocument = documentManager.documents.first { $0.id == testDocument.id }
        XCTAssertTrue(updatedDocument?.tags.contains("important") == true)
        XCTAssertTrue(updatedDocument?.tags.contains("lab-result") == true)
        
        // Remove tag
        await documentManager.removeTagFromDocument(testDocument.id, tag: "important")
        
        // Verify tag was removed
        let finalDocument = documentManager.documents.first { $0.id == testDocument.id }
        XCTAssertFalse(finalDocument?.tags.contains("important") == true)
        XCTAssertTrue(finalDocument?.tags.contains("lab-result") == true)
    }
    
    func testDocumentDeletion() async throws {
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        await documentManager.documents.append(testDocument)
        
        let initialCount = documentManager.documents.count
        
        // Delete document
        await documentManager.deleteDocument(testDocument)
        
        // Verify document was deleted
        XCTAssertEqual(documentManager.documents.count, initialCount - 1)
        XCTAssertFalse(documentManager.documents.contains { $0.id == testDocument.id })
        XCTAssertFalse(fileSystemManager.fileExists(at: testDocument.filePath))
    }
    
    // MARK: - Error Handling Tests
    func testDocumentProcessingFailureHandling() async throws {
        // Mock Docling failure
        mockDoclingFailure()
        
        // Create test document
        let testDocument = try await createTestDocument(type: .pdf)
        
        // Attempt to process document
        do {
            _ = try await documentProcessor.processDocumentImmediately(testDocument)
            XCTFail("Expected processing to fail")
        } catch {
            // Verify error is handled appropriately
            XCTAssertTrue(error is DoclingError)
        }
    }
    
    func testInvalidDocumentTypeHandling() async throws {
        // Create invalid document type
        let invalidData = Data("invalid content".utf8)
        let testURL = try createTemporaryFile(data: invalidData, extension: "xyz")
        
        // Attempt to import
        await documentManager.importDocument(from: testURL)
        
        // Verify error handling
        XCTAssertNotNil(documentManager.lastError)
    }
    
    // MARK: - Performance Tests
    func testLargeDocumentProcessing() async throws {
        // Create large test document (simulate 10MB PDF)
        let largeData = Data(repeating: 0, count: 10 * 1024 * 1024)
        let testURL = try createTemporaryFile(data: largeData, extension: "pdf")
        
        let startTime = Date()
        
        // Import and process large document
        await documentManager.importDocument(from: testURL)
        
        let importTime = Date().timeIntervalSince(startTime)
        
        // Verify performance is acceptable (should complete within 30 seconds)
        XCTAssertLessThan(importTime, 30.0)
    }
    
    func testConcurrentDocumentProcessing() async throws {
        // Create multiple test documents
        let testDocuments = try await createTestDocuments(count: 10)
        
        let startTime = Date()
        
        // Process documents concurrently
        await documentProcessor.processBatch(testDocuments)
        await documentProcessor.startProcessing()
        await waitForProcessingCompletion()
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Verify concurrent processing is faster than sequential
        // (This is a simplified test - in practice you'd compare with sequential processing)
        XCTAssertLessThan(processingTime, 60.0)
    }
    
    // MARK: - Helper Methods
    private func createTestPDFData() -> Data {
        // Create a simple PDF data for testing
        let pdfContent = """
        %PDF-1.4
        1 0 obj
        <<
        /Type /Catalog
        /Pages 2 0 R
        >>
        endobj
        2 0 obj
        <<
        /Type /Pages
        /Kids [3 0 R]
        /Count 1
        >>
        endobj
        3 0 obj
        <<
        /Type /Page
        /Parent 2 0 R
        /MediaBox [0 0 612 792]
        >>
        endobj
        xref
        0 4
        0000000000 65535 f 
        0000000009 00000 n 
        0000000074 00000 n 
        0000000120 00000 n 
        trailer
        <<
        /Size 4
        /Root 1 0 R
        >>
        startxref
        179
        %%EOF
        """
        return Data(pdfContent.utf8)
    }
    
    private func createTestImageData() -> Data {
        // Create a simple 1x1 pixel JPEG
        let image = UIImage(systemName: "heart.fill")!
        return image.jpegData(compressionQuality: 1.0)!
    }
    
    private func createTestTextData() -> Data {
        return Data("Test document content".utf8)
    }
    
    private func createTemporaryFile(data: Data, extension ext: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + "." + ext
        let fileURL = tempDir.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func createMockDocumentScan() -> VNDocumentCameraScan {
        // This would need to be implemented with a proper mock
        // For now, we'll use a placeholder that would need to be replaced with actual mock implementation
        fatalError("Mock implementation needed")
    }
    
    private func createTestDocument(type: DocumentType) async throws -> MedicalDocument {
        let testData: Data
        switch type {
        case .pdf:
            testData = createTestPDFData()
        case .jpeg, .jpg:
            testData = createTestImageData()
        default:
            testData = createTestTextData()
        }
        
        let testURL = try createTemporaryFile(data: testData, extension: type.rawValue)
        return try await documentImporter.importDocument(from: testURL)
    }
    
    private func createTestDocuments(count: Int) async throws -> [MedicalDocument] {
        var documents: [MedicalDocument] = []
        
        for i in 0..<count {
            let type: DocumentType = i % 2 == 0 ? .pdf : .jpeg
            let document = try await createTestDocument(type: type)
            documents.append(document)
        }
        
        return documents
    }
    
    private func createTestDocumentsWithVariedProperties() async throws -> [MedicalDocument] {
        var documents: [MedicalDocument] = []
        
        // Create documents with different names, types, and statuses
        let properties = [
            ("blood_test_results.pdf", DocumentType.pdf, ProcessingStatus.completed),
            ("xray_report.jpg", DocumentType.jpeg, ProcessingStatus.pending),
            ("prescription.pdf", DocumentType.pdf, ProcessingStatus.failed),
            ("lab_results.png", DocumentType.png, ProcessingStatus.completed)
        ]
        
        for (name, type, status) in properties {
            var document = try await createTestDocument(type: type)
            document.fileName = name
            document.processingStatus = status
            
            // Add relevant tags
            if name.contains("blood") {
                document.addTag("blood")
                document.addTag("lab")
            }
            if name.contains("xray") {
                document.addTag("imaging")
                document.addTag("radiology")
            }
            
            documents.append(document)
        }
        
        return documents
    }
    
    private func waitForProcessingCompletion() async {
        // Wait for processing to complete (with timeout)
        let timeout = Date().addingTimeInterval(30) // 30 second timeout
        
        while documentProcessor.isProcessing && Date() < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }
    
    // MARK: - Mock Methods
    private func mockDoclingSuccess() {
        // Mock successful Docling response
        // This would need to be implemented with proper mocking framework
    }
    
    private func mockDoclingFailure() {
        // Mock Docling failure
        // This would need to be implemented with proper mocking framework
    }
    
    private func mockDoclingFailureThenSuccess() {
        // Mock Docling failure followed by success on retry
        // This would need to be implemented with proper mocking framework
    }
    
    private func mockDoclingWithHealthData() {
        // Mock Docling response containing health data
        // This would need to be implemented with proper mocking framework
    }
    
    private func mockDoclingWithPersonalInfo() {
        // Mock Docling response containing personal information
        // This would need to be implemented with proper mocking framework
    }
    
    private func mockDoclingWithBloodTestData() {
        // Mock Docling response containing blood test data
        // This would need to be implemented with proper mocking framework
    }
}

// MARK: - Test Extensions
extension DatabaseManager {
    convenience init(inMemory: Bool) throws {
        // This would need to be implemented to support in-memory database for testing
        try self.init()
    }
    
    func clearAllData() async throws {
        // This would need to be implemented to clear all test data
    }
}