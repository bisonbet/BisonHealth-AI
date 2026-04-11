import Foundation
import SwiftUI
import Network
import Combine

// MARK: - AI Chat Manager
@MainActor
class AIChatManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var conversations: [ChatConversation] = []
    @Published var currentConversation: ChatConversation? = nil
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var isLoadingConversations: Bool = false
    @Published var isBuildingContext: Bool = false
    @Published var isGeneratingTitle: Bool = false
    @Published var isSendingMessage: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedHealthDataTypes: Set<HealthDataType> = [.personalInfo]
    @Published var selectedPersonalInfoCategories: Set<PersonalInfoCategory> = Set(PersonalInfoCategory.allCases)
    @Published var selectedDoctor: Doctor? = Doctor.defaultDoctors.first(where: { $0.name == "Primary Care Physician" })
    @Published var isOffline: Bool = false
    
    // MARK: - Dependencies
    private let healthDataManager: HealthDataManager
    private let databaseManager: DatabaseManager
    private let networkMonitor: NetworkMonitor
    private let settingsManager = SettingsManager.shared
    private let networkManager = NetworkManager.shared
    private let pendingOperationsManager = PendingOperationsManager.shared
    private let errorHandler = ErrorHandler.shared
    private let retryManager = NetworkRetryManager.shared
    
    // MARK: - Computed Properties
    /// Get context size limit from provider-specific settings
    var contextSizeLimit: Int {
        AIProviderContextLimits.limit(for: settingsManager.modelPreferences.aiProvider)
    }
    
    /// Context compression threshold (90% of limit to allow some headroom)
    private var contextCompressionThreshold: Int {
        Int(Double(contextSizeLimit) * 0.9)
    }
    
    // MARK: - Context Management
    private var currentContext: ChatContext = ChatContext()

    // MARK: - Streaming Debounce
    private var streamingUpdateTask: Task<Void, Never>?
    private var pendingStreamingContent: String?
    private var pendingStreamingIds: (conversationId: UUID, messageId: UUID)?

    // MARK: - Constants
    private enum Constants {
        static let streamingDebounceInterval: TimeInterval = 0.067 // ~15 fps (1/15 second)
    }
    
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
        // Use the new NetworkManager for monitoring
        networkManager.statusPublisher
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    self.isOffline = !status.isConnected
                    if status.isConnected {
                        // Only check connection if user has explicitly interacted with chat
                        // This prevents noisy connection attempts when network comes back
                        if !self.conversations.isEmpty {
                            await self.checkConnection()
                        }

                        // Process any pending operations
                        await self.pendingOperationsManager.retryAllOperations()
                    } else {
                        self.isConnected = false
                    }
                }
            }
            .store(in: &cancellables)

        // Keep legacy monitor for compatibility
        networkMonitor.onNetworkStatusChanged = { [weak self] isConnected in
            Task { @MainActor in
                self?.isOffline = !isConnected
            }
        }
        networkMonitor.startMonitoring()
    }
    
    // MARK: - Connection Management
    
    private func getOllamaClient() -> OllamaClient {
        return settingsManager.getOllamaClient()
    }

    private func getAIClient() -> any AIProviderInterface {
        return settingsManager.getAIClient()
    }
    
    func checkConnection() async {
        guard !isOffline else {
            isConnected = false
            return
        }

        // Only auto-check connection for Ollama and OpenAI-compatible servers
        // Don't auto-check for cloud providers to avoid rate limiting
        switch settingsManager.modelPreferences.aiProvider {
        case .ollama:
            do {
                let aiClient = getAIClient()
                isConnected = try await aiClient.testConnection()
            } catch {
                isConnected = false
                errorMessage = "Failed to connect to Ollama: \(error.localizedDescription)"
            }
        case .bedrock:
            // For AWS Bedrock, assume connected if credentials are configured
            // User can manually test in settings if needed
            isConnected = settingsManager.hasValidAWSCredentials()
        case .openAICompatible:
            // For OpenAI-compatible servers, assume connected if configuration is valid
            // User can manually test in settings if needed
            isConnected = settingsManager.hasValidOpenAICompatibleConfig()
        case .onDeviceLLM:
            // For on-device LLM, check if enabled and a model is downloaded
            isConnected = MLXModelInfo.isEnabled && MLXModelDownloadManager.shared.isModelDownloaded(MLXModelInfo.selectedModel)
        }
    }
    
    // MARK: - Conversation Management
    func loadConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversations = try await databaseManager.fetchConversations()
            AppLog.shared.ai("Loaded \(conversations.count) conversations")
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
            errorHandler.handle(error, context: "Load Conversations")
            AppLog.shared.error("Failed to load conversations", error: error, category: .ai)
        }
    }
    
    func startNewConversation(title: String? = nil) async throws -> ChatConversation {
        let conversationTitle = title ?? "New Conversation"
        let conversation = ChatConversation(
            title: conversationTitle,
            includedHealthDataTypes: selectedHealthDataTypes,
            includedPersonalInfoCategories: selectedPersonalInfoCategories
        )

        try await databaseManager.saveConversation(conversation)
        conversations.insert(conversation, at: 0)
        currentConversation = conversation

        return conversation
    }
    
    func selectConversation(_ conversation: ChatConversation) {
        currentConversation = conversation
        selectedHealthDataTypes = conversation.includedHealthDataTypes
        selectedPersonalInfoCategories = conversation.includedPersonalInfoCategories
        Task {
            await updateHealthDataContext()
        }
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
    
    func updateConversationTitle(_ conversation: ChatConversation, newTitle: String) async throws {
        var updatedConversation = conversation
        updatedConversation.updateTitle(newTitle)
        
        try await databaseManager.updateConversation(updatedConversation)
        
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = updatedConversation
        }
        
        if currentConversation?.id == conversation.id {
            currentConversation = updatedConversation
        }
    }
    
    // MARK: - Title Generation
    private func generateTitleIfNeeded(for conversation: ChatConversation) async {
        // Only generate title if:
        // 1. Title is still the default "New Conversation"
        // 2. We have at least 2 messages (1 user + 1 assistant) - the first exchange
        let userMessages = conversation.messages.filter({ $0.role == .user })
        let assistantMessages = conversation.messages.filter({ $0.role == .assistant && !$0.isError })

        guard conversation.title == "New Conversation",
              userMessages.count >= 1,
              assistantMessages.count >= 1 else {
            AppLog.shared.ai("Title generation skipped - title: '\(conversation.title)', user messages: \(userMessages.count), assistant messages: \(assistantMessages.count)", level: .debug)
            return
        }

        // Don't generate title if there's an error message
        guard !conversation.messages.contains(where: { $0.isError }) else {
            AppLog.shared.ai("Title generation skipped - conversation has error messages", level: .debug)
            return
        }

        isGeneratingTitle = true
        defer { isGeneratingTitle = false }

        AppLog.shared.ai("Generating title for conversation with \(conversation.messages.count) messages")
        do {
            let generatedTitle = try await generateConversationTitle(for: conversation)
            AppLog.shared.ai("Generated title: '\(generatedTitle)'")
            if !generatedTitle.isEmpty && generatedTitle != "New Conversation" {
                try await updateConversationTitle(conversation, newTitle: generatedTitle)
                AppLog.shared.ai("Successfully updated conversation title to: '\(generatedTitle)'")
            } else {
                AppLog.shared.ai("Generated title was empty or unchanged", level: .warning)
            }
        } catch {
            // Log error for debugging - don't show to user (not critical)
            AppLog.shared.ai("Failed to generate conversation title: \(error.localizedDescription)", level: .warning)
        }
    }
    
    private func generateConversationTitle(for conversation: ChatConversation) async throws -> String {
        guard let userMessage = conversation.messages.first(where: { $0.role == .user }) else {
            return "New Conversation"
        }

        guard let assistantMessage = conversation.messages.first(where: { $0.role == .assistant }) else {
            return "New Conversation"
        }

        let titlePrompt = """
        Summarize this conversation in 3-7 words as a short title. Output ONLY the title, nothing else.

        User: \(userMessage.content)
        Assistant: \(String(assistantMessage.content.prefix(300)))
        """

        // Uses an isolated session for on-device LLM — does not affect the chat session.
        let aiClient = getAIClient()
        do {
            let response = try await aiClient.sendMessage(titlePrompt, context: "")

            var title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove surrounding quotes if present
            if (title.hasPrefix("\"") && title.hasSuffix("\"")) ||
               (title.hasPrefix("'") && title.hasSuffix("'")) {
                title = String(title.dropFirst().dropLast())
            }

            // Remove common LLM preamble patterns
            let preambles = ["Title:", "title:", "Summary:", "summary:"]
            for preamble in preambles {
                if title.hasPrefix(preamble) {
                    title = String(title.dropFirst(preamble.count)).trimmingCharacters(in: .whitespaces)
                }
            }

            // Limit to 7 words
            let words = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count > 7 {
                title = words.prefix(7).joined(separator: " ")
            }

            // Validate — fall back to heuristic if LLM produced garbage
            if title.isEmpty || title.count > 60 || title.count < 2 {
                AppLog.shared.ai("LLM title was invalid ('\(title)'), falling back to heuristic", level: .warning)
                return generateHeuristicTitle(from: userMessage.content)
            }

            return title
        } catch {
            // On-device models may fail on short prompts — fall back to heuristic
            AppLog.shared.ai("LLM title generation failed: \(error.localizedDescription), using heuristic", level: .warning)
            return generateHeuristicTitle(from: userMessage.content)
        }
    }

    /// Generate a simple heuristic title from user message (fallback when LLM generation fails)
    private func generateHeuristicTitle(from message: String) -> String {
        // Clean the message
        var cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common question words and phrases
        let prefixesToRemove = ["what", "how", "why", "when", "where", "can you", "could you", "please", "tell me about", "explain"]
        for prefix in prefixesToRemove {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Take first 5 words
        let words = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let titleWords = words.prefix(5)

        // Join and capitalize
        let title = titleWords.joined(separator: " ")

        // Return capitalized title or default
        return title.isEmpty ? "New Conversation" : title.prefix(1).uppercased() + title.dropFirst()
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

        guard !isSendingMessage else {
            throw AIChatError.messageInFlight
        }

        guard !isOffline else {
            throw AIChatError.notConnected
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIChatError.emptyMessage
        }

        isLoading = true
        isSendingMessage = true
        errorMessage = nil
        defer {
            isLoading = false
            isSendingMessage = false
        }

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
            let healthContext = await buildHealthDataContext()

            // CRITICAL FIX: Use currentConversation (which has the new message) instead of stale 'conversation' variable
            // The 'conversation' variable was captured BEFORE adding the user message, so counts are wrong
            guard let updatedConversation = currentConversation else {
                throw AIChatError.noActiveConversation
            }

            // Check if this is the first user message and if current model requires instruction injection
            // IMPORTANT: Injection is ONLY for providers where WE control prompt formatting (Ollama)
            // OpenAI Compatible and Bedrock servers handle their own chat template formatting
            let currentModel: String
            switch settingsManager.modelPreferences.aiProvider {
            case .ollama, .openAICompatible:
                currentModel = settingsManager.modelPreferences.chatModel
            case .bedrock:
                currentModel = settingsManager.modelPreferences.bedrockModel
            case .onDeviceLLM:
                currentModel = MLXModelInfo.selectedModel.displayName
            }
            let userMessageCount = updatedConversation.messages.filter({ $0.role == .user }).count
            let assistantMessageCount = updatedConversation.messages.filter({ $0.role == .assistant }).count

            // CRITICAL: Only check for injection if provider requires it
            // OpenAI Compatible servers (llama.cpp, vLLM, etc.) handle chat templates themselves
            let providerNeedsInjection = settingsManager.modelPreferences.aiProvider == .ollama
            let requiresInjection = providerNeedsInjection &&
                                   SystemPromptExceptionList.shared.requiresInstructionInjection(for: currentModel)

            // FIX: The logic should be:
            // - First turn: userMessageCount == 1 AND assistantMessageCount == 0 (no assistant responses yet)
            // - Subsequent turns: userMessageCount > 1 OR assistantMessageCount > 0
            let isFirstTurn = (userMessageCount == 1 && assistantMessageCount == 0)
            let isFirstUserMessage = userMessageCount == 1

            AppLog.shared.ai("[Chat] sendMessage: provider=\(settingsManager.modelPreferences.aiProvider), model=\(currentModel), turn=\(userMessageCount)/\(assistantMessageCount), isFirstTurn=\(isFirstTurn), requiresInjection=\(requiresInjection), messageCount=\(updatedConversation.messages.count)")

            // Prepare the message content (potentially formatted for exception models)
            // NOTE: OpenAI Compatible/Bedrock NEVER get injection - they use standard API format
            var messageContent = content

            if isFirstTurn && requiresInjection {
                AppLog.shared.ai("[Chat] Applying instruction injection for model \(currentModel)")
                messageContent = SystemPromptExceptionList.shared.formatFirstUserMessage(
                    userMessage: content,
                    systemPrompt: selectedDoctor?.systemPrompt,
                    context: healthContext
                )
                AppLog.shared.ai("[Chat] Formatted message length: \(messageContent.count) chars", level: .debug)
            }

            AppLog.shared.ai("[Chat] Context length: \(healthContext.count) chars, hasContext=\(!healthContext.isEmpty)")

            if useStreaming {
                if isFirstTurn && requiresInjection {
                    AppLog.shared.ai("[Chat] First turn (injection) - sending formatted message (\(messageContent.count) chars)")
                    try await sendStreamingMessage(messageContent, context: "", conversationId: updatedConversation.id)
                } else {
                    AppLog.shared.ai("[Chat] Turn \(userMessageCount) - sending message (\(messageContent.count) chars)")
                    try await sendStreamingMessage(messageContent, context: healthContext, conversationId: updatedConversation.id)
                }
            } else {
                // Use non-streaming for complete response
                if isFirstUserMessage && requiresInjection {
                    // For Ollama exception models, send formatted message with empty context
                    try await sendNonStreamingMessage(messageContent, context: "", conversationId: updatedConversation.id)
                } else {
                    try await sendNonStreamingMessage(messageContent, context: healthContext, conversationId: updatedConversation.id)
                }
            }
            
        } catch {
            // Mark user message as failed
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }),
               let messageIndex = conversations[index].messages.firstIndex(where: { $0.id == userMessage.id }) {
                conversations[index].messages[messageIndex].markFailed(error: error.localizedDescription)
                currentConversation = conversations[index]
            }

            // Handle error with global error handler
            errorHandler.handle(
                error,
                context: "Send Message",
                retryAction: {
                    Task {
                        await self.retryFailedMessage(userMessage, conversationId: conversation.id)
                    }
                }
            )

            AppLog.shared.error("Failed to send message", error: error, category: .ai)

            throw error
        }

    }

    /// Retry a failed message
    func retryFailedMessage(_ message: ChatMessage, conversationId: UUID) async {
        guard message.canRetry else {
            AppLog.shared.ai("Cannot retry message: not a failed user message", level: .warning)
            return
        }

        AppLog.shared.ai("Retrying failed message: \(message.id)")

        // Mark message as retrying
        if let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
           let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
            conversations[convIndex].messages[msgIndex].markRetrying()
            currentConversation = conversations[convIndex]
        }

        // Use RetryManager to retry sending the message
        let result = await retryManager.retryNetworkOperation {
            // Build health data context
            let healthContext = await self.buildHealthDataContext()

            // Send via non-streaming (simpler for retries)
            try await self.sendNonStreamingMessage(
                message.content,
                context: healthContext,
                conversationId: conversationId
            )
        } onRetry: { attempt, error, delay in
            AppLog.shared.ai("Retry attempt \(attempt), waiting \(delay)s")
        }

        switch result {
        case .success:
            // Mark message as sent
            if let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
               let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
                conversations[convIndex].messages[msgIndex].markSent()
                currentConversation = conversations[convIndex]
            }
            AppLog.shared.ai("Successfully retried message \(message.id)")

        case .failure(let error, let attempts):
            // Mark as failed again
            if let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
               let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
                conversations[convIndex].messages[msgIndex].markFailed(error: "Failed after \(attempts) attempts: \(error.localizedDescription)")
                currentConversation = conversations[convIndex]
            }
            AppLog.shared.error("Failed to retry message after \(attempts) attempts", error: error, category: .ai)

            // Show error to user
            errorHandler.handle(error, context: "Retry Message")

        case .cancelled:
            AppLog.shared.ai("Message retry was cancelled")
        }
    }
    
    // MARK: - Streaming Helpers

    /// Update streaming message with throttling to prevent UI freezes
    /// - Parameters:
    ///   - content: The updated message content to display
    ///   - conversationId: ID of the conversation containing the message
    ///   - messageId: ID of the message being updated
    /// - Note: Uses a throttle pattern (update at most X times per second) rather than debounce (cancel if new update comes)
    ///   to ensure updates happen during rapid streaming
    @MainActor
    private func updateStreamingMessage(content: String, conversationId: UUID, messageId: UUID) {
        // Store the latest content and IDs
        pendingStreamingContent = content
        pendingStreamingIds = (conversationId, messageId)
        
        // If a task is already running, we don't need to do anything.
        // It will pick up the latest 'pendingStreamingContent' when it wakes up.
        if streamingUpdateTask != nil {
            return
        }

        // Start a throttling task
        streamingUpdateTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Wait for throttle interval
                try await Task.sleep(nanoseconds: UInt64(Constants.streamingDebounceInterval * 1_000_000_000))
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                // Apply the LATEST pending content
                if let content = self.pendingStreamingContent,
                   let ids = self.pendingStreamingIds {
                    
                    if let conversationIndex = self.conversations.firstIndex(where: { $0.id == ids.conversationId }),
                       let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == ids.messageId }) {
                        self.conversations[conversationIndex].messages[messageIndex].content = content
                        self.currentConversation = self.conversations[conversationIndex]
                    }
                }
                
                // Clear the task so next update can start a new one
                self.streamingUpdateTask = nil
                
            } catch is CancellationError {
                // Expected
            } catch {
                AppLog.shared.ai("Streaming throttle error: \(error)", level: .debug)
                self.streamingUpdateTask = nil
            }
        }
    }

    /// Force immediate update for final message (bypasses debouncing)
    /// - Parameters:
    ///   - conversationId: ID of the conversation containing the message
    ///   - messageId: ID of the message being finalized
    ///   - finalMessage: The complete final message
    @MainActor
    private func finalizeStreamingMessage(_ conversationId: UUID, messageId: UUID, finalMessage: ChatMessage) async {
        // Cancel any pending debounced updates
        streamingUpdateTask?.cancel()

        // Apply final update immediately
        if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }),
           let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageId }) {
            self.conversations[conversationIndex].messages[messageIndex] = finalMessage
            self.currentConversation = self.conversations[conversationIndex]
        }
    }

    private func sendStreamingMessage(_ content: String, context: String, conversationId: UUID) async throws {
        // IMPORTANT: Calculate message counts BEFORE adding the placeholder message
        // to correctly determine if this is the first turn
        let currentModel: String
        switch settingsManager.modelPreferences.aiProvider {
        case .ollama, .openAICompatible:
            currentModel = settingsManager.modelPreferences.chatModel
        case .bedrock:
            currentModel = settingsManager.modelPreferences.bedrockModel
        case .onDeviceLLM:
            currentModel = MLXModelInfo.selectedModel.displayName
        }

        // Get the conversation and its messages BEFORE adding the placeholder
        let conversation = conversations.first(where: { $0.id == conversationId })
        let conversationMessages = conversation?.messages ?? []

        let userMessageCount = conversationMessages.filter({ $0.role == .user }).count
        let assistantMessageCount = conversationMessages.filter({ $0.role == .assistant }).count

        // CRITICAL: Only check for injection if provider requires it
        // OpenAI Compatible and Bedrock servers handle chat templates themselves
        let providerNeedsInjection = settingsManager.modelPreferences.aiProvider == .ollama
        let requiresInjection = providerNeedsInjection &&
                               SystemPromptExceptionList.shared.requiresInstructionInjection(for: currentModel)

        // First turn: userMessageCount == 1 AND assistantMessageCount == 0 (no assistant responses yet)
        let isFirstTurn = (userMessageCount == 1 && assistantMessageCount == 0)

        AppLog.shared.ai("[Chat] sendStreamingMessage: provider=\(settingsManager.modelPreferences.aiProvider), model=\(currentModel), turn=\(userMessageCount)/\(assistantMessageCount), isFirstTurn=\(isFirstTurn), requiresInjection=\(requiresInjection), contentLength=\(content.count)")

        // Create a placeholder message for streaming content
        let streamingMessageId = UUID()
        let streamingMessage = ChatMessage(
            id: streamingMessageId,
            content: "",
            role: .assistant
        )

        // Add placeholder message to conversation (AFTER calculating isFirstTurn)
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].addMessage(streamingMessage)
            currentConversation = conversations[index]
        }

        // Determine if we should send systemPrompt separately
        // For Ollama exception models: never send system prompt (instructions embedded in first message)
        // For OpenAI Compatible/Bedrock: ALWAYS send via standard API (server handles formatting)
        // For normal models: send if context is provided
        let shouldSendSystemPrompt: Bool
        switch settingsManager.modelPreferences.aiProvider {
        case .onDeviceLLM:
            // Keep persona consistently active for small on-device models.
            shouldSendSystemPrompt = true
        default:
            if requiresInjection {
                // Ollama exception models only: instructions are embedded in first message by AIChatManager
                shouldSendSystemPrompt = false
            } else {
                // Normal models + OpenAI Compatible + Bedrock: send via standard API if context is provided
                shouldSendSystemPrompt = !context.isEmpty
            }
        }

        // Use the selected AI provider with streaming support
        switch settingsManager.modelPreferences.aiProvider {
        case .ollama:
            let ollamaClient = getOllamaClient()

            // Get conversation history for multi-turn support
            // Exclude the current user message and any empty placeholder messages
            let ollamaConversationHistory: [ChatMessage]
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                let allMessages = conversation.messages
                if let lastUserMessageIndex = allMessages.lastIndex(where: { $0.role == .user }) {
                    var messagesWithoutCurrent = allMessages
                    messagesWithoutCurrent.remove(at: lastUserMessageIndex)
                    ollamaConversationHistory = messagesWithoutCurrent.filter { !$0.content.isEmpty }
                } else {
                    ollamaConversationHistory = allMessages.filter { !$0.content.isEmpty }
                }
            } else {
                ollamaConversationHistory = []
            }

            try await ollamaClient.sendStreamingChatMessage(
                content,
                context: context,
                conversationHistory: ollamaConversationHistory,
                model: settingsManager.modelPreferences.chatModel,
                systemPrompt: shouldSendSystemPrompt ? selectedDoctor?.systemPrompt : nil,
                onUpdate: { [weak self] partialContent in
                    guard let self = self else { return }
                    // Use debounced update for better performance with long messages
                    // Explicitly dispatch to MainActor since onUpdate may be called from background thread
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.updateStreamingMessage(content: partialContent, conversationId: conversationId, messageId: streamingMessageId)
                    }
                },
                onComplete: { [weak self] finalResponse in
                    Task { @MainActor [weak self] in
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

                            // Use finalize to bypass debouncing for immediate final update
                            await self.finalizeStreamingMessage(conversationId, messageId: streamingMessageId, finalMessage: finalMessage)

                            // Generate title after first exchange if still using default title
                            if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                                await self.generateTitleIfNeeded(for: self.conversations[conversationIndex])
                            }
                        } catch {
                            self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                        }
                    }
                }
            )

        case .bedrock:
            let bedrockClient = settingsManager.getBedrockClient()

            // Get conversation history for multi-turn support
            // Exclude the current user message and any empty placeholder messages
            let bedrockConversationHistory: [ChatMessage]
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                let allMessages = conversation.messages
                if let lastUserMessageIndex = allMessages.lastIndex(where: { $0.role == .user }) {
                    var messagesWithoutCurrent = allMessages
                    messagesWithoutCurrent.remove(at: lastUserMessageIndex)
                    bedrockConversationHistory = messagesWithoutCurrent.filter { !$0.content.isEmpty }
                } else {
                    bedrockConversationHistory = allMessages.filter { !$0.content.isEmpty }
                }
            } else {
                bedrockConversationHistory = []
            }

            try await bedrockClient.sendStreamingMessage(
                content,
                context: context,
                conversationHistory: bedrockConversationHistory,
                systemPrompt: shouldSendSystemPrompt ? selectedDoctor?.systemPrompt : nil,
                onUpdate: { [weak self] partialContent in
                    guard let self = self else { return }
                    // Use debounced update for better performance with long messages
                    // Explicitly dispatch to MainActor since onUpdate may be called from background thread
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.updateStreamingMessage(content: partialContent, conversationId: conversationId, messageId: streamingMessageId)
                    }
                },
                onComplete: { [weak self] finalResponse in
                    Task { @MainActor [weak self] in
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

                            // Use finalize to bypass debouncing for immediate final update
                            await self.finalizeStreamingMessage(conversationId, messageId: streamingMessageId, finalMessage: finalMessage)

                            // Generate title after first exchange if still using default title
                            if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                                await self.generateTitleIfNeeded(for: self.conversations[conversationIndex])
                            }
                        } catch {
                            self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                        }
                    }
                }
            )

        case .openAICompatible:
            let openAIClient = settingsManager.getOpenAICompatibleClient()

            // Get conversation history for multi-turn support
            // Exclude the current user message and any empty placeholder messages
            let openAIConversationHistory: [ChatMessage]
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                let allMessages = conversation.messages
                if let lastUserMessageIndex = allMessages.lastIndex(where: { $0.role == .user }) {
                    var messagesWithoutCurrent = allMessages
                    messagesWithoutCurrent.remove(at: lastUserMessageIndex)
                    openAIConversationHistory = messagesWithoutCurrent.filter { !$0.content.isEmpty }
                } else {
                    openAIConversationHistory = allMessages.filter { !$0.content.isEmpty }
                }
            } else {
                openAIConversationHistory = []
            }

            AppLog.shared.ai("OpenAI: doctor=\(selectedDoctor?.name ?? "nil"), shouldSendSystemPrompt=\(shouldSendSystemPrompt), systemPromptLength=\(selectedDoctor?.systemPrompt.count ?? 0)")
            try await openAIClient.sendStreamingChatMessage(
                content,
                context: context,
                conversationHistory: openAIConversationHistory,
                model: settingsManager.modelPreferences.openAICompatibleModel,
                systemPrompt: shouldSendSystemPrompt ? selectedDoctor?.systemPrompt : nil,
                onUpdate: { [weak self] partialContent in
                    guard let self = self else { return }
                    // Use debounced update for better performance with long messages
                    // Explicitly dispatch to MainActor since onUpdate may be called from background thread
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.updateStreamingMessage(content: partialContent, conversationId: conversationId, messageId: streamingMessageId)
                    }
                },
                onComplete: { [weak self] finalResponse in
                    Task { @MainActor [weak self] in
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

                            // Use finalize to bypass debouncing for immediate final update
                            await self.finalizeStreamingMessage(conversationId, messageId: streamingMessageId, finalMessage: finalMessage)

                            // Generate title after first exchange if still using default title
                            if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                                await self.generateTitleIfNeeded(for: self.conversations[conversationIndex])
                            }
                        } catch {
                            self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                        }
                    }
                }
            )

        case .onDeviceLLM:
            let mlxClient = settingsManager.getMLXOnDeviceClient()

            // Build conversation history for re-hydration (used when ChatSession must be rebuilt).
            // Exclude the current user message and empty streaming placeholders.
            let mlxConversationHistory: [ChatMessage]
            if let conversation = conversations.first(where: { $0.id == conversationId }) {
                let allMessages = conversation.messages
                if let lastUserMessageIndex = allMessages.lastIndex(where: { $0.role == .user }) {
                    var messagesWithoutCurrent = allMessages
                    messagesWithoutCurrent.remove(at: lastUserMessageIndex)
                    mlxConversationHistory = messagesWithoutCurrent.filter { !$0.content.isEmpty }
                } else {
                    mlxConversationHistory = allMessages.filter { !$0.content.isEmpty }
                }
            } else {
                mlxConversationHistory = []
            }

            AppLog.shared.ai("OnDeviceTurn: conversationId=\(conversationId.uuidString), historyMessages=\(mlxConversationHistory.count), healthContextBytes=\(context.utf8.count)")

            // MLX ChatSession handles multi-turn context via KV cache internally.
            // System prompt + health context are set as session instructions (once per session).
            // Only the raw user message is passed to streamResponse(to:).
            try await mlxClient.sendStreamingChatMessage(
                content,
                healthContext: context,
                conversationHistory: mlxConversationHistory,
                conversationId: conversationId,
                systemPrompt: shouldSendSystemPrompt ? selectedDoctor?.compactSystemPrompt : nil,
                onUpdate: { [weak self] partialContent in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.updateStreamingMessage(content: partialContent, conversationId: conversationId, messageId: streamingMessageId)
                    }
                },
                onComplete: { [weak self] finalResponse in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        let finalMessage = ChatMessage(
                            id: streamingMessageId,
                            content: finalResponse.content,
                            role: .assistant,
                            metadata: self.stringifyMetadata(finalResponse.metadata),
                            tokens: finalResponse.tokenCount,
                            processingTime: finalResponse.responseTime
                        )

                        do {
                            try await self.databaseManager.addMessage(to: conversationId, message: finalMessage)
                            await self.finalizeStreamingMessage(conversationId, messageId: streamingMessageId, finalMessage: finalMessage)

                            if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }) {
                                await self.generateTitleIfNeeded(for: self.conversations[conversationIndex])
                            }
                        } catch {
                            self.errorMessage = "Failed to save message: \(error.localizedDescription)"
                        }
                    }
                }
            )

        }
    }
    
    private func sendNonStreamingMessage(_ content: String, context: String, conversationId: UUID) async throws {
        do {
            // Send to AI service
            let startTime = Date()
            let aiClient = getAIClient()

            // Prepare context with doctor's system prompt if available
            // For exception models (empty context), instructions are already embedded in content
            var fullContext = context
            if !context.isEmpty, let doctorPrompt = selectedDoctor?.systemPrompt {
                // Normal case: prepend doctor's system prompt to context
                fullContext = "System: \(doctorPrompt)\n\nContext: \(context)"
            }
            // If context is empty, it means we're using an exception model with embedded instructions
            // In this case, don't modify anything - content already has everything formatted

            let response = try await aiClient.sendMessage(content, context: fullContext)
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
                
                // Generate title after first exchange if still using default title
                await generateTitleIfNeeded(for: conversations[index])
            }
        } catch {
            // Queue for retry if network error
            if error is OpenAICompatibleError || error is DecodingError {
                throw error
            }
            let networkError = NetworkError.from(error: error)
            if networkError.isRetryable {
                AppLog.shared.ai("[Chat] Network error, queueing message for retry", level: .warning)
                await pendingOperationsManager.queueChatMessage(
                    conversationId: conversationId,
                    message: content,
                    context: context,
                    useStreaming: false,
                    model: settingsManager.modelPreferences.chatModel,
                    systemPrompt: selectedDoctor?.systemPrompt
                )
            }
            throw error
        }
    }
    
    // MARK: - Health Data Context Management
    func selectHealthDataForContext(_ types: Set<HealthDataType>) {
        selectHealthDataForContext(types, personalInfoCategories: selectedPersonalInfoCategories)
    }

    func selectHealthDataForContext(
        _ types: Set<HealthDataType>,
        personalInfoCategories: Set<PersonalInfoCategory>
    ) {
        AppLog.shared.ai("[Context] Selection updated: \(types.count) data types, \(personalInfoCategories.count) personal info categories")

        selectedHealthDataTypes = types
        selectedPersonalInfoCategories = personalInfoCategories
        Task {
            await updateHealthDataContext()
        }

        // Update current conversation's included data types and categories
        if var conversation = currentConversation {
            conversation.includedHealthDataTypes = types
            conversation.includedPersonalInfoCategories = personalInfoCategories
            Task {
                try await databaseManager.updateConversation(conversation)
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                    conversations[index] = conversation
                }
                AppLog.shared.ai("[Context] Conversation context preferences saved", level: .debug)
            }
        }
    }
    
    // MARK: - Doctor Persona Management
    func selectDoctor(_ doctor: Doctor) {
        selectedDoctor = doctor
    }
    
    private func updateHealthDataContext() async {
        // Map selected HealthDataType values to DocumentCategory filters
        var documentCategories: [DocumentCategory] = []
        for dataType in selectedHealthDataTypes {
            documentCategories.append(contentsOf: dataType.relatedDocumentCategories)
        }
        
        // Fetch medical documents selected for AI context, filtered by categories
        let medicalDocuments: [MedicalDocumentSummary]
        do {
            // If we have categories to filter by, use them
            // If no categories match but we have selected types, return empty (user selected types that don't map to documents)
            // If no types are selected at all, return all documents (backward compatibility)
            let categoriesToFilter: [DocumentCategory]?
            if !documentCategories.isEmpty {
                categoriesToFilter = documentCategories
            } else if !selectedHealthDataTypes.isEmpty {
                // User selected types but none map to document categories - return empty
                categoriesToFilter = []
            } else {
                // No types selected - backward compatibility, return all
                categoriesToFilter = nil
            }
            
            let fetchedDocs = try await databaseManager.fetchDocumentsForAIContext(categories: categoriesToFilter)
            medicalDocuments = fetchedDocs.map { MedicalDocumentSummary(from: $0) }
            
            AppLog.shared.ai("[Context] Fetched \(fetchedDocs.count) medical documents for \(selectedHealthDataTypes.count) data types, \(documentCategories.count) categories")
        } catch {
            AppLog.shared.ai("[Context] Failed to fetch medical documents: \(error.localizedDescription)", level: .warning)
            medicalDocuments = []
        }

        // Build context with selected health data and medical documents
        currentContext = ChatContext(
            personalInfo: selectedHealthDataTypes.contains(.personalInfo) ? healthDataManager.personalInfo : nil,
            bloodTests: selectedHealthDataTypes.contains(.bloodTest) ? healthDataManager.bloodTests : [],
            medicalDocuments: medicalDocuments,
            selectedDataTypes: selectedHealthDataTypes,
            selectedPersonalInfoCategories: selectedPersonalInfoCategories,
            maxTokens: contextSizeLimit
        )
    }
    
    private func buildHealthDataContext() async -> String {
        await updateHealthDataContext()

        // Use JSON format for structured health data
        let contextString = currentContext.buildContextJSON()
        let estimatedTokens = currentContext.estimatedTokenCountJSON

        AppLog.shared.ai("[Context] Built context: \(contextString.count) chars, ~\(estimatedTokens) tokens, limit=\(contextSizeLimit), hasPersonalInfo=\(currentContext.personalInfo != nil), bloodTests=\(currentContext.bloodTests.count), documents=\(currentContext.medicalDocuments.count)")

        if contextString.isEmpty || contextString == "{}" {
            AppLog.shared.ai("[Context] Context is empty — no data types selected or no data available", level: .warning)
        }

        // If context is too large, compress it
        if estimatedTokens > contextCompressionThreshold {
            AppLog.shared.ai("[Context] Compressing context (~\(estimatedTokens) tokens > threshold \(contextCompressionThreshold))")
            return compressHealthDataContext(contextString)
        }

        return contextString
    }
    
    private func compressHealthDataContext(_ context: String) -> String {
        // Estimate how much we need to compress
        let targetTokens = contextCompressionThreshold
        
        // Estimate characters per token (rough approximation: ~4 chars per token)
        let charsPerToken = 4.0
        let targetChars = Int(Double(targetTokens) * charsPerToken)
        
        if context.count <= targetChars {
            // Already small enough
            return context
        }
        
        // Truncate to target character count, but try to preserve structure
        let truncated = String(context.prefix(targetChars))
        
        // Try to end at a complete line if possible
        if let lastNewline = truncated.lastIndex(of: "\n") {
            let finalTruncated = String(truncated[..<lastNewline])
            return finalTruncated + "\n\n... (context truncated to fit \(contextSizeLimit) token limit)"
        }
        
        return truncated + "\n\n... (context truncated to fit \(contextSizeLimit) token limit)"
    }
    
    // MARK: - Context Size Management
    func getContextSizeEstimate() -> (tokens: Int, isOverLimit: Bool) {
        let estimatedTokens = currentContext.estimatedTokenCount
        return (estimatedTokens, estimatedTokens > contextSizeLimit)
    }
    
    // MARK: - Conversation Search and Filtering
    func searchConversations(_ query: String) async throws -> [ChatConversation] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conversations
        }
        
        return try await databaseManager.searchConversations(query: query)
    }
    
    func filterConversationsByDataType(_ dataType: HealthDataType) -> [ChatConversation] {
        return conversations.filter {
            $0.includedHealthDataTypes.contains(dataType)
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
    func buildHealthDataContextForTesting() async -> String {
        return await buildHealthDataContext()
    }

    func generateConversationTitleForTesting(for conversation: ChatConversation) async throws -> String {
        try await generateConversationTitle(for: conversation)
    }
    #endif

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()

    private func stringifyMetadata(_ metadata: [String: Any]?) -> [String: String]? {
        guard let metadata, !metadata.isEmpty else {
            return nil
        }

        var result: [String: String] = [:]
        for (key, value) in metadata {
            switch value {
            case let string as String:
                result[key] = string
            case let boolValue as Bool:
                result[key] = boolValue ? "true" : "false"
            case let intValue as Int:
                result[key] = String(intValue)
            case let doubleValue as Double:
                result[key] = String(format: "%.4f", doubleValue)
            case let floatValue as Float:
                result[key] = String(format: "%.4f", floatValue)
            default:
                if JSONSerialization.isValidJSONObject(value),
                   let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    result[key] = json
                } else {
                    result[key] = String(describing: value)
                }
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Cleanup
    deinit {
        // Cancel any pending streaming update task to prevent memory leaks
        streamingUpdateTask?.cancel()
        // Stop network monitoring
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
enum AIChatError: LocalizedError, Equatable {
    case noActiveConversation
    case notConnected
    case emptyMessage
    case messageInFlight
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
        case .messageInFlight:
            return "Please wait for the current response to finish before sending another message."
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
        case .messageInFlight:
            return "Wait for the current response, then send your next question."
        case .contextTooLarge:
            return "Try reducing the amount of health data included in the context"
        case .processingFailed:
            return "Please try again or check your server configuration"
        case .networkError:
            return "Check your network connection and try again"
        }
    }

    static func == (lhs: AIChatError, rhs: AIChatError) -> Bool {
        switch (lhs, rhs) {
        case (.noActiveConversation, .noActiveConversation),
             (.notConnected, .notConnected),
             (.emptyMessage, .emptyMessage),
             (.messageInFlight, .messageInFlight),
             (.contextTooLarge, .contextTooLarge):
            return true
        case let (.processingFailed(left), .processingFailed(right)):
            return left == right
        case (.networkError, .networkError):
            return true
        default:
            return false
        }
    }
}
