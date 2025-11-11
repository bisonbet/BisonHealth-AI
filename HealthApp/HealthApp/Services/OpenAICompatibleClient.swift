import Foundation

// MARK: - OpenAI Compatible Client
/// Client for OpenAI-compatible API servers (LiteLLM, LocalAI, vLLM, etc.)
@MainActor
class OpenAICompatibleClient: ObservableObject, AIProviderInterface {

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?

    // MARK: - Properties
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let timeout: TimeInterval
    private var defaultModel: String?
    private let temperature: Double
    private let maxTokens: Int

    // MARK: - Initialization
    init(baseURL: String, apiKey: String? = nil, timeout: TimeInterval = 60.0, defaultModel: String? = nil, temperature: Double = 0.1, maxTokens: Int = 2048) {
        guard let url = URL(string: baseURL) else {
            self.baseURL = URL(string: "http://localhost:8000")!
            self.apiKey = apiKey
            self.timeout = timeout
            self.defaultModel = defaultModel
            self.temperature = temperature
            self.maxTokens = maxTokens

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            self.session = URLSession(configuration: config)

            print("⚠️ OpenAICompatibleClient: Invalid base URL, using default")
            return
        }

        self.baseURL = url
        self.apiKey = apiKey
        self.timeout = timeout
        self.defaultModel = defaultModel
        self.temperature = temperature
        self.maxTokens = maxTokens

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: config)

        print("✓ OpenAICompatibleClient initialized with base URL: \(baseURL)")
    }

    // MARK: - Connection Management
    func testConnection() async throws -> Bool {
        connectionStatus = .connecting

        do {
            // Try to list models as a connection test
            let models = try await listModels()

            connectionStatus = .connected
            isConnected = true
            print("✅ OpenAICompatibleClient: Connected successfully, found \(models.count) models")
            return true

        } catch {
            connectionStatus = .disconnected
            isConnected = false
            lastError = error
            print("❌ OpenAICompatibleClient: Connection failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Chat Completion
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        let messagesURL = baseURL.appendingPathComponent("/v1/chat/completions")

        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add API key if provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            print("🔑 OpenAICompatibleClient: Setting Authorization header with API key (length: \(apiKey.count))")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            print("⚠️ OpenAICompatibleClient: No API key provided - request will be sent without Authorization header")
        }

        // Build messages array
        var messages: [[String: String]] = []

        // Add context as system message if provided
        if !context.isEmpty {
            messages.append([
                "role": "system",
                "content": context
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
            "max_tokens": maxTokens
        ]

        if let model = defaultModel, !model.isEmpty {
            requestBody["model"] = model
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Debug: Log request with sanitized headers and truncated body
        print("📤 OpenAICompatibleClient: Sending request to \(messagesURL)")
        print("   Model: \(defaultModel ?? "(none)")")

        // Sanitize headers to hide API key
        if let headers = request.allHTTPHeaderFields {
            var sanitizedHeaders = headers
            if sanitizedHeaders["Authorization"] != nil {
                sanitizedHeaders["Authorization"] = "Bearer [REDACTED]"
            }
            print("   Headers: \(sanitizedHeaders)")
        }

        // Truncate body to first 200 characters
        if let bodyData = request.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            let truncatedBody = bodyString.count > 200
                ? String(bodyString.prefix(200)) + "... (\(bodyString.count - 200) more chars)"
                : bodyString
            print("   Body: \(truncatedBody)")
        }

        let startTime = Date()

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAICompatibleError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ OpenAICompatibleClient: Request failed (\(httpResponse.statusCode)): \(errorMessage)")
                throw OpenAICompatibleError.requestFailed(httpResponse.statusCode, errorMessage)
            }

            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if let chatResponse = try? decoder.decode(OpenAIChatCompletionResponse.self, from: data),
               let choice = chatResponse.choices.first {
                if let content = choice.primaryContent {
                    let processingTime = Date().timeIntervalSince(startTime)
                    let resolvedModel = chatResponse.model ?? choice.model ?? defaultModel
                    return OpenAICompatibleChatResponse(
                        content: content,
                        model: resolvedModel,
                        processingTime: processingTime,
                        totalTokens: chatResponse.usage?.totalTokens
                    )
                }
            }

            // Attempt to extract content using a flexible fallback parser
            if let fallbackContent = try? parseFlexibleChatContent(from: data) {
                let processingTime = Date().timeIntervalSince(startTime)
                return OpenAICompatibleChatResponse(
                    content: fallbackContent.content,
                    model: fallbackContent.model ?? defaultModel,
                    processingTime: processingTime,
                    totalTokens: fallbackContent.totalTokens
                )
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("❌ OpenAICompatibleClient: Unable to parse chat response: \(raw)")
            }
            throw OpenAICompatibleError.emptyResponse

        } catch {
            lastError = error
            throw error
        }
    }

    func updateDefaultModel(_ model: String?) {
        defaultModel = model
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
                throw OpenAICompatibleError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw OpenAICompatibleError.requestFailed(httpResponse.statusCode, "Failed to list models")
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            if let modelsResponse = try? decoder.decode(OpenAIModelsResponse.self, from: data) {
                return modelsResponse.data.map { $0.id }
            }

            if let flexibleModels = try? parseFlexibleModels(from: data) {
                return flexibleModels
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("❌ OpenAICompatibleClient: Unable to parse models response: \(raw)")
            }
            throw OpenAICompatibleError.invalidResponse

        } catch {
            lastError = error
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
            supportsImages: false, // Can be enabled if needed
            supportsDocuments: false,
            supportedLanguages: ["en"]
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Configuration updates would require creating a new client instance
        throw OpenAICompatibleError.configurationUpdateNotSupported
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
enum OpenAICompatibleError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case requestFailed(Int, String)
    case configurationUpdateNotSupported
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyResponse:
            return "Server returned empty response"
        case .requestFailed(let code, let message):
            return "Request failed (\(code)): \(message)"
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
        case .requestFailed(let code, _):
            if code == 401 {
                return "Check your API key in settings"
            } else if (500...599).contains(code) {
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
