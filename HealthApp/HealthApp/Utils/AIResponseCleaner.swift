import Foundation

/// Utility for cleaning and sanitizing AI responses
struct AIResponseCleaner {

    // MARK: - Special Tokens

    /// Common special tokens that should be removed from AI responses
    private static let specialTokens: [String] = [
        "<|eot_id|>",
        "<|end_of_text|>",
        "<|start_header_id|>",
        "<|end_header_id|>",
        "<|begin_of_text|>",
        "<|im_start|>",
        "<|im_end|>",
        "<|end|>",        // Phi-3.5 chat template
        "<|system|>",     // Phi-3.5 chat template
        "<|user|>",       // Phi-3.5 chat template
        "<|assistant|>",  // Phi-3.5 chat template
        "<s>",
        "</s>",
        "[INST]",
        "[/INST]",
        "<<SYS>>",
        "<</SYS>>"
    ]

    /// Unwanted phase labels or prompt artifacts that sometimes appear in responses
    private static let unwantedPrefixes: [String] = [
        "Empathy Phase:",
        "Solution Phase:",
        "Information Gathering Phase:",
        "Response:",
        "Assistant:",
        "System:",
        "Context:"
    ]

    // MARK: - Public Cleaning Methods

    /// Clean an AI response by removing special tokens and unwanted text
    /// - Parameter response: The raw AI response
    /// - Returns: Cleaned response text
    static func clean(_ response: String) -> String {
        var cleaned = response

        // Remove special tokens
        cleaned = removeSpecialTokens(from: cleaned)

        // Remove unwanted phase labels
        cleaned = removeUnwantedPrefixes(from: cleaned)

        // Clean up excessive whitespace
        cleaned = normalizeWhitespace(in: cleaned)

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    // MARK: - Private Cleaning Methods

    /// Remove all special tokens from the text
    private static func removeSpecialTokens(from text: String) -> String {
        var result = text

        for token in specialTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        return result
    }

    /// Remove unwanted prefixes that sometimes appear at the start of lines
    private static func removeUnwantedPrefixes(from text: String) -> String {
        var lines = text.components(separatedBy: .newlines)

        // Process each line
        lines = lines.map { line in
            var processedLine = line

            // Check if line starts with any unwanted prefix
            for prefix in unwantedPrefixes {
                if processedLine.hasPrefix(prefix) {
                    // If the prefix is followed by content on the same line, keep the content
                    let withoutPrefix = String(processedLine.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespaces)

                    // Only keep the content if it's substantial (not just punctuation or whitespace)
                    if !withoutPrefix.isEmpty && withoutPrefix.count > 3 {
                        processedLine = withoutPrefix
                    } else {
                        // Otherwise, remove the entire line
                        processedLine = ""
                    }
                    break
                }
            }

            return processedLine
        }

        // Remove empty lines that resulted from prefix removal
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return lines.joined(separator: "\n")
    }

    /// Normalize whitespace by removing excessive blank lines and spaces
    private static func normalizeWhitespace(in text: String) -> String {
        var result = text

        // Replace multiple newlines with maximum of 2
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Replace multiple spaces with single space (but preserve newlines)
        let lines = result.components(separatedBy: .newlines)
        let normalizedLines = lines.map { line in
            line.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        }

        return normalizedLines.joined(separator: "\n")
    }

    // MARK: - Specialized Cleaning

    /// Clean response specifically for conversational AI (more aggressive)
    static func cleanConversational(_ response: String) -> String {
        var cleaned = clean(response)

        // Remove common conversational artifacts
        let conversationalPrefixes = [
            "Here's my response:",
            "My response:",
            "Response:",
            "Answer:"
        ]

        for prefix in conversationalPrefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return cleaned
    }

    /// Clean response for title generation (single line, no special formatting)
    static func cleanTitle(_ response: String) -> String {
        var cleaned = clean(response)

        // Remove quotes
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        if cleaned.hasPrefix("'") && cleaned.hasSuffix("'") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Take only first line if multiple lines
        if let firstLine = cleaned.components(separatedBy: .newlines).first {
            cleaned = firstLine
        }

        // Trim to reasonable length
        if cleaned.count > 50 {
            let words = cleaned.components(separatedBy: .whitespaces)
            cleaned = words.prefix(5).joined(separator: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
