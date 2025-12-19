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
