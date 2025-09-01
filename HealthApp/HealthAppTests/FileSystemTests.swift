import XCTest
import UIKit
@testable import HealthApp

final class FileSystemTests: XCTestCase {
    var fileSystemManager: FileSystemManager!
    var testDocumentData: Data!
    var testImageData: Data!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test file system manager
        fileSystemManager = try FileSystemManager()
        
        // Create test data
        testDocumentData = "This is a test document content".data(using: .utf8)!
        
        // Create test image data
        let testImage = UIImage(systemName: "heart.fill")!
        testImageData = testImage.pngData()!
    }
    
    override func tearDown() async throws {
        // Clean up test files
        fileSystemManager = nil
        testDocumentData = nil
        testImageData = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Document Storage Tests
    func testStoreAndRetrieveDocument() throws {
        let fileName = "test_document.txt"
        let fileType = DocumentType.other
        
        // Store document
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        XCTAssertTrue(fileSystemManager.fileExists(at: storedURL))
        
        // Retrieve document
        let retrievedData = try fileSystemManager.retrieveDocument(from: storedURL)
        
        XCTAssertEqual(retrievedData, testDocumentData)
    }
    
    func testDocumentEncryption() throws {
        let fileName = "encrypted_test.txt"
        let fileType = DocumentType.other
        
        // Store document (should be encrypted)
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        // Read raw file data (should be encrypted, not plain text)
        let rawFileData = try Data(contentsOf: storedURL)
        XCTAssertNotEqual(rawFileData, testDocumentData)
        
        // Retrieve through manager (should decrypt properly)
        let decryptedData = try fileSystemManager.retrieveDocument(from: storedURL)
        XCTAssertEqual(decryptedData, testDocumentData)
    }
    
    func testDeleteDocument() throws {
        let fileName = "delete_test.txt"
        let fileType = DocumentType.other
        
        // Store document
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        XCTAssertTrue(fileSystemManager.fileExists(at: storedURL))
        
        // Delete document
        try fileSystemManager.deleteDocument(at: storedURL)
        
        XCTAssertFalse(fileSystemManager.fileExists(at: storedURL))
    }
    
    // MARK: - Thumbnail Generation Tests
    func testImageThumbnailGeneration() async throws {
        let fileName = "test_image.png"
        let fileType = DocumentType.png
        
        // Store image
        let storedURL = try fileSystemManager.storeDocument(
            data: testImageData,
            fileName: fileName,
            fileType: fileType
        )
        
        // Generate thumbnail
        let thumbnailURL = try await fileSystemManager.generateThumbnail(
            for: storedURL,
            documentType: fileType
        )
        
        XCTAssertNotNil(thumbnailURL)
        XCTAssertTrue(fileSystemManager.fileExists(at: thumbnailURL!))
        
        // Verify thumbnail is smaller than original
        let originalSize = try fileSystemManager.getFileSize(at: storedURL)
        let thumbnailSize = try fileSystemManager.getFileSize(at: thumbnailURL!)
        
        XCTAssertLessThan(thumbnailSize, originalSize)
    }
    
    func testGenericThumbnailGeneration() async throws {
        let fileName = "test_document.txt"
        let fileType = DocumentType.other
        
        // Store document
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        // Generate thumbnail
        let thumbnailURL = try await fileSystemManager.generateThumbnail(
            for: storedURL,
            documentType: fileType
        )
        
        XCTAssertNotNil(thumbnailURL)
        XCTAssertTrue(fileSystemManager.fileExists(at: thumbnailURL!))
    }
    
    // MARK: - File Operations Tests
    func testCopyFile() throws {
        // Create temporary source file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("source.txt")
        try testDocumentData.write(to: tempURL)
        
        let fileName = "copied_file.txt"
        let fileType = DocumentType.other
        
        // Copy file
        let copiedURL = try fileSystemManager.copyFile(
            from: tempURL,
            fileName: fileName,
            fileType: fileType
        )
        
        XCTAssertTrue(fileSystemManager.fileExists(at: copiedURL))
        
        // Verify content
        let copiedData = try fileSystemManager.retrieveDocument(from: copiedURL)
        XCTAssertEqual(copiedData, testDocumentData)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    func testGetFileSize() throws {
        let fileName = "size_test.txt"
        let fileType = DocumentType.other
        
        // Store document
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        // Get file size
        let fileSize = try fileSystemManager.getFileSize(at: storedURL)
        
        XCTAssertGreaterThan(fileSize, 0)
        // Note: File size will be larger than original due to encryption overhead
        XCTAssertGreaterThan(fileSize, Int64(testDocumentData.count))
    }
    
    // MARK: - Storage Management Tests
    func testStorageUsageCalculation() throws {
        let fileName1 = "storage_test1.txt"
        let fileName2 = "storage_test2.txt"
        let fileType = DocumentType.other
        
        // Get initial storage usage
        let initialUsage = try fileSystemManager.getTotalStorageUsed()
        
        // Store documents
        _ = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName1,
            fileType: fileType
        )
        
        _ = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName2,
            fileType: fileType
        )
        
        // Check storage usage increased
        let finalUsage = try fileSystemManager.getTotalStorageUsed()
        XCTAssertGreaterThan(finalUsage, initialUsage)
    }
    
    func testDocumentStorageUsage() throws {
        let fileName = "doc_storage_test.txt"
        let fileType = DocumentType.other
        
        // Get initial document storage usage
        let initialUsage = try fileSystemManager.getDocumentStorageUsed()
        
        // Store document
        _ = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: fileName,
            fileType: fileType
        )
        
        // Check document storage usage increased
        let finalUsage = try fileSystemManager.getDocumentStorageUsed()
        XCTAssertGreaterThan(finalUsage, initialUsage)
    }
    
    // MARK: - Export Management Tests
    func testCreateExportFile() throws {
        let exportData = "Export test data".data(using: .utf8)!
        let fileName = "test_export"
        let fileType = ExportFileType.json
        
        // Create export file
        let exportURL = try fileSystemManager.createExportFile(
            data: exportData,
            fileName: fileName,
            fileType: fileType
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Verify content
        let retrievedData = try Data(contentsOf: exportURL)
        XCTAssertEqual(retrievedData, exportData)
        
        // Verify file extension
        XCTAssertEqual(exportURL.pathExtension, fileType.fileExtension)
    }
    
    func testGetExportURL() {
        let fileName = "test_export"
        let fileType = ExportFileType.pdf
        
        let exportURL = fileSystemManager.getExportURL(for: fileName, fileType: fileType)
        
        XCTAssertTrue(exportURL.lastPathComponent.contains(fileName))
        XCTAssertEqual(exportURL.pathExtension, fileType.fileExtension)
    }
    
    // MARK: - Error Handling Tests
    func testInvalidFileOperations() {
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/file.txt")
        
        // Test retrieving non-existent file
        XCTAssertThrowsError(try fileSystemManager.retrieveDocument(from: nonExistentURL))
        
        // Test deleting non-existent file
        XCTAssertThrowsError(try fileSystemManager.deleteDocument(at: nonExistentURL))
        
        // Test getting size of non-existent file
        XCTAssertThrowsError(try fileSystemManager.getFileSize(at: nonExistentURL))
    }
    
    // MARK: - File Name Sanitization Tests
    func testFileNameSanitization() throws {
        let unsafeFileName = "test/file:with\\invalid?chars*.txt"
        let fileType = DocumentType.other
        
        // This should not throw an error despite unsafe characters
        let storedURL = try fileSystemManager.storeDocument(
            data: testDocumentData,
            fileName: unsafeFileName,
            fileType: fileType
        )
        
        XCTAssertTrue(fileSystemManager.fileExists(at: storedURL))
        
        // Verify unsafe characters were replaced
        let finalFileName = storedURL.lastPathComponent
        XCTAssertFalse(finalFileName.contains("/"))
        XCTAssertFalse(finalFileName.contains(":"))
        XCTAssertFalse(finalFileName.contains("\\"))
        XCTAssertFalse(finalFileName.contains("?"))
        XCTAssertFalse(finalFileName.contains("*"))
    }
}

// MARK: - Document Importer Tests
final class DocumentImporterTests: XCTestCase {
    var documentImporter: DocumentImporter!
    var fileSystemManager: FileSystemManager!
    var databaseManager: DatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        fileSystemManager = try FileSystemManager()
        databaseManager = try DatabaseManager()
        documentImporter = DocumentImporter(
            fileSystemManager: fileSystemManager,
            databaseManager: databaseManager
        )
    }
    
    override func tearDown() async throws {
        documentImporter = nil
        fileSystemManager = nil
        databaseManager = nil
        
        try await super.tearDown()
    }
    
    func testImageImport() async throws {
        let testImage = UIImage(systemName: "heart.fill")!
        let fileName = "test_heart_image"
        
        // Import image
        let document = try await documentImporter.importImage(testImage, fileName: fileName)
        
        XCTAssertEqual(document.fileName, fileName)
        XCTAssertEqual(document.fileType, .jpeg)
        XCTAssertTrue(document.tags.contains("photo"))
        XCTAssertGreaterThan(document.fileSize, 0)
        
        // Verify file exists
        XCTAssertTrue(fileSystemManager.fileExists(at: document.filePath))
        
        // Verify document was saved to database
        let fetchedDocument = try await databaseManager.fetchDocument(id: document.id)
        XCTAssertNotNil(fetchedDocument)
        XCTAssertEqual(fetchedDocument?.fileName, fileName)
    }
    
    func testInvalidImageImport() async {
        // Create an invalid image (empty)
        let invalidImage = UIImage()
        
        do {
            _ = try await documentImporter.importImage(invalidImage)
            XCTFail("Should have thrown an error for invalid image")
        } catch DocumentImportError.imageProcessingFailed {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Document Exporter Tests
final class DocumentExporterTests: XCTestCase {
    var documentExporter: DocumentExporter!
    var fileSystemManager: FileSystemManager!
    var databaseManager: DatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        fileSystemManager = try FileSystemManager()
        databaseManager = try DatabaseManager()
        documentExporter = DocumentExporter(
            fileSystemManager: fileSystemManager,
            databaseManager: databaseManager
        )
    }
    
    override func tearDown() async throws {
        documentExporter = nil
        fileSystemManager = nil
        databaseManager = nil
        
        try await super.tearDown()
    }
    
    func testJSONExport() async throws {
        // Add some test data
        let personalInfo = PersonalHealthInfo(name: "Test User", gender: .male)
        try await databaseManager.save(personalInfo)
        
        // Export as JSON
        let exportURL = try await documentExporter.exportHealthDataAsJSON()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertEqual(exportURL.pathExtension, "json")
        
        // Verify JSON content
        let jsonData = try Data(contentsOf: exportURL)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        XCTAssertNotNil(jsonObject)
        XCTAssertNotNil(jsonObject?["exportDate"])
        XCTAssertNotNil(jsonObject?["appVersion"])
        XCTAssertNotNil(jsonObject?["personalHealthInfo"])
    }
    
    func testPDFExport() async throws {
        // Add some test data
        let personalInfo = PersonalHealthInfo(name: "Test User", gender: .male)
        try await databaseManager.save(personalInfo)
        
        // Export as PDF
        let exportURL = try await documentExporter.exportHealthReportAsPDF()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertEqual(exportURL.pathExtension, "pdf")
        
        // Verify file size (should be greater than 0)
        let fileSize = try fileSystemManager.getFileSize(at: exportURL)
        XCTAssertGreaterThan(fileSize, 0)
    }
}