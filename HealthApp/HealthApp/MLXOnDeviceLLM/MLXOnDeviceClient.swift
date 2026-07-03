//
//  MLXOnDeviceClient.swift
//  HealthApp
//
//  AIProviderInterface implementation using Apple MLX for on-device LLM inference
//

import Foundation
import SwiftUI
import CoreImage

#if !targetEnvironment(simulator)
import MLX
import MLXLMCommon
import MLXLLM
import MLXVLM
#endif

// MARK: - MLX On-Device Client

@MainActor
class MLXOnDeviceClient: ObservableObject, AIProviderInterface {

    private struct ChatSessionSignature: Equatable {
        let conversationId: UUID
        let modelId: String
        let instructionsHash: Int
        let maxTokens: Int?
        let maxKVSize: Int?
        let temperature: Float
        let topP: Float
        let repetitionPenalty: Float?
    }

    // MARK: - Published Properties (AIProviderInterface)

    @Published var isConnected: Bool = false
    @Published var connectionStatus: ProviderConnectionStatus = .disconnected
    @Published var lastError: Error?

    // MARK: - Private Properties

    private let modelProvider: @MainActor () -> MLXModelInfo

    #if !targetEnvironment(simulator)
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    #endif

    private var currentModelInfo: MLXModelInfo?
    private var isModelLoaded = false
    private var isSuspendedForBackground = false
    private var chatSessionSignature: ChatSessionSignature?

    private let visionExtractionMaxTokens = 1024
    private let visionExtractionMaxKVSize = 4096

    // MARK: - Init

    init(modelProvider: @escaping @MainActor () -> MLXModelInfo = { MLXModelInfo.selectedModel }) {
        self.modelProvider = modelProvider
    }

    // MARK: - AIProviderInterface Methods

    func testConnection() async throws -> Bool {
        #if targetEnvironment(simulator)
        connectionStatus = .error(MLXOnDeviceError.simulatorNotSupported)
        isConnected = false
        return false
        #else
        guard MLXModelInfo.isEnabled else {
            connectionStatus = .disconnected
            isConnected = false
            return false
        }

        do {
            try await loadModel()

            let session = try makeIsolatedSession(maxTokensOverride: 10)

            // Quick test: generate a short response
            let testResult = try await session.respond(to: "Say OK")

            let success = !testResult.isEmpty
            connectionStatus = success ? .connected : .error(MLXOnDeviceError.generationFailed("Empty test response"))
            isConnected = success
            return success
        } catch {
            connectionStatus = .error(error)
            isConnected = false
            lastError = error
            return false
        }
        #endif
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        #if targetEnvironment(simulator)
        throw MLXOnDeviceError.simulatorNotSupported
        #else
        try await ensureModelLoaded()

        let instructions = buildInstructions(systemPrompt: nil, healthContext: context)
        let session = try makeIsolatedSession(instructions: instructions)

        let startTime = Date()

        let response = try await session.respond(to: message)
        let responseTime = Date().timeIntervalSince(startTime)

        return MLXOnDeviceResponse(
            content: response,
            responseTime: responseTime
        )
        #endif
    }

    func getCapabilities() async throws -> AICapabilities {
        let model = modelProvider()
        return AICapabilities(
            supportedModels: MLXModelInfo.allModels.map { $0.displayName },
            maxTokens: model.contextWindow,
            supportsStreaming: true,
            supportsImages: model.modelType == .vlm,
            supportsDocuments: false,
            supportedLanguages: ["en"]
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Configuration is managed through UserDefaults/MLXModelInfo
        // Invalidate the current model so it reloads with new settings
        await unloadModel()
    }

    // MARK: - Streaming Chat

    /// Send a streaming chat message using MLX ChatSession.
    ///
    /// The ChatSession manages multi-turn context internally via KV cache:
    /// - `systemPrompt` + `healthContext` become the session `instructions` (set once per session)
    /// - `conversationHistory` is used for re-hydration when the session must be rebuilt
    ///   (e.g., conversation switch, model change, health context change)
    /// - `message` is passed as-is to `streamResponse(to:)` — no manual formatting needed
    func sendStreamingChatMessage(
        _ message: String,
        healthContext: String,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID,
        systemPrompt: String?,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXOnDeviceResponse) -> Void
    ) async throws {
        #if targetEnvironment(simulator)
        throw MLXOnDeviceError.simulatorNotSupported
        #else
        let startTime = Date()
        try await ensureModelLoaded()

        guard let modelContainer else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        // Build instructions from system prompt + health context (the model's "system message")
        let instructions = buildInstructions(systemPrompt: systemPrompt, healthContext: healthContext)

        let sessionSignature = makeChatSessionSignature(
            conversationId: conversationId,
            instructions: instructions
        )

        let needsRebuild = chatSessionSignature != sessionSignature
        if needsRebuild {
            AppLog.shared.mlx("[MLXClient] Session inputs changed, rebuilding chat session")
            chatSession = nil
            chatSessionSignature = sessionSignature
        }

        // Create ChatSession if needed
        if chatSession == nil {
            let history = makeChatHistory(from: conversationHistory)
            if history.isEmpty {
                // Fresh conversation — no history to re-hydrate
                chatSession = ChatSession(
                    modelContainer,
                    instructions: instructions,
                    generateParameters: currentGenerateParameters()
                )
                AppLog.shared.mlx("[MLXClient] Created new ChatSession (fresh conversation)")
            } else {
                // Re-hydrate from saved conversation history
                chatSession = ChatSession(
                    modelContainer,
                    instructions: instructions,
                    history: history,
                    generateParameters: currentGenerateParameters()
                )
                AppLog.shared.mlx("[MLXClient] Created new ChatSession (re-hydrated \(history.count) messages)")
            }
        }

        guard let chatSession else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        // Stream the response — just the raw user message; ChatSession handles the rest
        var accumulatedContent = ""

        do {
            for try await chunk in chatSession.streamResponse(to: message) {
                accumulatedContent += chunk
                onUpdate(accumulatedContent)
            }
        } catch {
            // If streaming fails partway, still return what we have
            if accumulatedContent.isEmpty {
                throw MLXOnDeviceError.generationFailed(error.localizedDescription)
            }
            AppLog.shared.mlx("[MLXClient] Streaming ended with error but got partial content: \(error.localizedDescription)", level: .warning)
        }

        let responseTime = Date().timeIntervalSince(startTime)

        let response = MLXOnDeviceResponse(
            content: accumulatedContent,
            responseTime: responseTime,
            tokenCount: nil,
            tokensPerSecond: nil,
            promptTokenCount: nil,
            metadata: [
                "conversationId": conversationId.uuidString,
                "modelId": currentModelInfo?.huggingFaceId ?? "unknown"
            ]
        )

        onComplete(response)
        #endif
    }

    // MARK: - Model Lifecycle

    func loadModel() async throws {
        #if targetEnvironment(simulator)
        throw MLXOnDeviceError.simulatorNotSupported
        #else
        let selectedModel = modelProvider()

        if isModelLoaded, currentModelInfo?.id == selectedModel.id, modelContainer != nil {
            return
        }

        if isModelLoaded {
            await unloadModel()
        }

        // Check if model is downloaded
        guard MLXModelDownloadManager.shared.isModelDownloaded(selectedModel) else {
            throw MLXOnDeviceError.modelNotDownloaded
        }

        AppLog.shared.mlx("[MLXClient] Loading model: \(selectedModel.displayName) (\(selectedModel.huggingFaceId))")

        // Keep retained MLX cache small on iPhone. VLM inference has large
        // transient allocations; retaining less cache leaves more headroom.
        let cacheLimit = selectedModel.modelType == .vlm
            ? 128 * 1024 * 1024
            : 512 * 1024 * 1024
        MLX.Memory.cacheLimit = cacheLimit

        let configuration = ModelConfiguration(id: selectedModel.huggingFaceId)

        // Load via the appropriate factory
        switch selectedModel.modelType {
        case .llm:
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
        case .vlm:
            modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
        }

        currentModelInfo = selectedModel
        isModelLoaded = true
        connectionStatus = .connected
        isConnected = true

        AppLog.shared.mlx("[MLXClient] Model loaded successfully: \(selectedModel.displayName)")
        #endif
    }

    func unloadModel() async {
        #if !targetEnvironment(simulator)
        chatSession = nil
        modelContainer = nil
        MLX.Memory.clearCache()
        #endif
        currentModelInfo = nil
        isModelLoaded = false
        chatSessionSignature = nil
        connectionStatus = .disconnected
        isConnected = false
    }

    // MARK: - App Lifecycle

    func suspendForBackground() async {
        guard !isSuspendedForBackground else { return }
        isSuspendedForBackground = true
        AppLog.shared.mlx("[MLXClient] Suspended for background")
        // MLX uses unified memory so model stays in RAM; no special action needed.
        // For memory pressure, the OS can reclaim GPU cache automatically.
    }

    func resumeAfterForeground() async {
        guard isSuspendedForBackground else { return }
        isSuspendedForBackground = false
        AppLog.shared.mlx("[MLXClient] Resumed from background")
    }

    // MARK: - Private Helpers

    private func ensureModelLoaded() async throws {
        if !isModelLoaded {
            try await loadModel()
        }
    }

    /// Build the combined instructions string from system prompt and health context.
    /// This becomes the ChatSession's system message — set once per session.
    private func buildInstructions(systemPrompt: String?, healthContext: String) -> String? {
        switch (systemPrompt, healthContext.isEmpty) {
        case (let prompt?, false):
            return "\(prompt)\n\nPatient health data:\n\(healthContext)"
        case (let prompt?, true):
            return prompt
        case (nil, false):
            return "Patient health data:\n\(healthContext)"
        case (nil, true):
            return nil
        }
    }

    #if !targetEnvironment(simulator)
    private func currentGenerateParameters(
        maxTokensOverride: Int? = nil,
        maxKVSizeOverride: Int? = nil
    ) -> GenerateParameters {
        let model = modelProvider()
        return GenerateParameters(
            maxTokens: maxTokensOverride ?? MLXModelInfo.configuredMaxTokens(for: model),
            maxKVSize: maxKVSizeOverride ?? MLXModelInfo.configuredContextSize,
            temperature: MLXModelInfo.configuredTemperature(for: model),
            topP: MLXModelInfo.configuredTopP(for: model),
            repetitionPenalty: MLXModelInfo.configuredRepetitionPenalty(for: model)
        )
    }

    private func makeIsolatedSession(
        instructions: String? = nil,
        maxTokensOverride: Int? = nil,
        maxKVSizeOverride: Int? = nil
    ) throws -> ChatSession {
        guard let modelContainer else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        return ChatSession(
            modelContainer,
            instructions: instructions,
            generateParameters: currentGenerateParameters(
                maxTokensOverride: maxTokensOverride,
                maxKVSizeOverride: maxKVSizeOverride
            )
        )
    }

    private func makeChatHistory(from conversationHistory: [ChatMessage]) -> [Chat.Message] {
        conversationHistory.compactMap { message in
            switch message.role {
            case .user:
                return .user(message.content)
            case .assistant:
                return .assistant(message.content)
            case .system:
                return nil
            }
        }
    }

    private func makeChatSessionSignature(
        conversationId: UUID,
        instructions: String?
    ) -> ChatSessionSignature {
        let params = currentGenerateParameters()
        return ChatSessionSignature(
            conversationId: conversationId,
            modelId: modelProvider().id,
            instructionsHash: instructions?.hashValue ?? 0,
            maxTokens: params.maxTokens,
            maxKVSize: params.maxKVSize,
            temperature: params.temperature,
            topP: params.topP,
            repetitionPenalty: params.repetitionPenalty
        )
    }
    #endif
}

// MARK: - Vision Document Extraction (on-device VLM)
extension MLXOnDeviceClient: VisionDocumentExtractor {

    /// Image input is available when the selected on-device model is a
    /// vision-language model (e.g. Qwen VLM) and on-device inference is enabled.
    var supportsVisionExtraction: Bool {
        MLXModelInfo.isEnabled && modelProvider().modelType == .vlm
    }

    /// Run the VLM over document pages ONE AT A TIME (memory-bounded on device),
    /// each with a fresh session, then merge the per-page JSON into a single
    /// response object. Everything stays on-device.
    func extractFromDocument(
        pages: [DocumentPageImage],
        ocrText: String,
        schemaPrompt: String
    ) async throws -> String {
        #if targetEnvironment(simulator)
        throw MLXOnDeviceError.simulatorNotSupported
        #else
        guard supportsVisionExtraction else {
            throw MLXOnDeviceError.generationFailed("Selected on-device model does not support image input")
        }
        try await ensureModelLoaded()

        var mergedLabValues: [[String: Any]] = []
        var mergedMetadata: [String: Any] = [:]

        for page in pages {
            guard let ciImage = CIImage(data: page.jpegData) else {
                AppLog.shared.mlx("[MLXClient] Could not decode page \(page.pageNumber) image for VLM extraction", level: .warning)
                continue
            }

            // Fresh session per page: no KV-cache accumulation across pages
            let session = try makeIsolatedSession(
                instructions: "You are a precise medical laboratory data extraction engine. You respond with valid JSON only — no prose, no markdown fences.",
                maxTokensOverride: visionExtractionMaxTokens,
                maxKVSizeOverride: visionExtractionMaxKVSize
            )

            let pagePrompt = Self.compactVisionExtractionPrompt(pageNumber: page.pageNumber)

            do {
                let response = try await session.respond(to: pagePrompt, image: .ciImage(ciImage))
                let parsedCount = mergePageJSON(
                    response,
                    pageNumber: page.pageNumber,
                    into: &mergedLabValues,
                    metadata: &mergedMetadata
                )
                AppLog.shared.mlx("[MLXClient] VLM extracted page \(page.pageNumber) (\(response.count) chars, parsed \(parsedCount) lab values)")
            } catch {
                AppLog.shared.mlx("[MLXClient] VLM extraction failed for page \(page.pageNumber): \(error.localizedDescription)", level: .warning)
            }
            MLX.Memory.clearCache()
        }

        var combined: [String: Any] = mergedMetadata
        combined["labValues"] = mergedLabValues

        let combinedData = try JSONSerialization.data(withJSONObject: combined)
        return String(data: combinedData, encoding: .utf8) ?? "{}"
        #endif
    }

    /// Pull labValues + document metadata out of one page's model output and
    /// accumulate them.
    private func mergePageJSON(
        _ response: String,
        pageNumber: Int,
        into labValues: inout [[String: Any]],
        metadata: inout [String: Any]
    ) -> Int {
        guard let json = Self.parseJSONObject(from: response) else {
            let fallbackValues = Self.recoverLabValueJSON(fromPlainText: response, pageNumber: pageNumber)
            if !fallbackValues.isEmpty {
                labValues.append(contentsOf: fallbackValues)
                AppLog.shared.mlx(
                    "[MLXClient] VLM page output contained no parseable JSON; recovered \(fallbackValues.count) lab values from text",
                    level: .warning
                )
                return fallbackValues.count
            } else {
                AppLog.shared.mlx("[MLXClient] VLM page output contained no parseable JSON", level: .warning)
                return 0
            }
        }

        let originalCount = labValues.count
        if let values = json["labValues"] as? [[String: Any]] {
            labValues.append(contentsOf: values)
        }
        for key in ["documentDate", "laboratoryName", "orderingPhysician"] {
            if metadata[key] == nil, let value = json[key], !(value is NSNull) {
                metadata[key] = value
            }
        }
        return labValues.count - originalCount
    }

    static func recoverLabValueJSON(fromPlainText text: String, pageNumber: Int) -> [[String: Any]] {
        let page = NativeDocumentExtractor.PageText(
            pageNumber: pageNumber,
            text: text,
            observations: nil,
            tables: nil
        )
        let candidates = LabReportParser().parse(pages: [page])

        return candidates.map { candidate in
            var item: [String: Any] = [
                "testName": candidate.originalTestName,
                "testType": candidate.testType == .urine ? "URINE" : "BLOOD",
                "value": candidate.value,
                "page": pageNumber
            ]
            if let unit = candidate.unit { item["unit"] = unit }
            if let referenceRange = candidate.referenceRange { item["referenceRange"] = referenceRange }
            if let abnormalFlag = candidate.abnormalFlag { item["flag"] = abnormalFlag }
            return item
        }
    }

    private static func compactVisionExtractionPrompt(pageNumber: Int) -> String {
        """
        Extract lab results from this image. Return ONLY valid JSON. No prose. No markdown.
        Use this exact object shape:
        {"labValues":[{"testName":"","testType":"BLOOD","value":"","unit":null,"referenceRange":null,"flag":null,"page":\(pageNumber)}],"documentDate":null,"laboratoryName":null,"orderingPhysician":null}

        Rules:
        - Include blood and urine lab values.
        - Preserve printed names, values, units, ranges, and flags.
        - Use "BLOOD" or "URINE" for testType.
        - Use page \(pageNumber) for every item.
        - If no lab values are visible, return {"labValues":[],"documentDate":null,"laboratoryName":null,"orderingPhysician":null}
        """
    }

    private static func parseJSONObject(from response: String) -> [String: Any]? {
        let cleaned = cleanModelJSONText(response)
        let candidates = jsonCandidates(from: cleaned)

        for candidate in candidates {
            if let json = decodeJSONObject(candidate) {
                return json
            }
            if let json = decodeJSONObject(repairCommonJSONIssues(candidate)) {
                return json
            }
        }

        return nil
    }

    private static func decodeJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let json = object as? [String: Any] {
            return json
        }
        if let values = object as? [[String: Any]] {
            return ["labValues": values]
        }
        return nil
    }

    private static func cleanModelJSONText(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: #"```(?:json)?"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\u{201C}", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "\u{201D}", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "\u{2018}", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "\u{2019}", with: "'")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jsonCandidates(from cleaned: String) -> [String] {
        var candidates: [String] = []
        if let object = firstJSONObject(in: cleaned) {
            candidates.append(object)
        }

        if cleaned.first == "[", cleaned.last == "]" {
            candidates.append(cleaned)
        }

        if let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]"),
           start < end {
            candidates.append(String(cleaned[start...end]))
        }

        return candidates
    }

    private static func repairCommonJSONIssues(_ text: String) -> String {
        var repaired = text.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )
        repaired = repaired.replacingOccurrences(
            of: #":\s*None\b"#,
            with: ": null",
            options: .regularExpression
        )
        repaired = repaired.replacingOccurrences(
            of: #":\s*nil\b"#,
            with: ": null",
            options: .regularExpression
        )
        repaired = repaired.trimmingCharacters(in: .whitespacesAndNewlines)

        if repaired.first == "[" {
            return #"{"labValues":"# + repaired + "}"
        }
        return repaired
    }

    /// Balanced-brace scan for the first JSON object, tolerant of markdown
    /// fences and <think> blocks that small models sometimes emit.
    private static func firstJSONObject(in text: String) -> String? {
        var cleaned = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: #"```(?:json)?"#, with: "", options: .regularExpression)

        guard let startIndex = cleaned.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = startIndex

        while index < cleaned.endIndex {
            let char = cleaned[index]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" { depth += 1 }
                if char == "}" {
                    depth -= 1
                    if depth == 0 { return String(cleaned[startIndex...index]) }
                }
            }
            index = cleaned.index(after: index)
        }

        if let endIndex = cleaned.lastIndex(of: "}"), endIndex > startIndex {
            return String(cleaned[startIndex...endIndex])
        }
        return nil
    }
}
