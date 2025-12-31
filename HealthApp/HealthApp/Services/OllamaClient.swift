import Foundation
import Ollama

// MARK: - Ollama Client
@MainActor
class OllamaClient: ObservableObject, AIProviderInterface {
    
    // MARK: - Shared Instance
    static let shared = OllamaClient(hostname: ServerConfigurationConstants.defaultOllamaHostname, port: ServerConfigurationConstants.defaultOllamaPort)
    
    @Published var isConnected = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var isStreaming = false
    @Published var streamingContent = ""
    
    // Default model to use when called via AIProviderInterface
    var currentModel: String = "llama3.2"
    
    private let client: Client
    private let timeout: TimeInterval = 300.0 // 5 minutes for large document processing
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        guard let hostURL = ServerConfigurationConstants.buildOllamaURL(hostname: hostname, port: port) else {
            // Fallback to default if URL creation fails
            let fallbackURL = ServerConfigurationConstants.fallbackOllamaURL
            self.client = Client(
                host: fallbackURL,
                userAgent: "BisonHealthAI/1.0"
            )
            return
        }
        
        self.client = Client(
            host: hostURL,
            userAgent: "BisonHealthAI/1.0"
        )
    }
    
    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting
        
        do {
            // Test connection by fetching available models
            _ = try await client.listModels()
            
            connectionStatus = .connected
            isConnected = true
            return true
            
        } catch {
            connectionStatus = .disconnected
            isConnected = false
            lastError = error
            throw OllamaError.connectionFailed(error)
        }
    }
    
    // MARK: - Chat Operations
    func sendChatMessage(_ message: String, context: String = "", model: String = "llama3.2", systemPrompt: String? = nil) async throws -> OllamaChatResponse {
        do {
            let messages = buildMessages(userMessage: message, context: context, systemPrompt: systemPrompt)

            let startTime = Date()
            let modelID = Model.ID(rawValue: model) ?? Model.ID(rawValue: "llama3.2")!

            // Get settings from SettingsManager
            let contextSize = SettingsManager.shared.modelPreferences.contextSizeLimit
            print("🔧 OllamaClient: Requesting model '\(model)' with context: \(contextSize) tokens, keep_alive: forever")

            // Simple timeout implementation using Task.timeout equivalent
            // Use Ollama.Value to create the options dictionary with the correct type
            let response = try await withTimeout(timeout) {
                // The library expects [String: Value] where Value is Ollama.Value
                // Initialize Value using .init() or Ollama.Value()
                return try await self.client.chat(
                    model: modelID,
                    messages: messages,
                    options: ["num_ctx": Ollama.Value(contextSize)],
                    keepAlive: .forever
                )
            }

            let processingTime = Date().timeIntervalSince(startTime)

            // Clean the response to remove special tokens and unwanted text
            let cleanedContent = AIResponseCleaner.cleanConversational(response.message.content)

            return OllamaChatResponse(
                content: cleanedContent,
                model: model,
                processingTime: processingTime,
                totalTokens: response.promptEvalCount
            )

        } catch {
            lastError = error
            if error is TimeoutError {
                throw OllamaError.timeout
            }
            // Convert to NetworkError for better handling
            let networkError = NetworkError.from(error: error)
            throw OllamaError.networkError(networkError)
        }
    }
    
    // MARK: - Streaming Chat Operations
    func sendStreamingChatMessage(
        _ message: String,
        context: String = "",
        model: String = "llama3.2",
        systemPrompt: String? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (OllamaChatResponse) -> Void
    ) async throws {
        do {
            isStreaming = true
            streamingContent = ""

            let messages = buildMessages(userMessage: message, context: context, systemPrompt: systemPrompt)
            let startTime = Date()

            // Get settings from SettingsManager
            let contextSize = SettingsManager.shared.modelPreferences.contextSizeLimit
            print("🔧 OllamaClient (streaming): Using context size: \(contextSize) tokens, keep_alive: forever")

            let modelID = Model.ID(rawValue: model) ?? Model.ID(rawValue: "llama3.2")!
            // Use Ollama.Value to create the options dictionary with the correct type
            let stream = try client.chatStream(
                model: modelID,
                messages: messages,
                options: ["num_ctx": Ollama.Value(contextSize)],
                keepAlive: .forever
            )
            
            var accumulatedContent = ""
            var totalTokens: Int?
            
            for try await response in stream {
                let content = response.message.content
                if !content.isEmpty {
                    accumulatedContent += content
                    streamingContent = accumulatedContent
                    
                    await MainActor.run {
                        onUpdate(accumulatedContent)
                    }
                }
                
                // Capture token count from final response
                if response.done {
                    totalTokens = response.promptEvalCount
                }
            }
            
            let processingTime = Date().timeIntervalSince(startTime)

            // Clean the accumulated content to remove special tokens and unwanted text
            let cleanedContent = AIResponseCleaner.cleanConversational(accumulatedContent)

            let finalResponse = OllamaChatResponse(
                content: cleanedContent,
                model: model,
                processingTime: processingTime,
                totalTokens: totalTokens
            )

            await MainActor.run {
                isStreaming = false
                onComplete(finalResponse)
            }
            
        } catch {
            await MainActor.run {
                isStreaming = false
                lastError = error
            }
            throw OllamaError.streamingFailed(error)
        }
    }
    
    // MARK: - Model Management
    func getAvailableModels() async throws -> [OllamaModel] {
        do {
            let modelsResponse = try await client.listModels()
            return modelsResponse.models.map {
                OllamaModel(
                    name: $0.name,
                    modifiedAt: $0.modifiedAt,
                    size: $0.size,
                    digest: $0.digest
                )
            }
        } catch {
            lastError = error
            throw OllamaError.requestFailed(error)
        }
    }
    
    func pullModel(_ modelName: String, onProgress: @escaping (Double) -> Void = { _ in }) async throws -> Bool {
        do {
            let modelID = Model.ID(rawValue: modelName) ?? Model.ID(rawValue: "llama3.2")!
            let success = try await client.pullModel(modelID)
            
            await MainActor.run {
                onProgress(1.0)
            }
            
            return success
            
        } catch {
            lastError = error
            throw OllamaError.pullFailed(error)
        }
    }
    
    // MARK: - Configuration
    func updateConfiguration(hostname: String, port: Int) {
        // Note: Client configuration is immutable, would need to recreate client
        // For now, this is a placeholder for future configuration updates
    }
    
    // MARK: - AIProviderInterface Conformance
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        return try await sendChatMessage(message, context: context, model: self.currentModel)
    }
    
    func getCapabilities() async throws -> AICapabilities {
        let models = try await getAvailableModels()
        return AICapabilities(
            supportedModels: models.map { $0.name },
            maxTokens: 4096, // Default for most Ollama models
            supportsStreaming: true,
            supportsImages: true, // Many models support images
            supportsDocuments: false, // Document processing is separate
            supportedLanguages: ["en"] // Default, many models support multiple languages
        )
    }
    
    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Would need to recreate client with new configuration
        throw OllamaError.configurationUpdateNotSupported
    }
    
    func authenticate(credentials: AuthCredentials) async throws {
        // Ollama typically doesn't require authentication
        // This is a placeholder for future implementation if needed
        throw OllamaError.authenticationNotSupported
    }
    
    // MARK: - Private Methods
    private func buildMessages(userMessage: String, context: String, systemPrompt: String?) -> [Chat.Message] {
        var messages: [Chat.Message] = []
        
        // Determine the base system prompt
        let baseSystemPrompt = systemPrompt ?? buildDefaultSystemPrompt()
        
        // Append health context to the chosen system prompt
        var finalSystemPrompt = baseSystemPrompt
        if !context.isEmpty {
            finalSystemPrompt += "\n\n--- User's Health Context (JSON Format) ---\n" + context
        }
        
        messages.append(.system(finalSystemPrompt))
        messages.append(.user(userMessage))
        
        return messages
    }
    
    private func buildDefaultSystemPrompt() -> String {
        return """
        CRITICAL INSTRUCTIONS:
        - Health data is provided in structured JSON format
        - You MUST ONLY use the health data explicitly present in the JSON (e.g., personal_info.name, blood_tests[0].results)
        - Parse nested structures: medications[], conditions[], vitals.blood_pressure.readings[]
        - NEVER make up, assume, or hallucinate any medical values, test results, or health data
        - If a JSON field is null or missing, clearly state that you don't have that information
        - If the user asks about specific test results not in the JSON, state you don't have that data
        - Always refer to the actual values provided in the JSON health context

        You are a helpful AI health assistant. You have access to the user's personal health information in JSON format and should provide informative, accurate responses about their health data.

        Important guidelines:
        - Always remind users that you are not a replacement for professional medical advice
        - Encourage users to consult with healthcare providers for medical decisions
        - Be supportive and informative while maintaining appropriate boundaries
        - Focus on helping users understand their health data and trends
        - Suggest when they should seek professional medical attention

        Please provide helpful, accurate information while encouraging appropriate medical consultation when needed.
        """
    }
}

// MARK: - Response Model
struct OllamaChatResponse: Codable, AIResponse {
    let content: String
    let model: String
    let processingTime: TimeInterval
    let totalTokens: Int?
    
    init(
        content: String,
        model: String,
        processingTime: TimeInterval = 0,
        totalTokens: Int? = nil
    ) {
        self.content = content
        self.model = model
        self.processingTime = processingTime
        self.totalTokens = totalTokens
    }
    
    // MARK: - AIResponse Conformance
    var responseTime: TimeInterval {
        return processingTime
    }
    
    var tokenCount: Int? {
        return totalTokens
    }
    
    var metadata: [String: Any]? {
        var meta: [String: Any] = [:]
        meta["model"] = model
        if let tokens = totalTokens {
            meta["total_tokens"] = tokens
        }
        meta["processing_time"] = processingTime
        return meta
    }
}

// MARK: - Model Struct
struct OllamaModel: Codable, Identifiable, Equatable {
    let name: String
    let modifiedAt: String
    let size: Int64
    let digest: String
    
    var id: String { name }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    // Vision capability detection based on model name patterns
    var supportsVision: Bool {
        let visionModels = [
            "llava", "llama3.2-vision", "llama4", "qwen2.5vl", "qwen3-vl",
            "granite3.2-vision", "mistral-small3.1", "mistral-small3.2", "ministral-3",
            "gemma3","deepseek-ocr"
        ]

        let modelNameLower = name.lowercased()
        return visionModels.contains { visionModel in
            modelNameLower.contains(visionModel)
        }
    }
    
    // Display name for UI (removes version tags for cleaner display)
    var displayName: String {
        // Remove common version suffixes for cleaner display
        let cleanName = name.replacingOccurrences(of: ":latest", with: "")
                           .replacingOccurrences(of: ":13b", with: " (13B)")
                           .replacingOccurrences(of: ":7b", with: " (7B)")
                           .replacingOccurrences(of: ":3b", with: " (3B)")
                           .replacingOccurrences(of: ":1b", with: " (1B)")
        
        // Add vision indicator for clarity
        return supportsVision ? "\(cleanName) 👁️" : cleanName
    }
    
    // Model type for categorization
    var modelType: OllamaModelType {
        if supportsVision {
            return .vision
        } else {
            return .chat
        }
    }
}

enum OllamaModelType {
    case chat
    case vision
    
    var displayName: String {
        switch self {
        case .chat: return "Text Chat"
        case .vision: return "Vision + Chat"
        }
    }
}

// MARK: - Authentication (Placeholder)
struct AuthCredentials {
    let apiKey: String?
    let username: String?
    let password: String?
}

// MARK: - Timeout Helper

struct TimeoutError: Error {
    let duration: TimeInterval
}

func withTimeout<T>(_ duration: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            throw TimeoutError(duration: duration)
        }

        guard let result = try await group.next() else {
            throw TimeoutError(duration: duration)
        }

        group.cancelAll()
        return result
    }
}

// MARK: - Errors
enum OllamaError: LocalizedError {
    case notConnected
    case connectionFailed(Error)
    case requestFailed(Error)
    case streamingFailed(Error)
    case pullFailed(Error)
    case invalidModel
    case authenticationNotSupported
    case configurationUpdateNotSupported
    case networkError(NetworkError)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Ollama server"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .streamingFailed(let error):
            return "Streaming failed: \(error.localizedDescription)"
        case .pullFailed(let error):
            return "Model pull failed: \(error.localizedDescription)"
        case .invalidModel:
            return "Invalid or unavailable model"
        case .authenticationNotSupported:
            return "Authentication not supported by Ollama"
        case .configurationUpdateNotSupported:
            return "Configuration updates require app restart"
        case .networkError(let networkError):
            return networkError.errorDescription ?? "Network error occurred"
        case .timeout:
            return "Request timed out - document processing took too long"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            return "Check your server configuration and test the connection"
        case .connectionFailed, .requestFailed:
            return "Verify the server is running and accessible"
        case .streamingFailed:
            return "Check server connection and try again"
        case .pullFailed:
            return "Check internet connection and server storage"
        case .invalidModel:
            return "Try pulling the model first or use a different model"
        case .authenticationNotSupported:
            return "Ollama typically doesn't require authentication"
        case .configurationUpdateNotSupported:
            return "Restart the app to apply configuration changes"
        case .networkError(let networkError):
            return networkError.recoverySuggestion
        case .timeout:
            return "Try using a smaller model or split the document into smaller parts"
        }
    }
}