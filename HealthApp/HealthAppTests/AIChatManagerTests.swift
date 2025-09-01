import XCTest
@testable import HealthApp

@MainActor
final class AIChatManagerTests: XCTestCase {
    
    var chatManager: AIChatManager!
    var mockOllamaClient: MockOllamaClient!
    var mockHealthDataManager: MockHealthDataManager!
    var mockDatabaseManager: MockDatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockOllamaClient = MockOllamaClient()
        mockHealthDataManager = MockHealthDataManager()
        mockDatabaseManager = MockDatabaseManager()
        
        chatManager = AIChatManager(
            ollamaClient: mockOllamaClient,
            healthDataManager: mockHealthDataManager,
            databaseManager: mockDatabaseManager
        )
    }
    
    override func tearDown() async throws {
        chatManager = nil
        mockOllamaClient = nil
        mockHealthDataManager = nil
        mockDatabaseManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    func testInitialization() {
        XCTAssertNotNil(chatManager)
        XCTAssertEqual(chatManager.conversations.count, 0)
        XCTAssertNil(chatManager.currentConversation)
        XCTAssertFalse(chatManager.isConnected)
        XCTAssertFalse(chatManager.isLoading)
        XCTAssertEqual(chatManager.contextSizeLimit, 4000)
    }
    
    // MARK: - Connection Management Tests
    func testCheckConnectionSuccess() async {
        // Given
        mockOllamaClient.shouldSucceedConnection = true
        
        // When
        await chatManager.checkConnection()
        
        // Then
        XCTAssertTrue(chatManager.isConnected)
        XCTAssertNil(chatManager.errorMessage)
    }
    
    func testCheckConnectionFailure() async {
        // Given
        mockOllamaClient.shouldSucceedConnection = false
        mockOllamaClient.connectionError = OllamaError.connectionFailed(500)
        
        // When
        await chatManager.checkConnection()
        
        // Then
        XCTAssertFalse(chatManager.isConnected)
        XCTAssertNotNil(chatManager.errorMessage)
    }
    
    func testOfflineHandling() {
        // Given
        chatManager.isOffline = true
        
        // When
        let result = chatManager.handleOfflineAction(.sendMessage)
        
        // Then
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.message.contains("offline"))
    }
    
    // MARK: - Conversation Management Tests
    func testStartNewConversation() async throws {
        // Given
        let title = "Test Conversation"
        
        // When
        let conversation = try await chatManager.startNewConversation(title: title)
        
        // Then
        XCTAssertEqual(conversation.title, title)
        XCTAssertEqual(chatManager.conversations.count, 1)
        XCTAssertEqual(chatManager.currentConversation?.id, conversation.id)
        XCTAssertTrue(mockDatabaseManager.savedConversations.contains { $0.id == conversation.id })
    }
    
    func testStartNewConversationWithDefaultTitle() async throws {
        // When
        let conversation = try await chatManager.startNewConversation()
        
        // Then
        XCTAssertEqual(conversation.title, "New Conversation")
        XCTAssertEqual(chatManager.conversations.count, 1)
    }
    
    func testSelectConversation() {
        // Given
        let conversation = ChatConversation(title: "Test", includedHealthDataTypes: [.bloodTest])
        
        // When
        chatManager.selectConversation(conversation)
        
        // Then
        XCTAssertEqual(chatManager.currentConversation?.id, conversation.id)
        XCTAssertTrue(chatManager.selectedHealthDataTypes.contains(.bloodTest))
    }
    
    func testDeleteConversation() async throws {
        // Given
        let conversation = try await chatManager.startNewConversation(title: "To Delete")
        XCTAssertEqual(chatManager.conversations.count, 1)
        
        // When
        try await chatManager.deleteConversation(conversation)
        
        // Then
        XCTAssertEqual(chatManager.conversations.count, 0)
        XCTAssertNil(chatManager.currentConversation)
        XCTAssertTrue(mockDatabaseManager.deletedConversationIds.contains(conversation.id))
    }
    
    func testArchiveConversation() async throws {
        // Given
        let conversation = try await chatManager.startNewConversation(title: "To Archive")
        
        // When
        try await chatManager.archiveConversation(conversation)
        
        // Then
        XCTAssertNil(chatManager.currentConversation)
        XCTAssertTrue(mockDatabaseManager.updatedConversations.contains { $0.isArchived })
    }
    
    // MARK: - Message Management Tests
    func testSendMessageSuccess() async throws {
        // Given
        let conversation = try await chatManager.startNewConversation(title: "Test Chat")
        mockOllamaClient.shouldSucceedConnection = true
        mockOllamaClient.mockResponse = OllamaChatResponse(
            model: "test-model",
            message: OllamaMessage(role: "assistant", content: "Test response"),
            done: true,
            totalDuration: 1000000000, // 1 second in nanoseconds
            loadDuration: nil,
            promptEvalCount: 10,
            promptEvalDuration: nil,
            evalCount: 20,
            evalDuration: nil
        )
        chatManager.isConnected = true
        
        // When
        try await chatManager.sendMessage("Hello, AI!")
        
        // Then
        XCTAssertFalse(chatManager.isLoading)
        XCTAssertEqual(mockDatabaseManager.savedMessages.count, 2) // User + Assistant messages
        XCTAssertEqual(chatManager.currentConversation?.messages.count, 2)
        
        let userMessage = chatManager.currentConversation?.messages.first
        let assistantMessage = chatManager.currentConversation?.messages.last
        
        XCTAssertEqual(userMessage?.content, "Hello, AI!")
        XCTAssertEqual(userMessage?.role, .user)
        XCTAssertEqual(assistantMessage?.content, "Test response")
        XCTAssertEqual(assistantMessage?.role, .assistant)
        XCTAssertEqual(assistantMessage?.tokens, 30) // 10 + 20
    }
    
    func testSendMessageWithoutActiveConversation() async {
        // Given
        chatManager.currentConversation = nil
        
        // When/Then
        do {
            try await chatManager.sendMessage("Hello")
            XCTFail("Should have thrown an error")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .noActiveConversation)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessageWhenNotConnected() async throws {
        // Given
        let _ = try await chatManager.startNewConversation(title: "Test")
        chatManager.isConnected = false
        
        // When/Then
        do {
            try await chatManager.sendMessage("Hello")
            XCTFail("Should have thrown an error")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendEmptyMessage() async throws {
        // Given
        let _ = try await chatManager.startNewConversation(title: "Test")
        chatManager.isConnected = true
        
        // When/Then
        do {
            try await chatManager.sendMessage("   ")
            XCTFail("Should have thrown an error")
        } catch let error as AIChatError {
            XCTAssertEqual(error, .emptyMessage)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessageWithAIError() async throws {
        // Given
        let conversation = try await chatManager.startNewConversation(title: "Test")
        mockOllamaClient.shouldSucceedConnection = true
        mockOllamaClient.shouldFailSendMessage = true
        mockOllamaClient.sendMessageError = OllamaError.requestFailed(500)
        chatManager.isConnected = true
        
        // When/Then
        do {
            try await chatManager.sendMessage("Hello")
            XCTFail("Should have thrown an error")
        } catch {
            // Should create an error message in the conversation
            XCTAssertEqual(mockDatabaseManager.savedMessages.count, 2) // User + Error messages
            let errorMessage = chatManager.currentConversation?.messages.last
            XCTAssertTrue(errorMessage?.isError == true)
            XCTAssertEqual(errorMessage?.role, .assistant)
        }
    }
    
    // MARK: - Health Data Context Tests
    func testSelectHealthDataForContext() {
        // Given
        let dataTypes: Set<HealthDataType> = [.personalInfo, .bloodTest]
        
        // When
        chatManager.selectHealthDataForContext(dataTypes)
        
        // Then
        XCTAssertEqual(chatManager.selectedHealthDataTypes, dataTypes)
    }
    
    func testBuildHealthDataContextWithPersonalInfo() {
        // Given
        mockHealthDataManager.personalInfo = PersonalHealthInfo(
            name: "John Doe",
            dateOfBirth: Date(),
            gender: .male,
            bloodType: .oPositive
        )
        chatManager.selectHealthDataForContext([.personalInfo])
        
        // When
        let context = chatManager.buildHealthDataContextForTesting()
        
        // Then
        XCTAssertTrue(context.contains("Personal Information"))
        XCTAssertTrue(context.contains("John Doe"))
        XCTAssertTrue(context.contains("Male"))
        XCTAssertTrue(context.contains("O+"))
    }
    
    func testBuildHealthDataContextWithBloodTests() {
        // Given
        let bloodTest = BloodTestResult(
            testDate: Date(),
            laboratoryName: "Test Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL", referenceRange: "70-100", isAbnormal: false)
            ]
        )
        mockHealthDataManager.bloodTests = [bloodTest]
        chatManager.selectHealthDataForContext([.bloodTest])
        
        // When
        let context = chatManager.buildHealthDataContextForTesting()
        
        // Then
        XCTAssertTrue(context.contains("Blood Test Results"))
        XCTAssertTrue(context.contains("Test Lab"))
    }
    
    func testContextSizeEstimation() {
        // Given
        mockHealthDataManager.personalInfo = PersonalHealthInfo(name: "Test User")
        mockHealthDataManager.bloodTests = [
            BloodTestResult(testDate: Date(), results: [
                BloodTestItem(name: "Test", value: "100", unit: "mg/dL", referenceRange: "80-120", isAbnormal: false)
            ])
        ]
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        
        // When
        let (tokens, isOverLimit) = chatManager.getContextSizeEstimate()
        
        // Then
        XCTAssertGreaterThan(tokens, 0)
        XCTAssertFalse(isOverLimit) // Should be under default 4000 limit
    }
    
    func testContextSizeLimitUpdate() {
        // Given
        let newLimit = 2000
        
        // When
        chatManager.updateContextSizeLimit(newLimit)
        
        // Then
        XCTAssertEqual(chatManager.contextSizeLimit, newLimit)
    }
    
    func testContextSizeLimitBounds() {
        // Test lower bound
        chatManager.updateContextSizeLimit(500)
        XCTAssertEqual(chatManager.contextSizeLimit, 1000) // Should be clamped to minimum
        
        // Test upper bound
        chatManager.updateContextSizeLimit(10000)
        XCTAssertEqual(chatManager.contextSizeLimit, 8000) // Should be clamped to maximum
    }
    
    // MARK: - Search and Filter Tests
    func testSearchConversations() async throws {
        // Given
        mockDatabaseManager.searchResults = [
            ChatConversation(title: "Health Discussion"),
            ChatConversation(title: "Blood Test Questions")
        ]
        
        // When
        let results = try await chatManager.searchConversations("health")
        
        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(mockDatabaseManager.lastSearchQuery, "health")
    }
    
    func testFilterConversationsByDataType() {
        // Given
        chatManager.conversations = [
            ChatConversation(title: "Personal Info Chat", includedHealthDataTypes: [.personalInfo]),
            ChatConversation(title: "Blood Test Chat", includedHealthDataTypes: [.bloodTest]),
            ChatConversation(title: "Mixed Chat", includedHealthDataTypes: [.personalInfo, .bloodTest])
        ]
        
        // When
        let filtered = chatManager.filterConversationsByDataType(.bloodTest)
        
        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.includedHealthDataTypes.contains(.bloodTest) })
    }
    
    // MARK: - Statistics Tests
    func testGetChatStatistics() async throws {
        // Given
        let expectedStats = ChatStatistics(
            totalConversations: 5,
            totalMessages: 20,
            totalTokensUsed: 1000,
            averageResponseTime: 2.5,
            mostUsedDataTypes: [.personalInfo, .bloodTest],
            lastChatDate: Date()
        )
        mockDatabaseManager.mockStatistics = expectedStats
        
        // When
        let stats = try await chatManager.getChatStatistics()
        
        // Then
        XCTAssertEqual(stats.totalConversations, 5)
        XCTAssertEqual(stats.totalMessages, 20)
        XCTAssertEqual(stats.totalTokensUsed, 1000)
        XCTAssertEqual(stats.averageResponseTime, 2.5)
    }
    
    // MARK: - Offline Capabilities Tests
    func testOfflineCapabilities() {
        // When
        let capabilities = chatManager.getOfflineCapabilities()
        
        // Then
        XCTAssertTrue(capabilities.canViewConversations)
        XCTAssertTrue(capabilities.canViewMessages)
        XCTAssertFalse(capabilities.canCreateConversations)
        XCTAssertFalse(capabilities.canSendMessages)
        XCTAssertTrue(capabilities.canEditConversations)
        XCTAssertTrue(capabilities.canDeleteConversations)
    }
    
    func testOfflineActionHandling() {
        // Test successful offline actions
        let viewResult = chatManager.handleOfflineAction(.viewConversations)
        XCTAssertTrue(viewResult.isSuccess)
        
        let deleteResult = chatManager.handleOfflineAction(.deleteConversation)
        XCTAssertTrue(deleteResult.isSuccess)
        
        // Test failed offline actions
        let sendResult = chatManager.handleOfflineAction(.sendMessage)
        XCTAssertFalse(sendResult.isSuccess)
        
        let createResult = chatManager.handleOfflineAction(.createConversation)
        XCTAssertFalse(createResult.isSuccess)
    }
}

// MARK: - Mock Classes
class MockOllamaClient: OllamaClient {
    var shouldSucceedConnection = true
    var shouldFailSendMessage = false
    var connectionError: Error?
    var sendMessageError: Error?
    var mockResponse: OllamaChatResponse?
    
    override init(hostname: String = "localhost", port: Int = 11434) {
        super.init(hostname: hostname, port: port)
    }
    
    override func testConnection() async throws -> Bool {
        if shouldSucceedConnection {
            return true
        } else {
            throw connectionError ?? OllamaError.connectionFailed(500)
        }
    }
    
    override func sendChatMessage(_ message: String, context: String, model: String = "llama2") async throws -> OllamaChatResponse {
        if shouldFailSendMessage {
            throw sendMessageError ?? OllamaError.requestFailed(500)
        }
        
        return mockResponse ?? OllamaChatResponse(
            model: model,
            message: OllamaMessage(role: "assistant", content: "Mock response"),
            done: true,
            totalDuration: 1000000000,
            loadDuration: nil,
            promptEvalCount: 10,
            promptEvalDuration: nil,
            evalCount: 15,
            evalDuration: nil
        )
    }
}

class MockHealthDataManager: HealthDataManager {
    override var personalInfo: PersonalHealthInfo? {
        get { _personalInfo }
        set { _personalInfo = newValue }
    }
    
    override var bloodTests: [BloodTestResult] {
        get { _bloodTests }
        set { _bloodTests = newValue }
    }
    
    override var documents: [HealthDocument] {
        get { _documents }
        set { _documents = newValue }
    }
    
    private var _personalInfo: PersonalHealthInfo?
    private var _bloodTests: [BloodTestResult] = []
    private var _documents: [HealthDocument] = []
    
    init() {
        // Create mock dependencies
        let mockDB = try! MockDatabaseManager()
        let mockFS = MockFileSystemManager()
        super.init(databaseManager: mockDB, fileSystemManager: mockFS)
    }
}

class MockDatabaseManager: DatabaseManager {
    var savedConversations: [ChatConversation] = []
    var savedMessages: [ChatMessage] = []
    var updatedConversations: [ChatConversation] = []
    var deletedConversationIds: [UUID] = []
    var searchResults: [ChatConversation] = []
    var lastSearchQuery: String?
    var mockStatistics: ChatStatistics?
    
    override init() throws {
        // Skip actual database initialization for testing
    }
    
    override func saveConversation(_ conversation: ChatConversation) async throws {
        savedConversations.append(conversation)
    }
    
    override func addMessage(to conversationId: UUID, message: ChatMessage) async throws {
        savedMessages.append(message)
    }
    
    override func updateConversation(_ conversation: ChatConversation) async throws {
        updatedConversations.append(conversation)
    }
    
    override func deleteConversation(id: UUID) async throws {
        deletedConversationIds.append(id)
    }
    
    override func searchConversations(query: String) async throws -> [ChatConversation] {
        lastSearchQuery = query
        return searchResults
    }
    
    override func getChatStatistics() async throws -> ChatStatistics {
        return mockStatistics ?? ChatStatistics()
    }
    
    override func fetchConversations() async throws -> [ChatConversation] {
        return savedConversations
    }
}

class MockFileSystemManager: FileSystemManager {
    override init() {
        // Skip actual file system initialization for testing
    }
}