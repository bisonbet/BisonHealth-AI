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

    init(
        content: String,
        responseTime: TimeInterval,
        tokenCount: Int? = nil,
        tokensPerSecond: Double? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount

        var mergedMetadata = metadata ?? [:]
        if let tokensPerSecond {
            mergedMetadata["tokensPerSecond"] = tokensPerSecond
        }
        self.metadata = mergedMetadata.isEmpty ? nil : mergedMetadata
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

    // Context cache scaffolding (disabled for reliability-first rollout)
    private var cachedContextHash: Int?
    private var cachedSystemPromptHash: Int?
    private var activeConversationId: UUID?
    private let reliabilityFirstDisableCacheReuse = true
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

        // Build deterministic payload without leaking "Question:" markers.
        let fullPrompt = OnDevicePromptBuilder.singleTurnPrompt(
            healthContext: context,
            userMessage: message
        )

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
    ///   - conversationId: Conversation identifier for session safety
    ///   - model: Model to use (optional)
    ///   - systemPrompt: System prompt (optional, uses default if nil)
    ///   - onUpdate: Callback for streaming updates
    ///   - onComplete: Callback when generation completes
    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID,
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

        // Set up template with provided or default system prompt.
        let effectiveSystemPrompt = systemPrompt ?? LLMTemplate.healthAssistantSystemPrompt
        llm.template = selectedModel.templateType.template(systemPrompt: effectiveSystemPrompt)

        if activeConversationId != conversationId {
            logger.info("[OnDeviceLLMClient] Conversation changed: \(self.activeConversationId?.uuidString ?? "none") -> \(conversationId.uuidString)")
            activeConversationId = conversationId
            await llm.clearHistory()
            cachedContextHash = nil
            cachedSystemPromptHash = nil
        }

        if reliabilityFirstDisableCacheReuse {
            await llm.clearHistory()
        } else {
            let currentContextHash = stableContextHash(context)
            let currentSystemPromptHash = effectiveSystemPrompt.hashValue
            let contextUnchanged = (cachedContextHash == currentContextHash &&
                                    cachedSystemPromptHash == currentSystemPromptHash &&
                                    !conversationHistory.isEmpty)
            if !contextUnchanged {
                await llm.clearHistory()
                cachedContextHash = currentContextHash
                cachedSystemPromptHash = currentSystemPromptHash
            }
        }

        let maxInputTokens = OnDevicePromptBuilder.maxInputTokens(
            forContextWindow: Int(OnDeviceLLMModelInfo.configuredMaxTokens)
        )
        let promptResult = OnDevicePromptBuilder.build(
            request: OnDevicePromptBuilder.Request(
                healthContext: context,
                conversationHistory: conversationHistory,
                userMessage: message,
                maxInputTokens: maxInputTokens
            ),
            tokenCounter: { llm.encode($0).count }
        )

        logger.info(
            "[OnDeviceLLMClient] Turn diagnostics: conversationId=\(conversationId.uuidString), promptTokens=\(promptResult.finalPromptTokens), trimmedHistory=\(promptResult.trimmedHistoryCount), shortenedHistory=\(promptResult.shortenedHistoryMessageCount), trimmedDocs=\(promptResult.trimmedDocumentCount), contextTailTrimBytes=\(promptResult.contextTailTrimmedBytes), contextBytes=\(promptResult.finalContextBytes), fitStatus=\(promptResult.fitStatus.rawValue)"
        )

        guard promptResult.fitStatus != .inputTooLargeAfterCompaction else {
            throw OnDeviceLLMError.inferenceFailed("Input too large after compaction; reduce shared context and try again.")
        }

        let fullPrompt = promptResult.prompt
        let systemPromptTokens = llm.encode(effectiveSystemPrompt).count
        logger.info("[OnDeviceLLMClient] Token breakdown: system=\(systemPromptTokens), payload=\(promptResult.finalPromptTokens), maxInput=\(maxInputTokens)")

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

            // If internal prompt markers leak into generation, stop streaming at that boundary.
            if let leakRange = self.firstPromptLeakRange(in: localStreamingContent) {
                let beforeLeak = String(localStreamingContent[..<leakRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                onUpdate(beforeLeak)
                stopStreamingUpdates = true
                Task { @InferenceActor in
                    llm.stop()
                }
                self.logger.debug("[OnDeviceLLMClient] Detected prompt marker leak, stopping streaming updates")
                return
            }

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
                    Task { @InferenceActor in
                        llm.stop()
                    }
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
            tokensPerSecond: tokensPerSecond,
            metadata: [
                "conversationId": conversationId.uuidString,
                "promptTokens": promptResult.finalPromptTokens,
                "trimmedHistoryCount": promptResult.trimmedHistoryCount,
                "shortenedHistoryMessageCount": promptResult.shortenedHistoryMessageCount,
                "trimmedDocumentCount": promptResult.trimmedDocumentCount,
                "contextTailTrimmedBytes": promptResult.contextTailTrimmedBytes,
                "contextBytes": promptResult.finalContextBytes,
                "fitStatus": promptResult.fitStatus.rawValue
            ]
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
        activeConversationId = nil
        cachedContextHash = nil
        cachedSystemPromptHash = nil
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

    private func stableContextHash(_ context: String) -> Int {
        guard let data = context.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return context.hashValue
        }

        // Exclude volatile fields from future cache/session comparisons.
        json.removeValue(forKey: "timestamp")

        if let stableData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
           let stableString = String(data: stableData, encoding: .utf8) {
            return stableString.hashValue
        }
        return context.hashValue
    }

    private func cleanupResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // If internal prompt block markers leak into output, trim everything from first leak onward.
        if let leakRange = firstPromptLeakRange(in: cleaned) {
            cleaned = String(cleaned[..<leakRange.lowerBound])
            logger.debug("[OnDeviceLLMClient] Trimmed leaked prompt marker content from output")
        }

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

    private func firstPromptLeakRange(in text: String) -> Range<String.Index>? {
        let markers = [
            "<<HEALTH_CONTEXT_JSON>>",
            "<</HEALTH_CONTEXT_JSON>>",
            "<<CHAT_HISTORY>>",
            "<</CHAT_HISTORY>>",
            "<<CURRENT_USER_MESSAGE>>",
            "<</CURRENT_USER_MESSAGE>>",
            "<HEALTH_CONTEXT_JSON>",
            "</HEALTH_CONTEXT_JSON>",
            "<CHAT_HISTORY>",
            "</CHAT_HISTORY>",
            "<CURRENT_USER_MESSAGE>",
            "</CURRENT_USER_MESSAGE>",
            "HEALTH_CONTEXT_JSON",
            "CHAT_HISTORY",
            "CURRENT_USER_MESSAGE"
        ]

        var earliest: Range<String.Index>?
        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive]) {
                if let existing = earliest {
                    if range.lowerBound < existing.lowerBound {
                        earliest = range
                    }
                } else {
                    earliest = range
                }
            }
        }
        return earliest
    }

}

// MARK: - On-Device Prompt Builder

struct OnDevicePromptBuilder {
    struct Request {
        let healthContext: String
        let conversationHistory: [ChatMessage]
        let userMessage: String
        let maxInputTokens: Int
    }

    enum FitStatus: String {
        case fitWithoutCompaction
        case fitAfterCompaction
        case inputTooLargeAfterCompaction
    }

    struct BuildResult {
        let prompt: String
        let fitStatus: FitStatus
        let finalPromptTokens: Int
        let trimmedHistoryCount: Int
        let shortenedHistoryMessageCount: Int
        let trimmedDocumentCount: Int
        let contextTailTrimmedBytes: Int
        let finalContextBytes: Int
    }

    static func maxInputTokens(forContextWindow contextWindow: Int) -> Int {
        let outputReserve = min(2048, max(256, contextWindow / 10))
        return max(256, contextWindow - outputReserve)
    }

    static func singleTurnPrompt(healthContext: String, userMessage: String) -> String {
        buildPrompt(
            healthContext: normalizedContext(healthContext),
            history: [],
            userMessage: userMessage
        )
    }

    static func build(
        request: Request,
        tokenCounter: (String) -> Int
    ) -> BuildResult {
        var context = normalizedContext(request.healthContext)
        var history = request.conversationHistory.filter { $0.role != .system && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let userMessage = request.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        var trimmedHistoryCount = 0
        var shortenedHistoryMessageCount = 0
        var trimmedDocumentCount = 0
        var contextTailTrimmedBytes = 0
        var didCompact = false

        var prompt = buildPrompt(healthContext: context, history: history, userMessage: userMessage)
        var tokens = tokenCounter(prompt)

        // 1) Trim oldest history first.
        while tokens > request.maxInputTokens && !history.isEmpty {
            history.removeFirst()
            trimmedHistoryCount += 1
            didCompact = true
            prompt = buildPrompt(healthContext: context, history: history, userMessage: userMessage)
            tokens = tokenCounter(prompt)
        }

        // 2) Compact long history message bodies.
        if tokens > request.maxInputTokens && !history.isEmpty {
            let thresholds = [600, 400, 250, 160]
            var alreadyShortened = Set<UUID>()

            for threshold in thresholds where tokens > request.maxInputTokens {
                var changedInPass = false
                for index in history.indices where tokens > request.maxInputTokens {
                    if history[index].content.count > threshold {
                        history[index].content = truncateForHistory(history[index].content, maxChars: threshold)
                        if !alreadyShortened.contains(history[index].id) {
                            alreadyShortened.insert(history[index].id)
                            shortenedHistoryMessageCount += 1
                        }
                        didCompact = true
                        changedInPass = true

                        prompt = buildPrompt(healthContext: context, history: history, userMessage: userMessage)
                        tokens = tokenCounter(prompt)
                    }
                }
                if !changedInPass {
                    break
                }
            }
        }

        // 3) Remove lowest-priority document content from the tail of medical_documents.
        while tokens > request.maxInputTokens {
            let trimResult = trimLowestPriorityDocumentContent(in: context)
            guard trimResult.changed else {
                break
            }
            context = trimResult.context
            trimmedDocumentCount += trimResult.trimmedCount
            didCompact = true

            prompt = buildPrompt(healthContext: context, history: history, userMessage: userMessage)
            tokens = tokenCounter(prompt)
        }

        // 4) Trim context tail if still too large.
        if tokens > request.maxInputTokens {
            let minContextChars = 128
            while tokens > request.maxInputTokens && context.count > minContextChars {
                let previousCount = context.utf8.count
                let nextCount = max(minContextChars, context.count - 512)
                let truncated = String(context.prefix(nextCount))
                context = "\(truncated)\n...[context tail trimmed]"
                contextTailTrimmedBytes += max(0, previousCount - context.utf8.count)
                didCompact = true

                prompt = buildPrompt(healthContext: context, history: history, userMessage: userMessage)
                tokens = tokenCounter(prompt)
            }
        }

        let fitStatus: FitStatus
        if tokens <= request.maxInputTokens {
            fitStatus = didCompact ? .fitAfterCompaction : .fitWithoutCompaction
        } else {
            fitStatus = .inputTooLargeAfterCompaction
        }

        return BuildResult(
            prompt: prompt,
            fitStatus: fitStatus,
            finalPromptTokens: tokens,
            trimmedHistoryCount: trimmedHistoryCount,
            shortenedHistoryMessageCount: shortenedHistoryMessageCount,
            trimmedDocumentCount: trimmedDocumentCount,
            contextTailTrimmedBytes: contextTailTrimmedBytes,
            finalContextBytes: context.utf8.count
        )
    }

    private static func normalizedContext(_ context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "{}" : trimmed
    }

    private static func truncateForHistory(_ content: String, maxChars: Int) -> String {
        guard content.count > maxChars else {
            return content
        }
        let candidate = String(content.prefix(maxChars))
        if let lastSpace = candidate.lastIndex(of: " ") {
            return String(candidate[..<lastSpace]) + " ..."
        }
        return candidate + " ..."
    }

    private static func buildPrompt(
        healthContext: String,
        history: [ChatMessage],
        userMessage: String
    ) -> String {
        let historyBlock: String
        if history.isEmpty {
            historyBlock = "(none)"
        } else {
            historyBlock = history.map { message in
                """
                <turn role="\(message.role.rawValue)">
                \(message.content)
                </turn>
                """
            }.joined(separator: "\n")
        }

        return """
        <<INSTRUCTIONS>>
        Answer only the current user message using the provided context and history.
        Do not output any block labels or XML-like tags.
        Do not echo HEALTH_CONTEXT_JSON, CHAT_HISTORY, or CURRENT_USER_MESSAGE.
        Stop after your answer.
        <</INSTRUCTIONS>>

        <<HEALTH_CONTEXT_JSON>>
        \(healthContext)
        <</HEALTH_CONTEXT_JSON>>

        <<CHAT_HISTORY>>
        \(historyBlock)
        <</CHAT_HISTORY>>

        <<CURRENT_USER_MESSAGE>>
        \(userMessage)
        <</CURRENT_USER_MESSAGE>>
        """
    }

    private static func trimLowestPriorityDocumentContent(in context: String) -> (context: String, trimmedCount: Int, changed: Bool) {
        guard let data = context.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var documents = json["medical_documents"] as? [[String: Any]],
              !documents.isEmpty else {
            return (context, 0, false)
        }

        for docIndex in stride(from: documents.count - 1, through: 0, by: -1) {
            var doc = documents[docIndex]

            if doc["content"] != nil {
                doc.removeValue(forKey: "content")
                documents[docIndex] = doc
                json["medical_documents"] = documents
                if let serialized = serializeJSON(json) {
                    return (serialized, 1, true)
                }
                return (context, 0, false)
            }

            if var sections = doc["sections"] as? [[String: Any]], !sections.isEmpty {
                for sectionIndex in stride(from: sections.count - 1, through: 0, by: -1) {
                    var section = sections[sectionIndex]
                    if section["content"] != nil {
                        section.removeValue(forKey: "content")
                        sections[sectionIndex] = section
                        doc["sections"] = sections
                        documents[docIndex] = doc
                        json["medical_documents"] = documents
                        if let serialized = serializeJSON(json) {
                            return (serialized, 1, true)
                        }
                        return (context, 0, false)
                    }
                }
            }
        }

        return (context, 0, false)
    }

    private static func serializeJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
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
