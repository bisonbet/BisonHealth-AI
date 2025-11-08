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
            return "BisonHealth AI"
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
    var medicalDocuments: [MedicalDocumentSummary]  // Medical documents selected for AI context
    var selectedDataTypes: Set<HealthDataType>
    var contextSummary: String?
    var maxTokens: Int

    init(
        personalInfo: PersonalHealthInfo? = nil,
        bloodTests: [BloodTestResult] = [],
        documents: [HealthDocument] = [],
        medicalDocuments: [MedicalDocumentSummary] = [],
        selectedDataTypes: Set<HealthDataType> = [],
        contextSummary: String? = nil,
        maxTokens: Int = 4000
    ) {
        self.personalInfo = personalInfo
        self.bloodTests = bloodTests
        self.documents = documents
        self.medicalDocuments = medicalDocuments
        self.selectedDataTypes = selectedDataTypes
        self.contextSummary = contextSummary
        self.maxTokens = maxTokens
    }
}

// MARK: - Medical Document Summary for Context
/// Lightweight summary of a medical document for inclusion in chat context
struct MedicalDocumentSummary: Codable, Hashable {
    let id: UUID
    let documentDate: Date?
    let providerName: String?
    let documentCategory: DocumentCategory
    let sections: [DocumentSection]
    let contextPriority: Int

    init(from medicalDocument: MedicalDocument) {
        self.id = medicalDocument.id
        self.documentDate = medicalDocument.documentDate
        self.providerName = medicalDocument.providerName
        self.documentCategory = medicalDocument.documentCategory
        self.sections = medicalDocument.extractedSections
        self.contextPriority = medicalDocument.contextPriority
    }

    var formattedHeader: String {
        var header = "[\(documentCategory.displayName)"

        if let date = documentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            header += " from \(formatter.string(from: date))"
        }

        if let provider = providerName {
            header += " - \(provider)"
        }

        header += "]"
        return header
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
               documents.isEmpty &&
               medicalDocuments.isEmpty
    }

    var estimatedTokenCount: Int {
        // Rough estimation: 1 token ≈ 4 characters
        let personalInfoTokens = personalInfo != nil ? 200 : 0
        let bloodTestTokens = bloodTests.count * 100
        let documentTokens = documents.count * 50

        // Estimate tokens for medical documents based on sections
        var medicalDocTokens = 0
        for doc in medicalDocuments {
            medicalDocTokens += 50 // Header
            for section in doc.sections {
                medicalDocTokens += section.content.count / 4 // ~4 chars per token
            }
        }

        return personalInfoTokens + bloodTestTokens + documentTokens + medicalDocTokens
    }
    
    func buildContextString() -> String {
        var contextParts: [String] = []
        
        // Add header indicating what context types were requested
        if !selectedDataTypes.isEmpty {
            let selectedTypesText = selectedDataTypes.map { $0.displayName }.joined(separator: ", ")
            contextParts.append("=== Health Context for: \(selectedTypesText) ===\n")
        }
        
        // Personal Information
        if selectedDataTypes.contains(.personalInfo) {
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
                    personalContext += "- Current Medications:\n"
                    for medication in personalInfo.medications {
                        personalContext += "  • \(medication.name)"
                        personalContext += " - \(medication.dosage.displayText), \(medication.frequency.displayName)"

                        if let prescribedBy = medication.prescribedBy, !prescribedBy.isEmpty {
                            personalContext += " (prescribed by \(prescribedBy))"
                        }

                        if let startDate = medication.startDate {
                            let startDateString = DateFormatter.mediumDate.string(from: startDate)
                            personalContext += " [started: \(startDateString)"

                            if let endDate = medication.endDate {
                                personalContext += ", \(endDate.displayText.lowercased())"
                            } else {
                                personalContext += ", ongoing"
                            }
                            personalContext += "]"
                        } else if let endDate = medication.endDate {
                            personalContext += " [\(endDate.displayText.lowercased())]"
                        }

                        if let notes = medication.notes, !notes.isEmpty {
                            personalContext += " (Notes: \(notes))"
                        }
                        personalContext += "\n"
                    }
                }

                if !personalInfo.personalMedicalHistory.isEmpty {
                    personalContext += "- Personal Medical History:\n"
                    for condition in personalInfo.personalMedicalHistory {
                        personalContext += "  • \(condition.name)"
                        personalContext += " - \(condition.status.displayName)"

                        if let severity = condition.severity {
                            personalContext += " (\(severity.displayName))"
                        }

                        if let diagnosedDate = condition.diagnosedDate {
                            let diagnosedDateString = DateFormatter.mediumDate.string(from: diagnosedDate)
                            personalContext += " [diagnosed: \(diagnosedDateString)]"
                        }

                        if let treatingPhysician = condition.treatingPhysician, !treatingPhysician.isEmpty {
                            personalContext += " (treating physician: \(treatingPhysician))"
                        }

                        if let notes = condition.notes, !notes.isEmpty {
                            personalContext += " (Notes: \(notes))"
                        }
                        personalContext += "\n"
                    }
                }

                contextParts.append(personalContext)
            } else {
                contextParts.append("Personal Information: No data available yet\n")
            }
        }
        
        // Blood Tests
        if selectedDataTypes.contains(.bloodTest) {
            if !bloodTests.isEmpty {
                var bloodTestContext = "Blood Test Results:\n"
                for test in bloodTests.prefix(3) { // Limit to most recent 3 tests
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    bloodTestContext += "\nTest Date: \(formatter.string(from: test.testDate))\n"

                    if let lab = test.laboratoryName {
                        bloodTestContext += "Laboratory: \(lab)\n"
                    }

                    // Include ALL results, not just abnormal ones
                    if !test.results.isEmpty {
                        bloodTestContext += "Results:\n"
                        for result in test.results {
                            var resultLine = "  - \(result.name): \(result.value)"
                            if let unit = result.unit {
                                resultLine += " \(unit)"
                            }
                            if let range = result.referenceRange {
                                resultLine += " (ref: \(range))"
                            }
                            if result.isAbnormal {
                                resultLine += " [ABNORMAL]"
                            }
                            bloodTestContext += resultLine + "\n"
                        }
                    }
                }
                contextParts.append(bloodTestContext)
            } else {
                contextParts.append("Blood Test Results: No data available yet\n")
            }
        }
        
        // Documents
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

        // Medical Documents (selected for AI context)
        if !medicalDocuments.isEmpty {
            var medicalDocContext = "\nMedical Documents:\n"

            // Sort by priority (highest first) and date (newest first)
            let sortedDocs = medicalDocuments.sorted { doc1, doc2 in
                if doc1.contextPriority != doc2.contextPriority {
                    return doc1.contextPriority > doc2.contextPriority
                }
                guard let date1 = doc1.documentDate, let date2 = doc2.documentDate else {
                    return doc1.documentDate != nil
                }
                return date1 > date2
            }

            for medicalDoc in sortedDocs {
                medicalDocContext += "\n\(medicalDoc.formattedHeader)\n"

                // Include extracted sections
                if !medicalDoc.sections.isEmpty {
                    for section in medicalDoc.sections {
                        medicalDocContext += "\n\(section.sectionType):\n"
                        medicalDocContext += "\(section.content)\n"
                    }
                }
            }

            contextParts.append(medicalDocContext)
        }

        // If no context parts were added but types were selected, provide feedback
        if contextParts.isEmpty && !selectedDataTypes.isEmpty {
            contextParts.append("Health context types were selected but no data is available yet. Please add health data to your profile.")
        }

        return contextParts.joined(separator: "\n")
    }
}