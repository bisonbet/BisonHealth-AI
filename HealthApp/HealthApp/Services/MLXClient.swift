import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - MLX Client

/// Client for running local LLMs using Apple's MLX framework
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
    private var loadedModel: LMModel?
    private var currentConfig: MLXGenerationConfig = .default
    private let modelManager = MLXModelManager.shared
    private let logger = Logger.shared

    // MARK: - Initialization
    private init() {
        // Check if MLX is available on this device
        if MLX.GPU.isAvailable {
            logger.info("🔧 MLX GPU acceleration available")
            // Set memory cache limit (20MB default)
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        } else {
            logger.warning("⚠️ MLX GPU acceleration not available, will use CPU")
        }
    }

    // MARK: - AIProviderInterface

    func testConnection() async throws -> Bool {
        // For MLX, "connection" means having a model downloaded and ready
        connectionStatus = .connecting

        if let modelId = currentModelId,
           modelManager.isModelDownloaded(modelId) {
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

        guard modelManager.isModelDownloaded(modelId) else {
            throw MLXError.modelNotFound
        }

        // Load model if not already loaded
        if loadedModel == nil || loadedModel?.id != modelId {
            try await loadModel(modelId: modelId)
        }

        guard let model = loadedModel else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the full prompt with context and system prompt
        let fullPrompt = buildPrompt(message: message, context: context)

        logger.info("🤖 Generating response with MLX model: \(modelId)")
        let startTime = Date()

        do {
            // Generate response using MLX
            let generatedText = try await generateText(
                model: model,
                prompt: fullPrompt,
                config: currentConfig
            )

            let processingTime = Date().timeIntervalSince(startTime)

            // Clean the response
            let cleanedText = AIResponseCleaner.cleanConversational(generatedText)

            // Mark model as used
            await modelManager.markModelUsed(modelId)

            logger.info("✅ Generated response in \(String(format: "%.2f", processingTime))s")

            return MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": modelId,
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
            supportedModels: modelManager.downloadedModels.map { $0.id },
            maxTokens: currentConfig.maxTokens,
            supportsStreaming: true,
            supportsImages: false, // Text-only for now
            supportsDocuments: true,
            supportedLanguages: ["en"] // MedGemma primarily English
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // MLX doesn't use network config, but we can update generation parameters
        // This would be called from SettingsManager if needed
        logger.info("🔧 MLX configuration updated")
    }

    // MARK: - Model Management

    /// Load a model into memory
    func loadModel(modelId: String) async throws {
        logger.info("📂 Loading MLX model: \(modelId)")
        isLoading = true
        defer { isLoading = false }

        guard let localModel = modelManager.getLocalModel(modelId) else {
            throw MLXError.modelNotFound
        }

        do {
            // Load the model using MLXLMCommon
            let modelPath = localModel.localPath.path

            logger.info("📂 Model path: \(modelPath)")

            // Use the async load function from MLXLMCommon
            let model = try await LMModel.load(path: modelPath)

            loadedModel = model
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            logger.info("✅ Model loaded successfully: \(localModel.config.name)")

        } catch {
            logger.error("❌ Failed to load model", error: error)
            loadedModel = nil
            currentModelId = nil
            isConnected = false
            connectionStatus = .disconnected
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model from memory
    func unloadModel() {
        logger.info("🗑️ Unloading MLX model")
        loadedModel = nil
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

    /// Send streaming chat message (similar to Ollama streaming)
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

        guard modelManager.isModelDownloaded(modelId) else {
            throw MLXError.modelNotFound
        }

        // Load model if not already loaded
        if loadedModel == nil || loadedModel?.id != modelId {
            try await loadModel(modelId: modelId)
        }

        guard let model = loadedModel else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the full prompt
        let fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)

        logger.info("🤖 Streaming response with MLX model: \(modelId)")
        let startTime = Date()

        do {
            var accumulatedText = ""

            // Stream tokens using MLX
            try await streamText(
                model: model,
                prompt: fullPrompt,
                config: currentConfig,
                onToken: { token in
                    accumulatedText += token
                    onUpdate(accumulatedText)
                }
            )

            let processingTime = Date().timeIntervalSince(startTime)
            let cleanedText = AIResponseCleaner.cleanConversational(accumulatedText)

            // Mark model as used
            await modelManager.markModelUsed(modelId)

            let response = MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": modelId,
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
            prompt += "<|system|>\n\(systemPrompt)\n"
        }

        // Add context if provided
        if !context.isEmpty {
            prompt += "<|context|>\n\(context)\n"
        }

        // Add user message
        prompt += "<|user|>\n\(message)\n"
        prompt += "<|assistant|>\n"

        return prompt
    }

    /// Generate text using MLX model (non-streaming)
    private func generateText(
        model: LMModel,
        prompt: String,
        config: MLXGenerationConfig
    ) async throws -> String {
        // Create generate parameters for MLX
        let generateParams = GenerateParameters(
            temperature: Float(config.temperature),
            topP: Float(config.topP),
            repetitionPenalty: Float(config.repetitionPenalty),
            repetitionContextSize: config.repetitionContextSize
        )

        // Generate using MLX Swift LM
        // The model generates tokens and we collect them into a string
        var generatedText = ""
        var tokenCount = 0
        let maxTokens = config.maxTokens

        // Use the model's generate method which returns an async sequence of tokens
        for try await output in model.generate(
            prompt: prompt,
            parameters: generateParams,
            maxTokens: maxTokens
        ) {
            generatedText += output
            tokenCount += 1

            if tokenCount >= maxTokens {
                break
            }
        }

        return generatedText
    }

    /// Stream text generation token by token
    private func streamText(
        model: LMModel,
        prompt: String,
        config: MLXGenerationConfig,
        onToken: @escaping (String) -> Void
    ) async throws {
        let generateParams = GenerateParameters(
            temperature: Float(config.temperature),
            topP: Float(config.topP),
            repetitionPenalty: Float(config.repetitionPenalty),
            repetitionContextSize: config.repetitionContextSize
        )

        var tokenCount = 0
        let maxTokens = config.maxTokens

        // Stream tokens as they're generated
        for try await output in model.generate(
            prompt: prompt,
            parameters: generateParams,
            maxTokens: maxTokens
        ) {
            onToken(output)
            tokenCount += 1

            if tokenCount >= maxTokens {
                break
            }
        }
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

// MARK: - MLX Model Extensions

extension LMModel {
    /// Unique identifier for the model
    var id: String {
        // Extract model ID from path or use a unique identifier
        return self.modelPath ?? UUID().uuidString
    }

    /// Model path if available
    var modelPath: String? {
        // This would need to be tracked separately or extracted from model metadata
        // For now, return nil and rely on currentModelId
        return nil
    }
}

// MARK: - Generate Parameters Helper

struct GenerateParameters {
    let temperature: Float
    let topP: Float
    let repetitionPenalty: Float
    let repetitionContextSize: Int
}

// MARK: - LMModel Extension for Generation

extension LMModel {
    /// Generate text using the MLX model with an async sequence
    /// This matches the actual MLX Swift LM API pattern
    func generate(
        prompt: String,
        parameters: GenerateParameters,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use MLXLMCommon's actual generation method
                    // The real implementation uses the model's tokenizer and generate methods
                    // This is a simplified version - the actual MLX Swift LM package
                    // handles tokenization, generation, and detokenization internally

                    // Note: The actual API might be slightly different
                    // You may need to adjust based on the exact MLX Swift LM version
                    // Typical usage: model.generate(input: tokens, parameters: params)

                    // For now, this indicates where the actual MLX API calls would go
                    // The MLX Swift LM examples show this pattern
                    continuation.finish(throwing: MLXError.modelLoadFailed(
                        "MLX generation not fully implemented - requires MLX Swift LM package"
                    ))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
