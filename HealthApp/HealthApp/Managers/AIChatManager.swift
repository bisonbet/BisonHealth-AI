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
    @Published var selectedDoctor: Doctor? = Doctor.defaultDoctors.first(where: { $0.name == "Family Medicine" })
    @Published var isOffline: Bool = false
    
    // MARK: - Dependencies
    private let healthDataManager: HealthDataManager
    private let databaseManager: DatabaseManager
    private let networkMonitor: NetworkMonitor
    private let settingsManager = SettingsManager.shared
    private let networkManager = NetworkManager.shared
    private let pendingOperationsManager = PendingOperationsManager.shared
    private let errorHandler = ErrorHandler.shared
    private let logger = Logger.shared
    private let retryManager = NetworkRetryManager.shared
    
    // MARK: - Computed Properties
    /// Get context size limit from settings (defaults to 16k for Ollama)
    var contextSizeLimit: Int {
        settingsManager.modelPreferences.contextSizeLimit
    }
    
    /// Context compression threshold (90% of limit to allow some headroom)
    private var contextCompressionThreshold: Int {
        Int(Double(contextSizeLimit) * 0.9)
    }
    
    // MARK: - Context Management
    private var currentContext: ChatContext = ChatContext()

    // MARK: - Streaming Debounce
    private var streamingUpdateTask: Task<Void, Never>?
    private var streamingSequenceNumber: UInt64 = 0

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
        case .mlx:
            // For MLX, check if a model is downloaded and available
            isConnected = settingsManager.hasValidMLXConfig()
        }
    }
    
    // MARK: - Conversation Management
    func loadConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversations = try await databaseManager.fetchConversations()
            logger.info("Loaded \(conversations.count) conversations")
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
            errorHandler.handle(error, context: "Load Conversations")
            logger.error("Failed to load conversations", error: error)
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
            logger.debug("Title generation skipped - title: '\(conversation.title)', user messages: \(userMessages.count), assistant messages: \(assistantMessages.count)")
            return
        }

        // Don't generate title if there's an error message
        guard !conversation.messages.contains(where: { $0.isError }) else {
            logger.debug("Title generation skipped - conversation has error messages")
            return
        }

        isGeneratingTitle = true
        defer { isGeneratingTitle = false }

        logger.info("Generating title for conversation with \(conversation.messages.count) messages")
        do {
            let generatedTitle = try await generateConversationTitle(for: conversation)
            logger.info("Generated title: '\(generatedTitle)'")
            if !generatedTitle.isEmpty && generatedTitle != "New Conversation" {
                try await updateConversationTitle(conversation, newTitle: generatedTitle)
                logger.info("Successfully updated conversation title to: '\(generatedTitle)'")
            } else {
                logger.warning("Generated title was empty or unchanged")
            }
        } catch {
            // Log error for debugging - don't show to user (not critical)
            logger.warning("Failed to generate conversation title: \(error.localizedDescription)")
        }
    }
    
    private func generateConversationTitle(for conversation: ChatConversation) async throws -> String {
        // Get the first user message and first assistant message
        guard let userMessage = conversation.messages.first(where: { $0.role == .user }),
              let assistantMessage = conversation.messages.first(where: { $0.role == .assistant }) else {
            return "New Conversation"
        }

        // For MLX provider, use the MLX client's built-in title generation
        // This uses the current session and then resets it to clear the title generation interaction
        if settingsManager.modelPreferences.aiProvider == .mlx {
            logger.info("🏷️ Using MLX LLM-based title generation")
            do {
                let mlxClient = settingsManager.getMLXClient()
                return try await mlxClient.generateTitle(
                    userMessage: userMessage.content,
                    assistantResponse: assistantMessage.content
                )
            } catch {
                logger.warning("⚠️ MLX title generation failed, falling back to heuristic: \(error.localizedDescription)")
                // Fall back to heuristic if LLM generation fails
                return generateHeuristicTitle(from: userMessage.content)
            }
        }

        // Create a prompt for title generation for other providers
        let titlePrompt = """
        Based on this conversation, generate a short, descriptive title (3-5 words) that summarizes the main topic.

        User: \(userMessage.content)
        Assistant: \(assistantMessage.content.prefix(200))

        Generate only the title, nothing else. The title should be 3-5 words and capture the essence of the conversation.
        """

        // Use the AI client to generate the title
        let aiClient = getAIClient()
        let response = try await aiClient.sendMessage(titlePrompt, context: "")

        // Clean up the response - remove quotes, extra whitespace, etc.
        var title = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding quotes if present
        if title.hasPrefix("\"") && title.hasSuffix("\"") {
            title = String(title.dropFirst().dropLast())
        }
        if title.hasPrefix("'") && title.hasSuffix("'") {
            title = String(title.dropFirst().dropLast())
        }

        // Limit to reasonable length and word count
        let words = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count > 5 {
            title = words.prefix(5).joined(separator: " ")
        }

        // Ensure title is not empty and not too long
        if title.isEmpty || title.count > 50 {
            return "New Conversation"
        }

        return title
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
            let healthContext = await buildHealthDataContext()

            // Check if this is the first user message and if current model requires instruction injection
            // Get the appropriate model name based on the current AI provider
            let currentModel: String
            switch settingsManager.modelPreferences.aiProvider {
            case .mlx:
                currentModel = settingsManager.modelPreferences.mlxModelId ?? ""
            case .ollama, .openAICompatible:
                currentModel = settingsManager.modelPreferences.chatModel
            case .bedrock:
                currentModel = settingsManager.modelPreferences.bedrockModel
            }
            let userMessageCount = conversation.messages.filter({ $0.role == .user }).count
            let assistantMessageCount = conversation.messages.filter({ $0.role == .assistant }).count
            let requiresInjection = SystemPromptExceptionList.shared.requiresInstructionInjection(for: currentModel)

            // FIX: The logic should be:
            // - First turn: userMessageCount == 1 AND assistantMessageCount == 0 (no assistant responses yet)
            // - Subsequent turns: userMessageCount > 1 OR assistantMessageCount > 0
            let isFirstTurn = (userMessageCount == 1 && assistantMessageCount == 0)
            let isFirstUserMessage = userMessageCount == 1

            print("🔍 AIChatManager.sendMessage: Provider=\(settingsManager.modelPreferences.aiProvider), Model='\(currentModel)', userMessageCount=\(userMessageCount), assistantMessageCount=\(assistantMessageCount), isFirstTurn=\(isFirstTurn), requiresInjection=\(requiresInjection)")
            print("🔍 AIChatManager.sendMessage: All messages in conversation: \(conversation.messages.count)")
            print("🔍 AIChatManager.sendMessage: Exception patterns: \(SystemPromptExceptionList.shared.getAllPatterns())")
            print("🔍 AIChatManager.sendMessage: Model contains 'medgemma': \(currentModel.lowercased().contains("medgemma"))")

            // Prepare the message content (potentially formatted for exception models)
            // NOTE: MLX handles its own formatting in MLXClient, so we don't format here for MLX
            var messageContent = content
            let isMLXProvider = settingsManager.modelPreferences.aiProvider == .mlx

            if isFirstTurn && requiresInjection && !isMLXProvider {
                // Format with INSTRUCTIONS/CONTEXT/QUESTION for non-MLX exception models
                print("📝 AIChatManager: Model '\(currentModel)' requires instruction injection - formatting first message")
                messageContent = SystemPromptExceptionList.shared.formatFirstUserMessage(
                    userMessage: content,
                    systemPrompt: selectedDoctor?.systemPrompt,
                    context: healthContext
                )
                print("📝 AIChatManager: Formatted message length: \(messageContent.count) chars")
            }

            // Debug: Log what context is being sent
            if isMLXProvider {
                print("🔍 AIChatManager: MLX provider - passing raw message, context, and systemPrompt to MLXClient")
                print("🔍 AIChatManager: Context length: \(healthContext.count) chars")
            } else if !requiresInjection || !isFirstTurn {
                print("🔍 AIChatManager: Sending message with context length: \(healthContext.count) chars")
                if !healthContext.isEmpty {
                    print("🔍 AIChatManager: Context preview (first 1000 chars): \(String(healthContext.prefix(1000)))")
                } else {
                    print("⚠️ AIChatManager: WARNING - Context is empty!")
                }
            }

            if useStreaming {
                // Use streaming for real-time response
                if isMLXProvider {
                    // MLX handles its own formatting - always pass raw message and full context
                    print("📝 AIChatManager: MLX - sending raw message (length: \(content.count)), letting MLXClient handle formatting")
                    try await sendStreamingMessage(content, context: healthContext, conversationId: conversation.id)
                } else if isFirstTurn && requiresInjection {
                    // For non-MLX exception models, send formatted message with empty context
                    print("📝 AIChatManager: FIRST turn - sending formatted message (length: \(messageContent.count))")
                    try await sendStreamingMessage(messageContent, context: "", conversationId: conversation.id)
                } else {
                    print("📝 AIChatManager: SUBSEQUENT turn - sending raw message (length: \(messageContent.count)), first 200 chars: '\(String(messageContent.prefix(200)))'")
                    try await sendStreamingMessage(messageContent, context: healthContext, conversationId: conversation.id)
                }
            } else {
                // Use non-streaming for complete response
                if isMLXProvider {
                    // MLX handles its own formatting
                    try await sendNonStreamingMessage(content, context: healthContext, conversationId: conversation.id)
                } else if isFirstUserMessage && requiresInjection {
                    // For non-MLX exception models, send formatted message with empty context
                    try await sendNonStreamingMessage(messageContent, context: "", conversationId: conversation.id)
                } else {
                    try await sendNonStreamingMessage(messageContent, context: healthContext, conversationId: conversation.id)
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

            logger.error("Failed to send message", error: error)

            throw error
        }

        isLoading = false
    }

    /// Retry a failed message
    func retryFailedMessage(_ message: ChatMessage, conversationId: UUID) async {
        guard message.canRetry else {
            logger.warning("Cannot retry message: not a failed user message")
            return
        }

        logger.info("Retrying failed message: \(message.id)")

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
            self.logger.info("Retry attempt \(attempt) for message \(message.id), waiting \(delay)s")
        }

        switch result {
        case .success:
            // Mark message as sent
            if let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
               let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
                conversations[convIndex].messages[msgIndex].markSent()
                currentConversation = conversations[convIndex]
            }
            logger.info("Successfully retried message \(message.id)")

        case .failure(let error, let attempts):
            // Mark as failed again
            if let convIndex = conversations.firstIndex(where: { $0.id == conversationId }),
               let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == message.id }) {
                conversations[convIndex].messages[msgIndex].markFailed(error: "Failed after \(attempts) attempts: \(error.localizedDescription)")
                currentConversation = conversations[convIndex]
            }
            logger.error("Failed to retry message after \(attempts) attempts", error: error)

            // Show error to user
            errorHandler.handle(error, context: "Retry Message")

        case .cancelled:
            logger.info("Message retry was cancelled")
        }
    }
    
    // MARK: - Streaming Helpers

    /// Debounce streaming updates to improve UI performance during long responses
    /// - Parameters:
    ///   - content: The updated message content to display
    ///   - conversationId: ID of the conversation containing the message
    ///   - messageId: ID of the message being updated
    /// - Note: Uses sequence numbers to prevent out-of-order updates from race conditions
    @MainActor
    private func updateStreamingMessage(content: String, conversationId: UUID, messageId: UUID) {
        // Cancel any pending update task
        streamingUpdateTask?.cancel()

        // Increment sequence number to track update ordering
        streamingSequenceNumber += 1
        let currentSequence = streamingSequenceNumber

        // Schedule debounced UI update
        // IMPORTANT: Use [weak self] to prevent retain cycle
        streamingUpdateTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Wait for debounce interval
                try await Task.sleep(nanoseconds: UInt64(Constants.streamingDebounceInterval * 1_000_000_000))

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                // Verify this is still the latest update (prevent out-of-order race condition)
                guard currentSequence == self.streamingSequenceNumber else {
                    logger.debug("Skipping stale update (sequence \(currentSequence) < \(self.streamingSequenceNumber))")
                    return
                }

                // Apply the update to the UI
                if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }),
                   let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageId }) {
                    self.conversations[conversationIndex].messages[messageIndex].content = content
                    self.currentConversation = self.conversations[conversationIndex]
                }
            } catch is CancellationError {
                // Expected - debouncing mechanism cancels old updates when new ones arrive
            } catch {
                self.logger.debug("⚠️ Streaming debounce error: \(error)")
            }
        }
    }

    /// Immediate update for streaming messages (bypasses debouncing)
    /// Used for MLX which is already on MainActor and doesn't need debouncing
    /// - Parameters:
    ///   - content: The streaming content to display
    ///   - conversationId: ID of the conversation containing the message
    ///   - messageId: ID of the message being updated
    @MainActor
    private func updateStreamingMessageImmediate(content: String, conversationId: UUID, messageId: UUID) {
        // Apply update immediately without debouncing
        if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }),
           let messageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageId }) {
            self.conversations[conversationIndex].messages[messageIndex].content = content
            self.currentConversation = self.conversations[conversationIndex]
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
        case .mlx:
            currentModel = settingsManager.modelPreferences.mlxModelId ?? ""
        case .ollama, .openAICompatible:
            currentModel = settingsManager.modelPreferences.chatModel
        case .bedrock:
            currentModel = settingsManager.modelPreferences.bedrockModel
        }

        // Get the conversation and its messages BEFORE adding the placeholder
        let conversation = conversations.first(where: { $0.id == conversationId })
        let conversationMessages = conversation?.messages ?? []

        let userMessageCount = conversationMessages.filter({ $0.role == .user }).count
        let assistantMessageCount = conversationMessages.filter({ $0.role == .assistant }).count
        let requiresInjection = SystemPromptExceptionList.shared.requiresInstructionInjection(for: currentModel)

        // First turn: userMessageCount == 1 AND assistantMessageCount == 0 (no assistant responses yet)
        let isFirstTurn = (userMessageCount == 1 && assistantMessageCount == 0)

        // Debug logging for instruction injection
        print("🔍 AIChatManager.sendStreamingMessage: Provider=\(settingsManager.modelPreferences.aiProvider), Model='\(currentModel)', userMessageCount=\(userMessageCount), assistantMessageCount=\(assistantMessageCount), isFirstTurn=\(isFirstTurn), requiresInjection=\(requiresInjection), contentLength=\(content.count)")
        if content.count > 200 {
            print("🔍 AIChatManager.sendStreamingMessage: Content preview: \(String(content.prefix(200)))...")
        } else {
            print("🔍 AIChatManager.sendStreamingMessage: Full content: \(content)")
        }

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
        // For MLX exception models: ALWAYS pass systemPrompt because MLXClient handles its own
        //   first-turn detection and needs the prompt for INSTRUCTIONS formatting
        // For other exception models: never send system prompt separately (instructions are embedded in first message)
        // For normal models: always send system prompt if context is provided
        let shouldSendSystemPrompt: Bool
        if settingsManager.modelPreferences.aiProvider == .mlx && requiresInjection {
            // MLX handles its own session management, so always provide the system prompt
            shouldSendSystemPrompt = true
        } else if requiresInjection {
            // Other exception models: instructions are embedded in first message by AIChatManager
            shouldSendSystemPrompt = false
        } else {
            // Normal models: send if context is provided
            shouldSendSystemPrompt = !context.isEmpty
        }

        // Use the selected AI provider with streaming support
        switch settingsManager.modelPreferences.aiProvider {
        case .ollama:
            let ollamaClient = getOllamaClient()
            try await ollamaClient.sendStreamingChatMessage(
                content,
                context: context,
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
            try await bedrockClient.sendStreamingMessage(
                content,
                context: context,
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
            try await openAIClient.sendStreamingChatMessage(
                content,
                context: context,
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

        case .mlx:
            let mlxClient = settingsManager.getMLXClient()
            // MLX handles its own session management and formatting
            // Always pass full context and system prompt - MLXClient will format as needed
            // Pass conversation history (excluding the current user message which is passed separately)
            // The history allows the model to maintain context across turns
            let relevantMessages = conversationMessages.filter { msg in
                msg.role == .user || msg.role == .assistant
            }
            // Drop the last user message (which is the current one being sent)
            // If there's only 1 or 0 messages, history will be empty
            let historyForMLX: [ChatMessage]
            if relevantMessages.count > 1 {
                historyForMLX = Array(relevantMessages.dropLast(1))
            } else {
                historyForMLX = []
            }
            print("📝 AIChatManager: Passing \(historyForMLX.count) history messages to MLX")

            try await mlxClient.sendStreamingChatMessage(
                content,
                context: context,
                systemPrompt: selectedDoctor?.systemPrompt,
                conversationHistory: historyForMLX,
                conversationId: conversationId,
                onUpdate: { [weak self] partialContent in
                    guard let self = self else { return }
                    // MLX is already on MainActor, call directly without Task wrapper
                    // to avoid unnecessary queuing and debouncing issues
                    self.updateStreamingMessageImmediate(content: partialContent, conversationId: conversationId, messageId: streamingMessageId)
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
                print("⚠️ AIChatManager: Network error, queueing message for retry")
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
        print("🎯 Context Selection - Selected types: \(types)")
        print("🎯 Context Selection - Previous types: \(selectedHealthDataTypes)")

        selectedHealthDataTypes = types
        Task {
            await updateHealthDataContext()
        }

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
            
            print("🔍 Context Debug - Selected HealthDataTypes: \(selectedHealthDataTypes.map { $0.displayName })")
            print("🔍 Context Debug - Mapped DocumentCategories: \(documentCategories.map { $0.displayName })")
            print("🔍 Context Debug - Fetched \(fetchedDocs.count) medical documents")
            
            // Debug: Log details about each fetched document
            for doc in fetchedDocs {
                print("🔍 Context Debug - Document: \(doc.fileName)")
                print("🔍 Context Debug -   Category: \(doc.documentCategory.displayName)")
                print("🔍 Context Debug -   Include in context: \(doc.includeInAIContext)")
                print("🔍 Context Debug -   Processing status: \(doc.processingStatus.rawValue)")
                print("🔍 Context Debug -   Sections count: \(doc.extractedSections.count)")
                print("🔍 Context Debug -   Extracted text length: \(doc.extractedText?.count ?? 0) chars")
            }
        } catch {
            print("⚠️ Failed to fetch medical documents for AI context: \(error)")
            medicalDocuments = []
        }

        // Build context with selected health data and medical documents
        currentContext = ChatContext(
            personalInfo: selectedHealthDataTypes.contains(.personalInfo) ? healthDataManager.personalInfo : nil,
            bloodTests: selectedHealthDataTypes.contains(.bloodTest) ? healthDataManager.bloodTests : [],
            medicalDocuments: medicalDocuments,
            selectedDataTypes: selectedHealthDataTypes,
            maxTokens: contextSizeLimit
        )
    }
    
    private func buildHealthDataContext() async -> String {
        await updateHealthDataContext()

        let contextString = currentContext.buildContextString()
        let estimatedTokens = currentContext.estimatedTokenCount

        print("🔍 Context Debug - Selected types: \(selectedHealthDataTypes.map { $0.displayName })")
        print("🔍 Context Debug - Personal info exists: \(currentContext.personalInfo != nil)")
        print("🔍 Context Debug - Blood tests count: \(currentContext.bloodTests.count)")
        print("🔍 Context Debug - Medical documents count: \(currentContext.medicalDocuments.count)")
        print("🔍 Context Debug - Context string length: \(contextString.count) characters")
        print("🔍 Context Debug - Estimated tokens: \(estimatedTokens)")
        print("🔍 Context Debug - Context size limit: \(contextSizeLimit) tokens")
        print("🔍 Context Debug - Compression threshold: \(contextCompressionThreshold) tokens")

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
    #endif

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()

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
