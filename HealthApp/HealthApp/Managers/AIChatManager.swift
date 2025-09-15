import Foundation
import SwiftUI
import Network

// MARK: - AI Chat Manager
@MainActor
class AIChatManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var conversations: [ChatConversation] = []
    @Published var currentConversation: ChatConversation?
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedHealthDataTypes: Set<HealthDataType> = []
    @Published var contextSizeLimit: Int = 4000
    @Published var isOffline: Bool = false
    
    // MARK: - Dependencies
    private let healthDataManager: HealthDataManager
    private let databaseManager: DatabaseManager
    private let networkMonitor: NetworkMonitor
    private let settingsManager = SettingsManager.shared
    
    // MARK: - Context Management
    private var currentContext: ChatContext = ChatContext()
    private let maxContextTokens = 4000
    private let contextCompressionThreshold = 3500
    
    // MARK: - Initialization
    init(
        healthDataManager: HealthDataManager,
        databaseManager: DatabaseManager
    ) {
        self.healthDataManager = healthDataManager
        self.databaseManager = databaseManager
        self.networkMonitor = NetworkMonitor()
        
        setupNetworkMonitoring()
        
        Task {
            await loadConversations()
            // Don't automatically test connection on startup to avoid noisy failures
            // User can test manually via Settings if needed
        }
    }
    
    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        networkMonitor.onNetworkStatusChanged = { [weak self] isConnected in
            Task { @MainActor in
                self?.isOffline = !isConnected
                if isConnected {
                    // Only check connection if user has explicitly interacted with chat
                    // This prevents noisy connection attempts when network comes back
                    if self?.conversations.isEmpty == false {
                        await self?.checkConnection()
                    }
                } else {
                    self?.isConnected = false
                }
            }
        }
        networkMonitor.startMonitoring()
    }
    
    // MARK: - Connection Management
    
    private func getOllamaClient() -> OllamaClient {
        return settingsManager.getOllamaClient()
    }
    
    func checkConnection() async {
        guard !isOffline else {
            isConnected = false
            return
        }
        
        do {
            let ollamaClient = getOllamaClient()
            isConnected = try await ollamaClient.testConnection()
        } catch {
            isConnected = false
            errorMessage = "Failed to connect to AI service: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Conversation Management
    func loadConversations() async {
        do {
            conversations = try await databaseManager.fetchConversations()
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }
    
    func startNewConversation(title: String? = nil) async throws -> ChatConversation {
        let conversationTitle = title ?? "New Conversation"
        let conversation = ChatConversation(
            title: conversationTitle,
            includedHealthDataTypes: selectedHealthDataTypes
        )
        
        try await databaseManager.saveConversation(conversation)
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        
        return conversation
    }
    
    func selectConversation(_ conversation: ChatConversation) {
        currentConversation = conversation
        selectedHealthDataTypes = conversation.includedHealthDataTypes
        updateHealthDataContext()
    }
    
    func deleteConversation(_ conversation: ChatConversation) async throws {
        try await databaseManager.deleteConversation(conversation)
        conversations.removeAll { $0.id == conversation.id }
        
        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
    }
    
    func archiveConversation(_ conversation: ChatConversation) async throws {
        var updatedConversation = conversation
        updatedConversation.archive()
        
        try await databaseManager.updateConversation(updatedConversation)
        
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = updatedConversation
        }
        
        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
    }
    
    func clearConversationMessages(_ conversation: ChatConversation) async throws {
        // Clear all messages from the conversation
        try await databaseManager.clearConversationMessages(conversation.id)
        
        // Update the local conversation object
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].messages.removeAll()
        }
        
        // Update current conversation if it's the one being cleared
        if currentConversation?.id == conversation.id {
            currentConversation?.messages.removeAll()
        }
    }
    
    // MARK: - Message Management
    func sendMessage(_ content: String, useStreaming: Bool = true) async throws {
        guard let conversation = currentConversation else {
            throw AIChatError.noActiveConversation
        }
        
        guard !isOffline else {
            throw AIChatError.notConnected
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIChatError.emptyMessage
        }
        
        isLoading = true
        errorMessage = nil
        
        // Create user message
        let userMessage = ChatMessage(
            content: content,
            role: .user
        )
        
        do {
            // Add user message to conversation
            try await databaseManager.addMessage(to: conversation.id, message: userMessage)
            
            // Update local conversation
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index].addMessage(userMessage)
                currentConversation = conversations[index]
            }
            
            // Build health data context
            let healthContext = buildHealthDataContext()
            
            if useStreaming {
                // Use streaming for real-time response
                try await sendStreamingMessage(content, context: healthContext, conversationId: conversation.id)
            } else {
                // Use non-streaming for complete response
                try await sendNonStreamingMessage(content, context: healthContext, conversationId: conversation.id)
            }
            
        } catch {
            // Create error message
            let errorMessage = ChatMessage(
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                role: .assistant,
                isError: true
            )
            
            try await databaseManager.addMessage(to: conversation.id, message: errorMessage)
            
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index].addMessage(errorMessage)
                currentConversation = conversations[index]
            }
            
            throw error
        }
        
        isLoading = false
    }
    
    private func sendStreamingMessage(_ content: String, context: String, conversationId: UUID) async throws {
        // Create a placeholder message for streaming content
        let streamingMessageId = UUID()
        var streamingMessage = ChatMessage(
            id: streamingMessageId,
            content: "",
            role: .assistant
        )
        
        // Add placeholder message to conversation
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].addMessage(streamingMessage)
            currentConversation = conversations[index]
        }
        
        let ollamaClient = getOllamaClient()
        try await ollamaClient.sendStreamingChatMessage(
            content,
            context: context,
            model: settingsManager.modelPreferences.chatModel,
            onUpdate: { [weak self] partialContent in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    // Update the streaming message content
                    streamingMessage.content = partialContent
                    
                    // Update in conversation
                    if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }),
                       let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == streamingMessageId }) {
                        self.conversations[conversationIndex].messages[messageIndex] = streamingMessage
                        self.currentConversation = self.conversations[conversationIndex]
                    }
                }
            },
            onComplete: { [weak self] finalResponse in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    // Create final message with complete content and metadata
                    let finalMessage = ChatMessage(
                        id: streamingMessageId,
                        content: finalResponse.content,
                        role: .assistant,
                        tokens: finalResponse.tokenCount,
                        processingTime: finalResponse.responseTime
                    )
                    
                    // Save final message to database
                    do {
                        try await self.databaseManager.addMessage(to: conversationId, message: finalMessage)
                        
                        // Update local conversation with final message
                        if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }),
                           let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == streamingMessageId }) {
                            self.conversations[conversationIndex].messages[messageIndex] = finalMessage
                            self.currentConversation = self.conversations[conversationIndex]
                        }
                    } catch {
                        self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                    }
                }
            }
        )
    }
    
    private func sendNonStreamingMessage(_ content: String, context: String, conversationId: UUID) async throws {
        // Send to AI service
        let startTime = Date()
        let ollamaClient = getOllamaClient()
        let response = try await ollamaClient.sendChatMessage(
            content,
            context: context,
            model: settingsManager.modelPreferences.chatModel
        )
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Create assistant message
        let assistantMessage = ChatMessage(
            content: response.content,
            role: .assistant,
            tokens: response.tokenCount,
            processingTime: processingTime
        )
        
        // Save assistant message
        try await databaseManager.addMessage(to: conversationId, message: assistantMessage)
        
        // Update local conversation
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].addMessage(assistantMessage)
            currentConversation = conversations[index]
        }
    }
    
    // MARK: - Health Data Context Management
    func selectHealthDataForContext(_ types: Set<HealthDataType>) {
        print("🎯 Context Selection - Selected types: \(types)")
        print("🎯 Context Selection - Previous types: \(selectedHealthDataTypes)")
        
        selectedHealthDataTypes = types
        updateHealthDataContext()
        
        print("🎯 Context Selection - After update, selectedHealthDataTypes: \(selectedHealthDataTypes)")
        
        // Update current conversation's included data types
        if var conversation = currentConversation {
            conversation.includedHealthDataTypes = types
            print("🎯 Context Selection - Updating conversation: \(conversation.title)")
            Task {
                try await databaseManager.updateConversation(conversation)
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                    conversations[index] = conversation
                }
                print("🎯 Context Selection - Conversation updated in database")
            }
        } else {
            print("🎯 Context Selection - No current conversation to update")
        }
    }
    
    private func updateHealthDataContext() {
        currentContext = ChatContext(
            personalInfo: selectedHealthDataTypes.contains(.personalInfo) ? healthDataManager.personalInfo : nil,
            bloodTests: selectedHealthDataTypes.contains(.bloodTest) ? healthDataManager.bloodTests : [],
            documents: healthDataManager.documents.filter { doc in
                doc.extractedData.contains { data in
                    selectedHealthDataTypes.contains(data.type)
                }
            },
            selectedDataTypes: selectedHealthDataTypes,
            maxTokens: contextSizeLimit
        )
    }
    
    private func buildHealthDataContext() -> String {
        updateHealthDataContext()
        
        let contextString = currentContext.buildContextString()
        let estimatedTokens = currentContext.estimatedTokenCount
        
        print("🔍 Context Debug - Selected types: \(selectedHealthDataTypes.map { $0.displayName })")
        print("🔍 Context Debug - Personal info exists: \(currentContext.personalInfo != nil)")
        print("🔍 Context Debug - Blood tests count: \(currentContext.bloodTests.count)")
        print("🔍 Context Debug - Documents count: \(currentContext.documents.count)")
        print("🔍 Context Debug - Context string length: \(contextString.count) characters")
        print("🔍 Context Debug - Estimated tokens: \(estimatedTokens)")
        
        if contextString.isEmpty {
            print("⚠️ Context Debug - WARNING: Context string is empty!")
            print("⚠️ Context Debug - This may indicate no data types were selected or no data is available")
        } else {
            print("🔍 Context Debug - Context preview: \(String(contextString.prefix(500)))")
        }
        
        // If context is too large, compress it
        if estimatedTokens > contextCompressionThreshold {
            print("🔍 Context Debug - Compressing context (tokens: \(estimatedTokens) > threshold: \(contextCompressionThreshold))")
            return compressHealthDataContext(contextString)
        }
        
        return contextString
    }
    
    private func compressHealthDataContext(_ context: String) -> String {
        // Simple compression strategy: truncate and summarize
        let lines = context.components(separatedBy: .newlines)
        let maxLines = min(lines.count, 50) // Limit to 50 lines
        
        var compressedLines = Array(lines.prefix(maxLines))
        
        if lines.count > maxLines {
            compressedLines.append("... (additional health data available but truncated for context size)")
        }
        
        return compressedLines.joined(separator: "\n")
    }
    
    // MARK: - Context Size Management
    func getContextSizeEstimate() -> (tokens: Int, isOverLimit: Bool) {
        let estimatedTokens = currentContext.estimatedTokenCount
        return (estimatedTokens, estimatedTokens > maxContextTokens)
    }
    
    func updateContextSizeLimit(_ newLimit: Int) {
        contextSizeLimit = max(1000, min(newLimit, 8000)) // Reasonable bounds
        updateHealthDataContext()
    }
    
    // MARK: - Conversation Search and Filtering
    func searchConversations(_ query: String) async throws -> [ChatConversation] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conversations
        }
        
        return try await databaseManager.searchConversations(query: query)
    }
    
    func filterConversationsByDataType(_ dataType: HealthDataType) -> [ChatConversation] {
        return conversations.filter { conversation in
            conversation.includedHealthDataTypes.contains(dataType)
        }
    }
    
    // MARK: - Statistics and Analytics
    func getChatStatistics() async throws -> ChatStatistics {
        return try await databaseManager.getChatStatistics()
    }
    
    // MARK: - Offline Handling
    func getOfflineCapabilities() -> OfflineCapabilities {
        return OfflineCapabilities(
            canViewConversations: true,
            canViewMessages: true,
            canCreateConversations: false,
            canSendMessages: false,
            canEditConversations: true,
            canDeleteConversations: true
        )
    }
    
    func handleOfflineAction(_ action: OfflineAction) -> OfflineActionResult {
        switch action {
        case .viewConversations:
            return .success("Conversations loaded from local storage")
        case .sendMessage:
            return .failure("Cannot send messages while offline. Please check your internet connection.")
        case .createConversation:
            return .failure("Cannot create new conversations while offline.")
        case .deleteConversation:
            return .success("Conversation deleted locally")
        }
    }
    
    // MARK: - Testing Support
    #if DEBUG
    func buildHealthDataContextForTesting() -> String {
        return buildHealthDataContext()
    }
    #endif
    
    // MARK: - Cleanup
    deinit {
        networkMonitor.stopMonitoring()
    }
}

// MARK: - Network Monitor
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    var onNetworkStatusChanged: ((Bool) -> Void)?
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            self?.onNetworkStatusChanged?(isConnected)
        }
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
}

// MARK: - Supporting Types
struct OfflineCapabilities {
    let canViewConversations: Bool
    let canViewMessages: Bool
    let canCreateConversations: Bool
    let canSendMessages: Bool
    let canEditConversations: Bool
    let canDeleteConversations: Bool
}

enum OfflineAction {
    case viewConversations
    case sendMessage
    case createConversation
    case deleteConversation
}

enum OfflineActionResult {
    case success(String)
    case failure(String)
    
    var message: String {
        switch self {
        case .success(let message), .failure(let message):
            return message
        }
    }
    
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

// MARK: - AI Chat Errors
enum AIChatError: LocalizedError {
    case noActiveConversation
    case notConnected
    case emptyMessage
    case contextTooLarge
    case processingFailed(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noActiveConversation:
            return "No active conversation selected"
        case .notConnected:
            return "Not connected to AI service"
        case .emptyMessage:
            return "Message cannot be empty"
        case .contextTooLarge:
            return "Health data context is too large"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noActiveConversation:
            return "Please select or create a conversation first"
        case .notConnected:
            return "Check your internet connection and server settings"
        case .emptyMessage:
            return "Please enter a message before sending"
        case .contextTooLarge:
            return "Try reducing the amount of health data included in the context"
        case .processingFailed:
            return "Please try again or check your server configuration"
        case .networkError:
            return "Check your network connection and try again"
        }
    }
}
