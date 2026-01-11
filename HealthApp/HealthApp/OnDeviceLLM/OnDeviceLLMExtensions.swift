//
//  OnDeviceLLMExtensions.swift
//  HealthApp
//
//  Extensions for llama.cpp types and helper utilities
//  Adapted from BisonNotes AI
//

import Foundation
import llama

// MARK: - LLMModel (OpaquePointer) Extensions

extension LLMModel {
    /// Get the vocabulary from this model
    private var vocab: OpaquePointer { llama_model_get_vocab(self)! }

    /// Token representing the end of sequence
    public var endToken: Token { llama_vocab_eos(vocab) }

    /// Token representing end of turn (for chat models)
    /// Returns -1 if not available
    public var eotToken: Token { llama_vocab_eot(vocab) }

    /// Token representing a newline character
    public var newLineToken: Token { llama_vocab_nl(vocab) }

    /// Check if a token is any kind of end/stop token
    /// Uses llama_vocab_is_eog() which checks ALL end-of-generation tokens
    /// See: https://github.com/huggingface/transformers/issues/38182 (Gemma 3 EOS vs EOT)
    /// See: https://github.com/ggml-org/llama.cpp/issues/6903 (Phi-3 end token)
    public func isEndToken(_ token: Token) -> Bool {
        // Use llama_vocab_is_eog which checks against ALL EOG tokens
        // This handles models like Gemma3 (uses <end_of_turn>) and Phi-3 (uses <|end|>)
        // which have multiple end tokens that may differ from the default EOS
        return llama_vocab_is_eog(vocab, token)
    }

    /// Determines whether Beginning-of-Sequence (BOS) token should be added
    public func shouldAddBOS() -> Bool {
        let addBOS = llama_vocab_get_add_bos(vocab)
        guard !addBOS else {
            return llama_vocab_type(vocab) == LLAMA_VOCAB_TYPE_SPM
        }
        return addBOS
    }

    /// Decodes a single token to string without handling multibyte characters
    public func decodeOnly(_ token: Token) -> String {
        var nothing: [CUnsignedChar] = []
        return decode(token, with: &nothing)
    }

    /// Decodes a token to string while handling multibyte characters
    public func decode(_ token: Token, with multibyteCharacter: inout [CUnsignedChar]) -> String {
        var bufferLength = 16
        var buffer: [CChar] = .init(repeating: 0, count: bufferLength)
        let actualLength = Int(llama_token_to_piece(vocab, token, &buffer, Int32(bufferLength), 0, false))
        guard 0 != actualLength else { return "" }
        if actualLength < 0 {
            bufferLength = -actualLength
            buffer = .init(repeating: 0, count: bufferLength)
            llama_token_to_piece(vocab, token, &buffer, Int32(bufferLength), 0, false)
        } else {
            buffer.removeLast(bufferLength - actualLength)
        }
        if multibyteCharacter.isEmpty, let decoded = String(cString: buffer + [0], encoding: .utf8) {
            return decoded
        }
        multibyteCharacter.append(contentsOf: buffer.map { CUnsignedChar(bitPattern: $0) })
        guard let decoded = String(data: .init(multibyteCharacter), encoding: .utf8) else { return "" }
        multibyteCharacter.removeAll(keepingCapacity: true)
        return decoded
    }

    /// Encodes text into model tokens
    public func encode(_ text: borrowing String) -> [Token] {
        let addBOS = true
        let count = Int32(text.cString(using: .utf8)!.count)
        var tokenCount = count + 1
        let cTokens = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(tokenCount))
        defer { cTokens.deallocate() }
        tokenCount = llama_tokenize(vocab, text, count, cTokens, tokenCount, addBOS, false)
        let tokens = (0..<Int(tokenCount)).map { cTokens[$0] }

        if OnDeviceLLMFeatureFlags.verboseLogging {
            print("Encoded tokens: \(tokens)")
        }

        return tokens
    }
}

// MARK: - llama_batch Extensions

extension llama_batch {
    mutating func clear() {
        self.n_tokens = 0
    }

    mutating func add(_ token: Token, _ position: Int32, _ ids: [Int], _ logit: Bool) {
        let i = Int(self.n_tokens)
        self.token[i] = token
        self.pos[i] = position
        self.n_seq_id[i] = Int32(ids.count)
        if let seq_id = self.seq_id[i] {
            for (j, id) in ids.enumerated() {
                seq_id[j] = Int32(id)
            }
        }
        self.logits[i] = logit ? 1 : 0
        self.n_tokens += 1
    }
}

// MARK: - Text Sanitization Extensions

extension String {
    /// Sanitizes text from LLM output by fixing encoding issues and normalizing characters.
    func sanitizedForLLMDisplay() -> String {
        var result = self

        // Step 1: Remove Unicode replacement characters (U+FFFD)
        result = result.replacingOccurrences(of: "\u{FFFD}\u{FFFD}\u{FFFD}", with: "'")
        result = result.replacingOccurrences(of: "\u{FFFD}\u{FFFD}", with: "'")
        result = result.replacingOccurrences(of: "\u{FFFD}", with: "'")

        // Step 2: Normalize smart quotes to ASCII
        result = result.replacingOccurrences(of: "\u{2018}", with: "'") // Left single quote
        result = result.replacingOccurrences(of: "\u{2019}", with: "'") // Right single quote
        result = result.replacingOccurrences(of: "\u{201A}", with: "'")
        result = result.replacingOccurrences(of: "\u{201B}", with: "'")
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"") // Left double quote
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"") // Right double quote
        result = result.replacingOccurrences(of: "\u{201E}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201F}", with: "\"")

        // Step 3: Normalize dashes
        result = result.replacingOccurrences(of: "\u{2014}", with: "-") // Em dash
        result = result.replacingOccurrences(of: "\u{2013}", with: "-") // En dash
        result = result.replacingOccurrences(of: "\u{2012}", with: "-")
        result = result.replacingOccurrences(of: "\u{2010}", with: "-")
        result = result.replacingOccurrences(of: "\u{2011}", with: "-")

        // Step 4: Normalize ellipsis and punctuation
        result = result.replacingOccurrences(of: "\u{2026}", with: "...")
        result = result.replacingOccurrences(of: "\u{2022}", with: "-") // Bullet
        result = result.replacingOccurrences(of: "\u{2023}", with: ">")

        // Step 5: Normalize spaces
        result = result.replacingOccurrences(of: "\u{00A0}", with: " ") // Non-breaking space
        result = result.replacingOccurrences(of: "\u{2003}", with: " ") // Em space
        result = result.replacingOccurrences(of: "\u{2002}", with: " ") // En space
        result = result.replacingOccurrences(of: "\u{2009}", with: " ") // Thin space

        // Step 6: Remove control characters (except newlines and tabs)
        result = result.unicodeScalars.filter { scalar in
            scalar.value >= 32 || scalar.value == 9 || scalar.value == 10 || scalar.value == 13
        }.map { String($0) }.joined()

        return result
    }

    /// Strips markdown formatting from text
    func strippingMarkdown() -> String {
        var result = self

        // Remove bold markers
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)

        // Remove italic markers
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_(.+?)_", with: "$1", options: .regularExpression)

        // Remove inline code
        result = result.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)

        // Remove link syntax [text](url) -> text
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)

        // Remove headers
        result = result.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)

        return result
    }

    /// Removes wrapping quotes from a string
    func strippingWrappingQuotes() -> String {
        var result = self.trimmingCharacters(in: .whitespaces)

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 2 {
            result = String(result.dropFirst().dropLast())
        }

        if result.hasPrefix("'") && result.hasSuffix("'") && result.count > 2 {
            let inner = String(result.dropFirst().dropLast())
            if !inner.contains("'") {
                result = inner
            }
        }

        return result
    }
}

// MARK: - URL Extensions for Model Storage

extension URL {
    /// Directory for storing downloaded LLM models
    public static var onDeviceLLMModelsDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let url = paths[0].appendingPathComponent("OnDeviceLLMModels")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // Exclude from iCloud backup
        do {
            var mutableURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            print("Error excluding from backup: \(error)")
        }

        return url
    }

    /// Check if file exists at this URL
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Get file size in bytes
    public var fileSize: Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }
}
