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
        guard let modelId = currentModelId else {
            throw MLXError.invalidConfiguration
        }

        // Auto-load model if not already loaded
        if chatSession == nil {
            logger.info("🔄 Auto-loading model: \(modelId)")
            try await loadModel(modelId: modelId)
        }

        // Check if chat session is loaded
        guard let session = chatSession else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the full prompt with context
        let fullPrompt = buildPrompt(message: message, context: context)

        logger.info("🤖 Generating response with MLX model")
        let startTime = Date()

        do {
            // Generate response using ChatSession
            let generatedText = try await session.respond(to: fullPrompt)

            let processingTime = Date().timeIntervalSince(startTime)

            // Clean the response
            let cleanedText = AIResponseCleaner.cleanConversational(generatedText)

            logger.info("✅ Generated response in \(String(format: "%.2f", processingTime))s")

            return MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": currentModelId ?? "unknown",
                    "temperature": currentConfig.temperature,
                    "maxTokens": currentConfig.maxTokens
                ]
            )

        } catch {
            logger.error("❌ MLX generation failed", error: error)
            lastError = error
            throw MLXError.generationFailed(error.localizedDescription)
        }
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
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        guard let modelId = currentModelId else {
            throw MLXError.invalidConfiguration
        }

        // Auto-load model if not already loaded
        if chatSession == nil {
            logger.info("🔄 Auto-loading model for streaming: \(modelId)")
            try await loadModel(modelId: modelId)
        }

        guard let session = chatSession else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the full prompt
        let fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)

        logger.info("🤖 Streaming response with MLX model")
        let startTime = Date()

        do {
            var finalText = ""

            // Stream tokens using ChatSession
            // Note: streamResponse yields complete accumulated text each iteration
            for try await text in session.streamResponse(to: fullPrompt) {
                finalText = text
                // Update with the full accumulated text so far
                // Already on MainActor, so just call directly
                onUpdate(text)
            }

            let processingTime = Date().timeIntervalSince(startTime)
            let cleanedText = AIResponseCleaner.cleanConversational(finalText)

            let response = MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": currentModelId ?? "unknown",
                    "temperature": currentConfig.temperature,
                    "streaming": true
                ]
            )

            onComplete(response)

        } catch {
            logger.error("❌ MLX streaming failed", error: error)
            throw MLXError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func buildPrompt(message: String, context: String, systemPrompt: String? = nil) -> String {
        var prompt = ""

        // Add system prompt if provided
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            prompt += "\(systemPrompt)\n\n"
        }

        // Add context if provided
        if !context.isEmpty {
            prompt += "Context:\n\(context)\n\n"
        }

        // Add user message
        prompt += "User: \(message)\n\nAssistant:"

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

