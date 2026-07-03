import Foundation

// MARK: - AI Provider Interface
@MainActor
protocol AIProviderInterface: ObservableObject {
    var isConnected: Bool { get }
    var connectionStatus: ProviderConnectionStatus { get }
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

#if DEBUG
// MARK: - Scripted AI Provider

struct ScriptedAIRequest: Equatable {
    let message: String
    let context: String
}

struct ScriptedAIResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(
        content: String,
        responseTime: TimeInterval = 0.01,
        tokenCount: Int? = nil,
        metadata: [String: Any]? = ["provider": "scripted"]
    ) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}

@MainActor
final class ScriptedAIProvider: ObservableObject, AIProviderInterface {
    static let shared = ScriptedAIProvider()

    @Published var isConnected = true
    @Published var connectionStatus: ProviderConnectionStatus = .connected
    @Published var lastError: Error?

    private(set) var requests: [ScriptedAIRequest] = []
    private var queuedResponses: [Result<String, Error>] = []

    func reset(responses: [Result<String, Error>] = []) {
        requests = []
        queuedResponses = responses
        isConnected = true
        connectionStatus = .connected
        lastError = nil
    }

    func testConnection() async throws -> Bool {
        isConnected = true
        connectionStatus = .connected
        return true
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        requests.append(ScriptedAIRequest(message: message, context: context))

        if !queuedResponses.isEmpty {
            let next = queuedResponses.removeFirst()
            switch next {
            case .success(let content):
                return ScriptedAIResponse(content: content)
            case .failure(let error):
                lastError = error
                throw error
            }
        }

        return ScriptedAIResponse(content: defaultResponse(for: message, context: context))
    }

    func getCapabilities() async throws -> AICapabilities {
        AICapabilities(
            supportedModels: ["scripted-test-provider"],
            maxTokens: 32_768,
            supportsStreaming: false,
            supportsImages: false,
            supportsDocuments: false,
            supportedLanguages: ["en"]
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // No-op; configuration is fixed for deterministic tests.
    }

    private func defaultResponse(for message: String, context: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("test/report date") || lowercased.contains("return your response in this exact format") {
            return """
            TEST_DATE: 2026-01-15
            LAB_NAME: Bison Diagnostics
            PHYSICIAN: Dr. Ada Test
            PATIENT: Test Patient
            """
        }

        if lowercased.contains("format (pipe-delimited") || lowercased.contains("test_name|test_type|value") {
            return """
            Glucose|BLOOD|98|mg/dL|70-100|Normal
            Total Cholesterol|BLOOD|220|mg/dL|<200|High
            Hemoglobin|BLOOD|13.5|g/dL|12.0-16.0|Normal
            """
        }

        if lowercased.contains("analyze this medical document") {
            return """
            {
              "document_date": "2026-01-15",
              "provider_name": "Bison Diagnostics",
              "provider_type": "laboratory",
              "document_category": "lab_report",
              "sections": [
                {
                  "section_type": "Test Results",
                  "content": "Glucose 98 mg/dL, Total Cholesterol 220 mg/dL, Hemoglobin 13.5 g/dL"
                }
              ]
            }
            """
        }

        if lowercased.contains("symptom history") || lowercased.contains("timeline") {
            return """
            TIMELINE:
            - Symptoms began three days ago and have been intermittent.
            - Symptoms are worse in the evening.
            - No emergency symptoms were reported in the test fixture.
            """
        }

        if lowercased.contains("questions") && lowercased.contains("doctor") {
            return """
            1. What diagnoses best fit these symptoms?
            2. Which tests should we consider next?
            3. Could current medications contribute?
            4. What warning signs need urgent care?
            5. What should I track after this visit?
            """
        }

        if lowercased.contains("relevant") || lowercased.contains("important considerations") {
            return """
            - Bring the recent lab report and medication list.
            - Ask whether abnormal cholesterol changes the care plan.
            - Seek urgent care for chest pain, fainting, or severe shortness of breath.
            """
        }

        if lowercased.contains("summarize this conversation") {
            return "Scripted Health Discussion"
        }

        if !context.isEmpty {
            return "SCRIPTED_DOCTOR_REPLY: I reviewed the provided context and would discuss the recent lab trends with your clinician."
        }

        return "SCRIPTED_DOCTOR_REPLY: I can help prepare concise questions for your clinician."
    }
}
#endif

// MARK: - Document Page Image
/// A rasterized document page prepared for vision-model extraction.
struct DocumentPageImage {
    let pageNumber: Int
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - Vision Document Extractor
/// Narrow capability protocol for providers that can read document page images
/// directly (bypassing OCR errors). Kept separate from `sendMessage` so the chat
/// path is untouched; `DocumentProcessor` checks conformance at runtime.
@MainActor
protocol VisionDocumentExtractor {
    /// Whether the currently configured model can accept image input
    var supportsVisionExtraction: Bool { get }

    /// Send page images + OCR text; returns the raw model output, expected to be
    /// JSON conforming to `schemaPrompt`.
    func extractFromDocument(
        pages: [DocumentPageImage],
        ocrText: String,
        schemaPrompt: String
    ) async throws -> String
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

// MARK: - Authentication

struct AuthCredentials {
    let apiKey: String?
    let username: String?
    let password: String?
    let token: String?

    init(
        apiKey: String? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
        self.token = token
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
    @Published var connectionStatus: ProviderConnectionStatus = .disconnected
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
    @Published var connectionStatus: ProviderConnectionStatus = .disconnected
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
        case openai
        case anthropic
        case bedrock
        case custom(String)
    }

    @MainActor
    static func createProvider(
        type: ProviderType,
        config: AIProviderConfig
    ) -> any AIProviderInterface {
        switch type {
        case .openai:
            return OpenAIProvider(apiKey: config.apiKey ?? "")
        case .anthropic:
            return AnthropicProvider(apiKey: config.apiKey ?? "")
        case .bedrock:
            // Use shared credentials manager (matches your pattern)
            let sharedCredentials = AWSCredentialsManager.shared.credentials
            let bedrockConfig = AWSBedrockConfig(
                region: sharedCredentials.region,
                accessKeyId: sharedCredentials.accessKeyId,
                secretAccessKey: sharedCredentials.secretAccessKey,
                sessionToken: nil,
                model: .claudeSonnet45,  // Default model
                temperature: 0.1,
                maxTokens: 4096,
                timeout: 300.0,
                useProfile: false,  // Use direct credentials
                profileName: nil
            )
            return BedrockClient(config: bedrockConfig)
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
