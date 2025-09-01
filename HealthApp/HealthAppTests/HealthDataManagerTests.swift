import XCTest
@testable import HealthApp

@MainActor
final class HealthDataManagerTests: XCTestCase {
    
    var healthDataManager: HealthDataManager!
    var mockDatabaseManager: MockDatabaseManager!
    var mockFileSystemManager: MockFileSystemManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockDatabaseManager = MockDatabaseManager()
        mockFileSystemManager = MockFileSystemManager()
        healthDataManager = HealthDataManager(
            databaseManager: mockDatabaseManager,
            fileSystemManager: mockFileSystemManager
        )
        
        // Wait for initial load to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    override func tearDown() async throws {
        healthDataManager = nil
        mockDatabaseManager = nil
        mockFileSystemManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Personal Info Tests
    func testSavePersonalInfo() async throws {
        // Given
        let personalInfo = PersonalHealthInfo(
            name: "John Doe",
            dateOfBirth: Date(timeIntervalSince1970: 0),
            gender: .male
        )
        
        // When
        try await healthDataManager.savePersonalInfo(personalInfo)
        
        // Then
        XCTAssertEqual(healthDataManager.personalInfo?.name, "John Doe")
        XCTAssertEqual(healthDataManager.personalInfo?.gender, .male)
        XCTAssertTrue(mockDatabaseManager.saveHealthDataCalled)
    }
    
    func testSaveInvalidPersonalInfo() async throws {
        // Given
        let invalidPersonalInfo = PersonalHealthInfo(name: "") // Empty name
        
        // When/Then
        do {
            try await healthDataManager.savePersonalInfo(invalidPersonalInfo)
            XCTFail("Should have thrown validation error")
        } catch HealthDataError.validationFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testUpdatePersonalInfo() async throws {
        // Given
        let initialInfo = PersonalHealthInfo(name: "John Doe")
        try await healthDataManager.savePersonalInfo(initialInfo)
        
        // When
        try await healthDataManager.updatePersonalInfo { info in
            info.gender = .male
            info.bloodType = .oPositive
        }
        
        // Then
        XCTAssertEqual(healthDataManager.personalInfo?.name, "John Doe")
        XCTAssertEqual(healthDataManager.personalInfo?.gender, .male)
        XCTAssertEqual(healthDataManager.personalInfo?.bloodType, .oPositive)
    }
    
    // MARK: - Blood Test Tests
    func testAddBloodTest() async throws {
        // Given
        let bloodTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Test Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL")
            ]
        )
        
        // When
        try await healthDataManager.addBloodTest(bloodTest)
        
        // Then
        XCTAssertEqual(healthDataManager.bloodTests.count, 1)
        XCTAssertEqual(healthDataManager.bloodTests.first?.laboratoryName, "Test Lab")
        XCTAssertTrue(mockDatabaseManager.saveHealthDataCalled)
    }
    
    func testAddInvalidBloodTest() async throws {
        // Given
        let invalidBloodTest = BloodTestResult(
            testDate: Date(),
            results: [] // No results
        )
        
        // When/Then
        do {
            try await healthDataManager.addBloodTest(invalidBloodTest)
            XCTFail("Should have thrown validation error")
        } catch HealthDataError.validationFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testUpdateBloodTest() async throws {
        // Given
        let bloodTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Test Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL")
            ]
        )
        try await healthDataManager.addBloodTest(bloodTest)
        
        // When
        var updatedBloodTest = bloodTest
        updatedBloodTest.laboratoryName = "Updated Lab"
        try await healthDataManager.updateBloodTest(updatedBloodTest)
        
        // Then
        XCTAssertEqual(healthDataManager.bloodTests.first?.laboratoryName, "Updated Lab")
        XCTAssertTrue(mockDatabaseManager.updateHealthDataCalled)
    }
    
    func testDeleteBloodTest() async throws {
        // Given
        let bloodTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Test Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL")
            ]
        )
        try await healthDataManager.addBloodTest(bloodTest)
        XCTAssertEqual(healthDataManager.bloodTests.count, 1)
        
        // When
        try await healthDataManager.deleteBloodTest(bloodTest)
        
        // Then
        XCTAssertEqual(healthDataManager.bloodTests.count, 0)
        XCTAssertTrue(mockDatabaseManager.deleteHealthDataCalled)
    }
    
    // MARK: - Document Tests
    func testImportDocumentFromURL() async throws {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test.pdf")
        mockFileSystemManager.mockFileSize = 1024
        mockFileSystemManager.mockThumbnailURL = URL(fileURLWithPath: "/tmp/thumb.jpg")
        
        // When
        let document = try await healthDataManager.importDocument(from: testURL)
        
        // Then
        XCTAssertEqual(document.fileName, "test.pdf")
        XCTAssertEqual(document.fileType, .pdf)
        XCTAssertEqual(document.fileSize, 1024)
        XCTAssertEqual(healthDataManager.documents.count, 1)
        XCTAssertTrue(mockFileSystemManager.copyFileCalled)
        XCTAssertTrue(mockFileSystemManager.generateThumbnailCalled)
        XCTAssertTrue(mockDatabaseManager.saveDocumentCalled)
    }
    
    func testImportFromCamera() async throws {
        // Given
        let testImage = UIImage(systemName: "heart.fill")!
        mockFileSystemManager.mockThumbnailURL = URL(fileURLWithPath: "/tmp/thumb.jpg")
        
        // When
        let document = try await healthDataManager.importFromCamera(testImage)
        
        // Then
        XCTAssertTrue(document.fileName.contains("Scanned_Document"))
        XCTAssertEqual(document.fileType, .jpeg)
        XCTAssertEqual(healthDataManager.documents.count, 1)
        XCTAssertTrue(mockFileSystemManager.storeDocumentCalled)
        XCTAssertTrue(mockFileSystemManager.generateThumbnailCalled)
        XCTAssertTrue(mockDatabaseManager.saveDocumentCalled)
    }
    
    func testUpdateDocumentProcessingStatus() async throws {
        // Given
        let document = HealthDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        healthDataManager.documents = [document]
        
        // When
        try await healthDataManager.updateDocumentProcessingStatus(document.id, status: .completed)
        
        // Then
        XCTAssertEqual(healthDataManager.documents.first?.processingStatus, .completed)
        XCTAssertNotNil(healthDataManager.documents.first?.processedAt)
        XCTAssertTrue(mockDatabaseManager.updateDocumentStatusCalled)
    }
    
    func testDeleteDocument() async throws {
        // Given
        let document = HealthDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        healthDataManager.documents = [document]
        
        // When
        try await healthDataManager.deleteDocument(document)
        
        // Then
        XCTAssertEqual(healthDataManager.documents.count, 0)
        XCTAssertTrue(mockDatabaseManager.deleteDocumentCalled)
        XCTAssertTrue(mockFileSystemManager.deleteDocumentCalled)
    }
    
    // MARK: - Data Export Tests
    func testExportHealthDataAsJSON() async throws {
        // Given
        let personalInfo = PersonalHealthInfo(name: "John Doe")
        try await healthDataManager.savePersonalInfo(personalInfo)
        
        let bloodTest = BloodTestResult(
            testDate: Date(),
            results: [BloodTestItem(name: "Glucose", value: "95")]
        )
        try await healthDataManager.addBloodTest(bloodTest)
        
        mockFileSystemManager.mockExportURL = URL(fileURLWithPath: "/tmp/export.json")
        
        // When
        let exportURL = try await healthDataManager.exportHealthDataAsJSON()
        
        // Then
        XCTAssertEqual(exportURL.pathExtension, "json")
        XCTAssertTrue(mockFileSystemManager.createExportFileCalled)
    }
    
    func testExportHealthDataAsPDF() async throws {
        // Given
        let personalInfo = PersonalHealthInfo(name: "John Doe")
        try await healthDataManager.savePersonalInfo(personalInfo)
        
        mockFileSystemManager.mockExportURL = URL(fileURLWithPath: "/tmp/export.pdf")
        
        // When
        let exportURL = try await healthDataManager.exportHealthDataAsPDF()
        
        // Then
        XCTAssertEqual(exportURL.pathExtension, "pdf")
        XCTAssertTrue(mockFileSystemManager.createExportFileCalled)
    }
    
    // MARK: - Validation Tests
    func testValidatePersonalInfo() async throws {
        // Given
        let validInfo = PersonalHealthInfo(name: "John Doe")
        let invalidInfo = PersonalHealthInfo(name: "")
        
        // When
        let validResult = healthDataManager.validateHealthData(validInfo)
        let invalidResult = healthDataManager.validateHealthData(invalidInfo)
        
        // Then
        XCTAssertTrue(validResult.isValid)
        XCTAssertTrue(validResult.errors.isEmpty)
        
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertFalse(invalidResult.errors.isEmpty)
        XCTAssertTrue(invalidResult.errors.contains("Name is required"))
    }
    
    func testValidateBloodTest() async throws {
        // Given
        let validBloodTest = BloodTestResult(
            testDate: Date(),
            results: [BloodTestItem(name: "Glucose", value: "95")]
        )
        let invalidBloodTest = BloodTestResult(
            testDate: Date(),
            results: []
        )
        
        // When
        let validResult = healthDataManager.validateHealthData(validBloodTest)
        let invalidResult = healthDataManager.validateHealthData(invalidBloodTest)
        
        // Then
        XCTAssertTrue(validResult.isValid)
        XCTAssertTrue(validResult.errors.isEmpty)
        
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertFalse(invalidResult.errors.isEmpty)
        XCTAssertTrue(invalidResult.errors.contains("At least one test result is required"))
    }
    
    // MARK: - Data Linking Tests
    func testLinkExtractedDataToDocument() async throws {
        // Given
        let document = HealthDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        healthDataManager.documents = [document]
        
        let extractedPersonalInfo = PersonalHealthInfo(name: "Jane Doe")
        let extractedData = [try AnyHealthData(extractedPersonalInfo)]
        
        // When
        try await healthDataManager.linkExtractedDataToDocument(document.id, extractedData: extractedData)
        
        // Then
        XCTAssertEqual(healthDataManager.documents.first?.processingStatus, .completed)
        XCTAssertNotNil(healthDataManager.documents.first?.processedAt)
        XCTAssertEqual(healthDataManager.documents.first?.extractedData.count, 1)
        XCTAssertEqual(healthDataManager.personalInfo?.name, "Jane Doe")
    }
    
    func testMergePersonalInfo() async throws {
        // Given
        let existingInfo = PersonalHealthInfo(
            name: "John Doe",
            gender: .male
        )
        try await healthDataManager.savePersonalInfo(existingInfo)
        
        let extractedInfo = PersonalHealthInfo(
            name: nil, // Should not override existing
            bloodType: .oPositive, // Should be added
            allergies: ["Peanuts"] // Should be added
        )
        
        let document = HealthDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        healthDataManager.documents = [document]
        
        let extractedData = [try AnyHealthData(extractedInfo)]
        
        // When
        try await healthDataManager.linkExtractedDataToDocument(document.id, extractedData: extractedData)
        
        // Then
        XCTAssertEqual(healthDataManager.personalInfo?.name, "John Doe") // Preserved
        XCTAssertEqual(healthDataManager.personalInfo?.gender, .male) // Preserved
        XCTAssertEqual(healthDataManager.personalInfo?.bloodType, .oPositive) // Added
        XCTAssertTrue(healthDataManager.personalInfo?.allergies.contains("Peanuts") ?? false) // Added
    }
}

// MARK: - Mock Database Manager
class MockDatabaseManager: DatabaseManager {
    var saveHealthDataCalled = false
    var updateHealthDataCalled = false
    var deleteHealthDataCalled = false
    var saveDocumentCalled = false
    var updateDocumentStatusCalled = false
    var deleteDocumentCalled = false
    
    var mockPersonalInfo: PersonalHealthInfo?
    var mockBloodTests: [BloodTestResult] = []
    var mockDocuments: [HealthDocument] = []
    
    override init() throws {
        // Skip the real initialization
        try super.init()
    }
    
    override func save<T: HealthDataProtocol>(_ data: T) async throws {
        saveHealthDataCalled = true
        
        if let personalInfo = data as? PersonalHealthInfo {
            mockPersonalInfo = personalInfo
        } else if let bloodTest = data as? BloodTestResult {
            mockBloodTests.append(bloodTest)
        }
    }
    
    override func update<T: HealthDataProtocol>(_ data: T) async throws {
        updateHealthDataCalled = true
        
        if let personalInfo = data as? PersonalHealthInfo {
            mockPersonalInfo = personalInfo
        } else if let bloodTest = data as? BloodTestResult {
            if let index = mockBloodTests.firstIndex(where: { $0.id == bloodTest.id }) {
                mockBloodTests[index] = bloodTest
            }
        }
    }
    
    override func delete<T: HealthDataProtocol>(_ data: T) async throws {
        deleteHealthDataCalled = true
        
        if data is PersonalHealthInfo {
            mockPersonalInfo = nil
        } else if let bloodTest = data as? BloodTestResult {
            mockBloodTests.removeAll { $0.id == bloodTest.id }
        }
    }
    
    override func fetchPersonalHealthInfo() async throws -> PersonalHealthInfo? {
        return mockPersonalInfo
    }
    
    override func fetchBloodTestResults() async throws -> [BloodTestResult] {
        return mockBloodTests
    }
    
    override func fetchDocuments() async throws -> [HealthDocument] {
        return mockDocuments
    }
    
    override func saveDocument(_ document: HealthDocument) async throws {
        saveDocumentCalled = true
        mockDocuments.append(document)
    }
    
    override func updateDocumentStatus(_ documentId: UUID, status: ProcessingStatus) async throws {
        updateDocumentStatusCalled = true
        if let index = mockDocuments.firstIndex(where: { $0.id == documentId }) {
            mockDocuments[index].processingStatus = status
        }
    }
    
    override func deleteDocument(_ documentId: UUID) async throws {
        deleteDocumentCalled = true
        mockDocuments.removeAll { $0.id == documentId }
    }
}

// MARK: - Mock File System Manager
class MockFileSystemManager: FileSystemManager {
    var copyFileCalled = false
    var storeDocumentCalled = false
    var deleteDocumentCalled = false
    var generateThumbnailCalled = false
    var createExportFileCalled = false
    
    var mockFileSize: Int64 = 0
    var mockThumbnailURL: URL?
    var mockExportURL: URL?
    
    override init() throws {
        // Skip the real initialization
        try super.init()
    }
    
    override func copyFile(from sourceURL: URL, fileName: String, fileType: DocumentType) throws -> URL {
        copyFileCalled = true
        return URL(fileURLWithPath: "/tmp/copied_\(fileName)")
    }
    
    override func storeDocument(data: Data, fileName: String, fileType: DocumentType) throws -> URL {
        storeDocumentCalled = true
        return URL(fileURLWithPath: "/tmp/stored_\(fileName)")
    }
    
    override func deleteDocument(at url: URL) throws {
        deleteDocumentCalled = true
    }
    
    override func generateThumbnail(for documentURL: URL, documentType: DocumentType) async throws -> URL? {
        generateThumbnailCalled = true
        return mockThumbnailURL
    }
    
    override func getFileSize(at url: URL) throws -> Int64 {
        return mockFileSize
    }
    
    override func createExportFile(data: Data, fileName: String, fileType: ExportFileType) throws -> URL {
        createExportFileCalled = true
        return mockExportURL ?? URL(fileURLWithPath: "/tmp/export.\(fileType.fileExtension)")
    }
}