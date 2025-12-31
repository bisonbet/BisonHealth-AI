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

// MARK: - Message Status
enum MessageStatus: String, Codable {
    case sent           // Successfully sent and received response
    case pending        // Waiting to be sent
    case sending        // Currently being sent
    case failed         // Failed to send
    case retrying       // Retrying after failure

    var icon: String {
        switch self {
        case .sent: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .sending: return "arrow.up.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .retrying: return "arrow.clockwise.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .sent: return "green"
        case .pending: return "gray"
        case .sending: return "blue"
        case .failed: return "red"
        case .retrying: return "orange"
        }
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
    var status: MessageStatus?         // Status for tracking message delivery
    var retryCount: Int                // Number of retry attempts
    var lastError: String?             // Last error message if failed

    init(
        id: UUID = UUID(),
        content: String,
        role: MessageRole,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil,
        isError: Bool = false,
        tokens: Int? = nil,
        processingTime: TimeInterval? = nil,
        status: MessageStatus? = nil,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.metadata = metadata
        self.isError = isError
        self.tokens = tokens
        self.processingTime = processingTime
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
    }

    /// Check if message can be retried
    var canRetry: Bool {
        return (status == .failed || isError) && role == .user
    }

    /// Mark message as failed with error
    mutating func markFailed(error: String) {
        self.status = .failed
        self.isError = true
        self.lastError = error
    }

    /// Mark message as retrying
    mutating func markRetrying() {
        self.status = .retrying
        self.retryCount += 1
    }

    /// Mark message as sent successfully
    mutating func markSent() {
        self.status = .sent
        self.isError = false
        self.lastError = nil
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
    var medicalDocuments: [MedicalDocumentSummary]  // Medical documents selected for AI context
    var selectedDataTypes: Set<HealthDataType>
    var contextSummary: String?
    var maxTokens: Int

    init(
        personalInfo: PersonalHealthInfo? = nil,
        bloodTests: [BloodTestResult] = [],
        medicalDocuments: [MedicalDocumentSummary] = [],
        selectedDataTypes: Set<HealthDataType> = [],
        contextSummary: String? = nil,
        maxTokens: Int = 4000
    ) {
        self.personalInfo = personalInfo
        self.bloodTests = bloodTests
        self.medicalDocuments = medicalDocuments
        self.selectedDataTypes = selectedDataTypes
        self.contextSummary = contextSummary
        self.maxTokens = maxTokens
    }
}

// MARK: - Medical Document Summary for Context
/// Lightweight summary of a medical document for inclusion in chat context
struct MedicalDocumentSummary: Codable, Hashable, Equatable {
    let id: UUID
    let fileName: String
    let documentDate: Date?
    let providerName: String?
    let documentCategory: DocumentCategory
    let sections: [DocumentSection]
    let extractedText: String?
    let contextPriority: Int

    init(from medicalDocument: MedicalDocument) {
        self.id = medicalDocument.id
        self.fileName = medicalDocument.fileName
        self.documentDate = medicalDocument.documentDate
        self.providerName = medicalDocument.providerName
        self.documentCategory = medicalDocument.documentCategory
        self.sections = medicalDocument.extractedSections
        self.extractedText = medicalDocument.extractedText
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

    // Explicit Equatable conformance
    static func == (lhs: MedicalDocumentSummary, rhs: MedicalDocumentSummary) -> Bool {
        return lhs.id == rhs.id
    }

    // Explicit Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
               medicalDocuments.isEmpty
    }

    var estimatedTokenCount: Int {
        // Rough estimation: 1 token ≈ 4 characters
        let personalInfoTokens = personalInfo != nil ? 200 : 0
        
        // Only count blood tests that are marked for inclusion in the AI context
        let includedBloodTests = bloodTests.filter { $0.includeInAIContext }
        let bloodTestTokens = includedBloodTests.count * 100

        // Estimate tokens for medical documents based on sections
        var medicalDocTokens = 0
        for doc in medicalDocuments {
            medicalDocTokens += 50 // Header
            for section in doc.sections {
                medicalDocTokens += section.content.count / 4 // ~4 chars per token
            }
        }

        return personalInfoTokens + bloodTestTokens + medicalDocTokens
    }
    
    func buildContextString() -> String {
        var contextParts: [String] = []
        
        // Add current date and time for temporal context
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = TimeZone.current
        let currentDateTime = dateFormatter.string(from: now)
        contextParts.append("Current Date and Time: \(currentDateTime)\n")
        
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

                // Vitals
                if !personalInfo.bloodPressureReadings.isEmpty ||
                   !personalInfo.heartRateReadings.isEmpty ||
                   !personalInfo.bodyTemperatureReadings.isEmpty ||
                   !personalInfo.oxygenSaturationReadings.isEmpty ||
                   !personalInfo.respiratoryRateReadings.isEmpty ||
                   !personalInfo.weightReadings.isEmpty {
                    personalContext += "\n- Recent Vitals:\n"

                    if !personalInfo.bloodPressureReadings.isEmpty {
                        let recent = personalInfo.bloodPressureReadings.prefix(3)
                        personalContext += "  • Blood Pressure (last \(recent.count) readings):\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }

                    if !personalInfo.heartRateReadings.isEmpty {
                        let recent = personalInfo.heartRateReadings.prefix(3)
                        let avgBPM = recent.reduce(0.0) { $0 + $1.value } / Double(recent.count)
                        personalContext += "  • Heart Rate (last \(recent.count) readings):\n"
                        personalContext += "    - Average: \(Int(avgBPM)) bpm\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }

                    if !personalInfo.bodyTemperatureReadings.isEmpty {
                        let recent = personalInfo.bodyTemperatureReadings.prefix(3)
                        personalContext += "  • Body Temperature (last \(recent.count) readings):\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }

                    if !personalInfo.oxygenSaturationReadings.isEmpty {
                        let recent = personalInfo.oxygenSaturationReadings.prefix(3)
                        let avgO2 = recent.reduce(0.0) { $0 + $1.value } / Double(recent.count)
                        personalContext += "  • Oxygen Saturation (last \(recent.count) readings):\n"
                        personalContext += "    - Average: \(Int(avgO2))%\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }

                    if !personalInfo.respiratoryRateReadings.isEmpty {
                        let recent = personalInfo.respiratoryRateReadings.prefix(3)
                        personalContext += "  • Respiratory Rate (last \(recent.count) readings):\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }

                    if !personalInfo.weightReadings.isEmpty {
                        let recent = personalInfo.weightReadings.prefix(5)
                        personalContext += "  • Weight (last \(recent.count) readings):\n"
                        for reading in recent {
                            let dateStr = DateFormatter.mediumDate.string(from: reading.timestamp)
                            personalContext += "    - \(reading.displayValue) on \(dateStr) (\(reading.source.displayName))\n"
                        }
                    }
                }

                // Sleep Data
                if !personalInfo.sleepData.isEmpty {
                    let recentSleep = personalInfo.sleepData.prefix(7)
                    let totalSleepMinutes = recentSleep.reduce(0) { $0 + $1.totalSleepMinutes }
                    let avgSleepHours = Double(totalSleepMinutes) / Double(recentSleep.count) / 60.0

                    personalContext += "\n- Sleep Data (last \(recentSleep.count) nights):\n"
                    personalContext += "  • Average: \(String(format: "%.1f", avgSleepHours)) hours per night\n"

                    for sleep in recentSleep {
                        let dateStr = DateFormatter.mediumDate.string(from: sleep.date)
                        personalContext += "  • \(dateStr): \(sleep.displayDuration)"

                        // Add sleep stages if available
                        var stageInfo: [String] = []
                        if let deep = sleep.deepSleepMinutes {
                            stageInfo.append("Deep: \(deep)m")
                        }
                        if let rem = sleep.remSleepMinutes {
                            stageInfo.append("REM: \(rem)m")
                        }
                        if let core = sleep.coreSleepMinutes {
                            stageInfo.append("Core: \(core)m")
                        }
                        if !stageInfo.isEmpty {
                            personalContext += " [\(stageInfo.joined(separator: ", "))]"
                        }

                        personalContext += " (\(sleep.source.displayName))\n"
                    }
                }

                contextParts.append(personalContext)
            } else {
                contextParts.append("Personal Information: No data available yet\n")
            }
        }
        
        // Blood Tests - Only include selected tests
        if selectedDataTypes.contains(.bloodTest) {
            // Filter to only tests marked for AI context
            let selectedTests = bloodTests.filter { $0.includeInAIContext }

            if !selectedTests.isEmpty {
                var bloodTestContext = "Blood Test Results:\n"
                // Sort by date (newest first) and limit to prevent token overflow
                let sortedTests = selectedTests.sorted { $0.testDate > $1.testDate }.prefix(5)

                for test in sortedTests {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    bloodTestContext += "\nTest Date: \(formatter.string(from: test.testDate))\n"

                    if let lab = test.laboratoryName {
                        bloodTestContext += "Laboratory: \(lab)\n"
                    }

                    // Include only the actual result data: name, value, unit, reference range
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
                contextParts.append("Blood Test Results: No tests selected for AI context\n")
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
                medicalDocContext += "File: \(medicalDoc.fileName)\n"
                
                // Debug logging
                print("🔍 Context Build - Processing medical doc: \(medicalDoc.fileName)")
                print("🔍 Context Build -   Sections count: \(medicalDoc.sections.count)")
                print("🔍 Context Build -   Extracted text length: \(medicalDoc.extractedText?.count ?? 0)")
                print("🔍 Context Build -   Extracted text is nil: \(medicalDoc.extractedText == nil)")

                // Only include extracted sections (NOT full text to save tokens)
                if !medicalDoc.sections.isEmpty {
                    print("🔍 Context Build -   Using sections for context")
                    for section in medicalDoc.sections {
                        medicalDocContext += "\n\(section.sectionType):\n"
                        // Limit section content to prevent token overflow (max 500 chars per section)
                        // Truncate at word boundaries to avoid cutting mid-word
                        let sectionContent: String
                        if section.content.count > 500 {
                            let truncated = section.content.prefix(500)
                            if let lastSpace = truncated.lastIndex(of: " ") {
                                sectionContent = String(section.content[..<lastSpace]) + "..."
                            } else {
                                sectionContent = String(truncated) + "..."
                            }
                        } else {
                            sectionContent = section.content
                        }
                        medicalDocContext += "\(sectionContent)\n"
                    }
                } else {
                    print("⚠️ Context Build -   No sections available for document")
                    medicalDocContext += "\n(No structured content available - please ensure document has been processed)\n"
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

    // MARK: - JSON Context Building

    /// Builds JSON formatted context string for AI providers
    /// - Returns: JSON string with structured health data, falls back to plain text on error
    func buildContextJSON() -> String {
        do {
            let jsonDict = HealthContextJSON.buildContextJSON(from: self)
            let data = try JSONSerialization.data(
                withJSONObject: jsonDict,
                options: [.prettyPrinted, .sortedKeys]
            )
            guard let jsonString = String(data: data, encoding: .utf8) else {
                print("⚠️ Failed to convert JSON data to string, falling back to plain text")
                return buildContextString()
            }
            return jsonString
        } catch {
            print("⚠️ JSON serialization error: \(error), falling back to plain text")
            return buildContextString()
        }
    }

    /// Estimated token count for JSON context (more efficient than plain text)
    var estimatedTokenCountJSON: Int {
        // JSON is more compact, approximately 1 token per 4 characters
        return buildContextJSON().count / 4
    }

    // MARK: - Helper Functions
    /// Cleans markdown text by removing base64 image data for AI context
    private func cleanMarkdownForContext(_ markdown: String) -> String {
        var cleaned = markdown
        
        // Remove base64 image references: ![Image](data:image/...)
        let imagePattern = #"!\[[^\]]*\]\(data:image/[^)]+\)"#
        cleaned = cleaned.replacingOccurrences(
            of: imagePattern,
            with: "",
            options: [.regularExpression]
        )
        
        // Remove standalone base64 data URLs
        let dataUrlPattern = #"data:image/[^;]+;base64,[A-Za-z0-9+/=]+"#
        cleaned = cleaned.replacingOccurrences(
            of: dataUrlPattern,
            with: "[Image removed]",
            options: [.regularExpression]
        )
        
        // Clean up multiple consecutive newlines
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: [.regularExpression]
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}