import XCTest
@testable import HealthApp

final class ModelTests: XCTestCase {
    
    // MARK: - PersonalHealthInfo Tests
    func testPersonalHealthInfoInitialization() {
        let personalInfo = PersonalHealthInfo(
            name: "John Doe",
            dateOfBirth: Date(),
            gender: .male,
            bloodType: .oPositive
        )
        
        XCTAssertEqual(personalInfo.name, "John Doe")
        XCTAssertEqual(personalInfo.gender, .male)
        XCTAssertEqual(personalInfo.bloodType, .oPositive)
        XCTAssertEqual(personalInfo.type, .personalInfo)
        XCTAssertTrue(personalInfo.isValid)
    }
    
    func testPersonalHealthInfoValidation() {
        var personalInfo = PersonalHealthInfo()
        XCTAssertFalse(personalInfo.isValid)
        
        personalInfo.name = "John Doe"
        XCTAssertTrue(personalInfo.isValid)
        
        personalInfo.name = ""
        XCTAssertFalse(personalInfo.isValid)
        
        personalInfo.name = "   "
        XCTAssertFalse(personalInfo.isValid)
    }
    
    func testPersonalHealthInfoCompletionPercentage() {
        var personalInfo = PersonalHealthInfo()
        XCTAssertEqual(personalInfo.completionPercentage, 0.0)
        
        personalInfo.name = "John Doe"
        XCTAssertEqual(personalInfo.completionPercentage, 1.0/6.0, accuracy: 0.01)
        
        personalInfo.dateOfBirth = Date()
        personalInfo.gender = .male
        personalInfo.bloodType = .oPositive
        XCTAssertEqual(personalInfo.completionPercentage, 4.0/6.0, accuracy: 0.01)
    }
    
    // MARK: - BloodTestResult Tests
    func testBloodTestResultInitialization() {
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
            laboratoryName: "Lab Corp",
            results: [testItem]
        )
        
        XCTAssertEqual(bloodTest.type, .bloodTest)
        XCTAssertEqual(bloodTest.results.count, 1)
        XCTAssertEqual(bloodTest.results.first?.name, "Glucose")
        XCTAssertTrue(bloodTest.isValid)
    }
    
    func testBloodTestResultValidation() {
        var bloodTest = BloodTestResult(testDate: Date())
        XCTAssertFalse(bloodTest.isValid)
        
        let testItem = BloodTestItem(name: "Glucose", value: "95")
        bloodTest.results = [testItem]
        XCTAssertTrue(bloodTest.isValid)
        
        let emptyTestItem = BloodTestItem(name: "", value: "95")
        bloodTest.results = [emptyTestItem]
        XCTAssertFalse(bloodTest.isValid)
    }
    
    func testBloodTestResultAbnormalResults() {
        let normalItem = BloodTestItem(name: "Glucose", value: "95", isAbnormal: false)
        let abnormalItem = BloodTestItem(name: "Cholesterol", value: "250", isAbnormal: true)
        
        let bloodTest = BloodTestResult(
            testDate: Date(),
            results: [normalItem, abnormalItem]
        )
        
        XCTAssertEqual(bloodTest.abnormalResults.count, 1)
        XCTAssertEqual(bloodTest.abnormalResults.first?.name, "Cholesterol")
        XCTAssertEqual(bloodTest.summary, "2 tests - 1 abnormal")
    }
    
    func testBloodTestResultsByCategory() {
        let glucoseItem = BloodTestItem(name: "Glucose", value: "95", category: .basicMetabolicPanel)
        let cholesterolItem = BloodTestItem(name: "Cholesterol", value: "180", category: .lipidPanel)
        let wbcItem = BloodTestItem(name: "WBC", value: "7.5", category: .completeBloodCount)
        
        let bloodTest = BloodTestResult(
            testDate: Date(),
            results: [glucoseItem, cholesterolItem, wbcItem]
        )
        
        let categorized = bloodTest.resultsByCategory
        XCTAssertEqual(categorized[.basicMetabolicPanel]?.count, 1)
        XCTAssertEqual(categorized[.lipidPanel]?.count, 1)
        XCTAssertEqual(categorized[.completeBloodCount]?.count, 1)
    }
    
    // MARK: - MedicalDocument Tests
    func testMedicalDocumentInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let document = MedicalDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: url,
            fileSize: 1024
        )
        
        XCTAssertEqual(document.fileName, "test.pdf")
        XCTAssertEqual(document.fileType, .pdf)
        XCTAssertEqual(document.processingStatus, .pending)
        XCTAssertTrue(document.canBeProcessed)
        XCTAssertFalse(document.isProcessed)
    }
    
    func testDocumentTypeFromExtension() {
        XCTAssertEqual(DocumentType.from(fileExtension: "pdf"), .pdf)
        XCTAssertEqual(DocumentType.from(fileExtension: "PDF"), .pdf)
        XCTAssertEqual(DocumentType.from(fileExtension: "jpg"), .jpg)
        XCTAssertEqual(DocumentType.from(fileExtension: "JPEG"), .jpeg)
        XCTAssertEqual(DocumentType.from(fileExtension: "unknown"), .other)
    }
    
    func testDocumentTypeProperties() {
        XCTAssertTrue(DocumentType.jpeg.isImage)
        XCTAssertFalse(DocumentType.jpeg.isDocument)
        XCTAssertTrue(DocumentType.pdf.isDocument)
        XCTAssertFalse(DocumentType.pdf.isImage)
    }
    
    func testMedicalDocumentTags() {
        var document = MedicalDocument(
            fileName: "test.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf")
        )
        
        document.addTag("blood test")
        document.addTag("2024")
        document.addTag("blood test") // Duplicate
        
        XCTAssertEqual(document.tags.count, 2)
        XCTAssertTrue(document.tags.contains("blood test"))
        XCTAssertTrue(document.tags.contains("2024"))
        
        document.removeTag("blood test")
        XCTAssertEqual(document.tags.count, 1)
        XCTAssertFalse(document.tags.contains("blood test"))
    }
    
    // MARK: - ChatConversation Tests
    func testChatConversationInitialization() {
        let conversation = ChatConversation(title: "Health Discussion")
        
        XCTAssertEqual(conversation.title, "Health Discussion")
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertFalse(conversation.hasMessages)
        XCTAssertEqual(conversation.messageCount, 0)
    }
    
    func testChatConversationMessages() {
        var conversation = ChatConversation(title: "Test Chat")
        
        let userMessage = ChatMessage(content: "Hello", role: .user)
        let assistantMessage = ChatMessage(content: "Hi there!", role: .assistant)
        
        conversation.addMessage(userMessage)
        conversation.addMessage(assistantMessage)
        
        XCTAssertEqual(conversation.messageCount, 2)
        XCTAssertEqual(conversation.userMessageCount, 1)
        XCTAssertEqual(conversation.assistantMessageCount, 1)
        XCTAssertTrue(conversation.hasMessages)
        XCTAssertEqual(conversation.lastMessage?.content, "Hi there!")
    }
    
    func testChatMessageProperties() {
        let message = ChatMessage(content: "Hello world", role: .user)
        
        XCTAssertTrue(message.isFromUser)
        XCTAssertFalse(message.isFromAssistant)
        XCTAssertEqual(message.wordCount, 2)
    }
    
    // MARK: - ChatContext Tests
    func testChatContextEmpty() {
        let context = ChatContext()
        XCTAssertTrue(context.isEmpty)
        XCTAssertEqual(context.estimatedTokenCount, 0)
    }
    
    func testChatContextWithData() {
        let personalInfo = PersonalHealthInfo(name: "John Doe")
        let bloodTest = BloodTestResult(testDate: Date())
        
        let context = ChatContext(
            personalInfo: personalInfo,
            bloodTests: [bloodTest]
        )
        
        XCTAssertFalse(context.isEmpty)
        XCTAssertGreaterThan(context.estimatedTokenCount, 0)
        
        let contextString = context.buildContextString()
        XCTAssertTrue(contextString.contains("John Doe"))
        XCTAssertTrue(contextString.contains("Personal Information"))
    }
    
    // MARK: - Enum Tests
    func testHealthDataTypeProperties() {
        XCTAssertEqual(HealthDataType.personalInfo.displayName, "Personal Information")
        XCTAssertEqual(HealthDataType.bloodTest.icon, "drop.fill")
    }
    
    func testGenderDisplayNames() {
        XCTAssertEqual(Gender.male.displayName, "Male")
        XCTAssertEqual(Gender.preferNotToSay.displayName, "Prefer not to say")
    }
    
    func testBloodTypeDisplayNames() {
        XCTAssertEqual(BloodType.aPositive.displayName, "A+")
        XCTAssertEqual(BloodType.oNegative.displayName, "O-")
    }
    
    func testProcessingStatusProperties() {
        XCTAssertEqual(ProcessingStatus.pending.displayName, "Pending")
        XCTAssertEqual(ProcessingStatus.completed.icon, "checkmark.circle")
        XCTAssertEqual(ProcessingStatus.failed.color, "red")
    }
    
    // MARK: - Codable Tests
    func testPersonalHealthInfoCodable() throws {
        let originalInfo = PersonalHealthInfo(
            name: "John Doe",
            gender: .male,
            bloodType: .oPositive
        )
        
        let encoded = try JSONEncoder().encode(originalInfo)
        let decoded = try JSONDecoder().decode(PersonalHealthInfo.self, from: encoded)
        
        XCTAssertEqual(decoded.name, originalInfo.name)
        XCTAssertEqual(decoded.gender, originalInfo.gender)
        XCTAssertEqual(decoded.bloodType, originalInfo.bloodType)
        XCTAssertEqual(decoded.id, originalInfo.id)
    }
    
    func testBloodTestResultCodable() throws {
        let testItem = BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL")
        let originalTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Lab Corp",
            results: [testItem]
        )
        
        let encoded = try JSONEncoder().encode(originalTest)
        let decoded = try JSONDecoder().decode(BloodTestResult.self, from: encoded)
        
        XCTAssertEqual(decoded.laboratoryName, originalTest.laboratoryName)
        XCTAssertEqual(decoded.results.count, originalTest.results.count)
        XCTAssertEqual(decoded.results.first?.name, originalTest.results.first?.name)
    }
    
    func testChatConversationCodable() throws {
        let message = ChatMessage(content: "Hello", role: .user)
        let originalConversation = ChatConversation(
            title: "Test Chat",
            messages: [message]
        )
        
        let encoded = try JSONEncoder().encode(originalConversation)
        let decoded = try JSONDecoder().decode(ChatConversation.self, from: encoded)
        
        XCTAssertEqual(decoded.title, originalConversation.title)
        XCTAssertEqual(decoded.messages.count, originalConversation.messages.count)
        XCTAssertEqual(decoded.messages.first?.content, originalConversation.messages.first?.content)
    }
}