import Foundation

/// Utility for cleaning and sanitizing AI responses
struct AIResponseCleaner {

    // MARK: - Runaway Repetition

    private struct NormalizedWord {
        let value: String
        let startIndex: String.Index
    }

    /// Truncates a response once a substantial word sequence has been emitted
    /// three times in a row. This is a final safety net for local models whose
    /// tokenizer metadata fails to stop on an end-of-turn token.
    ///
    /// The threshold is deliberately high enough to leave ordinary rhetorical
    /// repetition and short lists alone. The first copy is preserved.
    static func truncateRunawayRepetition(
        _ response: String,
        minimumPatternWords: Int = 10,
        maximumPatternWords: Int = 80
    ) -> (content: String, wasTruncated: Bool) {
        let words = normalizedWords(in: response)
        let maximumLength = min(maximumPatternWords, words.count / 3)

        guard minimumPatternWords > 0, maximumLength >= minimumPatternWords else {
            return (response, false)
        }

        for patternLength in stride(from: maximumLength, through: minimumPatternWords, by: -1) {
            let firstStart = words.count - (patternLength * 3)
            let secondStart = firstStart + patternLength
            let thirdStart = secondStart + patternLength

            guard wordSequenceMatches(
                words,
                lhsStart: firstStart,
                rhsStart: secondStart,
                length: patternLength
            ), wordSequenceMatches(
                words,
                lhsStart: secondStart,
                rhsStart: thirdStart,
                length: patternLength
            ) else {
                continue
            }

            var runStart = firstStart
            while runStart >= patternLength, wordSequenceMatches(
                words,
                lhsStart: runStart - patternLength,
                rhsStart: runStart,
                length: patternLength
            ) {
                runStart -= patternLength
            }

            let cutoff = words[runStart + patternLength].startIndex
            let prefix = String(response[..<cutoff])
            return (trimTrailingMarkdownSeparators(from: prefix), true)
        }

        return (response, false)
    }

    // MARK: - Special Tokens

    /// Common special tokens that should be removed from AI responses
    private static let specialTokens: [String] = [
        "<|eot_id|>",
        "<|end_of_text|>",
        "<|endoftext|>",  // Variation
        "<|start_header_id|>",
        "<|end_header_id|>",
        "<|begin_of_text|>",
        "<|im_start|>",
        "<|im_end|>",
        "<|end|>",        // Phi-3.5 chat template
        "<!end>",         // MediPhi / Custom
        "<|system|>",     // Phi-3.5 chat template
        "<|user|>",       // Phi-3.5 chat template
        "<|assistant|>",  // Phi-3.5 chat template
        "<s>",
        "</s>",
        "[INST]",
        "[/INST]",
        "<<SYS>>",
        "<</SYS>>",
        "<|stop|>"
    ]

    // MARK: - Public Cleaning Methods

    /// Clean an AI response by removing special tokens and fixing encoding
    /// - Parameter response: The raw AI response
    /// - Returns: Cleaned response text
    static func clean(_ response: String) -> String {
        var cleaned = response

        // Fix encoding issues first (before other cleaning)
        cleaned = fixEncodingIssues(in: cleaned)

        // Remove special tokens
        cleaned = removeSpecialTokens(from: cleaned)

        // Clean up excessive whitespace
        cleaned = normalizeWhitespace(in: cleaned)

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    // MARK: - Private Cleaning Methods

    /// Remove all special tokens from the text
    static func removeSpecialTokens(from text: String) -> String {
        var result = text

        for token in specialTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        return result
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

    /// Fix common encoding issues in text
    private static func fixEncodingIssues(in text: String) -> String {
        var result = text

        // Normalize Unicode to composed form (NFC)
        // This ensures characters like é are stored as a single character, not e + combining accent
        result = result.precomposedStringWithCanonicalMapping

        // Fix common UTF-8 mojibake patterns
        // These occur when UTF-8 bytes are interpreted as another encoding
        let mojibakeReplacements: [String: String] = [
            // Em-dash (—) UTF-8 bytes misinterpreted as Windows-1252
            "\u{00E2}\u{0080}\u{0094}": "—",  // â€"
            // En-dash (–) UTF-8 bytes misinterpreted as Windows-1252
            "\u{00E2}\u{0080}\u{0093}": "–",  // â€"
            // Ellipsis (…) UTF-8 bytes misinterpreted
            "\u{00E2}\u{0080}\u{00A6}": "…",  // â€¦
            // Right single quote (') UTF-8 bytes misinterpreted
            "\u{00E2}\u{0080}\u{0099}": "'",  // â€™
            // Left single quote (') UTF-8 bytes misinterpreted
            "\u{00E2}\u{0080}\u{0098}": "'",  // â€˜
            // Left double quote (") UTF-8 bytes misinterpreted
            "\u{00E2}\u{0080}\u{009C}": "\"", // â€œ
            // Right double quote (") UTF-8 bytes misinterpreted
            "\u{00E2}\u{0080}\u{009D}": "\"", // â€
            // Common Latin characters with UTF-8 mojibake
            "\u{00C3}\u{00A9}": "é",  // Ã©
            "\u{00C3}\u{00A8}": "è",  // Ã¨
            "\u{00C3}\u{00A0}": "à",  // Ã
            "\u{00C3}\u{00B1}": "ñ",  // Ã±
            "\u{00C3}\u{00A7}": "ç"   // Ã§
        ]

        for (bad, good) in mojibakeReplacements {
            result = result.replacingOccurrences(of: bad, with: good)
        }

        // Decode common HTML entities that might appear in AI responses
        let htmlEntities: [String: String] = [
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#8217;": "'",
            "&#8216;": "'",
            "&#8220;": "\"",
            "&#8221;": "\"",
            "&#8212;": "—",
            "&#8211;": "–",
            "&#8230;": "…"
        ]

        for (entity, char) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        return result
    }

    // MARK: - Specialized Cleaning

    /// Clean response specifically for conversational AI
    /// Applies encoding fixes and removes special tokens for consistent output
    ///
    /// - Parameter detectRunawayRepetition: Pass `false` when the caller has already run
    ///   `truncateRunawayRepetition` on this text. The scan walks every character to build a
    ///   word index, so repeating it per streamed chunk makes rendering quadratic in the
    ///   response length.
    static func cleanConversational(
        _ response: String,
        detectRunawayRepetition: Bool = true
    ) -> String {
        var cleaned = detectRunawayRepetition
            ? truncateRunawayRepetition(response).content
            : response

        // Fix encoding issues first (before other cleaning)
        cleaned = fixEncodingIssues(in: cleaned)

        // Remove special tokens
        cleaned = removeSpecialTokens(from: cleaned)

        // Clean up excessive whitespace
        cleaned = normalizeWhitespace(in: cleaned)

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private static func normalizedWords(in text: String) -> [NormalizedWord] {
        var words: [NormalizedWord] = []
        var wordStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber {
                if wordStart == nil {
                    wordStart = index
                }
            } else if let start = wordStart {
                let value = String(text[start..<index]).lowercased()
                words.append(NormalizedWord(value: value, startIndex: start))
                wordStart = nil
            }
            index = text.index(after: index)
        }

        if let start = wordStart {
            words.append(NormalizedWord(
                value: String(text[start..<text.endIndex]).lowercased(),
                startIndex: start
            ))
        }

        return words
    }

    private static func wordSequenceMatches(
        _ words: [NormalizedWord],
        lhsStart: Int,
        rhsStart: Int,
        length: Int
    ) -> Bool {
        for offset in 0..<length where words[lhsStart + offset].value != words[rhsStart + offset].value {
            return false
        }
        return true
    }

    private static func trimTrailingMarkdownSeparators(from text: String) -> String {
        let withoutSeparators = text.replacingOccurrences(
            of: #"(?:\s*\n\s*(?:-{3,}|\*{3,}|_{3,})\s*)+$"#,
            with: "",
            options: .regularExpression
        )
        return withoutSeparators.trimmingCharacters(in: .whitespacesAndNewlines)
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
