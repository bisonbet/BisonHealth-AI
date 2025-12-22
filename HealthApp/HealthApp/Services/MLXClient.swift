import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - MLX Client

/// Client for running local LLMs using Apple's MLX framework
/// All operations run on MainActor to prevent Metal background execution errors
@MainActor
class MLXClient: ObservableObject, AIProviderInterface {

    // MARK: - Shared Instance
    static let shared = MLXClient()

    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var isLoading: Bool = false
    @Published var currentModelId: String?

    // MARK: - Private Properties
    private var chatSession: ChatSession?
    private var loadedModel: ModelContext?  // Store model separately from session for reuse
    private var currentConfig: MLXGenerationConfig = .default
    private let logger = Logger.shared
    private let gpuInitializationTask: Task<Void, Never>
    private var isGPUInitialized: Bool = false
    private static let gpuCacheLimit: UInt64 = 4 * 1024 * 1024 * 1024  // 4GB GPU cache for medical LLMs

    // Conversation tracking
    private var currentConversationId: UUID?
    private var conversationTokenCount: Int = 0

    // Loading lock to prevent concurrent model loads
    private var isLoadingModel: Bool = false

    // MARK: - Initialization
    private init() {
        // Initialize GPU on MainActor to ensure Metal resources are properly bound
        // Note: No [weak self] needed - this is a singleton that won't be deallocated
        gpuInitializationTask = Task { @MainActor in
            let cacheLimit = Self.gpuCacheLimit
            // MLX.GPU.set is not a throwing function, so no try-catch needed
            MLX.GPU.set(cacheLimit: cacheLimit)
            logger.info("🔧 MLX initialized with \(cacheLimit / 1024 / 1024)MB GPU cache")
            isGPUInitialized = true
        }
    }

    // MARK: - GPU Management

    /// Retry GPU initialization if it failed
    /// This can be called if GPU initialization fails and you want to retry
    func retryGPUInitialization() async {
        guard !isGPUInitialized else {
            logger.info("ℹ️ GPU already initialized, skipping retry")
            return
        }

        logger.info("🔄 Retrying GPU initialization...")
        let cacheLimit = Self.gpuCacheLimit
        MLX.GPU.set(cacheLimit: cacheLimit)
        logger.info("🔧 MLX initialized with \(cacheLimit / 1024 / 1024)MB GPU cache")
        isGPUInitialized = true
    }

    // MARK: - Memory Monitoring

    /// Log current GPU memory usage for debugging
    private func logMemoryStats(label: String) {
        let activeMemory = GPU.activeMemory
        let cacheMemory = GPU.cacheMemory
        let peakMemory = GPU.peakMemory

        let activeMB = Double(activeMemory) / 1024 / 1024
        let cacheMB = Double(cacheMemory) / 1024 / 1024
        let peakMB = Double(peakMemory) / 1024 / 1024

        logger.info("📊 [\(label)] GPU Memory - Active: \(String(format: "%.1f", activeMB))MB, Cache: \(String(format: "%.1f", cacheMB))MB, Peak: \(String(format: "%.1f", peakMB))MB")
    }

    // MARK: - AIProviderInterface

    func testConnection() async throws -> Bool {
        // For MLX, "connection" means having a model loaded and ready
        connectionStatus = .connecting

        if chatSession != nil {
            connectionStatus = .connected
            isConnected = true
            return true
        } else {
            connectionStatus = .disconnected
            isConnected = false
            return false
        }
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        // MLX doesn't support one-off generation due to memory constraints
        // Title generation should use heuristics instead
        throw MLXError.invalidConfiguration
    }

    func getCapabilities() async throws -> AICapabilities {
        return AICapabilities(
            supportedModels: currentModelId.map { [$0] } ?? [],
            maxTokens: currentConfig.maxTokens,
            supportsStreaming: true,
            supportsImages: false, // Text-only for now
            supportsDocuments: true,
            supportedLanguages: ["en"] // MedGemma primarily English
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // MLX doesn't use network config, but we can update generation parameters
        logger.info("🔧 MLX configuration updated")
    }

    // MARK: - Model Management

    /// Load a model into memory using MLX's built-in download/cache system
    func loadModel(modelId: String) async throws {
        // Prevent concurrent loads - if already loading, wait for it to complete
        if isLoadingModel {
            logger.info("⏳ MLX: Model load already in progress, waiting...")
            // Wait for current load to complete (poll every 100ms, max 30 seconds)
            for _ in 0..<300 {
                try await Task.sleep(nanoseconds: 100_000_000)
                if !isLoadingModel {
                    logger.info("✅ MLX: Previous load completed, using existing session")
                    if chatSession != nil {
                        return // Model is now loaded
                    }
                    break // Load failed, try again
                }
            }
            if isLoadingModel {
                throw MLXError.modelLoadFailed("Timed out waiting for model to load")
            }
        }

        // If model is already loaded with this ID, skip reload
        // Check loadedModel (not chatSession) since session may be nil after reset
        if loadedModel != nil && currentModelId == modelId {
            logger.info("✅ MLX: Model already loaded, skipping reload")
            // Ensure we have a chat session even if model is loaded
            if chatSession == nil, let model = loadedModel {
                chatSession = ChatSession(model)
            }
            return
        }

        isLoadingModel = true
        logger.info("📂 Loading MLX model: \(modelId)")
        isLoading = true
        defer {
            isLoading = false
            isLoadingModel = false
        }

        // Get the HuggingFace repo ID from the model registry
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }

        let huggingFaceRepo = modelConfig.huggingFaceRepo
        logger.info("📦 Loading from HuggingFace: \(huggingFaceRepo)")

        do {
            // Ensure GPU initialization completes on the MainActor before loading
            await gpuInitializationTask.value

            // Verify GPU initialization succeeded
            guard isGPUInitialized else {
                logger.error("❌ GPU initialization failed - cannot load model. Try calling retryGPUInitialization()")
                throw MLXError.modelLoadFailed("GPU initialization failed. The GPU cache could not be configured. Try restarting the app or calling retryGPUInitialization().")
            }

            // Use MLX's built-in loading (downloads if needed, uses cache if available)
            // Already on MainActor due to class-level isolation
            let model = try await MLXLMCommon.loadModel(id: huggingFaceRepo)

            // Store the model reference for reuse when resetting sessions
            self.loadedModel = model

            // Create chat session with the loaded model
            chatSession = ChatSession(model)
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            logger.info("✅ Successfully loaded MLX model: \(modelId)")
            logMemoryStats(label: "After Model Load")

        } catch {
            logger.error("❌ Failed to load MLX model", error: error)
            loadedModel = nil
            chatSession = nil
            currentModelId = nil
            isConnected = false
            connectionStatus = .disconnected
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model from memory
    func unloadModel() {
        logger.info("🗑️ Unloading MLX model")
        chatSession = nil
        loadedModel = nil  // Clear the model reference to free memory
        currentModelId = nil
        isConnected = false
        connectionStatus = .disconnected
    }

    /// Delete a downloaded model from cache
    func deleteModel(modelId: String) async throws {
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }

        // Unload if this is the current model
        if currentModelId == modelId {
            unloadModel()
        }

        logger.info("🗑️ Deleting model: \(modelId)")

        // Get the HuggingFace cache directory (iOS compatible)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let cacheDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        // Model directories follow pattern: models--<org>--<model>
        let repoPath = modelConfig.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelDirectory = cacheDirectory.appendingPathComponent("models--\(repoPath)")

        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
            logger.info("✅ Deleted model cache at: \(modelDirectory.path)")
        } else {
            logger.warning("⚠️ Model cache not found at: \(modelDirectory.path)")
        }
    }

    /// Check if a model is downloaded
    func isModelDownloaded(modelId: String) -> Bool {
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            return false
        }

        // Get the HuggingFace cache directory (iOS compatible)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let cacheDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        let repoPath = modelConfig.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelDirectory = cacheDirectory.appendingPathComponent("models--\(repoPath)")

        return FileManager.default.fileExists(atPath: modelDirectory.path)
    }

    /// Reset the chat session to clear conversation history and KV cache
    /// This creates a fresh ChatSession without reloading the model from disk
    func resetSession() async throws {
        guard let model = loadedModel else {
            // No model loaded - need to load it first
            guard let modelId = currentModelId else {
                throw MLXError.invalidConfiguration
            }
            logger.info("🔄 No loaded model found, loading model: \(modelId)")
            try await loadModel(modelId: modelId)
            return
        }

        logger.info("🔄 Resetting chat session (reusing loaded model)")
        logMemoryStats(label: "Before Session Reset")

        // Clear the current session to free KV cache memory
        chatSession = nil

        // Force GPU cache cleanup to release KV cache memory
        // This is critical to prevent memory accumulation across turns
        GPU.clearCache()
        logMemoryStats(label: "After Cache Clear")

        // Longer delay to ensure memory is fully freed before allocating new session
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Create a fresh ChatSession with the already-loaded model
        // This avoids reloading ~2GB of model weights from disk
        chatSession = ChatSession(model)
        logMemoryStats(label: "After New Session")

        logger.info("✅ Chat session reset complete")
    }

    /// Set generation configuration
    func setGenerationConfig(_ config: MLXGenerationConfig) {
        logger.info("🔧 Updating generation config - temp: \(config.temperature), maxTokens: \(config.maxTokens)")
        currentConfig = config
    }

    // MARK: - Streaming Support

    /// Send streaming chat message
    /// - Parameters:
    ///   - message: The user's current message
    ///   - context: Health data context string
    ///   - systemPrompt: Doctor's system prompt/instructions
    ///   - conversationHistory: Previous messages in the conversation for context
    ///   - conversationId: UUID of the current conversation
    ///   - onUpdate: Callback for streaming updates
    ///   - onComplete: Callback when generation completes
    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        systemPrompt: String?,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        guard let modelId = currentModelId else {
            logger.error("❌ MLX: No model selected - currentModelId is nil")
            throw MLXError.invalidConfiguration
        }

        // Check if model is actually loaded
        if chatSession == nil {
            logger.info("🔄 MLX: Model not loaded, attempting to auto-load: \(modelId)")
            do {
                try await loadModel(modelId: modelId)
            } catch {
                logger.error("❌ MLX: Failed to auto-load model: \(modelId)", error: error)
                throw MLXError.modelLoadFailed("Failed to load model: \(error.localizedDescription)")
            }
        }

        // Check if this model requires special handling (like MedGemma)
        let requiresSpecialFormatting = SystemPromptExceptionList.shared.requiresInstructionInjection(for: modelId)

        // Check if we need to reset the session
        let (shouldReset, isNewConversation) = shouldResetSession(for: conversationId)

        // For MedGemma and similar models: reset session on EVERY turn
        // These models don't properly maintain KV cache across turns, so we
        // send the full context each time and reset to avoid shape mismatches.
        // LIMITATION: This means MedGemma doesn't have conversation history -
        // each turn is treated independently with only the health context.
        // TODO: To support conversation history, we would need to build previous
        // messages into the CONTEXT section of the prompt.
        let needsReset = shouldReset || (requiresSpecialFormatting && conversationTokenCount > 0)
        let isFirstTurn = isNewConversation || chatSession == nil || needsReset

        if needsReset && chatSession != nil {
            if requiresSpecialFormatting {
                logger.info("🔄 Resetting session for MedGemma - each turn gets fresh context")
            } else {
                logger.info("🔄 Resetting session - switching conversation or context limit reached")
            }
            try await resetSession()
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else if isNewConversation {
            // New conversation but no reset needed (session is fresh)
            logger.info("📝 New conversation, session is fresh - updating conversation ID")
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else {
            logger.debug("📝 Continuing conversation - token count: \(conversationTokenCount)")
        }

        guard let session = chatSession else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the prompt
        // Note: requiresSpecialFormatting already calculated above, modelId from guard statement

        let fullPrompt: String
        if requiresSpecialFormatting {
            // For MedGemma and similar models: ALWAYS use INSTRUCTIONS/CONTEXT/QUESTION format
            // These models don't properly maintain KV cache across turns with varying formats,
            // so we include the full context on every turn for consistency
            // Also include conversation history so the model has context from previous exchanges
            fullPrompt = SystemPromptExceptionList.shared.formatMessageWithHistory(
                userMessage: message,
                systemPrompt: systemPrompt,
                context: context,
                conversationHistory: conversationHistory,
                maxTokens: currentConfig.contextWindow
            )
            let historyCount = conversationHistory.filter { $0.role == .user || $0.role == .assistant }.count
            logger.info("📋 MedGemma format - including \(historyCount) history messages, context window: \(currentConfig.contextWindow)")
        } else if isFirstTurn {
            // Standard models: include context on first turn only
            fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)
            logger.debug("📋 First turn - using standard format with full context")
        } else {
            // Standard models: just the message on subsequent turns (ChatSession maintains history)
            fullPrompt = message
            logger.debug("📋 Subsequent turn - message only")
        }

        logger.info("🤖 Streaming response with MLX model")
        logger.debug("📋 Full prompt:\n\(fullPrompt.prefix(200))...")

        // Debug logging for instruction injection
        logger.info("🔍 MLXClient: isFirstTurn=\(isFirstTurn), shouldReset=\(shouldReset), promptLength=\(fullPrompt.count)")
        if fullPrompt.count > 200 {
            logger.debug("🔍 MLXClient: Prompt preview: \(String(fullPrompt.prefix(200)))...")
        } else {
            logger.debug("🔍 MLXClient: Full prompt: \(fullPrompt)")
        }

        logMemoryStats(label: "Before Generation")
        let startTime = Date()

        do {
            var finalText = ""
            var tokenCount = 0
            let maxTokens = currentConfig.maxTokens

            // Track last N characters to detect repetition
            var previousChunk = ""
            var repetitionCount = 0

            // Throttle UI updates to prevent performance degradation
            var lastUpdateTime = Date()
            let updateInterval: TimeInterval = 0.1 // Update UI every 100ms max
            var tokensPerUpdate = 0

            // Stream tokens using ChatSession
            // Note: We're already on MainActor (class-level isolation), so we can call
            // streamResponse directly without MainActor.run wrapper
            // The iteration may happen on a background thread (AsyncSequence behavior),
            // which is why we use deliverUpdate() to marshal callbacks back to MainActor
            for try await token in session.streamResponse(to: fullPrompt) {
                tokenCount += 1
                tokensPerUpdate += 1

                // Append the token to build the complete response
                finalText += token

                // Check for Gemma end-of-turn tokens
                // IMPORTANT: Only check the SUFFIX of the text (last 20 chars) to avoid false positives
                // when conversation history contains these tokens from previous turns
                // Also require minimum 50 tokens before stopping - prevents premature cutoff
                let recentSuffix = String(finalText.suffix(20))
                let hasEndToken = recentSuffix.contains("<end_of_turn>") ||
                                  recentSuffix.contains("<|eot_id|>") ||
                                  recentSuffix.contains("</s>")

                if hasEndToken && tokenCount >= 50 {
                    logger.info("🛑 Detected end-of-turn token at end of response, stopping stream (token #\(tokenCount))")
                    // Remove the end token from final text
                    finalText = finalText.replacingOccurrences(of: "<end_of_turn>", with: "")
                    finalText = finalText.replacingOccurrences(of: "<|eot_id|>", with: "")
                    finalText = finalText.replacingOccurrences(of: "</s>", with: "")
                    // Send final update before breaking
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    break
                } else if hasEndToken {
                    // End token detected but too early - log and remove it but continue
                    logger.warning("⚠️ End-of-turn token detected early (token #\(tokenCount)), removing and continuing...")
                    finalText = finalText.replacingOccurrences(of: "<end_of_turn>", with: "")
                    finalText = finalText.replacingOccurrences(of: "<|eot_id|>", with: "")
                    finalText = finalText.replacingOccurrences(of: "</s>", with: "")
                }

                // Detect repetition (same content being generated repeatedly)
                let recentChunk = String(finalText.suffix(100))
                if recentChunk == previousChunk {
                    repetitionCount += 1
                    if repetitionCount > 3 {
                        logger.warning("⚠️ Detected repetition loop, stopping stream")
                        // Send final update before breaking
                        deliverUpdate(finalText, onUpdate: onUpdate)
                        break
                    }
                } else {
                    repetitionCount = 0
                    previousChunk = recentChunk
                }

                // Safety check: respect maxTokens limit
                if tokenCount >= maxTokens {
                    logger.warning("⚠️ Reached max tokens limit (\(maxTokens)), stopping stream")
                    // Send final update before breaking
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    break
                }

                // Log every 50th token to track progress
                if tokenCount % 50 == 0 {
                    logger.debug("📝 MLX streaming token \(tokenCount), total length: \(finalText.count), last 50 chars: \(String(finalText.suffix(50)))")
                }

                // Throttle UI updates: only update every 100ms to prevent performance issues
                // This prevents CPU spikes from constant SwiftUI re-renders of growing text
                let now = Date()
                let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
                if timeSinceLastUpdate >= updateInterval {
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    lastUpdateTime = now
                    if tokensPerUpdate > 0 {
                        logger.debug("📊 Updated UI: \(tokensPerUpdate) tokens in \(String(format: "%.0f", timeSinceLastUpdate * 1000))ms")
                        tokensPerUpdate = 0
                    }
                }
            }

            // Send final update to ensure UI has the complete text
            deliverUpdate(finalText, onUpdate: onUpdate)

            logger.info("✅ MLX streaming completed: \(tokenCount) tokens, \(finalText.count) characters")
            logMemoryStats(label: "After Generation")

            // Update conversation token count
            conversationTokenCount += tokenCount

            let processingTime = Date().timeIntervalSince(startTime)
            let cleanedText = AIResponseCleaner.cleanConversational(finalText)

            let response = MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": currentModelId ?? "unknown",
                    "temperature": currentConfig.temperature,
                    "streaming": true,
                    "conversationTokens": conversationTokenCount
                ]
            )

            deliverCompletion(response, onComplete: onComplete)

        } catch {
            logger.error("❌ MLX streaming failed", error: error)
            throw MLXError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Delivers streaming update to MainActor, safe to call from any context
    ///
    /// Creates a new Task to ensure MainActor execution regardless of caller's context.
    /// While this creates one Task per update during streaming, it's necessary because:
    /// 1. AsyncSequence iteration may change execution context
    /// 2. Guarantees UI callbacks always run on MainActor
    /// 3. Swift's Task system is optimized for short-lived tasks
    ///
    /// - Parameters:
    ///   - text: The accumulated response text
    ///   - onUpdate: Callback to deliver the update (will be called on MainActor)
    private func deliverUpdate(_ text: String, onUpdate: @escaping (String) -> Void) {
        Task { @MainActor in
            onUpdate(text)
        }
    }

    /// Delivers completion response to MainActor, safe to call from any context
    /// - Parameters:
    ///   - response: The final MLX response
    ///   - onComplete: Callback to deliver completion (will be called on MainActor)
    private func deliverCompletion(_ response: MLXResponse, onComplete: @escaping (MLXResponse) -> Void) {
        Task { @MainActor in
            onComplete(response)
        }
    }

    /// Determine if we should reset the session
    /// Returns: (shouldReset, isNewConversation)
    private func shouldResetSession(for conversationId: UUID?) -> (shouldReset: Bool, isNewConversation: Bool) {
        // No session exists - don't reset, just load
        guard chatSession != nil else {
            return (shouldReset: false, isNewConversation: true)
        }

        // Conversation ID changed (switching to a different conversation)
        if let conversationId = conversationId, conversationId != currentConversationId {
            logger.debug("🔄 Conversation changed: \(String(describing: currentConversationId)) → \(conversationId)")
            // Only reset if we've actually had a conversation (token count > 0)
            // If token count is 0, the session is already fresh
            if conversationTokenCount > 0 {
                return (shouldReset: true, isNewConversation: true)
            } else {
                // Just update the conversation ID, no reset needed
                return (shouldReset: false, isNewConversation: true)
            }
        }

        // Reset if approaching context window limit (90% of max)
        let contextLimit = Int(Double(currentConfig.contextWindow) * 0.9)
        if conversationTokenCount >= contextLimit {
            logger.warning("⚠️ Approaching context limit: \(conversationTokenCount)/\(currentConfig.contextWindow)")
            return (shouldReset: true, isNewConversation: false)
        }

        return (shouldReset: false, isNewConversation: false)
    }

    private func buildPrompt(message: String, context: String, systemPrompt: String? = nil) -> String {
        // MedGemma uses Gemma's chat template format
        // ChatSession handles turn markers, so we provide a clean user message
        // Avoid mentioning turn markers or special tokens in the prompt itself

        var prompt = ""

        // Include system instructions as part of the message content
        // Don't use special formatting that might confuse the model
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            prompt += systemPrompt + "\n\n"
        }

        if !context.isEmpty {
            prompt += "Patient Health Information:\n\(context)\n\n"
        }

        // Simple, direct question format
        prompt += message

        logger.debug("📝 Prompt length: \(prompt.count) characters")

        return prompt
    }

    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
}

// MARK: - MLX Response

struct MLXResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(
        content: String,
        responseTime: TimeInterval,
        tokenCount: Int?,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}
