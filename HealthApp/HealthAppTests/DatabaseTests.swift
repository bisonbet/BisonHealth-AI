import XCTest
@testable import HealthApp

final class DatabaseTests: XCTestCase {
    var databaseManager: DatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a test database manager
        databaseManager = try DatabaseManager()
    }
    
    override func tearDown() async throws {
        // Clean up test data
        databaseManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Health Data Tests
    func testSaveAndFetchPersonalHealthInfo() async throws {
        let personalInfo = PersonalHealthInfo(
            name: "Test User",
            dateOfBirth: Date(),
            gender: .male,
            bloodType: .oPositive
        )
        
        // Save
        try await databaseManager.save(personalInfo)
        
        // Fetch
        let fetchedInfo = try await databaseManager.fetchPersonalHealthInfo()
        
        XCTAssertNotNil(fetchedInfo)
        XCTAssertEqual(fetchedInfo?.name, "Test User")
        XCTAssertEqual(fetchedInfo?.gender, .male)
        XCTAssertEqual(fetchedInfo?.bloodType, .oPositive)
        XCTAssertEqual(fetchedInfo?.id, personalInfo.id)
    }
    
    func testSaveAndFetchBloodTestResults() async throws {
        let testItem = BloodTestItem(
            name: "Glucose",
            value: "95",
            unit: "mg/dL",
            referenceRange: "70-100",
            isAbnormal: false,
            category: .basicMetabolicPanel
        )
        
        let bloodTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Test Lab",
            results: [testItem]
        )
        
        // Save
        try await databaseManager.save(bloodTest)
        
        // Fetch
        let fetchedTests = try await databaseManager.fetchBloodTestResults()
        
        XCTAssertEqual(fetchedTests.count, 1)
        XCTAssertEqual(fetchedTests.first?.laboratoryName, "Test Lab")
        XCTAssertEqual(fetchedTests.first?.results.count, 1)
        XCTAssertEqual(fetchedTests.first?.results.first?.name, "Glucose")
    }
    
    func testUpdateHealthData() async throws {
        var personalInfo = PersonalHealthInfo(name: "Original Name")
        
        // Save original
        try await databaseManager.save(personalInfo)
        
        // Update
        personalInfo.name = "Updated Name"
        personalInfo.updatedAt = Date()
        try await databaseManager.update(personalInfo)
        
        // Fetch and verify
        let fetchedInfo = try await databaseManager.fetchPersonalHealthInfo()
        XCTAssertEqual(fetchedInfo?.name, "Updated Name")
    }
    
    func testDeleteHealthData() async throws {
        let personalInfo = PersonalHealthInfo(name: "Test User")
        
        // Save
        try await databaseManager.save(personalInfo)
        
        // Verify it exists
        let fetchedInfo = try await databaseManager.fetchPersonalHealthInfo()
        XCTAssertNotNil(fetchedInfo)
        
        // Delete
        try await databaseManager.delete(personalInfo)
        
        // Verify it's gone
        let deletedInfo = try await databaseManager.fetchPersonalHealthInfo()
        XCTAssertNil(deletedInfo)
    }
    
    func testHealthDataStatistics() async throws {
        let personalInfo = PersonalHealthInfo(name: "Test User")
        let bloodTest1 = BloodTestResult(testDate: Date())
        let bloodTest2 = BloodTestResult(testDate: Date())
        
        // Save test data
        try await databaseManager.save(personalInfo)
        try await databaseManager.save(bloodTest1)
        try await databaseManager.save(bloodTest2)
        
        // Test statistics
        let personalInfoCount = try await databaseManager.getHealthDataCount(for: .personalInfo)
        let bloodTestCount = try await databaseManager.getHealthDataCount(for: .bloodTest)
        let totalCount = try await databaseManager.getTotalHealthDataCount()
        
        XCTAssertEqual(personalInfoCount, 1)
        XCTAssertEqual(bloodTestCount, 2)
        XCTAssertEqual(totalCount, 3)
    }
    
    // MARK: - Document Tests
    func testSaveAndFetchDocument() async throws {
        let document = MedicalDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileSize: 1024
        )
        
        // Save
        try await databaseManager.saveDocument(document)
        
        // Fetch
        let fetchedDocuments = try await databaseManager.fetchDocuments()
        
        XCTAssertEqual(fetchedDocuments.count, 1)
        XCTAssertEqual(fetchedDocuments.first?.fileName, "test.pdf")
        XCTAssertEqual(fetchedDocuments.first?.fileType, .pdf)
        XCTAssertEqual(fetchedDocuments.first?.fileSize, 1024)
    }
    
    func testUpdateDocumentStatus() async throws {
        let document = MedicalDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        
        // Save
        try await databaseManager.saveDocument(document)
        
        // Update status
        try await databaseManager.updateDocumentStatus(document.id, status: .completed)
        
        // Fetch and verify
        let fetchedDocument = try await databaseManager.fetchDocument(id: document.id)
        XCTAssertEqual(fetchedDocument?.processingStatus, .completed)
        XCTAssertNotNil(fetchedDocument?.processedAt)
    }
    
    func testFetchDocumentsByStatus() async throws {
        let pendingDoc = MedicalDocument(
            fileName: "pending.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/pending.pdf"),
            processingStatus: .pending
        )
        
        let completedDoc = MedicalDocument(
            fileName: "completed.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/completed.pdf"),
            processingStatus: .completed
        )
        
        // Save documents
        try await databaseManager.saveDocument(pendingDoc)
        try await databaseManager.saveDocument(completedDoc)
        
        // Fetch by status
        let pendingDocs = try await databaseManager.fetchDocuments(with: .pending)
        let completedDocs = try await databaseManager.fetchDocuments(with: .completed)
        
        XCTAssertEqual(pendingDocs.count, 1)
        XCTAssertEqual(completedDocs.count, 1)
        XCTAssertEqual(pendingDocs.first?.fileName, "pending.pdf")
        XCTAssertEqual(completedDocs.first?.fileName, "completed.pdf")
    }
    
    func testSearchDocuments() async throws {
        let doc1 = MedicalDocument(
            fileName: "blood_test_results.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/blood_test.pdf")
        )
        
        let doc2 = MedicalDocument(
            fileName: "xray_report.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/xray.pdf")
        )
        
        // Save documents
        try await databaseManager.saveDocument(doc1)
        try await databaseManager.saveDocument(doc2)
        
        // Search
        let bloodTestDocs = try await databaseManager.searchDocuments(query: "blood")
        let xrayDocs = try await databaseManager.searchDocuments(query: "xray")
        
        XCTAssertEqual(bloodTestDocs.count, 1)
        XCTAssertEqual(xrayDocs.count, 1)
        XCTAssertEqual(bloodTestDocs.first?.fileName, "blood_test_results.pdf")
        XCTAssertEqual(xrayDocs.first?.fileName, "xray_report.pdf")
    }
    
    // MARK: - Chat Tests
    func testSaveAndFetchConversation() async throws {
        let message1 = ChatMessage(content: "Hello", role: .user)
        let message2 = ChatMessage(content: "Hi there!", role: .assistant)
        
        let conversation = ChatConversation(
            title: "Test Chat",
            messages: [message1, message2],
            includedHealthDataTypes: [.personalInfo, .bloodTest]
        )
        
        // Save
        try await databaseManager.saveConversation(conversation)
        
        // Fetch
        let fetchedConversations = try await databaseManager.fetchConversations()
        
        XCTAssertEqual(fetchedConversations.count, 1)
        XCTAssertEqual(fetchedConversations.first?.title, "Test Chat")
        XCTAssertEqual(fetchedConversations.first?.messages.count, 2)
        XCTAssertEqual(fetchedConversations.first?.messages.first?.content, "Hello")
        XCTAssertEqual(fetchedConversations.first?.messages.last?.content, "Hi there!")
    }
    
    func testAddMessageToConversation() async throws {
        let conversation = ChatConversation(title: "Test Chat")
        
        // Save conversation
        try await databaseManager.saveConversation(conversation)
        
        // Add message
        let newMessage = ChatMessage(content: "New message", role: .user)
        try await databaseManager.addMessage(to: conversation.id, message: newMessage)
        
        // Fetch and verify
        let fetchedConversation = try await databaseManager.fetchConversation(id: conversation.id)
        XCTAssertEqual(fetchedConversation?.messages.count, 1)
        XCTAssertEqual(fetchedConversation?.messages.first?.content, "New message")
    }
    
    func testArchiveConversation() async throws {
        var conversation = ChatConversation(title: "Test Chat")
        
        // Save
        try await databaseManager.saveConversation(conversation)
        
        // Archive
        conversation.archive()
        try await databaseManager.updateConversation(conversation)
        
        // Verify it's not in regular conversations
        let regularConversations = try await databaseManager.fetchConversations()
        XCTAssertEqual(regularConversations.count, 0)
        
        // Verify it's in archived conversations
        let archivedConversations = try await databaseManager.fetchArchivedConversations()
        XCTAssertEqual(archivedConversations.count, 1)
        XCTAssertTrue(archivedConversations.first?.isArchived == true)
    }
    
    func testChatStatistics() async throws {
        let message1 = ChatMessage(content: "Hello", role: .user, tokens: 10)
        let message2 = ChatMessage(content: "Hi!", role: .assistant, tokens: 5, processingTime: 1.5)
        
        let conversation = ChatConversation(
            title: "Test Chat",
            messages: [message1, message2]
        )
        
        // Save
        try await databaseManager.saveConversation(conversation)
        
        // Get statistics
        let stats = try await databaseManager.getChatStatistics()
        
        XCTAssertEqual(stats.totalConversations, 1)
        XCTAssertEqual(stats.totalMessages, 2)
        XCTAssertEqual(stats.totalTokensUsed, 15)
        XCTAssertEqual(stats.averageResponseTime, 1.5, accuracy: 0.1)
    }
    
    // MARK: - Encryption Tests
    func testDataEncryption() async throws {
        let originalInfo = PersonalHealthInfo(
            name: "Sensitive Name",
            dateOfBirth: Date(),
            allergies: ["Peanuts", "Shellfish"]
        )
        
        // Save (which encrypts)
        try await databaseManager.save(originalInfo)
        
        // Fetch (which decrypts)
        let fetchedInfo = try await databaseManager.fetchPersonalHealthInfo()
        
        // Verify data integrity after encryption/decryption
        XCTAssertEqual(fetchedInfo?.name, "Sensitive Name")
        XCTAssertEqual(fetchedInfo?.allergies.count, 2)
        XCTAssertTrue(fetchedInfo?.allergies.contains("Peanuts") == true)
        XCTAssertTrue(fetchedInfo?.allergies.contains("Shellfish") == true)
    }
    
    func testChatMessageEncryption() async throws {
        let sensitiveMessage = ChatMessage(
            content: "My blood pressure is 140/90 and I'm concerned about my heart condition.",
            role: .user
        )
        
        let conversation = ChatConversation(
            title: "Health Discussion",
            messages: [sensitiveMessage]
        )
        
        // Save (encrypts message content)
        try await databaseManager.saveConversation(conversation)
        
        // Fetch (decrypts message content)
        let fetchedConversation = try await databaseManager.fetchConversation(id: conversation.id)
        
        // Verify message content is correctly decrypted
        XCTAssertEqual(fetchedConversation?.messages.first?.content, sensitiveMessage.content)
    }
    
    // MARK: - Error Handling Tests
    func testUpdateNonExistentRecord() async throws {
        let nonExistentInfo = PersonalHealthInfo(name: "Non-existent")
        
        do {
            try await databaseManager.update(nonExistentInfo)
            XCTFail("Should have thrown an error")
        } catch DatabaseError.notFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testDeleteNonExistentRecord() async throws {
        let nonExistentId = UUID()
        
        do {
            try await databaseManager.deleteHealthData(id: nonExistentId)
            XCTFail("Should have thrown an error")
        } catch DatabaseError.notFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}