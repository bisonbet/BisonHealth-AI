import Foundation
import AWSBedrockRuntime
import AWSClientRuntime

// MARK: - AWS Bedrock Models for Health App
enum AWSBedrockModel: String, CaseIterable {
    case claudeSonnet45 = "global.anthropic.claude-sonnet-4.5-20250929-v1:0"
    case llama4Maverick = "us.meta.llama4-maverick-17b-instruct-v1:0"
    case amazonNovaPremier = "us.amazon.nova-premier-v1:0"

    var displayName: String {
        switch self {
        case .claudeSonnet45:
            return "Claude Sonnet 4.5"
        case .llama4Maverick:
            return "Llama 4 Maverick"
        case .amazonNovaPremier:
            return "Amazon Nova Premier"
        }
    }

    var description: String {
        switch self {
        case .claudeSonnet45:
            return "Latest Claude Sonnet 4.5 with advanced reasoning and analysis capabilities"
        case .llama4Maverick:
            return "Meta's Llama 4 Maverick 17B with strong instruction-following"
        case .amazonNovaPremier:
            return "Amazon's Nova Premier model with high-performance AI capabilities"
        }
    }

    var maxTokens: Int {
        switch self {
        case .claudeSonnet45:
            return 8192
        case .llama4Maverick:
            return 4096
        case .amazonNovaPremier:
            return 8192
        }
    }

    var contextWindow: Int {
        switch self {
        case .claudeSonnet45:
            return 200000
        case .llama4Maverick:
            return 128000
        case .amazonNovaPremier:
            return 200000
        }
    }

    var provider: String {
        switch self {
        case .claudeSonnet45:
            return "Anthropic"
        case .llama4Maverick:
            return "Meta"
        case .amazonNovaPremier:
            return "Amazon"
        }
    }

    var supportsStructuredOutput: Bool {
        switch self {
        case .claudeSonnet45:
            return true
        case .llama4Maverick:
            return false
        case .amazonNovaPremier:
            return true
        }
    }
}

// MARK: - AWS Bedrock Configuration
struct AWSBedrockConfig: Equatable {
    let region: String
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let model: AWSBedrockModel
    let temperature: Double
    let maxTokens: Int
    let timeout: TimeInterval
    let useProfile: Bool
    let profileName: String?

    static let `default` = AWSBedrockConfig(
        region: "us-east-1",
        accessKeyId: "",
        secretAccessKey: "",
        sessionToken: nil,
        model: .claudeSonnet45,
        temperature: 0.1,
        maxTokens: 4096,
        timeout: 300.0,
        useProfile: false,
        profileName: nil
    )

    var isValid: Bool {
        if useProfile {
            return !region.isEmpty && profileName != nil && !profileName!.isEmpty
        } else {
            return !region.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
        }
    }
}

// MARK: - AWS Bedrock Service (matches your working implementation)
@MainActor
class BedrockClient: ObservableObject, AIProviderInterface {

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var config: AWSBedrockConfig

    // Default model to use when called via AIProviderInterface (overrides config.model if set)
    var currentModel: AWSBedrockModel?

    // MARK: - Private Properties
    private var bedrockClient: BedrockRuntimeClient?

    // MARK: - Initialization
    init(config: AWSBedrockConfig = .default) {
        self.config = config
        // Client will be initialized lazily when first needed
        self.bedrockClient = nil
    }

    // MARK: - Configuration Updates
    func updateConfig(_ newConfig: AWSBedrockConfig) {
        self.config = newConfig
        // Reset client to force reinitialization with new config
        self.bedrockClient = nil
    }

    // MARK: - Private Helper Methods (matches your working pattern)
    private func getBedrockClient() async throws -> BedrockRuntimeClient {
        if let client = bedrockClient {
            return client
        }

        guard config.isValid else {
            throw BedrockError.invalidConfiguration
        }

        // Set environment variables for AWS SDK to use
        setenv("AWS_ACCESS_KEY_ID", config.accessKeyId, 1)
        setenv("AWS_SECRET_ACCESS_KEY", config.secretAccessKey, 1)
        setenv("AWS_DEFAULT_REGION", config.region, 1)

        if let sessionToken = config.sessionToken {
            setenv("AWS_SESSION_TOKEN", sessionToken, 1)
        }

        do {
            let clientConfig = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(
                region: config.region
            )

            // AWS SDK for Swift will automatically use environment variables
            let client = BedrockRuntimeClient(config: clientConfig)
            self.bedrockClient = client
            return client
        } catch {
            throw BedrockError.networkError(error)
        }
    }

    // MARK: - AIProviderInterface Implementation
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting

        do {
            let testPrompt = "Hello, this is a test message. Please respond with 'Test successful'."
            let response = try await invokeModel(
                prompt: testPrompt,
                systemPrompt: "You are a helpful assistant.",
                maxTokens: 50,
                temperature: 0.1
            )

            let success = response.contains("Test successful") || response.contains("test successful")

            if success {
                connectionStatus = .connected
                isConnected = true
            } else {
                connectionStatus = .error(BedrockError.invalidResponse)
                isConnected = false
            }

            return success

        } catch {
            connectionStatus = .error(error)
            lastError = error
            isConnected = false
            throw error
        }
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        let startTime = Date()

        do {
            // Extract system prompt from context if present (format: "System: <prompt>\n\nContext: <context>")
            var systemPrompt = "You are a helpful AI assistant specialized in analyzing health data and providing medical insights. Focus on being accurate, helpful, and professional."
            var actualContext = context

            if context.hasPrefix("System: ") {
                // Split on "\n\nContext: " to separate system prompt from health context
                let components = context.components(separatedBy: "\n\nContext: ")
                if components.count >= 2 {
                    // Extract system prompt (remove "System: " prefix)
                    systemPrompt = String(components[0].dropFirst(8)) // "System: ".count = 8
                    // Remaining is the actual health context
                    actualContext = components.dropFirst().joined(separator: "\n\nContext: ")
                } else {
                    // Entire context is the system prompt
                    systemPrompt = String(context.dropFirst(8))
                    actualContext = ""
                }
            }

            // Prepare the conversation with context if provided
            var conversationInput = message
            if !actualContext.isEmpty {
                conversationInput = """
                Context (JSON Format): \(actualContext)

                User: \(message)
                """
            }

            let response = try await invokeModel(
                prompt: conversationInput,
                systemPrompt: systemPrompt,
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )

            let responseTime = Date().timeIntervalSince(startTime)

            // Clean the response to remove special tokens and unwanted text
            let cleanedResponse = AIResponseCleaner.cleanConversational(response)

            let modelUsed = currentModel ?? config.model

            return BedrockAIResponse(
                content: cleanedResponse,
                responseTime: responseTime,
                tokenCount: nil, // Token count not available from direct invoke
                metadata: [
                    "model": modelUsed.rawValue,
                    "region": config.region,
                    "provider": modelUsed.provider
                ]
            )

        } catch {
            lastError = error
            throw error
        }
    }

    func sendMessageWithDocument(_ message: String, documentData: Data, documentFormat: String, context: String = "") async throws -> AIResponse {
        // For now, just combine the document info with the message
        // TODO: Implement proper document handling when Bedrock supports it
        let documentInfo = "[Document attached: \(documentFormat) format, \(documentData.count) bytes]"
        let combinedMessage = "\(documentInfo)\n\n\(message)"

        return try await sendMessage(combinedMessage, context: context)
    }

    func getCapabilities() async throws -> AICapabilities {
        return AICapabilities(
            supportedModels: AWSBedrockModel.allCases.map { $0.rawValue },
            maxTokens: config.model.contextWindow,
            supportsStreaming: true,
            supportsImages: false, // For now
            supportsDocuments: true,
            supportedLanguages: ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"]
        )
    }

    // MARK: - Streaming Message
    func sendStreamingMessage(
        _ message: String,
        context: String,
        conversationHistory: [ChatMessage] = [],
        systemPrompt: String? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (BedrockAIResponse) -> Void
    ) async throws {
        let startTime = Date()

        // Extract system prompt from context if present
        var effectiveSystemPrompt = systemPrompt ?? "You are a helpful AI assistant specialized in analyzing health data and providing medical insights. Focus on being accurate, helpful, and professional."
        var actualContext = context

        if context.hasPrefix("System: ") {
            let components = context.components(separatedBy: "\n\nContext: ")
            if components.count >= 2 {
                effectiveSystemPrompt = String(components[0].dropFirst(8))
                actualContext = components.dropFirst().joined(separator: "\n\nContext: ")
            } else {
                effectiveSystemPrompt = String(context.dropFirst(8))
                actualContext = ""
            }
        }

        // Use ConversationContextBuilder to get trimmed history within token limits
        let contextResult = ConversationContextBuilder.buildContext(
            currentMessage: message,
            healthContext: actualContext,
            conversationHistory: conversationHistory,
            systemPrompt: effectiveSystemPrompt,
            provider: .bedrock
        )

        // Log context building results
        ConversationContextBuilder.logContextSummary(contextResult)

        // Prepare the conversation with context and history
        var conversationInput = ""

        // Add health context first (always included)
        if !actualContext.isEmpty {
            conversationInput += "Context (JSON Format): \(actualContext)\n\n"
        }

        // Add conversation history
        if !contextResult.conversationHistory.isEmpty {
            conversationInput += "Previous conversation:\n"
            conversationInput += ConversationContextBuilder.formatHistoryAsText(contextResult.conversationHistory)
            conversationInput += "\n\n"
        }

        // Add the current user message
        conversationInput += "User: \(message)"

        // Validate configuration
        guard config.isValid else {
            throw BedrockError.invalidCredentials
        }

        // Use currentModel if set (for extraction), otherwise use config.model (for chat)
        let modelToUse = currentModel ?? config.model

        // Create the model request payload
        let modelRequest = AWSBedrockModelFactory.createRequest(
            for: modelToUse,
            prompt: conversationInput,
            systemPrompt: effectiveSystemPrompt,
            maxTokens: config.maxTokens,
            temperature: config.temperature
        )

        // Encode the request body
        let requestBody: Data
        do {
            let encoder = JSONEncoder()
            requestBody = try encoder.encode(modelRequest)
        } catch {
            throw BedrockError.networkError(error)
        }

        do {
            let client = try await getBedrockClient()

            let invokeRequest = InvokeModelWithResponseStreamInput(
                body: requestBody,
                contentType: "application/json",
                modelId: modelToUse.rawValue
            )

            print("📡 BedrockClient: Starting streaming request for model \(modelToUse.displayName)")

            let response = try await client.invokeModelWithResponseStream(input: invokeRequest)

            var accumulatedContent = ""

            // Process the stream
            guard let stream = response.body else {
                throw BedrockError.invalidResponse
            }

            for try await event in stream {
                switch event {
                case .chunk(let payload):
                    if let bytes = payload.bytes {
                        let chunkData = Data(bytes)

                        // Parse the chunk based on model type
                        if let chunkContent = parseStreamingChunk(data: chunkData, model: modelToUse) {
                            accumulatedContent += chunkContent
                            onUpdate(accumulatedContent)
                        }
                    }

                case .sdkUnknown(let unknown):
                    print("⚠️ BedrockClient: Unknown stream event: \(unknown)")
                }
            }

            let responseTime = Date().timeIntervalSince(startTime)

            // Clean the final response
            let cleanedContent = AIResponseCleaner.cleanConversational(accumulatedContent)

            print("✅ BedrockClient: Streaming complete - \(cleanedContent.count) chars in \(String(format: "%.2f", responseTime))s")

            let finalResponse = BedrockAIResponse(
                content: cleanedContent,
                responseTime: responseTime,
                tokenCount: nil,
                metadata: [
                    "model": modelToUse.rawValue,
                    "region": config.region,
                    "provider": modelToUse.provider
                ]
            )

            onComplete(finalResponse)

        } catch {
            lastError = error
            throw BedrockError.networkError(error)
        }
    }

    // MARK: - Streaming Chunk Parser
    private func parseStreamingChunk(data: Data, model: AWSBedrockModel) -> String? {
        let decoder = JSONDecoder()

        switch model {
        case .claudeSonnet45:
            // Claude streaming format: content_block_delta events
            if let chunk = try? decoder.decode(ClaudeStreamingChunk.self, from: data) {
                if chunk.type == "content_block_delta",
                   let delta = chunk.delta,
                   delta.type == "text_delta" {
                    return delta.text
                }
            }
            return nil

        case .amazonNovaPremier:
            // Nova streaming format: similar to Claude
            if let chunk = try? decoder.decode(NovaStreamingChunk.self, from: data) {
                if let contentBlockDelta = chunk.contentBlockDelta,
                   let delta = contentBlockDelta.delta {
                    return delta.text
                }
            }
            return nil

        case .llama4Maverick:
            // Llama streaming format: generation field
            if let chunk = try? decoder.decode(LlamaStreamingChunk.self, from: data) {
                return chunk.generation
            }
            return nil
        }
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // For now, just update the model if provided
        if let modelName = config.model {
            if let model = AWSBedrockModel(rawValue: modelName) {
                let updatedConfig = AWSBedrockConfig(
                    region: self.config.region,
                    accessKeyId: self.config.accessKeyId,
                    secretAccessKey: self.config.secretAccessKey,
                    sessionToken: self.config.sessionToken,
                    model: model,
                    temperature: self.config.temperature,
                    maxTokens: self.config.maxTokens,
                    timeout: self.config.timeout,
                    useProfile: self.config.useProfile,
                    profileName: self.config.profileName
                )
                updateConfig(updatedConfig)
            }
        }
    }

    // MARK: - Core Bedrock Integration (matches your working pattern)
    private func invokeModel(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        // Validate configuration
        guard config.isValid else {
            throw BedrockError.invalidCredentials
        }

        // Use currentModel if set (for extraction), otherwise use config.model (for chat)
        let modelToUse = currentModel ?? config.model

        // Create the model request payload
        let modelRequest = AWSBedrockModelFactory.createRequest(
            for: modelToUse,
            prompt: prompt,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            temperature: temperature
        )

        // Encode the request body
        let requestBody: Data
        do {
            let encoder = JSONEncoder()
            requestBody = try encoder.encode(modelRequest)
        } catch {
            throw BedrockError.networkError(error)
        }

        do {

            // Get the Bedrock client (initialize if needed)
            let client = try await getBedrockClient()

            // Use the official AWS SDK to invoke the model
            let invokeRequest = InvokeModelInput(
                accept: "application/json",
                body: requestBody,
                contentType: "application/json",
                modelId: modelToUse.rawValue
            )

            let response = try await client.invokeModel(input: invokeRequest)

            guard let responseBody = response.body else {
                throw BedrockError.invalidResponse
            }

            // Convert response body to Data
            let responseData = Data(responseBody)

            // Parse the model-specific response
            let modelResponse = try AWSBedrockModelFactory.parseResponse(for: modelToUse, data: responseData)

            return modelResponse.content

        } catch {
            throw BedrockError.networkError(error)
        }
    }

    // MARK: - Model Management
    func setModel(_ modelId: String) {
        if let model = AWSBedrockModel(rawValue: modelId) {
            let updatedConfig = AWSBedrockConfig(
                region: config.region,
                accessKeyId: config.accessKeyId,
                secretAccessKey: config.secretAccessKey,
                sessionToken: config.sessionToken,
                model: model,
                temperature: config.temperature,
                maxTokens: config.maxTokens,
                timeout: config.timeout,
                useProfile: config.useProfile,
                profileName: config.profileName
            )
            updateConfig(updatedConfig)
        }
    }

    func getAvailableModels() async throws -> [AWSBedrockModel] {
        // Return predefined models (matches your pattern)
        return AWSBedrockModel.allCases
    }
}

// MARK: - Bedrock AI Response
struct BedrockAIResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?
}

// MARK: - Model Factory (matches your existing pattern)
class AWSBedrockModelFactory {
    static func createRequest(
        for model: AWSBedrockModel,
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int,
        temperature: Double
    ) -> any BedrockModelRequest {
        switch model {
        case .claudeSonnet45:
            var messages = [Claude35Message]()
            messages.append(Claude35Message(role: "user", text: prompt))
            return Claude35Request(
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                system: systemPrompt
            )

        case .amazonNovaPremier:
            return NovaRequest(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )

        case .llama4Maverick:
            let formattedPrompt = formatLlamaPrompt(prompt: prompt, systemPrompt: systemPrompt)
            return LlamaRequest(
                prompt: formattedPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }
    }

    static func parseResponse(
        for model: AWSBedrockModel,
        data: Data
    ) throws -> any BedrockModelResponse {
        let decoder = JSONDecoder()

        switch model {
        case .claudeSonnet45:
            return try decoder.decode(Claude35Response.self, from: data)

        case .amazonNovaPremier:
            return try decoder.decode(NovaResponse.self, from: data)

        case .llama4Maverick:
            return try decoder.decode(LlamaResponse.self, from: data)
        }
    }

    private static func formatLlamaPrompt(prompt: String, systemPrompt: String?) -> String {
        let system = systemPrompt ?? "You are a helpful assistant."
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>

        \(system)<|eot_id|><|start_header_id|>user<|end_header_id|>

        \(prompt)<|eot_id|><|start_header_id|>assistant<|end_header_id|>

        """
    }
}

// MARK: - Model Request/Response Protocols
protocol BedrockModelRequest: Codable {}
protocol BedrockModelResponse: Codable {
    var content: String { get }
}

// MARK: - Claude Model Structures
struct Claude35Request: BedrockModelRequest {
    let messages: [Claude35Message]
    let maxTokens: Int
    let temperature: Double
    let topP: Double?
    let topK: Int?
    let stopSequences: [String]?
    let anthropicVersion: String
    let system: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case stopSequences = "stop_sequences"
        case anthropicVersion = "anthropic_version"
        case system
    }

    init(messages: [Claude35Message], maxTokens: Int, temperature: Double, system: String? = nil) {
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = nil
        self.topK = nil
        self.stopSequences = nil
        self.anthropicVersion = "bedrock-2023-05-31"
        self.system = system
    }
}

struct Claude35Message: Codable {
    let role: String
    let content: [Claude35Content]

    init(role: String, text: String) {
        self.role = role
        self.content = [Claude35Content(type: "text", text: text)]
    }
}

struct Claude35Content: Codable {
    let type: String
    let text: String
}

struct Claude35Response: BedrockModelResponse {
    let id: String?
    let type: String?
    let role: String?
    let contentArray: [Claude35ResponseContent]
    let model: String?
    let stopReason: String?
    let stopSequence: String?
    let usage: Claude35Usage?

    var content: String {
        return contentArray.compactMap { $0.text }.joined(separator: "")
    }

    enum CodingKeys: String, CodingKey {
        case id, type, role, model
        case contentArray = "content"
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

struct Claude35ResponseContent: Codable {
    let type: String
    let text: String?
}

struct Claude35Usage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Amazon Nova Model Structures
struct NovaRequest: BedrockModelRequest {
    let messages: [NovaMessage]
    let system: [NovaSystemMessage]?
    let inferenceConfig: NovaInferenceConfig
    let schemaVersion: String

    enum CodingKeys: String, CodingKey {
        case messages
        case system
        case inferenceConfig
        case schemaVersion
    }

    init(prompt: String, systemPrompt: String?, maxTokens: Int, temperature: Double) {
        self.messages = [NovaMessage(role: "user", content: [NovaContent(text: prompt)])]
        if let system = systemPrompt {
            self.system = [NovaSystemMessage(text: system)]
        } else {
            self.system = nil
        }
        self.inferenceConfig = NovaInferenceConfig(
            maxTokens: maxTokens,
            temperature: temperature
        )
        self.schemaVersion = "messages-v1"
    }
}

struct NovaMessage: Codable {
    let role: String
    let content: [NovaContent]
}

struct NovaContent: Codable {
    let text: String
}

struct NovaSystemMessage: Codable {
    let text: String
}

struct NovaInferenceConfig: Codable {
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_new_tokens"
        case temperature
    }
}

struct NovaResponse: BedrockModelResponse {
    let output: NovaOutput
    let stopReason: String?
    let usage: NovaUsage?

    var content: String {
        return output.message.content.first?.text ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case output
        case stopReason
        case usage
    }
}

struct NovaOutput: Codable {
    let message: NovaMessage
}

struct NovaUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "inputTokens"
        case outputTokens = "outputTokens"
    }
}

// MARK: - Llama Model Structures
struct LlamaRequest: BedrockModelRequest {
    let prompt: String
    let maxGenLen: Int
    let temperature: Double
    let topP: Double

    enum CodingKeys: String, CodingKey {
        case prompt
        case maxGenLen = "max_gen_len"
        case temperature
        case topP = "top_p"
    }

    init(prompt: String, maxTokens: Int, temperature: Double) {
        self.prompt = prompt
        self.maxGenLen = maxTokens
        self.temperature = temperature
        self.topP = 0.9
    }
}

struct LlamaResponse: BedrockModelResponse {
    let generation: String
    let promptTokenCount: Int?
    let generationTokenCount: Int?
    let stopReason: String?

    var content: String { return generation }

    enum CodingKeys: String, CodingKey {
        case generation
        case promptTokenCount = "prompt_token_count"
        case generationTokenCount = "generation_token_count"
        case stopReason = "stop_reason"
    }
}

// MARK: - Streaming Chunk Structures

struct ClaudeStreamingChunk: Codable {
    let type: String
    let index: Int?
    let delta: ClaudeStreamingDelta?

    struct ClaudeStreamingDelta: Codable {
        let type: String?
        let text: String?
    }
}

struct NovaStreamingChunk: Codable {
    let contentBlockDelta: NovaContentBlockDelta?

    enum CodingKeys: String, CodingKey {
        case contentBlockDelta
    }

    struct NovaContentBlockDelta: Codable {
        let contentBlockIndex: Int?
        let delta: NovaDelta?

        struct NovaDelta: Codable {
            let text: String?
        }
    }
}

struct LlamaStreamingChunk: Codable {
    let generation: String?
    let promptTokenCount: Int?
    let generationTokenCount: Int?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case generation
        case promptTokenCount = "prompt_token_count"
        case generationTokenCount = "generation_token_count"
        case stopReason = "stop_reason"
    }
}

// MARK: - Bedrock Errors
enum BedrockError: LocalizedError {
    case clientNotInitialized
    case invalidCredentials
    case invalidConfiguration
    case invalidResponse
    case modelNotSupported(String)
    case documentFormatNotSupported(String)
    case rateLimitExceeded
    case insufficientPermissions
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "AWS Bedrock client not initialized"
        case .invalidCredentials:
            return "Invalid AWS credentials"
        case .invalidConfiguration:
            return "Invalid AWS Bedrock configuration"
        case .invalidResponse:
            return "Invalid response from Bedrock service"
        case .modelNotSupported(let model):
            return "Model \(model) is not supported or not available"
        case .documentFormatNotSupported(let format):
            return "Document format \(format) is not supported"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .insufficientPermissions:
            return "Insufficient permissions to access Bedrock service"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .clientNotInitialized:
            return "Configure AWS credentials using setCredentials method"
        case .invalidCredentials:
            return "Check your AWS access key and secret key"
        case .invalidConfiguration:
            return "Check your AWS region, access key, and secret key in settings"
        case .invalidResponse:
            return "Try again or check service status"
        case .modelNotSupported:
            return "Choose a different model from the available list"
        case .documentFormatNotSupported:
            return "Use a supported document format (PDF, DOCX, etc.)"
        case .rateLimitExceeded:
            return "Wait a moment before making another request"
        case .insufficientPermissions:
            return "Ensure your AWS credentials have Bedrock permissions"
        case .networkError:
            return "Check your internet connection and try again"
        }
    }
}

// MARK: - Convenience Extensions
extension BedrockClient {

    // Quick setup for common configurations
    static func createWithCredentials(
        accessKey: String,
        secretKey: String,
        region: String = "us-east-1",
        model: String = AWSBedrockModel.claudeSonnet45.rawValue
    ) -> BedrockClient {
        let config = AWSBedrockConfig(
            region: region,
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            sessionToken: nil,
            model: AWSBedrockModel(rawValue: model) ?? .claudeSonnet45,
            temperature: 0.1,
            maxTokens: 4096,
            timeout: 300.0,
            useProfile: false,
            profileName: nil
        )
        return BedrockClient(config: config)
    }
}