import Foundation

// MARK: - OpenAI-Compatible Endpoint Validation

enum OpenAICompatibleEndpointValidationError: Equatable, Error {
    case malformedURL
    case missingHost
    case unsupportedScheme
    case embeddedCredentials
    case publicHTTP

    var userMessage: String {
        switch self {
        case .malformedURL:
            return "Enter a complete server URL, such as https://api.example.com."
        case .missingHost:
            return "The server URL must include a host name or IP address."
        case .unsupportedScheme:
            return "Use HTTPS, or HTTP only with localhost, 127.0.0.1, or ::1."
        case .embeddedCredentials:
            return "Remove the username and password from the server URL."
        case .publicHTTP:
            return "For non-local servers, use HTTPS. HTTP is limited to local loopback addresses."
        }
    }
}

struct OpenAICompatibleEndpointValidator {
    static func validate(_ value: String) -> Result<URL, OpenAICompatibleEndpointValidationError> {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let url = URL(string: trimmedValue) else {
            return .failure(.malformedURL)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedURL)
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return .failure(.unsupportedScheme)
        }

        guard components.user == nil, components.password == nil else {
            return .failure(.embeddedCredentials)
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return .failure(.missingHost)
        }

        if scheme == "http" {
            let normalizedHost = host
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .lowercased()
            guard normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1" else {
                return .failure(.publicHTTP)
            }
        }

        return .success(url)
    }

    static func validatedURL(_ value: String) -> URL? {
        guard case .success(let url) = validate(value) else { return nil }
        return url
    }

    static func validationError(for value: String) -> OpenAICompatibleEndpointValidationError? {
        guard case .failure(let error) = validate(value) else { return nil }
        return error
    }

    static func isValid(_ value: String) -> Bool {
        validatedURL(value) != nil
    }
}

// MARK: - OpenAI Compatible Client
/// Client for OpenAI-compatible API servers (LiteLLM, LocalAI, vLLM, etc.)
@MainActor
class OpenAICompatibleClient: ObservableObject, AIProviderInterface {

    private static let providerName = "OpenAI-compatible"
    private static let maxStreamingErrorBytes = 4 * 1024

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: ProviderConnectionStatus = .disconnected
    @Published var lastError: Error?

    // MARK: - Properties
    private let baseURL: URL?
    private let apiKey: String?
    private let session: URLSession
    private let timeout: TimeInterval
    private var defaultModel: String?
    private let temperature: Double
    private let maxTokens: Int
    private let contextSize: Int

    // Default model to use when called via AIProviderInterface
    var currentModel: String?

    /// User-declared flag: whether the configured server/model accepts image input.
    /// Capability discovery is unreliable across OpenAI-compatible servers, so this
    /// is driven by an explicit settings toggle.
    var declaresVisionSupport: Bool = false

    // MARK: - Initialization
    init(baseURL: String, apiKey: String? = nil, timeout: TimeInterval = 300.0, defaultModel: String? = nil, temperature: Double = 0.1, maxTokens: Int = 2048, contextSize: Int = 32768, session: URLSession? = nil) {
        self.baseURL = OpenAICompatibleEndpointValidator.validatedURL(baseURL)
        self.apiKey = apiKey
        self.timeout = timeout
        self.defaultModel = defaultModel
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.contextSize = contextSize

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        self.session = session ?? URLSession(configuration: config)

        if self.baseURL == nil {
            AppLog.shared.ai("OpenAI-compatible client initialized with a rejected endpoint", level: .warning)
        } else {
            AppLog.shared.ai("OpenAI-compatible client initialized")
        }
    }

    // MARK: - Safe Diagnostics

    private func safeURLDescription(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "configured provider URL"
        }

        // URL userinfo, query items, and fragments can contain credentials or
        // request data. Keep only the endpoint identity in durable diagnostics.
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "configured provider URL"
    }

    private func providerRequestFailure(
        operation: String,
        response: HTTPURLResponse,
        body: Data
    ) -> OpenAICompatibleError {
        let error = OpenAICompatibleError.requestFailed(
            response: response,
            body: body,
            provider: Self.providerName
        )
        AppLog.shared.error(
            "OpenAI-compatible \(operation) request failed",
            error: error,
            category: .ai
        )
        return error
    }

    private func providerConnectionFailure(operation: String, error: Error) {
        lastError = error
        AppLog.shared.error(
            "OpenAI-compatible \(operation) connection failed",
            error: error,
            category: .ai
        )
    }

    private func invalidProviderResponse(operation: String, error: OpenAICompatibleError) -> OpenAICompatibleError {
        AppLog.shared.error(
            "OpenAI-compatible \(operation) returned an invalid response",
            error: error,
            category: .ai
        )
        return error
    }

    private func validatedBaseURLForRequest() throws -> URL {
        guard let baseURL,
              let validatedURL = OpenAICompatibleEndpointValidator.validatedURL(baseURL.absoluteString) else {
            throw OpenAICompatibleError.invalidURL
        }
        return validatedURL
    }

    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting

        do {
            // Try to list models as a connection test
            let models = try await listModels()

            connectionStatus = .connected
            isConnected = true
            AppLog.shared.ai("Connected successfully, found \(models.count) models")
            return true

        } catch {
            connectionStatus = .disconnected
            isConnected = false
            lastError = error
            AppLog.shared.error("OpenAI-compatible connection failed", error: error, category: .ai)
            throw error
        }
    }

    // MARK: - Chat Completion
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        let baseURL = try validatedBaseURLForRequest()
        let messagesURL = baseURL.appendingPathComponent("/v1/chat/completions")

        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add API key if provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            AppLog.shared.ai("No API key provided - request will be sent without Authorization header", level: .debug)
        }

        // Build messages array
        var messages: [[String: String]] = []

        // Add context as system message if provided
        if !context.isEmpty {
            messages.append([
                "role": "system",
                "content": "Health data (JSON format):\n" + context
            ])
        }

        // Add user message
        messages.append([
            "role": "user",
            "content": message
        ])

        // Create request body
        var requestBody: [String: Any] = [
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "max_context_length": contextSize  // Some implementations may use this
        ]

        // Use currentModel (for extraction), fallback to defaultModel (for chat)
        if let model = currentModel ?? defaultModel, !model.isEmpty {
            requestBody["model"] = model
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Debug: Log request with sanitized headers and truncated body
        AppLog.shared.ai("Sending request to \(safeURLDescription(messagesURL))")
        AppLog.shared.ai("Model: \(currentModel ?? defaultModel ?? "(none)")", level: .debug)

        // Log request metadata only (no body content — it contains health data)
        if let bodyData = request.httpBody {
            AppLog.shared.ai("Request body size: \(bodyData.count) bytes", level: .debug)
        }

        let startTime = Date()

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAICompatibleError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw providerRequestFailure(operation: "chat", response: httpResponse, body: data)
            }

            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if let chatResponse = try? decoder.decode(OpenAIChatCompletionResponse.self, from: data),
               let choice = chatResponse.choices.first {
                if let content = choice.primaryContent {
                    let processingTime = Date().timeIntervalSince(startTime)
                    let resolvedModel = chatResponse.model ?? choice.model ?? defaultModel

                    // Clean the response to remove special tokens and unwanted text
                    let cleanedContent = AIResponseCleaner.cleanConversational(content)

                    return OpenAICompatibleChatResponse(
                        content: cleanedContent,
                        model: resolvedModel,
                        processingTime: processingTime,
                        totalTokens: chatResponse.usage?.totalTokens
                    )
                }
            }

            // Attempt to extract content using a flexible fallback parser
            if let fallbackContent = try? parseFlexibleChatContent(from: data) {
                let processingTime = Date().timeIntervalSince(startTime)

                // Clean the response to remove special tokens and unwanted text
                let cleanedContent = AIResponseCleaner.cleanConversational(fallbackContent.content)

                return OpenAICompatibleChatResponse(
                    content: cleanedContent,
                    model: fallbackContent.model ?? defaultModel,
                    processingTime: processingTime,
                    totalTokens: fallbackContent.totalTokens
                )
            }

            let error = invalidProviderResponse(operation: "chat", error: .emptyResponse)
            throw error

        } catch {
            if let providerError = error as? OpenAICompatibleError,
               case .requestFailed = providerError {
                lastError = providerError
            } else {
                providerConnectionFailure(operation: "chat", error: error)
            }
            throw error
        }
    }

    func updateDefaultModel(_ model: String?) {
        defaultModel = model
    }

    // MARK: - Vision Document Extraction

    /// Send page images + OCR text as a multimodal chat completion.
    /// Uses `response_format: json_object` when the server accepts it, and
    /// retries once without it on a 4xx (many compatible servers don't support it).
    func performVisionExtraction(
        pages: [DocumentPageImage],
        ocrText: String,
        schemaPrompt: String
    ) async throws -> String {
        let baseURL = try validatedBaseURLForRequest()
        let messagesURL = baseURL.appendingPathComponent("/v1/chat/completions")

        // Build multimodal content parts: page images followed by the instruction text
        var contentParts: [[String: Any]] = []
        for page in pages.prefix(20) {
            contentParts.append(["type": "text", "text": "Page \(page.pageNumber):"])
            contentParts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(page.jpegData.base64EncodedString())"]
            ])
        }
        let textPrompt = """
        \(schemaPrompt)

        For cross-checking, here is the on-device OCR text of the same document \
        (it may contain OCR errors — trust the images over the OCR text when they disagree):

        \(String(ocrText.prefix(30_000)))
        """
        contentParts.append(["type": "text", "text": textPrompt])

        let messages: [[String: Any]] = [
            [
                "role": "system",
                "content": "You are a precise medical laboratory data extraction engine. You respond with valid JSON only — no prose, no markdown fences."
            ],
            [
                "role": "user",
                "content": contentParts
            ]
        ]

        func makeBody(includeResponseFormat: Bool) throws -> Data {
            var requestBody: [String: Any] = [
                "messages": messages,
                "temperature": 0.0,
                "max_tokens": maxTokens
            ]
            if let model = currentModel ?? defaultModel, !model.isEmpty {
                requestBody["model"] = model
            }
            if includeResponseFormat {
                requestBody["response_format"] = ["type": "json_object"]
            }
            return try JSONSerialization.data(withJSONObject: requestBody)
        }

        func send(_ body: Data) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: messagesURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                providerConnectionFailure(operation: "vision", error: error)
                throw error
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw invalidProviderResponse(operation: "vision", error: .invalidResponse)
            }
            return (data, httpResponse)
        }

        AppLog.shared.ai("Vision extraction request: \(pages.count) pages to \(safeURLDescription(messagesURL))")
        var (data, httpResponse) = try await send(makeBody(includeResponseFormat: true))

        if (400...499).contains(httpResponse.statusCode) {
            // Server may not support response_format — retry once without it
            AppLog.shared.ai("Vision extraction got \(httpResponse.statusCode), retrying without response_format", level: .warning)
            (data, httpResponse) = try await send(makeBody(includeResponseFormat: false))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw providerRequestFailure(operation: "vision", response: httpResponse, body: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let chatResponse = try? decoder.decode(OpenAIChatCompletionResponse.self, from: data),
           let content = chatResponse.choices.first?.primaryContent {
            return content
        }
        if let fallbackContent = try? parseFlexibleChatContent(from: data) {
            return fallbackContent.content
        }
        throw invalidProviderResponse(operation: "vision", error: .emptyResponse)
    }

    // MARK: - Streaming Chat Completion
    func sendStreamingChatMessage(
        _ message: String,
        context: String = "",
        conversationHistory: [ChatMessage] = [],
        model: String? = nil,
        systemPrompt: String? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (OpenAICompatibleChatResponse) -> Void
    ) async throws {
        let baseURL = try validatedBaseURLForRequest()
        let messagesURL = baseURL.appendingPathComponent("/v1/chat/completions")

        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Add API key if provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build messages array
        var messages: [[String: String]] = []

        // Build combined system message with both prompt and context
        var systemContent = ""

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            systemContent = systemPrompt
        }

        if !context.isEmpty {
            if !systemContent.isEmpty {
                systemContent += "\n\nPATIENT HEALTH INFORMATION (JSON Format):\n"
            }
            systemContent += context
        }

        // Add combined system message if we have any system content
        if !systemContent.isEmpty {
            messages.append([
                "role": "system",
                "content": systemContent
            ])
            AppLog.shared.ai("System message length: \(systemContent.count) chars", level: .debug)
        }

        // Use ConversationContextBuilder to get trimmed history within token limits
        let contextResult = ConversationContextBuilder.buildContext(
            currentMessage: message,
            healthContext: context,
            conversationHistory: conversationHistory,
            systemPrompt: systemContent,
            provider: .openAICompatible
        )

        // Log context building results
        ConversationContextBuilder.logContextSummary(contextResult)

        // Add conversation history (already trimmed to fit)
        for historyMessage in contextResult.conversationHistory {
            messages.append([
                "role": historyMessage.role.rawValue,
                "content": historyMessage.content
            ])
        }

        // Add user message
        messages.append([
            "role": "user",
            "content": message
        ])

        // Create request body with streaming enabled
        var requestBody: [String: Any] = [
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": true  // Enable streaming
        ]

        if let modelToUse = model ?? defaultModel, !modelToUse.isEmpty {
            requestBody["model"] = modelToUse
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        AppLog.shared.ai("Starting streaming request to \(safeURLDescription(messagesURL))")

        let startTime = Date()
        var accumulatedContent = ""
        var responseModel: String? = nil

        // Use URLSession bytes for streaming. Only a bounded prefix of a failed
        // response is retained, and it is never included in the error object.
        let stream: (URLSession.AsyncBytes, URLResponse)
        do {
            stream = try await session.bytes(for: request)
        } catch {
            providerConnectionFailure(operation: "streaming", error: error)
            throw error
        }
        let (bytes, response) = stream

        guard let httpResponse = response as? HTTPURLResponse else {
            throw invalidProviderResponse(operation: "streaming", error: .invalidResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Drain the stream so URLSession can finish it, but retain only a
            // bounded prefix for safe diagnostics.
            var errorData = Data()
            for try await byte in bytes {
                if errorData.count < Self.maxStreamingErrorBytes {
                    errorData.append(byte)
                }
            }
            throw providerRequestFailure(operation: "streaming", response: httpResponse, body: errorData)
        }

        // Parse SSE stream
        var lineBuffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))

            if char == "\n" {
                // Process completed line
                let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                lineBuffer = ""

                // Skip empty lines and comments
                if line.isEmpty || line.hasPrefix(":") {
                    continue
                }

                // Parse SSE data field
                if line.hasPrefix("data: ") {
                    let dataContent = String(line.dropFirst(6))

                    // Check for stream end
                    if dataContent == "[DONE]" {
                        AppLog.shared.ai("Stream completed")
                        break
                    }

                    // Parse JSON chunk
                    if let chunkData = dataContent.data(using: .utf8) {
                        do {
                            if let chunk = try JSONSerialization.jsonObject(with: chunkData) as? [String: Any] {
                                // Extract model if present
                                if let model = chunk["model"] as? String {
                                    responseModel = model
                                }

                                // Extract content delta
                                if let choices = chunk["choices"] as? [[String: Any]],
                                   let firstChoice = choices.first,
                                   let delta = firstChoice["delta"] as? [String: Any],
                                   let content = delta["content"] as? String {
                                    accumulatedContent += content
                                    onUpdate(accumulatedContent)
                                }
                            }
                        } catch {
                            // Log but continue - some chunks might not parse
                            AppLog.shared.ai("Failed to parse streaming chunk (\(dataContent.count) bytes)", level: .warning)
                        }
                    }
                }
            } else {
                lineBuffer.append(char)
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)

        // Clean the final response
        let cleanedContent = AIResponseCleaner.cleanConversational(accumulatedContent)

        let finalResponse = OpenAICompatibleChatResponse(
            content: cleanedContent,
            model: responseModel ?? defaultModel,
            processingTime: processingTime,
            totalTokens: nil  // Token count not available in streaming mode
        )

        AppLog.shared.ai("Streaming complete - \(cleanedContent.count) chars in \(String(format: "%.2f", processingTime))s")

        onComplete(finalResponse)
    }

    private func parseFlexibleChatContent(from data: Data) throws -> (content: String, model: String?, totalTokens: Int?) {
        // Attempt lightweight JSON parsing without assuming exact schema
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let json = jsonObject as? [String: Any]
        else {
            throw OpenAICompatibleError.invalidResponse
        }

        var extractedContent: String?
        var extractedModel: String?
        var extractedTokens: Int?

        if let model = json["model"] as? String {
            extractedModel = model
        }

        if let usage = json["usage"] as? [String: Any],
           let tokens = usage["total_tokens"] as? Int {
            extractedTokens = tokens
        }

        if let responseText = json["response"] as? String, !responseText.isEmpty {
            extractedContent = responseText
        } else if let outputText = json["output"] as? String, !outputText.isEmpty {
            extractedContent = outputText
        } else if let outputArray = json["output"] as? [[String: Any]] {
            let text = outputArray.compactMap { entry -> String? in
                if let textString = entry["text"] as? String {
                    return textString
                } else if let textObject = entry["text"] as? [String: Any],
                          let value = textObject["value"] as? String {
                    return value
                }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty {
                extractedContent = text
            }
        } else if let message = json["message"] as? String, !message.isEmpty {
            extractedContent = message
        } else if let contentArray = json["content"] as? [[String: Any]] {
            let text = contentArray.compactMap { entry -> String? in
                if let textString = entry["text"] as? String {
                    return textString
                } else if let textObject = entry["text"] as? [String: Any],
                          let value = textObject["value"] as? String {
                    return value
                }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty {
                extractedContent = text
            }
        } else if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any] {
                    if let contentString = message["content"] as? String, !contentString.isEmpty {
                        extractedContent = contentString
                        break
                    } else if let contentArray = message["content"] as? [[String: Any]] {
                        let text = contentArray.compactMap { entry -> String? in
                            if let textString = entry["text"] as? String {
                                return textString
                            } else if let textObject = entry["text"] as? [String: Any],
                                      let value = textObject["value"] as? String {
                                return value
                            }
                            return nil
                        }.joined(separator: "\n")
                        if !text.isEmpty {
                            extractedContent = text
                            break
                        }
                    }
                    if let roleModel = message["model"] as? String {
                        extractedModel = roleModel
                    }
                }

                if let text = choice["text"] as? String, !text.isEmpty {
                    extractedContent = text
                    break
                }
            }
        }

        guard let content = extractedContent, !content.isEmpty else {
            throw OpenAICompatibleError.emptyResponse
        }

        return (content: content, model: extractedModel, totalTokens: extractedTokens)
    }

    private func parseFlexibleModels(from data: Data) throws -> [String] {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let json = jsonObject as? [String: Any]
        else {
            throw OpenAICompatibleError.invalidResponse
        }

        if let dataArray = json["data"] as? [String] {
            return dataArray
        }

        if let modelsArray = json["models"] as? [String] {
            return modelsArray
        }

        if let dataObjects = json["data"] as? [[String: Any]] {
            let identifiers = dataObjects.compactMap { entry -> String? in
                if let id = entry["id"] as? String {
                    return id
                } else if let name = entry["name"] as? String {
                    return name
                }
                return nil
            }
            if !identifiers.isEmpty {
                return identifiers
            }
        }

        if let array = json["models"] as? [[String: Any]] {
            let identifiers = array.compactMap { entry -> String? in
                if let id = entry["id"] as? String {
                    return id
                } else if let name = entry["name"] as? String {
                    return name
                }
                return nil
            }
            if !identifiers.isEmpty {
                return identifiers
            }
        }

        throw OpenAICompatibleError.invalidResponse
    }

    // MARK: - Models
    func listModels() async throws -> [String] {
        let baseURL = try validatedBaseURLForRequest()
        let modelsURL = baseURL.appendingPathComponent("/v1/models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add API key if provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw invalidProviderResponse(operation: "models", error: .invalidResponse)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw providerRequestFailure(operation: "models", response: httpResponse, body: data)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if let modelsResponse = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
                return modelsResponse.data.map { $0.id }
            }

            if let flexibleModels = try? parseFlexibleModels(from: data) {
                return flexibleModels
            }

            throw invalidProviderResponse(operation: "models", error: .invalidResponse)

        } catch {
            if let providerError = error as? OpenAICompatibleError,
               case .requestFailed = providerError {
                lastError = providerError
            } else {
                providerConnectionFailure(operation: "models", error: error)
            }
            throw error
        }
    }

    // MARK: - AIProviderInterface
    func getCapabilities() async throws -> AICapabilities {
        let models = try await listModels()

        return AICapabilities(
            supportedModels: models,
            maxTokens: 4096, // Common default
            supportsStreaming: true,
            supportsImages: declaresVisionSupport, // User-declared in settings
            supportsDocuments: false,
            supportedLanguages: ["en"]
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Configuration updates would require creating a new client instance
        throw OpenAICompatibleError.configurationUpdateNotSupported
    }
}

// MARK: - Vision Document Extraction
extension OpenAICompatibleClient: VisionDocumentExtractor {
    var supportsVisionExtraction: Bool {
        declaresVisionSupport
    }

    func extractFromDocument(
        pages: [DocumentPageImage],
        ocrText: String,
        schemaPrompt: String
    ) async throws -> String {
        try await performVisionExtraction(pages: pages, ocrText: ocrText, schemaPrompt: schemaPrompt)
    }
}

// MARK: - Response Models

struct OpenAICompatibleChatResponse: AIResponse {
    let content: String
    let model: String?
    let processingTime: TimeInterval
    let totalTokens: Int?

    var responseTime: TimeInterval {
        return processingTime
    }

    var tokenCount: Int? {
        return totalTokens
    }

    var metadata: [String: Any]? {
        var meta: [String: Any] = [
            "processing_time": processingTime
        ]
        if let model {
            meta["model"] = model
        }
        if let totalTokens {
            meta["total_tokens"] = totalTokens
        }
        return meta
    }
}

struct OpenAIChatCompletionResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [ChatChoice]
    let usage: Usage?

    struct ChatChoice: Codable {
        let index: Int?
        let message: Message?
        let text: String?
        let finishReason: String?
        let model: String?
        let delta: Delta?

        enum CodingKeys: String, CodingKey {
            case index, message, text, model, delta
            case finishReason = "finish_reason"
        }

        var primaryContent: String? {
            if let messageContent = message?.content, !messageContent.isEmpty {
                return messageContent
            }
            if let text = text, !text.isEmpty {
                return text
            }
            if let deltaContent = delta?.content, !deltaContent.isEmpty {
                return deltaContent
            }
            return nil
        }
    }

    struct Message: Codable {
        let role: String?
        let content: String?
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
    }

    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenAIModelsResponse: Codable {
    let object: String?
    let data: [ModelData]

    struct ModelData: Codable {
        let id: String
        let object: String?
        let created: Int?
        let ownedBy: String?

        enum CodingKeys: String, CodingKey {
            case id, object, created
            case ownedBy = "owned_by"
        }
    }
}

// MARK: - Errors
struct OpenAICompatibleFailure: Equatable {
    let statusCode: Int
    let provider: String
    let requestIdentifier: String?
    let message: String?

    init(
        statusCode: Int,
        provider: String = "OpenAI-compatible",
        requestIdentifier: String? = nil,
        message: String? = nil
    ) {
        self.statusCode = statusCode
        self.provider = String(provider.prefix(64))
        self.requestIdentifier = Self.safeRequestIdentifier(requestIdentifier)
        self.message = Self.safeMessage(message)
    }

    var localizedDescription: String {
        var description = "\(provider) request failed (HTTP \(statusCode))"
        if let message {
            description += ": \(message)"
        }
        if let requestIdentifier {
            description += " [request ID: \(requestIdentifier)]"
        }
        return String(description.prefix(512))
    }

    private static func safeRequestIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:/-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func safeMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let redacted = AppLog.redactForSupport(message)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redacted.isEmpty else { return nil }
        return String(redacted.prefix(256))
    }
}

enum OpenAICompatibleError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case requestFailed(OpenAICompatibleFailure)
    case configurationUpdateNotSupported
    case authenticationFailed

    /// Compatibility overload for existing internal callers. The message is
    /// sanitized and bounded before it is retained in the error value.
    static func requestFailed(_ statusCode: Int, _ message: String) -> OpenAICompatibleError {
        .requestFailed(OpenAICompatibleFailure(statusCode: statusCode, message: message))
    }

    /// Builds a safe failure from an HTTP response without retaining its body.
    static func requestFailed(
        response: HTTPURLResponse,
        body _: Data,
        provider: String = "OpenAI-compatible"
    ) -> OpenAICompatibleError {
        let requestIdentifier = ["x-request-id", "request-id", "x-amzn-requestid"]
            .compactMap { response.value(forHTTPHeaderField: $0) }
            .first

        return .requestFailed(OpenAICompatibleFailure(
            statusCode: response.statusCode,
            provider: provider,
            requestIdentifier: requestIdentifier
        ))
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyResponse:
            return "Server returned empty response"
        case .requestFailed(let failure):
            return failure.localizedDescription
        case .configurationUpdateNotSupported:
            return "Configuration updates require app restart"
        case .authenticationFailed:
            return "Authentication failed - check your API key"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Check the server URL in settings"
        case .invalidResponse, .emptyResponse:
            return "Verify the server is OpenAI-compatible"
        case .requestFailed(let failure):
            if failure.statusCode == 401 {
                return "Check your API key in settings"
            } else if (500...599).contains(failure.statusCode) {
                return "Server error - try again later"
            }
            return "Check your request and try again"
        case .configurationUpdateNotSupported:
            return "Restart the app to apply changes"
        case .authenticationFailed:
            return "Enter a valid API key in settings"
        }
    }
}
