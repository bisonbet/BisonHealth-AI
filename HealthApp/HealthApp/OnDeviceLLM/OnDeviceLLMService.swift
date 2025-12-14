//
//  OnDeviceLLMService.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import Foundation
import UIKit
import os.log

#if canImport(LocalLLMClient)
import LocalLLMClient
import LocalLLMClientLlama
#endif

private let logger = Logger(subsystem: "com.bisonhealth.ai", category: "OnDeviceLLM")

@MainActor
class OnDeviceLLMService: ObservableObject {
    static let shared = OnDeviceLLMService()

    @Published var isModelLoaded: Bool = false
    @Published var isModelLoading: Bool = false
    @Published var currentModel: OnDeviceLLMModel?
    @Published var currentQuantization: OnDeviceLLMQuantization?
    @Published var loadError: String?

    #if canImport(LocalLLMClient)
    private var llmSession: LLMSession?
    #endif

    private let maxFileSizeBytes: Int64 = 5_000_000_000  // 5GB max model size

    private init() {
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        logger.warning("Received memory warning, unloading model")
        unloadModel()
    }

    // MARK: - Model Loading

    func loadModel(modelID: String, quantization: OnDeviceLLMQuantization) async throws {
        #if canImport(LocalLLMClient)
        // Prevent concurrent loading
        guard !isModelLoading else {
            logger.warning("Model loading already in progress")
            return
        }

        isModelLoading = true
        loadError = nil

        defer {
            isModelLoading = false
        }

        // Find model
        guard let model = OnDeviceLLMModel.model(withID: modelID) else {
            throw OnDeviceLLMError.modelNotFound(modelID)
        }

        // Check if model is downloaded
        let filePath = ModelDownloadManager.shared.modelFilePath(for: model, quantization: quantization)
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        // Validate file size
        let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        if fileSize > maxFileSizeBytes {
            throw OnDeviceLLMError.modelTooLarge(fileSize)
        }

        if fileSize < 500_000_000 {  // Less than 500MB suggests corruption
            throw OnDeviceLLMError.modelLoadFailed("Model file appears corrupted (size: \(fileSize) bytes)")
        }

        logger.info("Loading model: \(model.displayName) (\(quantization.rawValue)) from \(filePath.path)")

        // Unload existing model first
        if llmSession != nil {
            unloadModel()
        }

        do {
            // Create LLM session
            llmSession = try await LLMSession(
                modelPath: filePath.path,
                modelType: .llama  // All GGUF models use llama.cpp backend
            )

            currentModel = model
            currentQuantization = quantization
            isModelLoaded = true

            logger.info("Successfully loaded model: \(model.displayName)")

        } catch {
            loadError = error.localizedDescription
            logger.error("Failed to load model: \(error.localizedDescription)")
            throw OnDeviceLLMError.modelLoadFailed(error.localizedDescription)
        }
        #else
        throw OnDeviceLLMError.modelLoadFailed("LocalLLMClient not available")
        #endif
    }

    func unloadModel() {
        #if canImport(LocalLLMClient)
        llmSession = nil
        #endif
        currentModel = nil
        currentQuantization = nil
        isModelLoaded = false
        loadError = nil
        logger.info("Model unloaded")
    }

    // MARK: - Text Generation

    func generate(prompt: String, config: OnDeviceLLMConfig) async throws -> String {
        #if canImport(LocalLLMClient)
        guard let session = llmSession, let model = currentModel else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        // Validate context length
        // Note: Approximate token counting (1 token ≈ 4 characters)
        let estimatedTokens = prompt.count / 4
        if estimatedTokens > config.contextWindow {
            throw OnDeviceLLMError.contextTooLong(estimatedTokens, max: config.contextWindow)
        }

        logger.info("Generating response with model: \(model.displayName)")

        do {
            let response = try await session.generate(
                prompt: prompt,
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )

            guard !response.isEmpty else {
                throw OnDeviceLLMError.invalidResponse
            }

            return response.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            logger.error("Generation failed: \(error.localizedDescription)")
            throw OnDeviceLLMError.inferenceError(error.localizedDescription)
        }
        #else
        throw OnDeviceLLMError.inferenceError("LocalLLMClient not available")
        #endif
    }

    func generateStreaming(prompt: String, config: OnDeviceLLMConfig) -> AsyncThrowingStream<String, Error> {
        #if canImport(LocalLLMClient)
        return AsyncThrowingStream { continuation in
            Task {
                guard let session = llmSession, let model = currentModel else {
                    continuation.finish(throwing: OnDeviceLLMError.modelNotDownloaded)
                    return
                }

                // Validate context length
                let estimatedTokens = prompt.count / 4
                if estimatedTokens > config.contextWindow {
                    continuation.finish(throwing: OnDeviceLLMError.contextTooLong(estimatedTokens, max: config.contextWindow))
                    return
                }

                logger.info("Starting streaming generation with model: \(model.displayName)")

                do {
                    for try await chunk in session.generateStream(
                        prompt: prompt,
                        maxTokens: config.maxTokens,
                        temperature: config.temperature
                    ) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    logger.info("Streaming generation completed")

                } catch {
                    logger.error("Streaming generation failed: \(error.localizedDescription)")
                    continuation.finish(throwing: OnDeviceLLMError.inferenceError(error.localizedDescription))
                }
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: OnDeviceLLMError.inferenceError("LocalLLMClient not available"))
        }
        #endif
    }

    // MARK: - Medical Analysis

    func analyzeHealthData(_ text: String, context: String, config: OnDeviceLLMConfig) async throws -> String {
        guard let model = currentModel else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        let systemPrompt = """
        You are a medical AI assistant specialized in analyzing health data. You have been trained on medical literature and clinical knowledge. Provide accurate, evidence-based analysis while being clear about limitations. Always recommend consulting healthcare professionals for medical decisions.
        """

        let userPrompt = """
        Context: \(context)

        Health Data to Analyze:
        \(text)

        Please provide a comprehensive analysis including:
        1. Key findings and observations
        2. Potential patterns or trends
        3. Important considerations
        4. Recommendations for discussion with healthcare provider
        """

        let formattedPrompt = model.promptTemplate.formatPrompt(system: systemPrompt, user: userPrompt)

        return try await generate(prompt: formattedPrompt, config: config)
    }

    func summarizeConversation(_ messages: [String], config: OnDeviceLLMConfig) async throws -> String {
        guard let model = currentModel else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        let systemPrompt = """
        You are a medical AI assistant. Summarize the following health-related conversation concisely, highlighting key medical information, concerns, and recommendations.
        """

        let conversationText = messages.enumerated().map { index, message in
            let role = index % 2 == 0 ? "User" : "Assistant"
            return "\(role): \(message)"
        }.joined(separator: "\n\n")

        let userPrompt = """
        Please summarize this conversation:

        \(conversationText)
        """

        let formattedPrompt = model.promptTemplate.formatPrompt(system: systemPrompt, user: userPrompt)

        return try await generate(prompt: formattedPrompt, config: config)
    }

    // MARK: - Vision Model Support

    func analyzeImage(imageData: Data, prompt: String, config: OnDeviceLLMConfig) async throws -> String {
        #if canImport(LocalLLMClient)
        guard let model = currentModel else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        guard model.isVisionModel else {
            throw OnDeviceLLMError.visionNotSupported
        }

        guard let session = llmSession else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        let systemPrompt = """
        You are a medical AI assistant with vision capabilities. Analyze medical images, lab reports, and documents accurately. Identify key information while being clear about limitations. Always recommend professional medical review.
        """

        let formattedPrompt = model.promptTemplate.formatPrompt(system: systemPrompt, user: prompt)

        do {
            // Note: Vision support requires LocalLLMClient with image processing capabilities
            // This is a simplified implementation - actual vision processing may require
            // additional setup depending on the model format
            logger.info("Analyzing image with vision model: \(model.displayName)")

            let response = try await session.generateWithImage(
                imageData: imageData,
                prompt: formattedPrompt,
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )

            guard !response.isEmpty else {
                throw OnDeviceLLMError.invalidResponse
            }

            return response.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            logger.error("Image analysis failed: \(error.localizedDescription)")
            throw OnDeviceLLMError.imageProcessingFailed(error.localizedDescription)
        }
        #else
        throw OnDeviceLLMError.visionNotSupported
        #endif
    }

    // MARK: - Utility Methods

    func estimateTokenCount(_ text: String) -> Int {
        // Rough approximation: 1 token ≈ 4 characters
        return text.count / 4
    }

    func canProcessText(_ text: String, config: OnDeviceLLMConfig) -> Bool {
        let estimatedTokens = estimateTokenCount(text)
        return estimatedTokens <= config.contextWindow
    }

    // MARK: - Health Check

    func testModel() async -> Bool {
        guard isModelLoaded else { return false }

        do {
            let testPrompt = "Hello"
            let config = OnDeviceLLMConfig.load()
            let response = try await generate(prompt: testPrompt, config: config)
            return !response.isEmpty
        } catch {
            logger.error("Model test failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - LocalLLMClient Extensions

#if canImport(LocalLLMClient)
extension LLMSession {
    func generateWithImage(imageData: Data, prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
        // This is a placeholder for vision model support
        // Actual implementation depends on LocalLLMClient's vision capabilities
        // For now, we'll just generate text without image context
        logger.warning("Vision support not fully implemented, processing as text-only")
        return try await generate(prompt: prompt, maxTokens: maxTokens, temperature: temperature)
    }
}
#endif
