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
    @Published var connectionStatus: AIConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var isLoading: Bool = false
    @Published var currentModelId: String?

    // MARK: - Private Properties
    private var loadedModel: LMModelContainer?
    private var currentModelPath: String?
    private var currentConfig: MLXGenerationConfig = .default
    private let modelManager = MLXModelManager.shared
    private let logger = Logger.shared

    // MARK: - Initialization
    private init() {
        // Check if MLX is available on this device
        if MLX.GPU.isAvailable {
            logger.info("🔧 MLX GPU acceleration available")
            // Set cache limit to 512MB for better performance with 2.5GB models
            MLX.GPU.set(cacheLimit: 512 * 1024 * 1024)
        } else {
            logger.warning("⚠️ MLX GPU acceleration not available, will use CPU")
            // Still set a reasonable cache for CPU mode
            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
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

        // Load model if not already loaded or if different model selected
        if loadedModel == nil || currentModelPath != modelManager.getLocalModel(modelId)?.localPath.path {
            try await loadModel(modelId: modelId)
        }

        guard let model = loadedModel else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the full prompt with context
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
            let modelPath = localModel.localPath.path
            logger.info("📂 Model path: \(modelPath)")

            // Create model configuration
            let modelConfig = ModelConfiguration(
                id: modelId,
                defaultPrompt: ""
            )

            // Load the model using MLXLMCommon
            logger.info("📂 Loading model from disk...")
            let container = try await LMModelContainer.load(
                path: modelPath,
                configuration: modelConfig
            )

            loadedModel = container
            currentModelPath = modelPath
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            logger.info("✅ Model loaded successfully: \(localModel.config.name)")

        } catch {
            logger.error("❌ Failed to load model", error: error)
            loadedModel = nil
            currentModelPath = nil
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
        currentModelPath = nil
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

        guard modelManager.isModelDownloaded(modelId) else {
            throw MLXError.modelNotFound
        }

        // Load model if not already loaded
        if loadedModel == nil || currentModelPath != modelManager.getLocalModel(modelId)?.localPath.path {
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

    /// Generate text using MLX model (non-streaming)
    private func generateText(
        model: LMModelContainer,
        prompt: String,
        config: MLXGenerationConfig
    ) async throws -> String {
        // Create generation parameters
        let generateParams = GenerateParameters(
            temperature: Float(config.temperature),
            topP: Float(config.topP),
            repetitionPenalty: Float(config.repetitionPenalty) ?? 1.0,
            repetitionContextSize: config.repetitionContextSize
        )

        // Generate using MLX Swift LM
        logger.info("🔮 Generating with temp: \(config.temperature), maxTokens: \(config.maxTokens)")

        let result = try await model.perform { model in
            try await model.generate(
                prompt: MLXLMCommon.UserInput(prompt: prompt),
                parameters: generateParams,
                maxTokens: config.maxTokens
            )
        }

        return result.output
    }

    /// Stream text generation token by token
    private func streamText(
        model: LMModelContainer,
        prompt: String,
        config: MLXGenerationConfig,
        onToken: @escaping (String) -> Void
    ) async throws {
        let generateParams = GenerateParameters(
            temperature: Float(config.temperature),
            topP: Float(config.topP),
            repetitionPenalty: Float(config.repetitionPenalty) ?? 1.0,
            repetitionContextSize: config.repetitionContextSize
        )

        logger.info("🔮 Streaming with temp: \(config.temperature), maxTokens: \(config.maxTokens)")

        // Use the streaming generate API
        try await model.perform { model in
            let stream = try await model.generateStream(
                prompt: MLXLMCommon.UserInput(prompt: prompt),
                parameters: generateParams,
                maxTokens: config.maxTokens
            )

            for try await token in stream {
                onToken(token.text)
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

// MARK: - LMModelContainer Wrapper

/// Container for managing MLX model lifecycle
class LMModelContainer {
    private let model: any LanguageModel
    private let modelPath: String

    init(model: any LanguageModel, path: String) {
        self.model = model
        self.modelPath = path
    }

    static func load(path: String, configuration: ModelConfiguration) async throws -> LMModelContainer {
        // Load model using MLX Swift LM
        let modelDirectory = URL(fileURLWithPath: path)

        // Use the actual MLX Swift LM API to load the model
        let loadedModel = try await MLXLLM.loadModel(configuration: .init(
            id: modelDirectory.lastPathComponent,
            name: configuration.id
        )) { progress in
            // Progress callback during model loading
            print("📊 Loading model: \(Int(progress * 100))%")
        }

        return LMModelContainer(model: loadedModel, path: path)
    }

    func perform<T>(_ operation: (any LanguageModel) async throws -> T) async throws -> T {
        return try await operation(model)
    }
}
