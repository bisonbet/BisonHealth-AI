import Foundation
import Ollama

// MARK: - Ollama Client
@MainActor
class OllamaClient: ObservableObject, AIProviderInterface {
    
    // MARK: - Shared Instance
    static let shared = OllamaClient(hostname: "localhost", port: 11434)
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var isStreaming = false
    @Published var streamingContent = ""
    
    private let client: Client
    private let timeout: TimeInterval = 30.0
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        let hostURL = URL(string: "http://\(hostname):\(port)")!
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
            let models = try await client.listModels()
            
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
    func sendChatMessage(_ message: String, context: String = "", model: String = "llama3.2") async throws -> OllamaChatResponse {
        guard isConnected else {
            throw OllamaError.notConnected
        }
        
        do {
            let messages = buildMessages(userMessage: message, context: context)
            
            let startTime = Date()
            let modelID = Model.ID(rawValue: model) ?? Model.ID(rawValue: "llama3.2")!
            let response = try await client.chat(
                model: modelID,
                messages: messages,
                keepAlive: .minutes(10)
            )
            let processingTime = Date().timeIntervalSince(startTime)
            
            return OllamaChatResponse(
                content: response.message.content,
                model: model,
                processingTime: processingTime,
                totalTokens: response.promptEvalCount
            )
            
        } catch {
            lastError = error
            throw OllamaError.requestFailed(error)
        }
    }
    
    // MARK: - Streaming Chat Operations
    func sendStreamingChatMessage(
        _ message: String,
        context: String = "",
        model: String = "llama3.2",
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (OllamaChatResponse) -> Void
    ) async throws {
        guard isConnected else {
            throw OllamaError.notConnected
        }
        
        do {
            isStreaming = true
            streamingContent = ""
            
            let messages = buildMessages(userMessage: message, context: context)
            let startTime = Date()
            
            let modelID = Model.ID(rawValue: model) ?? Model.ID(rawValue: "llama3.2")!
            let stream = try client.chatStream(
                model: modelID,
                messages: messages,
                keepAlive: .minutes(10)
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
            
            let finalResponse = OllamaChatResponse(
                content: accumulatedContent,
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
        guard isConnected else {
            throw OllamaError.notConnected
        }
        
        do {
            let modelsResponse = try await client.listModels()
            return modelsResponse.models.map { model in
                OllamaModel(
                    name: model.name,
                    modifiedAt: model.modifiedAt,
                    size: model.size,
                    digest: model.digest
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
        return try await sendChatMessage(message, context: context)
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
    private func buildMessages(userMessage: String, context: String) -> [Chat.Message] {
        var messages: [Chat.Message] = []
        
        // Add system message with context
        let systemPrompt = buildSystemPrompt(with: context)
        messages.append(.system(systemPrompt))
        
        // Add user message
        messages.append(.user(userMessage))
        
        return messages
    }
    
    private func buildSystemPrompt(with context: String) -> String {
        var prompt = """
        You are a helpful AI health assistant. You have access to the user's personal health information and should provide informative, accurate responses about their health data.
        
        Important guidelines:
        - Always remind users that you are not a replacement for professional medical advice
        - Encourage users to consult with healthcare providers for medical decisions
        - Be supportive and informative while maintaining appropriate boundaries
        - Focus on helping users understand their health data and trends
        - Suggest when they should seek professional medical attention
        
        """
        
        if !context.isEmpty {
            prompt += "\nUser's Health Context:\n\(context)\n"
        }
        
        prompt += "\nPlease provide helpful, accurate information while encouraging appropriate medical consultation when needed."
        
        return prompt
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
struct OllamaModel: Codable, Identifiable {
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
}

// MARK: - Connection Status
enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(Error)
    
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error:
            return "Error"
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .connecting:
            return "wifi.exclamationmark"
        case .connected:
            return "wifi"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Authentication (Placeholder)
struct AuthCredentials {
    let apiKey: String?
    let username: String?
    let password: String?
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
    case networkError(Error)
    
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
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
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
        case .networkError:
            return "Check your network connection and server availability"
        }
    }
}