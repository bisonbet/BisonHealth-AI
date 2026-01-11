//
//  OnDeviceLLMTemplate.swift
//  HealthApp
//
//  Prompt formatting templates for on-device LLM inference
//  Adapted from BisonNotes AI
//

import Foundation

// MARK: - Template Structure

/// A structure that defines how to format prompts for different LLM architectures
public struct LLMTemplate {
    /// Represents prefix and suffix text to wrap around different message types
    public typealias Attachment = (prefix: String, suffix: String)

    /// Formatting for system messages
    public let system: Attachment

    /// Formatting for user messages
    public let user: Attachment

    /// Formatting for bot/assistant messages
    public let bot: Attachment

    /// Optional system prompt to set context
    public let systemPrompt: String?

    /// Sequences that indicate the end of the model's response
    public let stopSequences: [String]

    /// Legacy accessor for the first stop sequence
    public var stopSequence: String? { stopSequences.first }

    /// Text to prepend to the entire prompt
    public let prefix: String

    /// Whether to drop the last character of the bot prefix
    public let shouldDropLast: Bool

    // MARK: - Initialization

    public init(
        prefix: String = "",
        system: Attachment? = nil,
        user: Attachment? = nil,
        bot: Attachment? = nil,
        stopSequence: String? = nil,
        stopSequences: [String] = [],
        systemPrompt: String?,
        shouldDropLast: Bool = false
    ) {
        self.system = system ?? ("", "")
        self.user = user ?? ("", "")
        self.bot = bot ?? ("", "")

        var sequences = stopSequences
        if let single = stopSequence, !sequences.contains(single) {
            sequences.insert(single, at: 0)
        }
        self.stopSequences = sequences

        self.systemPrompt = systemPrompt
        self.prefix = prefix
        self.shouldDropLast = shouldDropLast
    }

    // MARK: - Preprocessing

    /// Formats input into model-ready prompt
    public func formatPrompt(_ input: String) -> String {
        var processed = prefix

        if let systemPrompt = systemPrompt {
            processed += "\(system.prefix)\(systemPrompt)\(system.suffix)"
        }

        processed += "\(user.prefix)\(input)\(user.suffix)"

        if shouldDropLast {
            processed += String(bot.prefix.dropLast())
        } else {
            processed += bot.prefix
        }

        return processed
    }

    /// Legacy preprocess closure for compatibility with LLM class
    public var preprocess: (_ input: String, _ history: [LLMChat], _ llmInstance: OnDeviceLLM) -> String {
        return { [self] input, history, llmInstance in
            if llmInstance.savedState != nil {
                var processed = prefix
                processed += "\(user.prefix)\(input)\(user.suffix)"
                processed += bot.prefix
                return processed
            } else {
                return formatPrompt(input)
            }
        }
    }
}

// MARK: - Predefined Templates

extension LLMTemplate {

    // MARK: - ChatML Format

    /// ChatML format - widely supported by many models
    public static func chatML(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("<|im_start|>system\n", "<|im_end|>\n"),
            user: ("<|im_start|>user\n", "<|im_end|>\n"),
            bot: ("<|im_start|>assistant\n", "<|im_end|>\n"),
            stopSequence: "<|im_end|>",
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Phi-3 Format

    /// Phi-3 format for Microsoft Phi models (including MediPhi)
    /// Stop sequences include template tokens and horizontal rule to prevent meta-commentary
    /// MediPhi uses <|end_of_assistant_response|> as its stop token
    public static func phi3(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("<|system|>\n", "<|end|>\n"),
            user: ("<|user|>\n", "<|end|>\n"),
            bot: ("<|assistant|>\n", "<|end|>\n"),
            stopSequences: ["<|end|>", "<|end_of_assistant_response|>", "<|user|>", "<|endoftext|>", "\n---"],
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Llama Format

    /// Llama/Llama2 format
    public static func llama(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            prefix: "[INST] ",
            system: ("<<SYS>>\n", "\n<</SYS>>\n\n"),
            user: ("", " [/INST]"),
            bot: (" ", "</s><s>[INST] "),
            stopSequence: "</s>",
            systemPrompt: systemPrompt,
            shouldDropLast: true
        )
    }

    // MARK: - Llama 3 Format

    /// Llama 3 format with updated tokens
    public static func llama3(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            prefix: "<|begin_of_text|>",
            system: ("<|start_header_id|>system<|end_header_id|>\n\n", "<|eot_id|>"),
            user: ("<|start_header_id|>user<|end_header_id|>\n\n", "<|eot_id|>"),
            bot: ("<|start_header_id|>assistant<|end_header_id|>\n\n", "<|eot_id|>"),
            stopSequence: "<|eot_id|>",
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Mistral Format

    /// Mistral format
    public static let mistral = LLMTemplate(
        user: ("[INST] ", " [/INST]"),
        bot: ("", "</s> "),
        stopSequence: "</s>",
        systemPrompt: nil
    )

    // MARK: - Alpaca Format

    /// Alpaca format for instruction-tuned models
    public static func alpaca(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("", "\n\n"),
            user: ("### Instruction:\n", "\n\n"),
            bot: ("### Response:\n", "\n\n"),
            stopSequence: "###",
            systemPrompt: systemPrompt
        )
    }

    // MARK: - OLMoE Format

    /// OLMoE format (AI2's model)
    public static func olmoe(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            prefix: "<|endoftext|>",
            system: ("<|system|>\n", "\n"),
            user: ("<|user|>\n", "\n"),
            bot: ("<|assistant|>\n", "\n"),
            stopSequence: "<|endoftext|>",
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Qwen Format

    /// Qwen format for Alibaba's models
    public static func qwen(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("<|im_start|>system\n", "<|im_end|>\n"),
            user: ("<|im_start|>user\n", "<|im_end|>\n"),
            bot: ("<|im_start|>assistant\n", "<|im_end|>\n"),
            stopSequences: ["<|im_end|>", "<|endoftext|>"],
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Qwen3 Format

    /// Qwen3 format for Alibaba's Qwen3 models
    public static func qwen3(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("<|im_start|>system\n", "<|im_end|>\n"),
            user: ("<|im_start|>user\n", "<|im_end|>\n"),
            bot: ("<|im_start|>assistant\n", "<|im_end|>\n"),
            stopSequences: ["<|im_end|>", "<|endoftext|>"],
            systemPrompt: systemPrompt
        )
    }

    // MARK: - Gemma 3 Format

    /// Gemma 3 format for Google's Gemma 3 models (including MedGemma)
    /// Stop sequences include template tokens and horizontal rule to prevent meta-commentary
    public static func gemma3(_ systemPrompt: String? = nil) -> LLMTemplate {
        let systemText = systemPrompt.map { "<start_of_turn>user\n\($0)<end_of_turn>\n" } ?? ""
        return LLMTemplate(
            prefix: systemText,
            system: ("", ""),
            user: ("<start_of_turn>user\n", "<end_of_turn>\n"),
            bot: ("<start_of_turn>model\n", "<end_of_turn>\n"),
            stopSequences: ["<end_of_turn>", "<eos>", "<start_of_turn>", "\n---"],
            systemPrompt: nil
        )
    }

    // MARK: - Generic/Simple Format

    /// Simple format for models that don't need special tokens
    public static func simple(_ systemPrompt: String? = nil) -> LLMTemplate {
        return LLMTemplate(
            system: ("System: ", "\n\n"),
            user: ("User: ", "\n\n"),
            bot: ("Assistant: ", "\n\n"),
            stopSequences: ["User:", "System:", "\n\n\n"],
            systemPrompt: systemPrompt
        )
    }
}

// MARK: - Health Assistant System Prompts

extension LLMTemplate {

    /// Compact system prompt for on-device health assistant (small models need concise instructions)
    public static let healthAssistantSystemPrompt = """
Health assistant. Some context may be JSON; respond in natural language (NOT JSON). If data missing, say so. Be concise. No disclaimers.
"""

    /// Compact system prompt for on-device document analysis
    public static let documentAnalysisSystemPrompt = """
Medical document analyst. Some context may be JSON; respond in natural language (NOT JSON). If data missing, say so. Be concise. No disclaimers.
"""
}
