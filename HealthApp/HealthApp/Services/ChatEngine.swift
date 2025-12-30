import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - Chat Engine

/// Thin wrapper around MLX's low-level generate() API that provides ChatSession-like interface
/// with control over generation parameters (especially prefillStepSize for memory management)
@MainActor
class ChatEngine {

    // MARK: - Properties

    private let modelContext: ModelContext
    private var parameters: GenerateParameters  // var to allow maxTokens modification
    private let logger = Logger.shared
    private let maxHistoryMessages: Int

    // MARK: - Initialization

    /// Create a ChatEngine with specified generation parameters
    /// - Parameters:
    ///   - context: The loaded model context
    ///   - prefillStepSize: Tokens processed per step during prompt processing (default: 256)
    ///                      Lower values reduce peak scratch memory but may be slightly slower
    ///                      Recommended: 256 for balance, 128 for memory-constrained scenarios
    ///   - temperature: Sampling temperature (default: 0.7)
    ///   - topP: Top-p sampling parameter (default: 0.9)
    ///   - maxTokens: Maximum tokens to generate (default: 2048)
    ///   - maxHistoryMessages: Maximum number of messages to keep in context (default: 10)
    init(
        context: ModelContext,
        prefillStepSize: Int = 256,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        maxTokens: Int = 2048,
        maxHistoryMessages: Int = 10
    ) {
        self.modelContext = context
        self.maxHistoryMessages = maxHistoryMessages
        self.parameters = GenerateParameters(
            temperature: temperature,
            topP: topP,
            repetitionPenalty: 1.1,
            repetitionContextSize: 20,
            prefillStepSize: prefillStepSize
        )

        logger.info("🔧 ChatEngine initialized - prefillStepSize: \(prefillStepSize), maxTokens: \(maxTokens)")
    }

    // MARK: - Streaming Response

    /// Stream a response to the given prompt using low-level generate() API
    /// - Parameters:
    ///   - prompt: The formatted prompt string (should include chat template formatting)
    ///   - maxTokens: Optional override for max tokens (uses default from parameters if nil)
    /// - Returns: AsyncThrowingStream of token strings
    func streamResponse(
        to prompt: String,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    logger.debug("🔄 ChatEngine starting generation (prefillStepSize: \(parameters.prefillStepSize))")

                    var tokenCount = 0
                    // Clamp max tokens to be safe
                    let maxTokenLimit = min(maxTokens ?? 2048, 4096)

                    // Create UserInput with the prompt
                    let userInput = UserInput(prompt: prompt)

                    // Prepare generation parameters with maxTokens limit
                    var params = parameters
                    params.maxTokens = maxTokenLimit

                    // Prepare the input using the model's processor
                    let input = try await modelContext.processor.prepare(input: userInput)

                    // Use MLXLMCommon.generate() with our custom GenerateParameters
                    // This gives us control over prefillStepSize
                    let stream = try MLXLMCommon.generate(
                        input: input,
                        cache: nil,  // Reset KV cache each request (lowest memory risk)
                        parameters: params,
                        context: modelContext
                    )

                    // Stream generated chunks
                    for try await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                            tokenCount += 1

                            // Check if we should stop
                            if tokenCount >= maxTokenLimit {
                                logger.info("⚠️ Reached max tokens limit (\(maxTokenLimit))")
                                break
                            }

                        case .info(let info):
                            logger.debug("✅ ChatEngine generation complete - \(info.generationTokenCount) tokens at \(info.tokensPerSecond) tokens/s")

                        case .toolCall:
                            // We don't use tool calls in this implementation
                            break
                        }
                    }

                    continuation.finish()

                } catch {
                    logger.error("❌ ChatEngine generation failed", error: error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Message-Based Interface

    /// Stream a response based on conversation messages
    /// - Parameters:
    ///   - messages: Array of chat messages (conversation history)
    ///   - currentMessage: The new user message to append (optional, if not already in messages)
    ///   - systemPrompt: Optional system prompt
    ///   - context: Optional context information (e.g., patient health data)
    /// - Returns: AsyncThrowingStream of token strings
    func streamResponse(
        messages: [ChatMessage],
        currentMessage: String? = nil,
        systemPrompt: String? = nil,
        context: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        // Trim history to prevent unbounded context growth
        let trimmedMessages = trimHistory(messages)

        // Build prompt using chat template
        let prompt = buildChatTemplatePrompt(
            messages: trimmedMessages,
            currentMessage: currentMessage,
            systemPrompt: systemPrompt,
            context: context
        )

        logger.debug("📋 ChatEngine prompt length: \(prompt.count) chars, \(trimmedMessages.count) history messages")

        return streamResponse(to: prompt)
    }

    // MARK: - History Management

    /// Trim conversation history to prevent unbounded growth
    /// Keeps the most recent messages up to maxHistoryMessages
    private func trimHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.count > maxHistoryMessages else {
            return messages
        }

        // Keep the most recent messages
        let trimmedMessages = Array(messages.suffix(maxHistoryMessages))
        logger.info("✂️ Trimmed history from \(messages.count) to \(trimmedMessages.count) messages")

        return trimmedMessages
    }

    // MARK: - Chat Template Formatting

    /// Build prompt using Phi-3.5 chat template format
    /// Format: <|system|>...<|end|><|user|>...<|end|><|assistant|>
    /// WARNING: This template is specific to Phi-3. Other models (Llama, Gemma) may require different templates.
    /// Future improvement: Use model.tokenizer.applyChatTemplate() or switch based on model type.
    private func buildChatTemplatePrompt(
        messages: [ChatMessage],
        currentMessage: String? = nil,
        systemPrompt: String? = nil,
        context: String? = nil
    ) -> String {
        // Prepend BOS token for Phi-3 models
        var prompt = "<s>"

        // Build system prompt (Role Only)
        // Kept pure to ensure model adheres to persona instructions
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            prompt += "<|system|>\n\(systemPrompt)<|end|>\n"
        }

        // Prepare context string to inject into the FIRST user message (or current if no history)
        var contextToInject = ""
        if let context = context, !context.isEmpty {
            contextToInject = "PATIENT HEALTH INFORMATION:\n\(context)\n\n"
        }

        // Add conversation messages
        var isFirstUserMessage = true
        for message in messages {
            switch message.role {
            case .user:
                // Inject context into the very first user message found in history
                var content = message.content
                if isFirstUserMessage && !contextToInject.isEmpty {
                    content = contextToInject + content
                    // Clear contextToInject so we don't inject it again
                    contextToInject = ""
                }
                isFirstUserMessage = false
                
                prompt += "<|user|>\n\(content)<|end|>\n"
            case .assistant:
                prompt += "<|assistant|>\n\(message.content)<|end|>\n"
            case .system:
                // System messages already handled above
                break
            }
        }

        // Add current user message if provided
        if let currentMessage = currentMessage, !currentMessage.isEmpty {
             // If we haven't injected context yet (e.g. no history), inject it here
             var content = currentMessage
             if !contextToInject.isEmpty {
                 content = contextToInject + content
             }
             prompt += "<|user|>\n\(content)<|end|>\n"
        }

        // Add assistant prompt for response
        prompt += "<|assistant|>\n"

        return prompt
    }

    // MARK: - Parameter Updates

    /// Update generation parameters
    /// Note: Creates new GenerateParameters instance as it's a struct
    func updateParameters(
        temperature: Float? = nil,
        topP: Float? = nil,
        prefillStepSize: Int? = nil
    ) {
        // GenerateParameters is a struct, so we need to recreate the engine
        // or store parameters as var and recreate on each generation
        // For now, log a warning - this would require reinitializing
        logger.warning("⚠️ Parameter updates require creating a new ChatEngine instance")
    }
}

