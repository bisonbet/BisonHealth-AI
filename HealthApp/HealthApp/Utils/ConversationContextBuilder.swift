//
//  ConversationContextBuilder.swift
//  HealthApp
//
//  Unified conversation context builder for all AI providers
//  Handles token budgeting and intelligent trimming of conversation history
//

import Foundation

// MARK: - Context Limits per Provider

/// Context window limits for different AI providers (in tokens)
@MainActor
enum AIProviderContextLimits {
    /// On-device LLM - uses configured context size (default 16k, max 64k)
    static var onDeviceLLM: Int {
        OnDeviceLLMModelInfo.configuredContextSize
    }

    /// Ollama - configurable, uses SettingsManager value (default 16k)
    static var ollama: Int {
        SettingsManager.shared.modelPreferences.contextSizeLimit
    }

    /// OpenAI Compatible servers - uses configured context size (default 32k)
    static var openAICompatible: Int {
        SettingsManager.shared.openAICompatibleContextSize
    }

    /// AWS Bedrock Claude - 200k context
    static let bedrock = 200_000

    /// Get limit for a specific provider
    static func limit(for provider: AIProvider) -> Int {
        switch provider {
        case .ollama:
            return ollama
        case .openAICompatible:
            return openAICompatible
        case .bedrock:
            return bedrock
        case .onDeviceLLM:
            return onDeviceLLM
        }
    }
}

// MARK: - Conversation Context Builder

/// Builds conversation context with intelligent token management
/// Prioritizes: System Prompt > Health Context > Recent Messages > Older Messages
@MainActor
struct ConversationContextBuilder {

    // MARK: - Token Estimation Constants

    private enum TokenEstimates {
        /// Approximate characters per token (conservative estimate)
        static let charsPerToken = 4

        /// Overhead for message formatting (role labels, separators)
        static let messageOverhead = 10

        /// Reserve tokens for the response
        static let responseReserve = 512

        /// Minimum tokens to keep for at least one exchange
        static let minimumHistoryTokens = 200
    }

    // MARK: - Build Context Result

    struct ContextResult {
        /// Messages to send (formatted for the provider)
        let conversationHistory: [ChatMessage]
        /// Number of messages trimmed due to token limits
        let trimmedMessageCount: Int
        /// Estimated total tokens used
        let estimatedTokens: Int
        /// Whether health context was included
        let includesHealthContext: Bool
        /// Debug info for logging
        let debugInfo: String
    }

    // MARK: - Main Builder Method

    /// Build conversation context within token limits
    /// - Parameters:
    ///   - currentMessage: The user's current message
    ///   - healthContext: JSON health data context (ALWAYS included)
    ///   - conversationHistory: Previous messages in the conversation
    ///   - systemPrompt: System prompt (Doctor persona)
    ///   - provider: The AI provider being used
    /// - Returns: ContextResult with trimmed history and token info
    static func buildContext(
        currentMessage: String,
        healthContext: String,
        conversationHistory: [ChatMessage],
        systemPrompt: String?,
        provider: AIProvider
    ) -> ContextResult {
        let contextLimit = AIProviderContextLimits.limit(for: provider)

        // Calculate fixed token costs (these cannot be trimmed)
        let systemPromptTokens = estimateTokens(systemPrompt ?? "")
        let healthContextTokens = estimateTokens(healthContext)
        let currentMessageTokens = estimateTokens(currentMessage) + TokenEstimates.messageOverhead

        let fixedTokens = systemPromptTokens + healthContextTokens + currentMessageTokens + TokenEstimates.responseReserve

        // Calculate available tokens for conversation history
        let availableForHistory = max(0, contextLimit - fixedTokens)

        // Filter out system messages (handled separately) and get user/assistant only
        let relevantHistory = conversationHistory.filter { $0.role != .system }

        // Build trimmed history that fits within budget
        let (trimmedHistory, historyTokens, trimmedCount) = trimConversationHistory(
            messages: relevantHistory,
            tokenBudget: availableForHistory
        )

        let totalTokens = fixedTokens + historyTokens

        let debugInfo = """
        [ContextBuilder] Provider: \(provider), Limit: \(contextLimit) tokens
        [ContextBuilder] Fixed costs: system=\(systemPromptTokens), health=\(healthContextTokens), current=\(currentMessageTokens), reserve=\(TokenEstimates.responseReserve)
        [ContextBuilder] History: \(trimmedHistory.count)/\(relevantHistory.count) messages (\(historyTokens) tokens), trimmed \(trimmedCount)
        [ContextBuilder] Total: ~\(totalTokens) tokens
        """

        return ContextResult(
            conversationHistory: trimmedHistory,
            trimmedMessageCount: trimmedCount,
            estimatedTokens: totalTokens,
            includesHealthContext: !healthContext.isEmpty,
            debugInfo: debugInfo
        )
    }

    // MARK: - History Trimming

    /// Trim conversation history to fit within token budget
    /// Keeps most recent messages, trims oldest first
    private static func trimConversationHistory(
        messages: [ChatMessage],
        tokenBudget: Int
    ) -> (messages: [ChatMessage], tokens: Int, trimmedCount: Int) {
        guard !messages.isEmpty else {
            return ([], 0, 0)
        }

        // If budget is too small, return empty
        guard tokenBudget >= TokenEstimates.minimumHistoryTokens else {
            return ([], 0, messages.count)
        }

        // Start from the most recent and work backwards
        var includedMessages: [ChatMessage] = []
        var totalTokens = 0
        var trimmedCount = 0

        // Process messages from newest to oldest
        for message in messages.reversed() {
            let messageTokens = estimateMessageTokens(message)

            if totalTokens + messageTokens <= tokenBudget {
                includedMessages.insert(message, at: 0) // Maintain chronological order
                totalTokens += messageTokens
            } else {
                trimmedCount += 1
            }
        }

        return (includedMessages, totalTokens, trimmedCount)
    }

    // MARK: - Token Estimation

    /// Estimate tokens for a string
    static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return max(1, text.count / TokenEstimates.charsPerToken)
    }

    /// Estimate tokens for a chat message (includes overhead)
    static func estimateMessageTokens(_ message: ChatMessage) -> Int {
        return estimateTokens(message.content) + TokenEstimates.messageOverhead
    }

    // MARK: - Format Helpers

    /// Format conversation history as plain text for providers that need it
    static func formatHistoryAsText(_ messages: [ChatMessage], truncateAt: Int = 500) -> String {
        guard !messages.isEmpty else { return "" }

        var lines: [String] = []
        for msg in messages {
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.count > truncateAt
                ? String(msg.content.prefix(truncateAt)) + "..."
                : msg.content
            lines.append("\(roleLabel): \(content)")
        }

        return lines.joined(separator: "\n")
    }

    /// Format for providers that use message arrays (Ollama, OpenAI)
    static func formatHistoryAsMessages(_ messages: [ChatMessage]) -> [(role: String, content: String)] {
        return messages.map { msg in
            (role: msg.role.rawValue, content: msg.content)
        }
    }
}

// MARK: - Convenience Extensions

extension ConversationContextBuilder {

    /// Quick check if conversation history should be included
    /// (provider supports it and there's room in context)
    static func shouldIncludeHistory(
        healthContextTokens: Int,
        systemPromptTokens: Int,
        provider: AIProvider
    ) -> Bool {
        let fixedCosts = healthContextTokens + systemPromptTokens + TokenEstimates.responseReserve + 100 // 100 for current message estimate
        let available = AIProviderContextLimits.limit(for: provider) - fixedCosts
        return available >= TokenEstimates.minimumHistoryTokens
    }

    /// Get a summary of what was included/trimmed for logging
    static func logContextSummary(_ result: ContextResult) {
        print(result.debugInfo)
        if result.trimmedMessageCount > 0 {
            print("[ContextBuilder] WARNING: Trimmed \(result.trimmedMessageCount) older messages to fit context limit")
        }
    }
}
