import Foundation

// MARK: - AI Provider Interface
@MainActor
protocol AIProviderInterface: ObservableObject {
    var isConnected: Bool { get }
    var connectionStatus: ConnectionStatus { get }
    var lastError: Error? { get }
    
    func testConnection() async throws -> Bool
    func sendMessage(_ message: String, context: String) async throws -> AIResponse
    func getCapabilities() async throws -> AICapabilities
    func updateConfiguration(_ config: AIProviderConfig) async throws
}

// MARK: - AI Response Protocol
protocol AIResponse {
    var content: String { get }
    var responseTime: TimeInterval { get }
    var tokenCount: Int? { get }
    var metadata: [String: Any]? { get }
}

// MARK: - AI Capabilities
struct AICapabilities {
    let supportedModels: [String]
    let maxTokens: Int
    let supportsStreaming: Bool
    let supportsImages: Bool
    let supportsDocuments: Bool
    let supportedLanguages: [String]
}

// MARK: - AI Provider Configuration
struct AIProviderConfig {
    let hostname: String
    let port: Int
    let apiKey: String?
    let model: String?
    let timeout: TimeInterval
    let maxRetries: Int
    
    init(
        hostname: String,
        port: Int,
        apiKey: String? = nil,
        model: String? = nil,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 3
    ) {
        self.hostname = hostname
        self.port = port
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
        self.maxRetries = maxRetries
    }
}



// MARK: - Future AI Provider Implementations
// This interface allows for easy addition of other AI providers like:
// - OpenAI GPT
// - Anthropic Claude
// - Google Gemini
// - Local models via other frameworks

// MARK: - Example Future Provider (Placeholder)
class OpenAIProvider: AIProviderInterface {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    
    private let apiKey: String
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func testConnection() async throws -> Bool {
        // TODO: Implement OpenAI connection test
        throw AIProviderError.notImplemented
    }
    
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        // TODO: Implement OpenAI chat completion
        throw AIProviderError.notImplemented
    }
    
    func getCapabilities() async throws -> AICapabilities {
        // TODO: Return OpenAI capabilities
        throw AIProviderError.notImplemented
    }
    
    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // TODO: Update OpenAI configuration
        throw AIProviderError.notImplemented
    }
}

class AnthropicProvider: AIProviderInterface {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: Error?
    
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func testConnection() async throws -> Bool {
        // TODO: Implement Anthropic connection test
        throw AIProviderError.notImplemented
    }
    
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        // TODO: Implement Anthropic message API
        throw AIProviderError.notImplemented
    }
    
    func getCapabilities() async throws -> AICapabilities {
        // TODO: Return Anthropic capabilities
        throw AIProviderError.notImplemented
    }
    
    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // TODO: Update Anthropic configuration
        throw AIProviderError.notImplemented
    }
}

// MARK: - AI Provider Factory
class AIProviderFactory {
    enum ProviderType {
        case ollama
        case openai
        case anthropic
        case custom(String)
    }
    
    @MainActor
    static func createProvider(
        type: ProviderType,
        config: AIProviderConfig
    ) -> any AIProviderInterface {
        switch type {
        case .ollama:
            return OllamaClient(hostname: config.hostname, port: config.port)
        case .openai:
            return OpenAIProvider(apiKey: config.apiKey ?? "")
        case .anthropic:
            return AnthropicProvider(apiKey: config.apiKey ?? "")
        case .custom(let providerName):
            // TODO: Implement custom provider loading
            fatalError("Custom provider \(providerName) not implemented")
        }
    }
}

// MARK: - Network Error Handling
class NetworkErrorHandler {
    static func handleError(_ error: Error) -> AIProviderError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .networkUnavailable
            case .timedOut:
                return .timeout
            case .cannotFindHost, .cannotConnectToHost:
                return .serverUnavailable
            case .badServerResponse:
                return .invalidResponse
            default:
                return .networkError(urlError)
            }
        }
        
        return .unknown(error)
    }
    
    static func shouldRetry(_ error: Error, attempt: Int, maxRetries: Int) -> Bool {
        guard attempt < maxRetries else { return false }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - Retry Logic
class RetryManager {
    static func executeWithRetry<T>(
        maxRetries: Int = 3,
        delay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if NetworkErrorHandler.shouldRetry(error, attempt: attempt, maxRetries: maxRetries) {
                    let backoffDelay = delay * pow(2.0, Double(attempt)) // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }
        
        throw lastError ?? AIProviderError.maxRetriesExceeded
    }
}

// MARK: - AI Provider Errors
enum AIProviderError: LocalizedError {
    case notImplemented
    case networkUnavailable
    case timeout
    case serverUnavailable
    case invalidResponse
    case maxRetriesExceeded
    case configurationError
    case authenticationFailed
    case rateLimitExceeded
    case networkError(Error)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This AI provider is not yet implemented"
        case .networkUnavailable:
            return "Network connection is not available"
        case .timeout:
            return "Request timed out"
        case .serverUnavailable:
            return "AI server is not available"
        case .invalidResponse:
            return "Invalid response from AI server"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .configurationError:
            return "AI provider configuration error"
        case .authenticationFailed:
            return "Authentication failed"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notImplemented:
            return "This feature will be available in a future update"
        case .networkUnavailable:
            return "Check your internet connection"
        case .timeout:
            return "Try again or check server status"
        case .serverUnavailable:
            return "Verify server configuration and availability"
        case .invalidResponse:
            return "Check server compatibility and version"
        case .maxRetriesExceeded:
            return "Check network connection and server status"
        case .configurationError:
            return "Review and update AI provider settings"
        case .authenticationFailed:
            return "Check API key and authentication credentials"
        case .rateLimitExceeded:
            return "Wait before making more requests"
        case .networkError, .unknown:
            return "Check network connection and try again"
        }
    }
}