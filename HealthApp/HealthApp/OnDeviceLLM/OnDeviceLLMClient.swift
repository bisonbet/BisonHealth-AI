//
//  OnDeviceLLMClient.swift
//  HealthApp
//
//  AIProviderInterface implementation for on-device LLM
//  Provides local AI chat without internet connection
//

import Foundation
import os.log

// MARK: - On-Device LLM Response

/// Response from on-device LLM inference
struct OnDeviceLLMResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(content: String, responseTime: TimeInterval, tokenCount: Int? = nil, tokensPerSecond: Double? = nil) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount
        self.metadata = tokensPerSecond != nil ? ["tokensPerSecond": tokensPerSecond!] : nil
    }
}

// MARK: - On-Device LLM Client

/// Client for on-device LLM inference implementing AIProviderInterface
@MainActor
class OnDeviceLLMClient: ObservableObject, AIProviderInterface {

    // MARK: - Published Properties

    @Published var isConnected: Bool = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?

    // MARK: - Private Properties

    private var llm: OnDeviceLLM?
    private var currentModelInfo: OnDeviceLLMModelInfo?
    private var isModelLoaded = false
    private let logger = os.Logger(subsystem: "com.bisonhealth.app", category: "OnDeviceLLMClient")

    // Streaming support
    private var streamingContent: String = ""
    private var onStreamUpdate: ((String) -> Void)?
    private var onStreamComplete: ((OnDeviceLLMResponse) -> Void)?

    // Context caching for faster follow-up questions
    private var cachedContextHash: Int?
    private var cachedSystemPromptHash: Int?
    private var isSuspendedForBackground = false

    // MARK: - Initialization

    init() {
        updateConnectionStatus()
    }

    // MARK: - AIProviderInterface Implementation

    func testConnection() async throws -> Bool {
        logger.info("[OnDeviceLLMClient] Testing connection...")

        // Check if on-device LLM is enabled
        guard OnDeviceLLMModelInfo.isEnabled else {
            logger.info("[OnDeviceLLMClient] On-device LLM is not enabled")
            connectionStatus = .disconnected
            isConnected = false
            return false
        }

        // Check if a model is downloaded
        let selectedModel = OnDeviceLLMModelInfo.selectedModel
        guard selectedModel.isDownloaded else {
            logger.info("[OnDeviceLLMClient] No model downloaded")
            connectionStatus = .error(NSError(domain: "OnDeviceLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model downloaded"]))
            isConnected = false
            return false
        }

        // Try to load the model if not already loaded
        do {
            try await loadModel()

            // Do a simple test generation
            guard let llm = llm else {
                throw OnDeviceLLMError.modelNotLoaded
            }

            llm.template = selectedModel.templateType.template(systemPrompt: nil)
            let testResult = await llm.generate(from: "Say 'OK' if you're working.")

            let success = !testResult.isEmpty
            connectionStatus = success ? .connected : .error(NSError(domain: "OnDeviceLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Test generation failed"]))
            isConnected = success

            logger.info("[OnDeviceLLMClient] Connection test result: \(success)")
            return success

        } catch {
            logger.error("[OnDeviceLLMClient] Connection test failed: \(error.localizedDescription)")
            connectionStatus = .error(error)
            isConnected = false
            lastError = error
            return false
        }
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        let startTime = Date()

        try await ensureModelLoaded()
        guard let llm = llm else {
            throw OnDeviceLLMError.modelNotLoaded
        }

        let selectedModel = OnDeviceLLMModelInfo.selectedModel

        // CRITICAL: Preserve conversation state AND hash values before non-conversational tasks (like title generation)
        // This prevents title generation from corrupting the KV cache
        let preservedState = llm.savedState
        let preservedContextHash = cachedContextHash
        let preservedSystemPromptHash = cachedSystemPromptHash
        logger.debug("[OnDeviceLLMClient] Preserved conversation state for non-conversational task (state: \(preservedState != nil), contextHash: \(preservedContextHash != nil), promptHash: \(preservedSystemPromptHash != nil))")

        // Build the full prompt with context
        // Note: Don't add "User:" prefix - the template already wraps in user tags
        let fullPrompt: String
        if !context.isEmpty {
            fullPrompt = """
            Context:
            \(context)

            Question: \(message)
            """
        } else {
            fullPrompt = message
        }

        // Set up template with health assistant system prompt
        llm.template = selectedModel.templateType.template(
            systemPrompt: LLMTemplate.healthAssistantSystemPrompt
        )

        // Generate response
        let result = await llm.generate(from: fullPrompt)
        let responseTime = Date().timeIntervalSince(startTime)

        // Restore the original conversation state AND hash values after title generation completes
        // This ensures the next user message can continue from the correct KV cache state
        if let preservedState = preservedState {
            await llm.restoreSavedState(preservedState)
            cachedContextHash = preservedContextHash
            cachedSystemPromptHash = preservedSystemPromptHash
            logger.debug("[OnDeviceLLMClient] Restored conversation state after non-conversational task")
        }

        // Clean up the response
        let cleanedResult = cleanupResponse(result)

        // Get metrics
        let tokenCount = Int(llm.metrics.inferenceTokenCount)
        let tokensPerSecond = llm.metrics.inferenceTokensPerSecond

        logger.info("[OnDeviceLLMClient] Generated response in \(String(format: "%.1f", responseTime))s at \(String(format: "%.1f", tokensPerSecond)) tokens/sec")

        return OnDeviceLLMResponse(
            content: cleanedResult,
            responseTime: responseTime,
            tokenCount: tokenCount,
            tokensPerSecond: tokensPerSecond
        )
    }

    func getCapabilities() async throws -> AICapabilities {
        let selectedModel = OnDeviceLLMModelInfo.selectedModel

        return AICapabilities(
            supportedModels: OnDeviceLLMModelInfo.allModels.filter { $0.isDownloaded }.map { $0.displayName },
            maxTokens: selectedModel.contextWindow,
            supportsStreaming: true,
            supportsImages: false,
            supportsDocuments: false,
            supportedLanguages: ["en"]
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // Reload model if configuration changes
        // Properly shut down the existing LLM first
        if let llm = llm {
            await llm.shutdown()
        }
        isModelLoaded = false
        llm = nil
        try await loadModel()
    }

    // MARK: - Streaming Support

    /// Send a streaming chat message with callbacks for updates
    /// - Parameters:
    ///   - message: The user's current message
    ///   - context: Health context in JSON format
    ///   - conversationHistory: Previous messages in the conversation (for multi-turn support)
    ///   - model: Model to use (optional)
    ///   - systemPrompt: System prompt (optional, uses default if nil)
    ///   - onUpdate: Callback for streaming updates
    ///   - onComplete: Callback when generation completes
    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        conversationHistory: [ChatMessage] = [],
        model: String? = nil,
        systemPrompt: String?,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (OnDeviceLLMResponse) -> Void
    ) async throws {
        let startTime = Date()

        logger.info("[OnDeviceLLMClient] sendStreamingChatMessage() called - isModelLoaded=\(self.isModelLoaded)")

        try await ensureModelLoaded()

        logger.info("[OnDeviceLLMClient] After ensureModelLoaded - isModelLoaded=\(self.isModelLoaded), llm=\(self.llm != nil ? "present" : "nil")")

        guard let llm = llm else {
            throw OnDeviceLLMError.modelNotLoaded
        }

        let selectedModel = OnDeviceLLMModelInfo.selectedModel

        // Set up template with provided or default system prompt FIRST (needed for hash calculation)
        let effectiveSystemPrompt = systemPrompt ?? LLMTemplate.healthAssistantSystemPrompt
        llm.template = selectedModel.templateType.template(systemPrompt: effectiveSystemPrompt)

        // Check if context and system prompt are the same as last time (for KV cache optimization)
        // IMPORTANT: Do this BEFORE building the prompt so we know whether to include context
        let currentContextHash = context.hash
        let currentSystemPromptHash = effectiveSystemPrompt.hash
        let contextUnchanged = (cachedContextHash == currentContextHash &&
                                cachedSystemPromptHash == currentSystemPromptHash &&
                                !conversationHistory.isEmpty)  // Only reuse if we have history

        // Debug logging for hash comparison
        logger.debug("[OnDeviceLLMClient] Hash check: current=(\(currentContextHash),\(currentSystemPromptHash)), cached=(\(self.cachedContextHash ?? -1),\(self.cachedSystemPromptHash ?? -1)), historyEmpty=\(!conversationHistory.isEmpty)")

        if contextUnchanged {
            logger.info("[OnDeviceLLMClient] ✅ Context unchanged - will reuse KV cache from previous turn")
            logger.info("[OnDeviceLLMClient] Skipping ~\(context.isEmpty ? 0 : llm.encode(context).count) context tokens")
        } else {
            logger.info("[OnDeviceLLMClient] Context changed or first turn - processing full context")
            logger.debug("[OnDeviceLLMClient] Reason: contextHashMatch=\(self.cachedContextHash == currentContextHash), promptHashMatch=\(self.cachedSystemPromptHash == currentSystemPromptHash), hasHistory=\(!conversationHistory.isEmpty)")
            // Clear conversation history since context changed
            await llm.clearHistory()
            // Update cached hashes
            cachedContextHash = currentContextHash
            cachedSystemPromptHash = currentSystemPromptHash
        }

        // Build the prompt - optimize based on whether context is cached
        // Note: Don't add "User:" prefix - the template already wraps in user tags
        let fullPrompt: String
        var promptParts: [String] = []

        // If context is unchanged and we have KV cache, ONLY send the new message
        // Otherwise, send full context + message
        if contextUnchanged {
            // Context is in KV cache - only send the new question
            logger.info("[OnDeviceLLMClient] Using cached context - sending only new question")
            promptParts.append("Question: \(message)")
        } else {
            // First turn or context changed - send everything
            // Add health context if provided
            if !context.isEmpty {
                promptParts.append("Context:\n\(context)")

                // Debug logging for context
                logger.debug("[OnDeviceLLMClient] Sending context (\(context.count) chars)")
                if context.contains("medical_documents") {
                    logger.debug("[OnDeviceLLMClient] Context includes medical_documents")
                } else {
                    logger.warning("[OnDeviceLLMClient] Context does NOT include medical_documents")
                }
            } else {
                logger.debug("[OnDeviceLLMClient] No context provided")
            }

            // Add conversation history if provided (for multi-turn conversations)
            if !conversationHistory.isEmpty {
                let historyText = formatConversationHistory(conversationHistory)
                promptParts.append("Previous conversation:\n\(historyText)")
                logger.info("[OnDeviceLLMClient] Including \(conversationHistory.count) previous messages in context")
            }

            // Add the current question
            promptParts.append("Question: \(message)")
        }

        fullPrompt = promptParts.joined(separator: "\n\n")

        // Debug: Log token breakdown for context analysis using ACTUAL tokenization
        let systemPromptTokens = llm.encode(effectiveSystemPrompt).count
        let contextTokens = context.isEmpty ? 0 : llm.encode(context).count
        let messageTokens = llm.encode(message).count
        let fullPromptTokens = llm.encode(fullPrompt).count

        logger.info("[OnDeviceLLMClient] Token breakdown (actual counts):")
        logger.info("[OnDeviceLLMClient]   System prompt: \(effectiveSystemPrompt.count) chars = \(systemPromptTokens) tokens")
        logger.info("[OnDeviceLLMClient]   Context: \(context.count) chars = \(contextTokens) tokens")
        logger.info("[OnDeviceLLMClient]   User message: \(message.count) chars = \(messageTokens) tokens")
        logger.info("[OnDeviceLLMClient]   Full prompt (context+message): \(fullPrompt.count) chars = \(fullPromptTokens) tokens")

        // The template adds special tokens, estimate ~50-100 tokens overhead
        let templateOverhead = 75
        let estimatedTotal = systemPromptTokens + fullPromptTokens + templateOverhead
        logger.info("[OnDeviceLLMClient]   Estimated total with template: ~\(estimatedTotal) tokens")

        // If context unchanged, we should only process the new message (much faster!)
        // But the current architecture processes the full prompt each time
        // TODO: Optimize to only process new message when context is cached
        if contextUnchanged {
            logger.info("[OnDeviceLLMClient]   Actual tokens to process: ~\(messageTokens + templateOverhead) (context in KV cache)")
        }

        // Set up streaming callbacks
        // Note: llm.update is called from InferenceActor, not MainActor
        // We need to dispatch to MainActor for UI updates
        streamingContent = ""
        var localStreamingContent = ""
        var stopStreamingUpdates = false  // Flag to stop sending updates after meta-commentary marker

        llm.update = { [weak self] (delta: String?) in
            guard let self = self, let delta = delta else { return }
            guard !stopStreamingUpdates else { return }  // Don't send more updates if we hit meta-commentary

            // Accumulate locally (thread-safe since this is called sequentially)
            localStreamingContent += delta

            // ALWAYS send the update first (for smooth streaming)
            // The callback (from AIChatManager) will dispatch to MainActor
            onUpdate(localStreamingContent)

            // Check if we've hit a horizontal rule followed by meta-commentary
            // Only check after we have substantial content (>200 chars) to avoid premature detection
            if localStreamingContent.count > 200 && localStreamingContent.contains("\n---\n") {
                // Extract content before the horizontal rule
                if let ruleRange = localStreamingContent.range(of: "\n---\n") {
                    let beforeRule = String(localStreamingContent[..<ruleRange.lowerBound])
                    // Send the cleaned content (without the horizontal rule)
                    onUpdate(beforeRule)
                    // Stop sending further updates
                    stopStreamingUpdates = true
                    self.logger.debug("[OnDeviceLLMClient] Detected horizontal rule marker, stopping streaming updates")
                    return
                }
            }
        }

        // Generate response
        logger.info("[OnDeviceLLMClient] Starting inference (prefill may take a few seconds for large contexts)...")
        await llm.respond(to: fullPrompt)
        logger.info("[OnDeviceLLMClient] llm.respond() returned")

        let responseTime = Date().timeIntervalSince(startTime)
        logger.info("[OnDeviceLLMClient] Raw output length: \(llm.output.count) chars")

        // Clean up the response
        let cleanedResult = cleanupResponse(llm.output)
        logger.info("[OnDeviceLLMClient] Cleaned output length: \(cleanedResult.count) chars")

        // Get metrics
        let tokenCount = Int(llm.metrics.inferenceTokenCount)
        let tokensPerSecond = llm.metrics.inferenceTokensPerSecond

        logger.info("[OnDeviceLLMClient] Streaming completed in \(String(format: "%.1f", responseTime))s at \(String(format: "%.1f", tokensPerSecond)) tokens/sec")

        let response = OnDeviceLLMResponse(
            content: cleanedResult,
            responseTime: responseTime,
            tokenCount: tokenCount,
            tokensPerSecond: tokensPerSecond
        )

        logger.info("[OnDeviceLLMClient] Calling onComplete callback with \(cleanedResult.count) char response")
        onComplete(response)
        logger.info("[OnDeviceLLMClient] onComplete callback finished")
    }

    // MARK: - Model Management

    /// Load the selected model into memory
    func loadModel() async throws {
        logger.info("[OnDeviceLLMClient] loadModel() called - isModelLoaded=\(self.isModelLoaded), llm=\(self.llm != nil ? "present" : "nil")")

        guard !isModelLoaded else {
            logger.info("[OnDeviceLLMClient] Model already loaded, skipping")
            return
        }

        let selectedModel = OnDeviceLLMModelInfo.selectedModel

        guard selectedModel.isDownloaded else {
            throw OnDeviceLLMError.modelNotDownloaded
        }

        logger.info("[OnDeviceLLMClient] Loading model: \(selectedModel.displayName)")

        let modelURL = selectedModel.fileURL
        let template = selectedModel.templateType.template(
            systemPrompt: LLMTemplate.healthAssistantSystemPrompt
        )

        llm = OnDeviceLLM(
            from: modelURL,
            template: template,
            topK: OnDeviceLLMModelInfo.configuredTopK,
            topP: OnDeviceLLMModelInfo.configuredTopP,
            minP: OnDeviceLLMModelInfo.configuredMinP,
            temp: OnDeviceLLMModelInfo.configuredTemperature,
            repeatPenalty: OnDeviceLLMModelInfo.configuredRepeatPenalty,
            maxTokenCount: Int32(OnDeviceLLMModelInfo.configuredMaxTokens)
        )

        currentModelInfo = selectedModel
        isModelLoaded = true
        connectionStatus = .connected
        isConnected = true

        logger.info("[OnDeviceLLMClient] Model loaded successfully")
    }

    /// Unload the model from memory
    func unloadModel() async {
        // Properly shut down the LLM before releasing it
        if let llm = llm {
            await llm.shutdown()
        }
        llm = nil
        currentModelInfo = nil
        isModelLoaded = false
        connectionStatus = .disconnected
        isConnected = false
        logger.info("[OnDeviceLLMClient] Model unloaded")
    }

    // MARK: - App Lifecycle

    func suspendForBackground() async {
        guard !isSuspendedForBackground else { return }
        isSuspendedForBackground = true
        logger.info("[OnDeviceLLMClient] Suspending on-device LLM for background")

        if let llm = llm {
            await llm.suspendForBackground()
        }
    }

    func resumeAfterForeground() async {
        guard isSuspendedForBackground else { return }
        isSuspendedForBackground = false
        logger.info("[OnDeviceLLMClient] Resuming on-device LLM after foreground")

        if let llm = llm {
            await llm.resumeAfterForeground()
        }
    }

    /// Check if a model is loaded
    var isModelLoaded_: Bool {
        isModelLoaded && llm != nil
    }

    // MARK: - Private Helpers

    private func ensureModelLoaded() async throws {
        if !isModelLoaded {
            try await loadModel()
        }
    }

    private func updateConnectionStatus() {
        let selectedModel = OnDeviceLLMModelInfo.selectedModel

        if !OnDeviceLLMModelInfo.isEnabled {
            connectionStatus = .disconnected
            isConnected = false
        } else if !selectedModel.isDownloaded {
            connectionStatus = .error(NSError(domain: "OnDeviceLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No model downloaded"]))
            isConnected = false
        } else if isModelLoaded {
            connectionStatus = .connected
            isConnected = true
        } else {
            connectionStatus = .disconnected
            isConnected = false
        }
    }

    private func cleanupResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove meta-commentary after horizontal rules (---)
        // Some models add explanations about their own responses that aren't helpful
        if let horizontalRuleRange = cleaned.range(of: "\n---\n") {
            // Get the text after the horizontal rule
            let afterRule = String(cleaned[horizontalRuleRange.upperBound...])

            // List of phrases that indicate meta-commentary to remove
            let metaCommentaryPrefixes = [
                "This response",
                "This answer",
                "Note:",
                "Important:",
                "Please note",
                "It is important to note",
                "The above",
                "These recommendations",
                "This information",
                "This suggestion"
            ]

            // Check if the content after --- starts with meta-commentary
            let afterRuleTrimmed = afterRule.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldRemove = metaCommentaryPrefixes.contains { prefix in
                afterRuleTrimmed.hasPrefix(prefix)
            }

            if shouldRemove {
                // Remove everything from the horizontal rule onwards
                cleaned = String(cleaned[..<horizontalRuleRange.lowerBound])
                logger.debug("[OnDeviceLLMClient] Removed meta-commentary after horizontal rule")
            }
        }

        // Also check for meta-commentary at the end without horizontal rules
        // Split into paragraphs and check the last one
        let paragraphs = cleaned.components(separatedBy: "\n\n")
        if paragraphs.count >= 2 {
            let lastParagraph = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let metaCommentaryPrefixes = [
                "This response",
                "This answer",
                "Note:",
                "Important:",
                "Please note",
                "It is important to note",
                "The above",
                "These recommendations",
                "This information",
                "This suggestion",
                "Always consult with a healthcare professional"
            ]

            let shouldRemoveLastParagraph = metaCommentaryPrefixes.contains { prefix in
                lastParagraph.hasPrefix(prefix)
            }

            if shouldRemoveLastParagraph {
                // Remove the last paragraph
                let withoutLast = paragraphs.dropLast().joined(separator: "\n\n")
                cleaned = withoutLast
                logger.debug("[OnDeviceLLMClient] Removed meta-commentary paragraph at end")
            }
        }

        // Remove any remaining template tokens (covers ChatML, Phi-3, Gemma3, etc.)
        let tokensToRemove = [
            // ChatML / Qwen
            "<|im_end|>", "<|im_start|>",
            // Phi-3 / MediPhi
            "<|end|>", "<|end_of_assistant_response|>", "<|assistant|>", "<|user|>", "<|system|>", "<|endoftext|>",
            // Gemma3
            "<end_of_turn>", "<start_of_turn>", "<eos>",
            // Partial tokens that might leak
            "model\n", "user\n"
        ]
        for token in tokensToRemove {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        // Sanitize encoding issues
        cleaned = cleaned.sanitizedForLLMDisplay()

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Format conversation history for inclusion in the prompt
    /// Limits to last N messages to avoid token overflow
    private func formatConversationHistory(_ messages: [ChatMessage]) -> String {
        // Limit to last 6 messages (3 exchanges) to avoid token overflow
        // Skip system messages as they're handled separately
        let relevantMessages = messages
            .filter { $0.role != .system }
            .suffix(6)

        var historyLines: [String] = []
        for msg in relevantMessages {
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            // Truncate very long messages to save tokens
            let content = msg.content.count > 500
                ? String(msg.content.prefix(500)) + "..."
                : msg.content
            historyLines.append("\(roleLabel): \(content)")
        }

        return historyLines.joined(separator: "\n")
    }
}

// MARK: - Connection Status Extension

extension OnDeviceLLMClient {

    /// Check if on-device LLM is available (enabled and model downloaded)
    var isAvailable: Bool {
        OnDeviceLLMModelInfo.isEnabled && OnDeviceLLMModelInfo.selectedModel.isDownloaded
    }

    /// Get the currently selected model info
    var selectedModelInfo: OnDeviceLLMModelInfo {
        OnDeviceLLMModelInfo.selectedModel
    }

    /// Get all downloaded models
    var downloadedModels: [OnDeviceLLMModelInfo] {
        OnDeviceLLMModelInfo.allModels.filter { $0.isDownloaded }
    }
}
