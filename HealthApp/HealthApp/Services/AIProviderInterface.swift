import Foundation

// MARK: - AI Provider Interface
/// `Sendable` is required rather than merely implied: every conformer is a `@MainActor`
/// class and so is already implicitly `Sendable`, but without the constraint the
/// `any AIProviderInterface` existential is not, and cannot be handed to main-actor code
/// from the nonisolated extraction pipeline.
@MainActor
protocol AIProviderInterface: ObservableObject, Sendable {
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
