//
//  LocalLLMProvider.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import Foundation

@MainActor
class LocalLLMProvider: AIProviderInterface {
    @Published var isConnected: Bool = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?

    private let llmService = OnDeviceLLMService.shared
    private let downloadManager = ModelDownloadManager.shared
    private var config: OnDeviceLLMConfig

    init() {
        self.config = OnDeviceLLMConfig.load()

        // Auto-load model if available and enabled
        Task {
            await initializeIfNeeded()
        }
    }

    private func initializeIfNeeded() async {
        guard OnDeviceLLMConfig.isEnabled else {
            connectionStatus = .disconnected
            isConnected = false
            return
        }

        // Check if model is downloaded
        guard let model = OnDeviceLLMModel.model(withID: config.modelID) else {
            connectionStatus = .disconnected
            isConnected = false
            return
        }

        if downloadManager.isModelDownloaded(model: model, quantization: config.quantization) {
            do {
                try await llmService.loadModel(modelID: config.modelID, quantization: config.quantization)
                connectionStatus = .connected
                isConnected = true
            } catch {
                connectionStatus = .error(error)
                lastError = error
                isConnected = false
            }
        } else {
            connectionStatus = .disconnected
            isConnected = false
        }
    }

    // MARK: - AIProviderInterface

    func testConnection() async throws -> Bool {
        guard OnDeviceLLMConfig.isEnabled else {
            throw AIProviderError.configurationError
        }

        guard let model = OnDeviceLLMModel.model(withID: config.modelID) else {
            throw OnDeviceLLMError.modelNotFound(config.modelID)
        }

        // Check if model is downloaded
        guard downloadManager.isModelDownloaded(model: model, quantization: config.quantization) else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        // Try to load model if not already loaded
        if !llmService.isModelLoaded {
            connectionStatus = .connecting
            do {
                try await llmService.loadModel(modelID: config.modelID, quantization: config.quantization)
                connectionStatus = .connected
                isConnected = true
            } catch {
                connectionStatus = .error(error)
                lastError = error
                isConnected = false
                throw error
            }
        }

        // Test the model
        let isWorking = await llmService.testModel()

        if isWorking {
            connectionStatus = .connected
            isConnected = true
        } else {
            connectionStatus = .error(AIProviderError.serverUnavailable)
            isConnected = false
        }

        return isWorking
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        guard OnDeviceLLMConfig.isEnabled else {
            throw AIProviderError.configurationError
        }

        guard let model = llmService.currentModel else {
            // Try to load model
            try await testConnection()
            guard llmService.currentModel != nil else {
                throw OnDeviceLLMError.modelNotDownloaded
            }
        }

        let startTime = Date()

        // Build the prompt with system context
        let systemPrompt = """
        You are a medical AI assistant. You have access to the following health data context:

        \(context)

        Use this context to provide accurate, personalized health insights. Always recommend consulting healthcare professionals for medical decisions.
        """

        guard let currentModel = model else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        let fullPrompt = currentModel.promptTemplate.formatPrompt(system: systemPrompt, user: message)

        // Generate response
        do {
            let responseText = try await llmService.generate(prompt: fullPrompt, config: config)
            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = llmService.estimateTokenCount(responseText)

            return LocalLLMResponse(
                content: responseText,
                responseTime: responseTime,
                tokenCount: tokenCount,
                metadata: [
                    "model": currentModel.displayName,
                    "quantization": config.quantization.rawValue,
                    "temperature": config.temperature,
                    "maxTokens": config.maxTokens
                ]
            )

        } catch {
            lastError = error
            throw error
        }
    }

    func getCapabilities() async throws -> AICapabilities {
        let downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()
        let modelNames = downloadedModels.compactMap { downloadedModel -> String? in
            OnDeviceLLMModel.model(withID: downloadedModel.modelID)?.displayName
        }

        let currentModel = llmService.currentModel ?? OnDeviceLLMModel.model(withID: config.modelID)

        return AICapabilities(
            supportedModels: modelNames.isEmpty ? OnDeviceLLMModel.availableModels.map(\.displayName) : modelNames,
            maxTokens: currentModel?.contextWindow ?? 8192,
            supportsStreaming: true,
            supportsImages: currentModel?.isVisionModel ?? false,
            supportsDocuments: currentModel?.isVisionModel ?? false,
            supportedLanguages: ["en"]  // English by default, can be expanded
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Map AIProviderConfig to OnDeviceLLMConfig if needed
        // For now, local LLM uses its own configuration system via UserDefaults
        // This method is here for protocol conformance

        // Reload config from UserDefaults
        self.config = OnDeviceLLMConfig.load()

        // Reload model if configuration changed
        if llmService.isModelLoaded {
            if llmService.currentModel?.id != self.config.modelID ||
               llmService.currentQuantization != self.config.quantization {
                llmService.unloadModel()
                await initializeIfNeeded()
            }
        }
    }

    // MARK: - Streaming Support

    func sendMessageStreaming(_ message: String, context: String) -> AsyncThrowingStream<String, Error> {
        guard OnDeviceLLMConfig.isEnabled else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AIProviderError.configurationError)
            }
        }

        guard let model = llmService.currentModel else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: OnDeviceLLMError.modelNotDownloaded)
            }
        }

        let systemPrompt = """
        You are a medical AI assistant. You have access to the following health data context:

        \(context)

        Use this context to provide accurate, personalized health insights. Always recommend consulting healthcare professionals for medical decisions.
        """

        let fullPrompt = model.promptTemplate.formatPrompt(system: systemPrompt, user: message)

        return llmService.generateStreaming(prompt: fullPrompt, config: config)
    }

    // MARK: - Image Analysis

    func analyzeImage(imageData: Data, prompt: String, context: String) async throws -> AIResponse {
        guard OnDeviceLLMConfig.isEnabled else {
            throw AIProviderError.configurationError
        }

        guard let model = llmService.currentModel, model.isVisionModel else {
            throw OnDeviceLLMError.visionNotSupported
        }

        let startTime = Date()

        let fullPrompt = """
        Health Data Context:
        \(context)

        User Request:
        \(prompt)

        Please analyze the provided medical image or document and extract relevant information.
        """

        do {
            let responseText = try await llmService.analyzeImage(
                imageData: imageData,
                prompt: fullPrompt,
                config: config
            )
            let responseTime = Date().timeIntervalSince(startTime)
            let tokenCount = llmService.estimateTokenCount(responseText)

            return LocalLLMResponse(
                content: responseText,
                responseTime: responseTime,
                tokenCount: tokenCount,
                metadata: [
                    "model": model.displayName,
                    "quantization": config.quantization.rawValue,
                    "isVisionAnalysis": true
                ]
            )

        } catch {
            lastError = error
            throw error
        }
    }
}

// MARK: - Local LLM Response

struct LocalLLMResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(content: String, responseTime: TimeInterval, tokenCount: Int?, metadata: [String: Any]?) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}
