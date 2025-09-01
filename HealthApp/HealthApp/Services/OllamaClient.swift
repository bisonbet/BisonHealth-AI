import Foundation

// MARK: - Ollama Client
@MainActor
class OllamaClient: ObservableObject, AIProviderInterface {
    
    // MARK: - Shared Instance
    static let shared = OllamaClient(hostname: "localhost", port: 11434)
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval = 30.0
    
    // TODO: Add authentication properties when needed
    // private var apiKey: String?
    // private var authToken: String?
    
    // MARK: - Initialization
    init(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")!
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting
        
        do {
            let healthURL = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // TODO: Add authentication headers when needed
            // if let apiKey = apiKey {
            //     request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            // }
            
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            let success = (200...299).contains(httpResponse.statusCode)
            
            if success {
                connectionStatus = .connected
                isConnected = true
            } else {
                connectionStatus = .disconnected
                isConnected = false
                throw OllamaError.connectionFailed(httpResponse.statusCode)
            }
            
            return success
            
        } catch {
            connectionStatus = .disconnected
            isConnected = false
            lastError = error
            throw error
        }
    }
    
    // MARK: - Chat Operations
    func sendChatMessage(_ message: String, context: String = "", model: String = "llama2") async throws -> OllamaChatResponse {
        guard isConnected else {
            throw OllamaError.notConnected
        }
        
        let chatURL = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication headers when needed
        // if let apiKey = apiKey {
        //     request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // }
        
        // Build system prompt with health context
        let systemPrompt = buildSystemPrompt(with: context)
        
        let chatRequest = OllamaChatRequest(
            model: model,
            messages: [
                OllamaMessage(role: "system", content: systemPrompt),
                OllamaMessage(role: "user", content: message)
            ],
            stream: false
        )
        
        let requestData = try JSONEncoder().encode(chatRequest)
        request.httpBody = requestData
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.requestFailed(httpResponse.statusCode)
            }
            
            let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            return chatResponse
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Model Management
    func getAvailableModels() async throws -> [OllamaModel] {
        guard isConnected else {
            throw OllamaError.notConnected
        }
        
        let modelsURL = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // TODO: Add authentication headers when needed
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw OllamaError.requestFailed(httpResponse.statusCode)
            }
            
            let modelsResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            return modelsResponse.models
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    func pullModel(_ modelName: String) async throws -> Bool {
        let pullURL = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: pullURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let pullRequest = OllamaPullRequest(name: modelName)
        let requestData = try JSONEncoder().encode(pullRequest)
        request.httpBody = requestData
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            
            return (200...299).contains(httpResponse.statusCode)
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Configuration
    func updateConfiguration(hostname: String, port: Int) {
        // Update base URL
        // Note: In a real implementation, you'd want to recreate the client
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
            supportsStreaming: false, // Not implemented yet
            supportsImages: false, // Not implemented yet
            supportsDocuments: false, // Not implemented yet
            supportedLanguages: ["en"] // Default
        )
    }
    
    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // TODO: Implement configuration updates
        // This would recreate the client with new settings
        throw OllamaError.authenticationNotImplemented
    }
    
    // TODO: Placeholder for future authentication implementation
    func authenticate(credentials: AuthCredentials) async throws {
        // Placeholder for future authentication implementation
        // This would handle API key validation, token refresh, etc.
        throw OllamaError.authenticationNotImplemented
    }
    
    // MARK: - Private Methods
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

// MARK: - Data Models
struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions?
    
    init(model: String, messages: [OllamaMessage], stream: Bool = false, options: OllamaOptions? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
    }
}

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaOptions: Codable {
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let maxTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case maxTokens = "num_predict"
    }
}

struct OllamaChatResponse: Codable {
    let model: String
    let message: OllamaMessage
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?
    
    enum CodingKeys: String, CodingKey {
        case model, message, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
    
    var responseTime: TimeInterval {
        guard let totalDuration = totalDuration else { return 0 }
        return TimeInterval(totalDuration) / 1_000_000_000 // Convert nanoseconds to seconds
    }
    
    var tokenCount: Int? {
        let promptTokens = promptEvalCount ?? 0
        let evalTokens = evalCount ?? 0
        return promptTokens + evalTokens
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable, Identifiable {
    let name: String
    let modifiedAt: String
    let size: Int64
    let digest: String
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
        case digest
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct OllamaPullRequest: Codable {
    let name: String
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
    
    // TODO: Add more authentication fields as needed
}

// MARK: - Errors
enum OllamaError: LocalizedError {
    case notConnected
    case connectionFailed(Int)
    case requestFailed(Int)
    case invalidResponse
    case invalidModel
    case authenticationNotImplemented
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Ollama server"
        case .connectionFailed(let code):
            return "Connection failed with status code: \(code)"
        case .requestFailed(let code):
            return "Request failed with status code: \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidModel:
            return "Invalid or unavailable model"
        case .authenticationNotImplemented:
            return "Authentication not yet implemented"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            return "Check your server configuration and test the connection"
        case .connectionFailed, .requestFailed:
            return "Verify the server is running and accessible"
        case .invalidResponse:
            return "Check if the server is running the correct version of Ollama"
        case .invalidModel:
            return "Try pulling the model first or use a different model"
        case .authenticationNotImplemented:
            return "Authentication will be available in a future update"
        case .networkError:
            return "Check your network connection and server availability"
        case .decodingError:
            return "This may be a server compatibility issue"
        }
    }
}