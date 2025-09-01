import Foundation

// MARK: - Chat Conversation
struct ChatConversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var includedHealthDataTypes: Set<HealthDataType>
    var isArchived: Bool
    var tags: [String]
    
    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        includedHealthDataTypes: Set<HealthDataType> = [],
        isArchived: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.includedHealthDataTypes = includedHealthDataTypes
        self.isArchived = isArchived
        self.tags = tags
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var content: String
    let role: MessageRole
    let timestamp: Date
    var metadata: [String: String]?
    var isError: Bool
    var tokens: Int?
    var processingTime: TimeInterval?
    
    init(
        id: UUID = UUID(),
        content: String,
        role: MessageRole,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil,
        isError: Bool = false,
        tokens: Int? = nil,
        processingTime: TimeInterval? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.metadata = metadata
        self.isError = isError
        self.tokens = tokens
        self.processingTime = processingTime
    }
}

// MARK: - Message Role
enum MessageRole: String, CaseIterable, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "Bison Health"
        case .system:
            return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .user:
            return "person.circle.fill"
        case .assistant:
            return "brain.head.profile"
        case .system:
            return "gear.circle.fill"
        }
    }
}

// MARK: - Chat Context
struct ChatContext: Codable {
    var personalInfo: PersonalHealthInfo?
    var bloodTests: [BloodTestResult]
    var documents: [HealthDocument]
    var selectedDataTypes: Set<HealthDataType>
    var contextSummary: String?
    var maxTokens: Int
    
    init(
        personalInfo: PersonalHealthInfo? = nil,
        bloodTests: [BloodTestResult] = [],
        documents: [HealthDocument] = [],
        selectedDataTypes: Set<HealthDataType> = [],
        contextSummary: String? = nil,
        maxTokens: Int = 4000
    ) {
        self.personalInfo = personalInfo
        self.bloodTests = bloodTests
        self.documents = documents
        self.selectedDataTypes = selectedDataTypes
        self.contextSummary = contextSummary
        self.maxTokens = maxTokens
    }
}

// MARK: - Chat Statistics
struct ChatStatistics: Codable {
    var totalConversations: Int
    var totalMessages: Int
    var totalTokensUsed: Int
    var averageResponseTime: TimeInterval
    var mostUsedDataTypes: [HealthDataType]
    var lastChatDate: Date?
    
    init(
        totalConversations: Int = 0,
        totalMessages: Int = 0,
        totalTokensUsed: Int = 0,
        averageResponseTime: TimeInterval = 0,
        mostUsedDataTypes: [HealthDataType] = [],
        lastChatDate: Date? = nil
    ) {
        self.totalConversations = totalConversations
        self.totalMessages = totalMessages
        self.totalTokensUsed = totalTokensUsed
        self.averageResponseTime = averageResponseTime
        self.mostUsedDataTypes = mostUsedDataTypes
        self.lastChatDate = lastChatDate
    }
}

// MARK: - Extensions
extension ChatConversation {
    var lastMessage: ChatMessage? {
        return messages.last
    }
    
    var messageCount: Int {
        return messages.count
    }
    
    var userMessageCount: Int {
        return messages.filter { $0.role == .user }.count
    }
    
    var assistantMessageCount: Int {
        return messages.filter { $0.role == .assistant }.count
    }
    
    var hasMessages: Bool {
        return !messages.isEmpty
    }
    
    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var formattedUpdatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }
    
    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
    }
    
    mutating func updateTitle(_ newTitle: String) {
        title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAt = Date()
    }
    
    mutating func archive() {
        isArchived = true
        updatedAt = Date()
    }
    
    mutating func unarchive() {
        isArchived = false
        updatedAt = Date()
    }
}

extension ChatMessage {
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var isFromUser: Bool {
        return role == .user
    }
    
    var isFromAssistant: Bool {
        return role == .assistant
    }
    
    var wordCount: Int {
        return content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
}

extension ChatContext {
    var isEmpty: Bool {
        return personalInfo == nil && 
               bloodTests.isEmpty && 
               documents.isEmpty
    }
    
    var estimatedTokenCount: Int {
        // Rough estimation: 1 token ≈ 4 characters
        let personalInfoTokens = personalInfo != nil ? 200 : 0
        let bloodTestTokens = bloodTests.count * 100
        let documentTokens = documents.count * 50
        
        return personalInfoTokens + bloodTestTokens + documentTokens
    }
    
    func buildContextString() -> String {
        var contextParts: [String] = []
        
        if let personalInfo = personalInfo {
            var personalContext = "Personal Information:\n"
            if let name = personalInfo.name {
                personalContext += "- Name: \(name)\n"
            }
            if let dob = personalInfo.dateOfBirth {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                personalContext += "- Date of Birth: \(formatter.string(from: dob))\n"
            }
            if let gender = personalInfo.gender {
                personalContext += "- Gender: \(gender.displayName)\n"
            }
            if let bloodType = personalInfo.bloodType {
                personalContext += "- Blood Type: \(bloodType.displayName)\n"
            }
            if !personalInfo.allergies.isEmpty {
                personalContext += "- Allergies: \(personalInfo.allergies.joined(separator: ", "))\n"
            }
            if !personalInfo.medications.isEmpty {
                personalContext += "- Current Medications: \(personalInfo.medications.map { $0.name }.joined(separator: ", "))\n"
            }
            contextParts.append(personalContext)
        }
        
        if !bloodTests.isEmpty {
            var bloodTestContext = "Recent Blood Test Results:\n"
            for test in bloodTests.prefix(3) { // Limit to most recent 3 tests
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                bloodTestContext += "- Test Date: \(formatter.string(from: test.testDate))\n"
                
                let abnormalResults = test.abnormalResults
                if !abnormalResults.isEmpty {
                    bloodTestContext += "  Abnormal Results: \(abnormalResults.map { "\($0.name): \($0.value) \($0.unit ?? "")" }.joined(separator: ", "))\n"
                }
            }
            contextParts.append(bloodTestContext)
        }
        
        if !documents.isEmpty {
            let processedDocs = documents.filter { $0.isProcessed }
            if !processedDocs.isEmpty {
                var docContext = "Available Health Documents:\n"
                for doc in processedDocs.prefix(5) { // Limit to 5 most recent documents
                    docContext += "- \(doc.fileName) (\(doc.fileType.displayName))\n"
                }
                contextParts.append(docContext)
            }
        }
        
        return contextParts.joined(separator: "\n")
    }
}