import XCTest
@testable import HealthApp

@MainActor
final class ChatIntegrationTests: XCTestCase {
    
    var chatManager: AIChatManager!
    var healthDataManager: HealthDataManager!
    var databaseManager: DatabaseManager!
    var fileSystemManager: FileSystemManager!
    var ollamaClient: OllamaClient!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test database in memory
        databaseManager = try DatabaseManager(inMemory: true)
        fileSystemManager = FileSystemManager()
        
        // Create health data manager with test data
        healthDataManager = HealthDataManager(
            databaseManager: databaseManager,
            fileSystemManager: fileSystemManager
        )
        
        // Create Ollama client (will use mock server in tests)
        ollamaClient = OllamaClient(hostname: "localhost", port: 11434)
        
        // Create chat manager
        chatManager = AIChatManager(
            ollamaClient: ollamaClient,
            healthDataManager: healthDataManager,
            databaseManager: databaseManager
        )
        
        // Set up test health data
        try await setupTestHealthData()
    }
    
    override func tearDown() async throws {
        chatManager = nil
        healthDataManager = nil
        databaseManager = nil
        fileSystemManager = nil
        ollamaClient = nil
        try await super.tearDown()
    }
    
    // MARK: - Setup Helper
    private func setupTestHealthData() async throws {
        // Create test personal info
        let personalInfo = PersonalHealthInfo(
            name: "John Doe",
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: Date()),
            gender: .male,
            height: Measurement(value: 180, unit: .centimeters),
            weight: Measurement(value: 75, unit: .kilograms),
            bloodType: .oPositive,
            allergies: ["Peanuts", "Shellfish"],
            medications: [
                Medication(name: "Lisinopril"),
                Medication(name: "Metformin")
            ],
            personalMedicalHistory: [
                MedicalCondition(name: "Hypertension", diagnosedDate: Date(), status: .active),
                MedicalCondition(name: "Type 2 Diabetes", diagnosedDate: Date(), status: .active)
            ],
        )
        
        try await healthDataManager.savePersonalInfo(personalInfo)
        
        // Create test blood test results
        let bloodTest1 = BloodTestResult(
            testDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            laboratoryName: "City Medical Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "95", unit: "mg/dL", referenceRange: "70-100", isAbnormal: false),
                BloodTestItem(name: "HbA1c", value: "6.8", unit: "%", referenceRange: "<7.0", isAbnormal: false),
                BloodTestItem(name: "Total Cholesterol", value: "220", unit: "mg/dL", referenceRange: "<200", isAbnormal: true),
                BloodTestItem(name: "HDL Cholesterol", value: "45", unit: "mg/dL", referenceRange: ">40", isAbnormal: false),
                BloodTestItem(name: "LDL Cholesterol", value: "150", unit: "mg/dL", referenceRange: "<100", isAbnormal: true)
            ]
        )
        
        let bloodTest2 = BloodTestResult(
            testDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            laboratoryName: "City Medical Lab",
            results: [
                BloodTestItem(name: "Glucose", value: "102", unit: "mg/dL", referenceRange: "70-100", isAbnormal: true),
                BloodTestItem(name: "HbA1c", value: "7.2", unit: "%", referenceRange: "<7.0", isAbnormal: true),
                BloodTestItem(name: "Creatinine", value: "1.1", unit: "mg/dL", referenceRange: "0.7-1.3", isAbnormal: false)
            ]
        )
        
        try await healthDataManager.addBloodTest(bloodTest1)
        try await healthDataManager.addBloodTest(bloodTest2)
    }
    
    // MARK: - Full Conversation Flow Tests
    func testCompleteConversationFlow() async throws {
        // Test creating a new conversation
        let conversation = try await chatManager.startNewConversation(title: "Health Discussion")
        XCTAssertNotNil(chatManager.currentConversation)
        XCTAssertEqual(chatManager.conversations.count, 1)
        
        // Test selecting health data for context
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        XCTAssertEqual(chatManager.selectedHealthDataTypes.count, 2)
        
        // Test context building
        let (tokens, isOverLimit) = chatManager.getContextSizeEstimate()
        XCTAssertGreaterThan(tokens, 0)
        XCTAssertFalse(isOverLimit)
        
        // Verify conversation was saved to database
        let savedConversations = try await databaseManager.fetchConversations()
        XCTAssertEqual(savedConversations.count, 1)
        XCTAssertEqual(savedConversations.first?.title, "Health Discussion")
    }
    
    func testHealthDataContextBuilding() async throws {
        // Given: Set up conversation with health data context
        let _ = try await chatManager.startNewConversation(title: "Context Test")
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        
        // When: Build context (using testing method)
        let context = chatManager.buildHealthDataContextForTesting()
        
        // Then: Verify context contains expected health data
        XCTAssertTrue(context.contains("Personal Information"))
        XCTAssertTrue(context.contains("John Doe"))
        XCTAssertTrue(context.contains("Male"))
        XCTAssertTrue(context.contains("O+"))
        XCTAssertTrue(context.contains("Hypertension"))
        XCTAssertTrue(context.contains("Type 2 Diabetes"))
        XCTAssertTrue(context.contains("Peanuts"))
        XCTAssertTrue(context.contains("Lisinopril"))
        
        XCTAssertTrue(context.contains("Blood Test Results"))
        XCTAssertTrue(context.contains("City Medical Lab"))
        XCTAssertTrue(context.contains("Glucose"))
        XCTAssertTrue(context.contains("HbA1c"))
        XCTAssertTrue(context.contains("Total Cholesterol"))
    }
    
    func testContextSizeOptimization() async throws {
        // Given: Create conversation with all data types
        let _ = try await chatManager.startNewConversation(title: "Large Context Test")
        chatManager.selectHealthDataForContext(Set(HealthDataType.allCases))
        
        // When: Set a very small context limit
        chatManager.updateContextSizeLimit(1000)
        
        // Then: Context should be compressed when built
        let (tokens, isOverLimit) = chatManager.getContextSizeEstimate()
        
        // The context should still be buildable even if it exceeds the limit
        let context = chatManager.buildHealthDataContext()
        XCTAssertFalse(context.isEmpty)
        
        // If over limit, context should contain truncation notice
        if isOverLimit {
            XCTAssertTrue(context.contains("truncated") || context.contains("additional"))
        }
    }
    
    func testConversationPersistence() async throws {
        // Create and save multiple conversations
        let conv1 = try await chatManager.startNewConversation(title: "First Chat")
        chatManager.selectHealthDataForContext([.personalInfo])
        
        let conv2 = try await chatManager.startNewConversation(title: "Second Chat")
        chatManager.selectHealthDataForContext([.bloodTest])
        
        let conv3 = try await chatManager.startNewConversation(title: "Third Chat")
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        
        // Verify all conversations are saved
        XCTAssertEqual(chatManager.conversations.count, 3)
        
        // Reload conversations from database
        await chatManager.loadConversations()
        
        // Verify conversations are loaded correctly
        XCTAssertEqual(chatManager.conversations.count, 3)
        
        let titles = chatManager.conversations.map { $0.title }
        XCTAssertTrue(titles.contains("First Chat"))
        XCTAssertTrue(titles.contains("Second Chat"))
        XCTAssertTrue(titles.contains("Third Chat"))
        
        // Verify health data types are preserved
        let firstChat = chatManager.conversations.first { $0.title == "First Chat" }
        XCTAssertEqual(firstChat?.includedHealthDataTypes, [.personalInfo])
        
        let secondChat = chatManager.conversations.first { $0.title == "Second Chat" }
        XCTAssertEqual(secondChat?.includedHealthDataTypes, [.bloodTest])
        
        let thirdChat = chatManager.conversations.first { $0.title == "Third Chat" }
        XCTAssertEqual(thirdChat?.includedHealthDataTypes, [.personalInfo, .bloodTest])
    }
    
    func testConversationArchiving() async throws {
        // Create a conversation
        let conversation = try await chatManager.startNewConversation(title: "To Archive")
        XCTAssertEqual(chatManager.conversations.count, 1)
        
        // Archive the conversation
        try await chatManager.archiveConversation(conversation)
        
        // Verify conversation is no longer in active list
        XCTAssertNil(chatManager.currentConversation)
        
        // Verify conversation is marked as archived in database
        let archivedConversations = try await databaseManager.fetchArchivedConversations()
        XCTAssertEqual(archivedConversations.count, 1)
        XCTAssertTrue(archivedConversations.first?.isArchived == true)
    }
    
    func testConversationSearch() async throws {
        // Create conversations with different titles
        try await chatManager.startNewConversation(title: "Blood Pressure Discussion")
        try await chatManager.startNewConversation(title: "Diabetes Management")
        try await chatManager.startNewConversation(title: "General Health Questions")
        try await chatManager.startNewConversation(title: "Medication Review")
        
        // Test search functionality
        let bloodResults = try await chatManager.searchConversations("blood")
        XCTAssertEqual(bloodResults.count, 1)
        XCTAssertEqual(bloodResults.first?.title, "Blood Pressure Discussion")
        
        let healthResults = try await chatManager.searchConversations("health")
        XCTAssertEqual(healthResults.count, 1)
        XCTAssertEqual(healthResults.first?.title, "General Health Questions")
        
        let emptyResults = try await chatManager.searchConversations("xyz")
        XCTAssertEqual(emptyResults.count, 0)
    }
    
    func testConversationFiltering() async throws {
        // Create conversations with different data types
        let conv1 = try await chatManager.startNewConversation(title: "Personal Info Only")
        chatManager.selectHealthDataForContext([.personalInfo])
        
        let conv2 = try await chatManager.startNewConversation(title: "Blood Tests Only")
        chatManager.selectHealthDataForContext([.bloodTest])
        
        let conv3 = try await chatManager.startNewConversation(title: "Mixed Data")
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        
        // Test filtering by data type
        let personalInfoConversations = chatManager.filterConversationsByDataType(.personalInfo)
        XCTAssertEqual(personalInfoConversations.count, 2) // conv1 and conv3
        
        let bloodTestConversations = chatManager.filterConversationsByDataType(.bloodTest)
        XCTAssertEqual(bloodTestConversations.count, 2) // conv2 and conv3
        
        let imagingConversations = chatManager.filterConversationsByDataType(.imagingReport)
        XCTAssertEqual(imagingConversations.count, 0)
    }
    
    func testHealthDataUpdatesReflectedInContext() async throws {
        // Create conversation with personal info context
        let _ = try await chatManager.startNewConversation(title: "Context Update Test")
        chatManager.selectHealthDataForContext([.personalInfo])
        
        // Get initial context
        let initialContext = chatManager.buildHealthDataContextForTesting()
        XCTAssertTrue(initialContext.contains("John Doe"))
        
        // Update personal info
        var updatedPersonalInfo = healthDataManager.personalInfo!
        updatedPersonalInfo.name = "Jane Smith"
        try await healthDataManager.savePersonalInfo(updatedPersonalInfo)
        
        // Get updated context
        let updatedContext = chatManager.buildHealthDataContextForTesting()
        XCTAssertTrue(updatedContext.contains("Jane Smith"))
        XCTAssertFalse(updatedContext.contains("John Doe"))
    }
    
    func testOfflineGracefulDegradation() async throws {
        // Create conversation while online
        let conversation = try await chatManager.startNewConversation(title: "Offline Test")
        XCTAssertNotNil(chatManager.currentConversation)
        
        // Simulate going offline
        chatManager.isOffline = true
        chatManager.isConnected = false
        
        // Test offline capabilities
        let capabilities = chatManager.getOfflineCapabilities()
        XCTAssertTrue(capabilities.canViewConversations)
        XCTAssertTrue(capabilities.canViewMessages)
        XCTAssertFalse(capabilities.canSendMessages)
        
        // Test offline actions
        let viewResult = chatManager.handleOfflineAction(.viewConversations)
        XCTAssertTrue(viewResult.isSuccess)
        
        let sendResult = chatManager.handleOfflineAction(.sendMessage)
        XCTAssertFalse(sendResult.isSuccess)
        XCTAssertTrue(sendResult.message.contains("offline"))
        
        // Verify conversations are still accessible
        await chatManager.loadConversations()
        XCTAssertEqual(chatManager.conversations.count, 1)
        
        // Verify conversation can still be selected and viewed
        chatManager.selectConversation(conversation)
        XCTAssertEqual(chatManager.currentConversation?.id, conversation.id)
    }
    
    func testChatStatisticsAccuracy() async throws {
        // Create multiple conversations with messages
        let conv1 = try await chatManager.startNewConversation(title: "Stats Test 1")
        let conv2 = try await chatManager.startNewConversation(title: "Stats Test 2")
        
        // Add some mock messages to test statistics
        let message1 = ChatMessage(content: "Hello", role: .user)
        let message2 = ChatMessage(content: "Hi there", role: .assistant, tokens: 50, processingTime: 1.5)
        let message3 = ChatMessage(content: "How are you?", role: .user)
        let message4 = ChatMessage(content: "I'm doing well", role: .assistant, tokens: 75, processingTime: 2.0)
        
        try await databaseManager.addMessage(to: conv1.id, message: message1)
        try await databaseManager.addMessage(to: conv1.id, message: message2)
        try await databaseManager.addMessage(to: conv2.id, message: message3)
        try await databaseManager.addMessage(to: conv2.id, message: message4)
        
        // Get statistics
        let stats = try await chatManager.getChatStatistics()
        
        // Verify statistics
        XCTAssertEqual(stats.totalConversations, 2)
        XCTAssertEqual(stats.totalMessages, 4)
        XCTAssertEqual(stats.totalTokensUsed, 125) // 50 + 75
        XCTAssertEqual(stats.averageResponseTime, 1.75) // (1.5 + 2.0) / 2
        XCTAssertNotNil(stats.lastChatDate)
    }
    
    // MARK: - Performance Tests
    func testLargeContextPerformance() async throws {
        // Create a large amount of test data
        for i in 0..<50 {
            let bloodTest = BloodTestResult(
                testDate: Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date(),
                laboratoryName: "Test Lab \(i)",
                results: [
                    BloodTestItem(name: "Test \(i)", value: "\(100 + i)", unit: "mg/dL", referenceRange: "80-120", isAbnormal: false)
                ]
            )
            try await healthDataManager.addBloodTest(bloodTest)
        }
        
        // Create conversation with all data
        let _ = try await chatManager.startNewConversation(title: "Performance Test")
        chatManager.selectHealthDataForContext([.personalInfo, .bloodTest])
        
        // Measure context building performance
        let startTime = Date()
        let context = chatManager.buildHealthDataContextForTesting()
        let endTime = Date()
        
        let buildTime = endTime.timeIntervalSince(startTime)
        
        // Context should be built quickly (under 1 second for reasonable data sizes)
        XCTAssertLessThan(buildTime, 1.0)
        XCTAssertFalse(context.isEmpty)
        
        // Context should be compressed if too large
        let (tokens, isOverLimit) = chatManager.getContextSizeEstimate()
        if isOverLimit {
            XCTAssertTrue(context.contains("truncated") || context.count < 10000)
        }
    }
    
    func testMemoryUsageWithManyConversations() async throws {
        // Create many conversations to test memory usage
        for i in 0..<100 {
            let _ = try await chatManager.startNewConversation(title: "Conversation \(i)")
        }
        
        // Verify all conversations are created
        XCTAssertEqual(chatManager.conversations.count, 100)
        
        // Load conversations from database
        await chatManager.loadConversations()
        
        // Verify conversations are loaded efficiently
        XCTAssertEqual(chatManager.conversations.count, 100)
        
        // Memory usage should be reasonable (this is more of a manual check)
        // In a real test, you might use memory profiling tools
    }
}

// MARK: - Test Extensions
extension DatabaseManager {
    convenience init(inMemory: Bool) throws {
        if inMemory {
            // Create in-memory database for testing
            try self.init(databasePath: ":memory:")
        } else {
            try self.init()
        }
    }
}