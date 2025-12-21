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
    private var currentConfig: MLXGenerationConfig = .default
    private let logger = Logger.shared

    // Conversation tracking
    private var currentConversationId: UUID?
    private var conversationTokenCount: Int = 0

    // MARK: - Initialization
    private init() {
        // Set GPU cache limit for MLX
        // Increased from 512MB to 4GB to support larger models
        // Requires increased-memory-limit entitlement in production
        let cacheLimit = 4 * 1024 * 1024 * 1024  // 4GB GPU cache for medical LLMs
        MLX.GPU.set(cacheLimit: cacheLimit)

        logger.info("🔧 MLX initialized with \(cacheLimit / 1024 / 1024)MB GPU cache")
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
        logger.info("📂 Loading MLX model: \(modelId)")
        isLoading = true
        defer { isLoading = false }

        // Get the HuggingFace repo ID from the model registry
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }

        let huggingFaceRepo = modelConfig.huggingFaceRepo
        logger.info("📦 Loading from HuggingFace: \(huggingFaceRepo)")

        do {
            // Use MLX's built-in loading (downloads if needed, uses cache if available)
            let loadedModel = try await MLXLMCommon.loadModel(id: huggingFaceRepo)

            // Create chat session with the loaded model
            chatSession = ChatSession(loadedModel)
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            logger.info("✅ Successfully loaded MLX model: \(modelId)")

        } catch {
            logger.error("❌ Failed to load MLX model", error: error)
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
    func resetSession() async throws {
        guard let modelId = currentModelId else {
            throw MLXError.invalidConfiguration
        }

        logger.info("🔄 Resetting chat session")

        // Explicitly unload the current session first to free memory
        // This prevents having both old and new models in memory simultaneously
        chatSession = nil

        // Small delay to ensure memory is freed
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Reload the model to get a fresh session
        try await loadModel(modelId: modelId)
    }

    /// Set generation configuration
    func setGenerationConfig(_ config: MLXGenerationConfig) {
        logger.info("🔧 Updating generation config - temp: \(config.temperature), maxTokens: \(config.maxTokens)")
        currentConfig = config
    }

    // MARK: - Streaming Support

    /// Send streaming chat message
    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        systemPrompt: String?,
        conversationId: UUID? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        guard let modelId = currentModelId else {
            throw MLXError.invalidConfiguration
        }

        // Check if we need to reset the session
        let shouldReset = shouldResetSession(for: conversationId)
        let isFirstTurn = shouldReset || chatSession == nil

        if shouldReset {
            logger.info("🔄 Resetting session - new conversation or context limit")
            try await resetSession()
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else {
            logger.debug("📝 Continuing conversation - token count: \(conversationTokenCount)")
        }

        // Auto-load model if not already loaded
        if chatSession == nil {
            logger.info("🔄 Auto-loading model: \(modelId)")
            try await loadModel(modelId: modelId)
        }

        guard let session = chatSession else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the prompt
        // For first turn: include full context (system prompt + health data + message)
        // For subsequent turns: only the new message (ChatSession maintains history)
        let fullPrompt: String
        if isFirstTurn {
            fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)
            logger.debug("📋 First turn - including full context")
        } else {
            fullPrompt = message
            logger.debug("📋 Subsequent turn - message only")
        }

        logger.info("🤖 Streaming response with MLX model")
        logger.debug("📋 Full prompt:\n\(fullPrompt.prefix(200))...")
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
            // streamResponse yields individual token strings that need to be accumulated
            for try await token in session.streamResponse(to: fullPrompt) {
                tokenCount += 1
                tokensPerUpdate += 1

                // Append the token to build the complete response
                finalText += token

                // Check for Gemma end-of-turn tokens
                if finalText.contains("<end_of_turn>") ||
                   finalText.contains("<|eot_id|>") ||
                   finalText.contains("</s>") {
                    logger.info("🛑 Detected end-of-turn token, stopping stream")
                    // Remove the end token from final text
                    finalText = finalText.replacingOccurrences(of: "<end_of_turn>", with: "")
                    finalText = finalText.replacingOccurrences(of: "<|eot_id|>", with: "")
                    finalText = finalText.replacingOccurrences(of: "</s>", with: "")
                    // Send final update before breaking
                    onUpdate(finalText)
                    break
                }

                // Detect repetition (same content being generated repeatedly)
                let recentChunk = String(finalText.suffix(100))
                if recentChunk == previousChunk {
                    repetitionCount += 1
                    if repetitionCount > 3 {
                        logger.warning("⚠️ Detected repetition loop, stopping stream")
                        // Send final update before breaking
                        onUpdate(finalText)
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
                    onUpdate(finalText)
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
                    onUpdate(finalText)
                    lastUpdateTime = now
                    if tokensPerUpdate > 0 {
                        logger.debug("📊 Updated UI: \(tokensPerUpdate) tokens in \(String(format: "%.0f", timeSinceLastUpdate * 1000))ms")
                        tokensPerUpdate = 0
                    }
                }
            }

            // Send final update to ensure UI has the complete text
            onUpdate(finalText)

            logger.info("✅ MLX streaming completed: \(tokenCount) tokens, \(finalText.count) characters")

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

            onComplete(response)

        } catch {
            logger.error("❌ MLX streaming failed", error: error)
            throw MLXError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Determine if we should reset the session
    private func shouldResetSession(for conversationId: UUID?) -> Bool {
        // Reset if no session exists
        guard chatSession != nil else {
            return true
        }

        // Reset if conversation ID changed (new conversation)
        if let conversationId = conversationId, conversationId != currentConversationId {
            logger.debug("🔄 Conversation changed: \(String(describing: currentConversationId)) → \(conversationId)")
            return true
        }

        // Reset if approaching context window limit (90% of max)
        let contextLimit = Int(Double(currentConfig.contextWindow) * 0.9)
        if conversationTokenCount >= contextLimit {
            logger.warning("⚠️ Approaching context limit: \(conversationTokenCount)/\(currentConfig.contextWindow)")
            return true
        }

        return false
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

