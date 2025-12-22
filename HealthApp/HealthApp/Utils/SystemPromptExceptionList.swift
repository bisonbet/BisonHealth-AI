import Foundation

/// Manages a list of model names/patterns that don't properly support system prompts
/// and require instructions to be injected into the first user message instead.
///
/// Models in this list will have their system prompts formatted as:
/// ```
/// INSTRUCTIONS:
/// <doctor's system prompt>
///
/// CONTEXT:
/// <health data context>
///
/// QUESTION:
/// <user's actual message>
/// ```
class SystemPromptExceptionList {

    // MARK: - Singleton
    static let shared = SystemPromptExceptionList()

    // MARK: - Properties

    /// List of lowercase model name patterns that require instruction injection
    /// Supports partial matching (e.g., "medgemma" matches "medgemma-2b", "google/medgemma", etc.)
    private var exceptionPatterns: Set<String>

    // MARK: - Initialization

    private init() {
        // Default exception patterns
        self.exceptionPatterns = [
            "medgemma",  // Matches any model with "medgemma" in the name
            // Add more patterns here as needed
        ]

        // Load any user-added patterns from UserDefaults
        if let savedPatterns = UserDefaults.standard.array(forKey: "SystemPromptExceptionPatterns") as? [String] {
            self.exceptionPatterns.formUnion(savedPatterns)
        }
    }

    // MARK: - Public Methods

    /// Check if a model requires instruction injection instead of system prompts
    /// - Parameter modelName: The model name to check (case-insensitive)
    /// - Returns: True if the model is in the exception list
    func requiresInstructionInjection(for modelName: String) -> Bool {
        let lowercasedModel = modelName.lowercased()

        // Check if any pattern matches the model name
        return exceptionPatterns.contains { pattern in
            lowercasedModel.contains(pattern.lowercased())
        }
    }

    /// Format the first user message with instructions for exception models
    /// - Parameters:
    ///   - userMessage: The actual user's question/message
    ///   - systemPrompt: The doctor's system prompt (instructions)
    ///   - context: The health data context
    /// - Returns: Formatted message with INSTRUCTIONS, CONTEXT, and QUESTION sections
    func formatFirstUserMessage(userMessage: String, systemPrompt: String?, context: String) -> String {
        var formattedMessage = ""

        // Add INSTRUCTIONS section if system prompt provided
        if let instructions = systemPrompt, !instructions.isEmpty {
            formattedMessage += "INSTRUCTIONS:\n\(instructions)\n\n"
        }

        // Add CONTEXT section if context provided
        if !context.isEmpty {
            formattedMessage += "CONTEXT:\n\(context)\n\n"
        }

        // Add QUESTION section with user's actual message
        formattedMessage += "QUESTION:\n\(userMessage)"

        return formattedMessage
    }

    /// Format message with conversation history for exception models
    /// - Parameters:
    ///   - userMessage: The current user's question/message
    ///   - systemPrompt: The doctor's system prompt (instructions)
    ///   - context: The health data context
    ///   - conversationHistory: Previous messages in the conversation (will be trimmed if needed)
    ///   - maxTokens: Maximum tokens allowed for the entire prompt
    /// - Returns: Formatted message with INSTRUCTIONS, CONTEXT, CONVERSATION HISTORY, and QUESTION sections
    func formatMessageWithHistory(
        userMessage: String,
        systemPrompt: String?,
        context: String,
        conversationHistory: [ChatMessage],
        maxTokens: Int
    ) -> String {
        var formattedMessage = ""

        // Add INSTRUCTIONS section if system prompt provided
        if let instructions = systemPrompt, !instructions.isEmpty {
            formattedMessage += "INSTRUCTIONS:\n\(instructions)\n\n"
        }

        // Add CONTEXT section if context provided (health data)
        if !context.isEmpty {
            formattedMessage += "CONTEXT:\n\(context)\n\n"
        }

        // Calculate tokens used by fixed parts
        let fixedTokens = estimateTokens(formattedMessage) + estimateTokens(userMessage) + 50 // 50 tokens buffer for formatting

        // Calculate available tokens for conversation history
        // Reserve some tokens for the model's response (at least 500 tokens)
        let reservedForResponse = 500
        let availableForHistory = maxTokens - fixedTokens - reservedForResponse

        // Build conversation history, trimming oldest messages if needed
        let historyText = buildTrimmedHistory(
            conversationHistory: conversationHistory,
            maxTokens: availableForHistory
        )

        if !historyText.isEmpty {
            formattedMessage += "CONVERSATION HISTORY:\n\(historyText)\n\n"
        }

        // Add QUESTION section with user's actual message
        formattedMessage += "QUESTION:\n\(userMessage)"

        return formattedMessage
    }

    /// Estimate token count for a string (rough approximation: ~4 chars per token)
    func estimateTokens(_ text: String) -> Int {
        return max(1, text.count / 4)
    }

    /// Build conversation history string, trimming oldest messages to fit within token limit
    /// - Parameters:
    ///   - conversationHistory: All messages in the conversation
    ///   - maxTokens: Maximum tokens allowed for history
    /// - Returns: Formatted history string with recent messages that fit within limit
    private func buildTrimmedHistory(conversationHistory: [ChatMessage], maxTokens: Int) -> String {
        guard !conversationHistory.isEmpty else { return "" }

        // Filter to only user and assistant messages (not system messages)
        let relevantMessages = conversationHistory.filter { $0.role == .user || $0.role == .assistant }

        guard !relevantMessages.isEmpty else { return "" }

        // Build history from newest to oldest, stopping when we exceed token limit
        var historyParts: [String] = []
        var totalTokens = 0

        // Iterate from newest to oldest (reversed)
        for message in relevantMessages.reversed() {
            let roleLabel = message.role == .user ? "User" : "Assistant"
            let messageLine = "\(roleLabel): \(message.content)"
            let messageTokens = estimateTokens(messageLine)

            // Check if adding this message would exceed limit
            if totalTokens + messageTokens > maxTokens {
                // Stop adding more messages
                break
            }

            historyParts.insert(messageLine, at: 0) // Insert at beginning to maintain order
            totalTokens += messageTokens
        }

        // If we had to trim, add indicator
        let includedCount = historyParts.count
        let totalCount = relevantMessages.count
        var result = historyParts.joined(separator: "\n")

        if includedCount < totalCount {
            let trimmedCount = totalCount - includedCount
            result = "[... \(trimmedCount) earlier message(s) omitted ...]\n" + result
        }

        return result
    }

    /// Add a new model pattern to the exception list
    /// - Parameter pattern: Model name pattern to add (case-insensitive, supports partial matching)
    func addPattern(_ pattern: String) {
        guard !pattern.isEmpty else { return }
        exceptionPatterns.insert(pattern.lowercased())
        savePatterns()
    }

    /// Remove a model pattern from the exception list
    /// - Parameter pattern: Model name pattern to remove
    func removePattern(_ pattern: String) {
        exceptionPatterns.remove(pattern.lowercased())
        savePatterns()
    }

    /// Get all current exception patterns
    /// - Returns: Array of exception patterns
    func getAllPatterns() -> [String] {
        return Array(exceptionPatterns).sorted()
    }

    /// Check if a pattern exists in the exception list
    /// - Parameter pattern: Pattern to check
    /// - Returns: True if pattern exists
    func hasPattern(_ pattern: String) -> Bool {
        return exceptionPatterns.contains(pattern.lowercased())
    }

    /// Reset to default patterns only
    func resetToDefaults() {
        exceptionPatterns = ["medgemma"]
        savePatterns()
    }

    // MARK: - Private Methods

    private func savePatterns() {
        let patternsArray = Array(exceptionPatterns)
        UserDefaults.standard.set(patternsArray, forKey: "SystemPromptExceptionPatterns")
    }
}
