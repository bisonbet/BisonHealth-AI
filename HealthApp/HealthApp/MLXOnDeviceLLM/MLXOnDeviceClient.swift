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
    private var activeConversationId: UUID?
    private var isSuspendedForBackground = false
    private let logger = Logger.shared

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

            guard modelContainer != nil else {
                throw MLXOnDeviceError.modelNotLoaded
            }

            // Quick test: generate a short response
            let session = ChatSession(
                modelContainer!,
                generateParameters: GenerateParameters(maxTokens: 10)
            )
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

        guard let chatSession else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        let startTime = Date()

        // Prepend health context to the user message
        let fullMessage = context.isEmpty ? message : "Health context:\n\(context)\n\nQuestion: \(message)"

        let response = try await chatSession.respond(to: fullMessage)
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

    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID,
        model: String? = nil,
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

        // Handle conversation switching — clear session when conversation changes
        if activeConversationId != conversationId {
            logger.info("[MLXClient] Conversation changed, resetting session")
            activeConversationId = conversationId
            chatSession = nil
        }

        // Create or update the ChatSession with the current system prompt
        if chatSession == nil {
            let generateParams = GenerateParameters(
                maxTokens: MLXModelInfo.configuredMaxTokens,
                temperature: MLXModelInfo.configuredTemperature,
                topP: MLXModelInfo.configuredTopP,
                repetitionPenalty: MLXModelInfo.configuredRepetitionPenalty
            )

            // Build history from conversation messages for session rehydration
            var history: [Chat.Message] = []
            for msg in conversationHistory {
                switch msg.role {
                case .user:
                    history.append(.user(msg.content))
                case .assistant:
                    history.append(.assistant(msg.content))
                case .system:
                    break // System messages handled via instructions parameter
                }
            }

            chatSession = ChatSession(
                modelContainer,
                instructions: systemPrompt,
                history: history,
                generateParameters: generateParams
            )
        }

        guard let chatSession else {
            throw MLXOnDeviceError.modelNotLoaded
        }

        // Prepend health context to the user message
        let fullMessage = context.isEmpty ? message : "Health context:\n\(context)\n\nQuestion: \(message)"

        // Stream the response
        var accumulatedContent = ""
        var completionInfo: GenerateCompletionInfo?

        do {
            for try await chunk in chatSession.streamResponse(to: fullMessage) {
                accumulatedContent += chunk
                onUpdate(accumulatedContent)
            }
        } catch {
            // If streaming fails partway, still return what we have
            if accumulatedContent.isEmpty {
                throw MLXOnDeviceError.generationFailed(error.localizedDescription)
            }
            logger.warning("[MLXClient] Streaming ended with error but got partial content: \(error.localizedDescription)")
        }

        let responseTime = Date().timeIntervalSince(startTime)

        let response = MLXOnDeviceResponse(
            content: accumulatedContent,
            responseTime: responseTime,
            tokenCount: completionInfo.map { Int($0.generationTokenCount) },
            tokensPerSecond: completionInfo?.tokensPerSecond,
            promptTokenCount: completionInfo.map { Int($0.promptTokenCount) },
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
        guard !isModelLoaded else { return }

        let selectedModel = MLXModelInfo.selectedModel

        // Check if model is downloaded
        guard MLXModelDownloadManager.shared.isModelDownloaded(selectedModel) else {
            throw MLXOnDeviceError.modelNotDownloaded
        }

        logger.info("[MLXClient] Loading model: \(selectedModel.displayName) (\(selectedModel.huggingFaceId))")

        // Set GPU memory cache limit
        MLX.GPU.set(cacheLimit: 512 * 1024 * 1024) // 512MB cache

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

        logger.info("[MLXClient] Model loaded successfully: \(selectedModel.displayName)")
        #endif
    }

    func unloadModel() async {
        #if !targetEnvironment(simulator)
        chatSession = nil
        modelContainer = nil
        #endif
        currentModelInfo = nil
        isModelLoaded = false
        activeConversationId = nil
        connectionStatus = .disconnected
        isConnected = false
    }

    // MARK: - App Lifecycle

    func suspendForBackground() async {
        guard !isSuspendedForBackground else { return }
        isSuspendedForBackground = true
        logger.info("[MLXClient] Suspended for background")
        // MLX uses unified memory so model stays in RAM; no special action needed.
        // For memory pressure, the OS can reclaim GPU cache automatically.
    }

    func resumeAfterForeground() async {
        guard isSuspendedForBackground else { return }
        isSuspendedForBackground = false
        logger.info("[MLXClient] Resumed from background")
    }

    // MARK: - Private Helpers

    private func ensureModelLoaded() async throws {
        if !isModelLoaded {
            try await loadModel()
        }
    }
}
