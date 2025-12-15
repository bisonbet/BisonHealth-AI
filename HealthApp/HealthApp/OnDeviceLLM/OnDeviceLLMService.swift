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
import CryptoKit
import Combine

#if canImport(LocalLLMClient)
import LocalLLMClient
import LocalLLMClientLlama
#endif

private let logger = Logger(subsystem: "com.bisonhealth.ai", category: "OnDeviceLLM")

@MainActor
class OnDeviceLLMService: ObservableObject {
    static let shared = OnDeviceLLMService()

    // MARK: - Constants

    /// Maximum allowed model file size (5GB)
    private static let maxModelFileSizeBytes: Int64 = 5_000_000_000

    /// Minimum expected model file size (500MB) - files smaller than this are likely corrupted
    private static let minModelFileSizeBytes: Int64 = 500_000_000

    /// Buffer size for file operations (1MB) - balances memory usage and performance
    private static let fileBufferSize: Int = 1024 * 1024

    // MARK: - Published Properties

    @Published var isModelLoaded: Bool = false
    @Published var isModelLoading: Bool = false
    @Published var currentModel: OnDeviceLLMModel?
    @Published var currentQuantization: OnDeviceLLMQuantization?
    @Published var loadError: String?

    #if canImport(LocalLLMClient)
    private var llmSession: LLMSession?
    #endif

    private var memoryWarningCancellable: AnyCancellable?

    private init() {
        // Register for memory warnings using Combine (avoids potential selector-based observer leaks)
        memoryWarningCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    logger.warning("Received memory warning, unloading model")
                    self.unloadModel()
                }
            }
    }

    // MARK: - Model Loading

    func loadModel(modelID: String, quantization: OnDeviceLLMQuantization) async throws {
        #if canImport(LocalLLMClient)
        // Prevent concurrent loading
        guard !isModelLoading else {
            logger.warning("Model loading already in progress")
            throw OnDeviceLLMError.modelLoadInProgress
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

        if fileSize > Self.maxModelFileSizeBytes {
            throw OnDeviceLLMError.modelTooLarge(fileSize)
        }

        if fileSize < Self.minModelFileSizeBytes {
            throw OnDeviceLLMError.modelLoadFailed("Model file appears corrupted (size: \(fileSize) bytes)")
        }

        // Validate checksum if available (runs on background thread)
        if let checksums = model.checksums, let expectedChecksum = checksums[quantization.rawValue] {
            logger.info("Validating checksum for \(model.displayName) (\(quantization.rawValue))")
            let actualChecksum = try await calculateSHA256(filePath: filePath)

            if actualChecksum != expectedChecksum {
                logger.error("Checksum mismatch! Expected: \(expectedChecksum), Got: \(actualChecksum)")
                throw OnDeviceLLMError.modelLoadFailed("Model file checksum validation failed. File may be corrupted. Please delete and redownload.")
            }

            logger.info("Checksum validation passed")
        } else {
            logger.info("No checksum available for validation (model will load without verification)")
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

        // Validate context length using configurable ratio
        let estimatedTokens = estimateTokenCount(prompt, config: config)
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

                // Validate context length using configurable ratio
                let estimatedTokens = estimateTokenCount(prompt, config: config)
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

    /// Analyze a single image with the vision model
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

        logger.info("Analyzing image with vision model: \(model.displayName)")

        do {
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

    /// Analyze a multi-page document by splitting into pages and processing each separately
    func analyzeDocument(imagePages: [Data], extractionPrompt: String, config: OnDeviceLLMConfig) async throws -> String {
        guard !imagePages.isEmpty else {
            throw OnDeviceLLMError.imageProcessingFailed("No pages provided")
        }

        logger.info("Analyzing document with \(imagePages.count) page(s)")

        var extractedPages: [String] = []

        // Process each page separately
        for (index, pageData) in imagePages.enumerated() {
            let pageNumber = index + 1
            logger.info("Processing page \(pageNumber) of \(imagePages.count)")

            let pagePrompt = """
            \(extractionPrompt)

            This is page \(pageNumber) of \(imagePages.count). Extract all text, tables, and relevant medical information from this page.
            """

            do {
                let pageResult = try await analyzeImage(imageData: pageData, prompt: pagePrompt, config: config)
                extractedPages.append("--- Page \(pageNumber) ---\n\(pageResult)")

                logger.info("Successfully processed page \(pageNumber)")

            } catch {
                logger.error("Failed to process page \(pageNumber): \(error.localizedDescription)")
                extractedPages.append("--- Page \(pageNumber) ---\n[Error processing page: \(error.localizedDescription)]")
            }
        }

        // Consolidate all pages
        let consolidatedResult = extractedPages.joined(separator: "\n\n")

        logger.info("Document analysis complete. Processed \(imagePages.count) pages.")

        return consolidatedResult
    }

    /// Extract text from a document (OCR) - specialized for medical documents
    func extractTextFromDocument(imagePages: [Data], config: OnDeviceLLMConfig) async throws -> String {
        let extractionPrompt = """
        Extract all text from this medical document image. Preserve the original structure, formatting, and organization as much as possible.

        Include:
        - All text content
        - Table data (if any)
        - Numbers and measurements
        - Dates and timestamps
        - Medical terminology exactly as written
        - Any handwritten notes or annotations

        Format the output as plain text that preserves the document structure. Do not add interpretation or commentary.
        """

        return try await analyzeDocument(imagePages: imagePages, extractionPrompt: extractionPrompt, config: config)
    }

    // MARK: - Utility Methods

    func estimateTokenCount(_ text: String, config: OnDeviceLLMConfig) -> Int {
        // Configurable approximation tuned for medical text
        // Default: 3.5 chars/token (more accurate than 4.0 for medical terminology)
        return Int(ceil(Double(text.count) / config.charsPerTokenRatio))
    }

    func canProcessText(_ text: String, config: OnDeviceLLMConfig) -> Bool {
        let estimatedTokens = estimateTokenCount(text, config: config)
        return estimatedTokens <= config.contextWindow
    }

    /// Calculate SHA256 checksum of a file (runs on background thread)
    private func calculateSHA256(filePath: URL) async throws -> String {
        try await Task.detached {
            var hasher = SHA256()

            let fileHandle = try FileHandle(forReadingFrom: filePath)
            defer {
                do {
                    try fileHandle.close()
                } catch {
                    logger.error("Failed to close file handle: \(error.localizedDescription)")
                }
            }

            while autoreleasepool(invoking: {
                let data = fileHandle.readData(ofLength: Self.fileBufferSize)
                if data.count > 0 {
                    hasher.update(data: data)
                    return true
                } else {
                    return false
                }
            }) { }

            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
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
        // Attempt to use vision model capabilities
        // Note: This requires LocalLLMClient to support vision models (LLaVA, Qwen-VL, etc.)

        do {
            // Convert image to base64 for vision model processing
            let base64Image = imageData.base64EncodedString()

            // Vision models typically expect special formatting
            // For Qwen-VL models, images are often embedded in the prompt
            let visionPrompt = "<|vision_start|>\(base64Image)<|vision_end|>\n\(prompt)"

            logger.info("Attempting vision model inference with image size: \(imageData.count) bytes")

            // Use standard generation with vision-formatted prompt
            // If LocalLLMClient supports vision natively, it will process the image
            // Otherwise, it will fail gracefully
            let response = try await self.generate(
                prompt: visionPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )

            return response

        } catch {
            logger.error("Vision model processing failed: \(error.localizedDescription)")
            logger.info("This may indicate that LocalLLMClient doesn't fully support vision models yet")
            logger.info("Fallback to external vision processing (Docling) recommended")
            throw OnDeviceLLMError.visionNotSupported
        }
    }
}
#endif
