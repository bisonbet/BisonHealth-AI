//
//  MLXOnDeviceClient.swift
//  HealthApp
//
//  AIProviderInterface implementation using Apple MLX for on-device LLM inference
//

import Foundation
import SwiftUI

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
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?

    // MARK: - Private Properties

    #if !targetEnvironment(simulator)
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    #endif

    private var currentModelInfo: MLXModelInfo?
    private var isModelLoaded = false
    private var isSuspendedForBackground = false
    private var chatSessionSignature: ChatSessionSignature?

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
        let model = MLXModelInfo.selectedModel
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
        let selectedModel = MLXModelInfo.selectedModel

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

        // Set GPU memory cache limit
        MLX.Memory.cacheLimit = 512 * 1024 * 1024 // 512MB cache

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
    private func currentGenerateParameters(maxTokensOverride: Int? = nil) -> GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokensOverride ?? MLXModelInfo.configuredMaxTokens,
            maxKVSize: MLXModelInfo.configuredContextSize,
            temperature: MLXModelInfo.configuredTemperature,
            topP: MLXModelInfo.configuredTopP,
            repetitionPenalty: MLXModelInfo.configuredRepetitionPenalty
        )
    }

    private func makeIsolatedSession(instructions: String? = nil, maxTokensOverride: Int? = nil) throws -> ChatSession {
        guard let modelContainer else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        return ChatSession(
            modelContainer,
            instructions: instructions,
            generateParameters: currentGenerateParameters(maxTokensOverride: maxTokensOverride)
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
            modelId: MLXModelInfo.selectedModel.id,
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
