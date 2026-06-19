import Foundation

// MARK: - Appointment Prep Processor
/// Input validation and output post-processing for the appointment-prep workflow.
///
/// Ported from the Python `medical-appt-prep` tool (`src/processor.py`). Since
/// the iOS flow generates each section with its own LLM call, only the
/// single-section helpers are needed (no combined-report parser).
enum AppointmentPrepProcessor {

    // MARK: - Constants
    static let minSymptomLength = 10
    static let maxFieldLength = 4000

    static let noOutputFallback = "_No output generated. Check that the model is running and try again._"
    static let sectionOutputFallback = "_The model returned text that could not be formatted for this section. Please try Generate again._"

    /// Item caps per section (timeline / questions / relevant info).
    static let timelineMaxItems = 8
    static let questionsMaxItems = 5
    static let relevantInfoMaxItems = 4

    // MARK: - Validation

    /// Returns human-readable error strings; an empty array means inputs are valid.
    static func validateInputs(symptoms: String, notes: String = "", medications: String = "") -> [String] {
        var errors: [String] = []

        let trimmedSymptoms = symptoms.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSymptoms.isEmpty {
            errors.append("Please describe your symptoms before generating a report.")
        } else if trimmedSymptoms.count < minSymptomLength {
            errors.append("Symptom description is too short (minimum \(minSymptomLength) characters). Please provide more detail.")
        }

        for (label, value) in [("Symptoms", symptoms), ("Notes", notes), ("Medications", medications)] {
            if value.count > maxFieldLength {
                errors.append("\(label) field exceeds the maximum length of \(maxFieldLength) characters. Please shorten your input.")
            }
        }

        return errors
    }

    // MARK: - Output Post-Processing

    /// Light cleanup: trim, collapse 3+ blank lines to 2, fall back when empty.
    static func parseOutput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return noOutputFallback }
        return regexReplace(trimmed, pattern: "\\n{3,}", template: "\n\n")
    }

    /// Cleans one section response without exposing hidden reasoning text.
    static func cleanSectionOutput(_ raw: String, maxItems: Int? = nil, requiredSuffix: String = "") -> String {
        var cleaned = parseOutput(raw)
        if cleaned.hasPrefix("_No output generated") { return cleaned }

        // Strip <think>...</think> blocks.
        cleaned = regexReplace(
            cleaned,
            pattern: "<think>.*?</think>\\s*",
            template: "",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // If the response opens with a reasoning prefix, keep only the final answer.
        if firstMatch(cleaned, pattern: "^\\s*(?:<think>|<unused\\d+>\\s*)?(?:thought\\b|thinking\\b|analysis\\b|reasoning\\b)", options: [.caseInsensitive]) != nil {
            if let final = firstMatchGroup(
                cleaned,
                pattern: "(?:^|\\n)\\s*(?:final(?:\\s+answer)?|answer|report)\\s*:?\\s*(.+)",
                group: 1,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                cleaned = final.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return sectionOutputFallback
            }
        }

        // Remove a leading section header (TIMELINE:/QUESTIONS:/RELEVANT_INFO:).
        cleaned = regexReplace(
            cleaned,
            pattern: "^\\s*(?:TIMELINE|QUESTIONS|RELEVANT(?:_|\\s+)INFO)\\s*:\\s*",
            template: "",
            options: [.caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove a leading bold heading line (e.g. "**Important Considerations:**").
        cleaned = regexReplace(
            cleaned,
            pattern: "^\\s*\\*\\*[^*\\n]{1,80}:?\\*\\*\\s*\\n+",
            template: "",
            options: [.anchorsMatchLines]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a short preamble before the first list item.
        if let range = firstMatch(cleaned, pattern: "^\\s*(?:[-*]\\s+|\\d+[.)]\\s+)", options: [.anchorsMatchLines]) {
            if range.lowerBound > cleaned.startIndex {
                let preamble = String(cleaned[cleaned.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if preamble.count <= 240 {
                    cleaned = String(cleaned[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Drop an incomplete trailing line (one that doesn't end with sentence punctuation).
        var lines = cleaned.components(separatedBy: "\n")
        if lines.count > 1 {
            let lastLine = lines[lines.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !lastLine.isEmpty && firstMatch(lastLine, pattern: "[.!?*_)]\\s*$") == nil {
                lines.removeLast()
                cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let maxItems = maxItems {
            cleaned = limitListItems(cleaned, maxItems: maxItems)
        }

        if !requiredSuffix.isEmpty && !cleaned.lowercased().contains(requiredSuffix.lowercased()) {
            cleaned = (rstrip(cleaned) + "\n" + requiredSuffix).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned.isEmpty ? sectionOutputFallback : cleaned
    }

    /// Keeps at most `maxItems` list items, dropping trailing overflow lines.
    static func limitListItems(_ text: String, maxItems: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        var itemCount = 0
        var kept: [String] = []
        for line in lines {
            let isItem = firstMatch(line, pattern: "^\\s*(?:[-*]\\s+|\\d+[.)]\\s+)") != nil
            if isItem {
                itemCount += 1
                if itemCount > maxItems { continue }
                kept.append(line)
            } else if itemCount > maxItems {
                continue
            } else {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regex Helpers

    private static func regexReplace(_ text: String, pattern: String, template: String, options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func firstMatch(_ text: String, pattern: String, options: NSRegularExpression.Options = []) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return Range(match.range, in: text)
    }

    private static func firstMatchGroup(_ text: String, pattern: String, group: Int, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let groupRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[groupRange])
    }

    private static func rstrip(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
}
