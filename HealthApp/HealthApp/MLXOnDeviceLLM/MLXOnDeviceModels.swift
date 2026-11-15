//
//  MLXOnDeviceModels.swift
//  HealthApp
//
//  Model catalog for MLX on-device LLM models
//

import Foundation

// MARK: - Model Type

/// Whether a model is a text-only LLM or a Vision-Language Model
public enum MLXModelType: String, Codable, CaseIterable, Sendable {
    case llm
    case vlm

    var displayName: String {
        switch self {
        case .llm: return "Text"
        case .vlm: return "Vision"
        }
    }

    var badge: String {
        switch self {
        case .llm: return "LLM"
        case .vlm: return "VLM"
        }
    }
}

// MARK: - Default Model Settings

/// Default sampling parameters for a model
public struct MLXModelDefaultSettings: Equatable, Codable, Sendable {
    public let temperature: Float
    public let topP: Float
    public let maxTokens: Int
    public let repetitionPenalty: Float?

    public init(
        temperature: Float = 0.6,
        topP: Float = 0.9,
        maxTokens: Int = 800,
        repetitionPenalty: Float? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
    }
}

// MARK: - Response Budget

enum MLXResponseBudget {
    /// Give the model a word target below the hard token ceiling so it has room
    /// to finish its final sentence. The estimate is intentionally conservative
    /// because medical terms and structured identifiers often use extra tokens.
    static func targetWordLimit(forMaxTokens maxTokens: Int) -> Int {
        let estimatedWords = max(1, maxTokens) * 55 / 100
        return max(50, ((estimatedWords + 25) / 50) * 50)
    }

    static func instruction(forMaxTokens maxTokens: Int) -> String {
        let wordLimit = targetWordLimit(forMaxTokens: maxTokens)
        return "Response length: fit a complete answer within roughly \(wordLimit) words. Scale detail to the question, lead with the answer, prioritize patient-specific findings, and never end mid-sentence. If more detail would help, finish a coherent summary and offer the next section instead of starting material that will be cut off."
    }

    static let lengthLimitNotice =
        "_This response reached the on-device length limit. Ask “continue” to continue from here._"

    /// Repetition truncation can also fire on a legitimate answer whose items share a long
    /// identical scaffold, so the cut is always surfaced rather than silently applied.
    static let repetitionNotice =
        "_This response was cut short because it began repeating itself. Ask “continue” or rephrase for the rest._"
}

// MARK: - Device Memory Budget

/// How large a context window this device can plausibly hold.
///
/// Bounding the window is the whole mechanism: the KV cache is sized from it before any
/// allocation happens. An earlier version also set `MLX.Memory.memoryLimit`; see
/// `MLXOnDeviceClient.performLoadModel` for why that was removed.
///
/// Nothing capped either before. `MLX.Memory.memoryLimit` was never set, and the context
/// slider went to 65,536 on any device. The KV cache is the dominant cost and it scales
/// linearly with the window: WS-11 derived roughly 384 KiB per token for MediPhi from its
/// published config (32 layers, no grouped-query attention, fp16 cache), which puts a 64K
/// window at about 24 GiB. On an 8 GB iPhone that is an OOM kill, and the app had no
/// opinion about it.
///
/// **The per-token figure is an estimate and has never been measured on a device**, which is
/// why this type is shaped the way it is:
///
/// - It only ever lowers the *maximum selectable* window. The 16,384 default is left alone,
///   and `maximumContextSize` never returns less than it. That does not make the default
///   safe: a ~5,000-token first turn has been killed for memory on an 11.3 GB iPhone well
///   inside it. The window only caps what the cache *may* grow to; what a given turn will
///   actually cost is checked per turn by `promptFits(promptTokens:replyTokens:availableBytes:)`.
/// - The arithmetic is pure and tested, so correcting `assumedKVBytesPerToken` after one
///   device measurement is a one-line change with the consequences already covered.
enum MLXMemoryBudget {

    /// WS-11's estimate for the worst case in the catalog — a model without grouped-query
    /// attention, whose cache is therefore several times larger per token than a GQA model's.
    /// Applied to every model on purpose: over-estimating shrinks the window, which is the
    /// safe direction to be wrong in.
    static let assumedKVBytesPerToken = 384 * 1024

    /// Share of *installed* memory the KV cache may plan to occupy, after the weights.
    /// iOS kills an app well before it reaches the installed total, and generation needs
    /// transient room on top of the cache.
    static let kvShareOfPhysicalMemory = 0.35

    /// The largest context window to offer on this device.
    ///
    /// - Parameters:
    ///   - physicalMemory: installed memory, not free memory — matching the existing
    ///     MedGemma gate, which uses `ProcessInfo.physicalMemory` for the same reason.
    ///   - modelSizeBytes: the weights, which are resident alongside the cache.
    ///   - ceiling: the app's own hard maximum.
    ///   - floor: never return less than this. Defaults to the shipping default window.
    static func maximumContextSize(
        physicalMemory: UInt64,
        modelSizeBytes: Int64,
        ceiling: Int,
        floor: Int = MLXModelInfo.defaultContextSize
    ) -> Int {
        let forKVCache = Double(physicalMemory) * kvShareOfPhysicalMemory - Double(modelSizeBytes)
        guard forKVCache > 0 else { return floor }

        let affordableTokens = Int(forKVCache / Double(assumedKVBytesPerToken))
        // Round down to a whole 4K step so the slider lands on familiar values.
        let stepped = (affordableTokens / 4096) * 4096
        return min(ceiling, max(floor, stepped))
    }

    // MARK: Prompt Admission

    /// What processing one prompt is expected to cost, per token, *during prefill*.
    ///
    /// Measured, not derived: on an iPhone19,4 (11.3 GB, increased-memory-limit entitlement)
    /// MediPhi with ~2 GB of weights was killed by jetsam once the process passed ~6 GB while
    /// prefilling a ~15,400-character first turn, roughly 5,000 tokens. That is over 4 GB on
    /// top of the weights, about twice the KV cache `assumedKVBytesPerToken` accounts for.
    /// `RotatingKVCache` concatenates a fresh copy of every layer's cache for each prefill
    /// chunk, and the freed buffers are too small to reuse, so the cache's own size is not
    /// the whole cost. Correct this factor from the heartbeat lines in an exported log.
    static let prefillOverheadFactor = 2.0

    /// Kept free for everything that is not the KV cache: activations, logits, the app.
    static let admissionReserveBytes: UInt64 = 512 * 1024 * 1024

    /// Conservative characters-per-token for sizing a prompt before it is tokenized.
    /// Patient data is dense with numbers and units, which tokenize poorly; a low ratio
    /// over-counts tokens, and over-counting is the safe direction.
    static let charactersPerTokenEstimate = 3

    static func estimatedTokens(forCharacters characters: Int) -> Int {
        (max(0, characters) + charactersPerTokenEstimate - 1) / charactersPerTokenEstimate
    }

    /// Bytes this turn is expected to add before it finishes: the prompt at prefill cost,
    /// plus the reply, whose tokens are decoded one at a time and pay only the cache.
    ///
    /// `kvBytesPerToken` is the model's own figure (`MLXModelInfo.kvBytesPerToken`); it
    /// varies by more than 10× across the catalog, so one constant would either refuse
    /// everything a grouped-query model can do or admit what MediPhi cannot.
    static func bytesRequired(
        promptTokens: Int,
        replyTokens: Int,
        kvBytesPerToken: Int = assumedKVBytesPerToken
    ) -> UInt64 {
        let perToken = Double(max(0, kvBytesPerToken))
        let prompt = Double(max(0, promptTokens)) * perToken * prefillOverheadFactor
        let reply = Double(max(0, replyTokens)) * perToken
        return UInt64(prompt + reply) + admissionReserveBytes
    }

    /// The largest prompt, in tokens, that `availableBytes` can take with this reply budget.
    static func affordablePromptTokens(
        availableBytes: UInt64,
        replyTokens: Int,
        kvBytesPerToken: Int = assumedKVBytesPerToken
    ) -> Int {
        let perToken = Double(max(1, kvBytesPerToken))
        let replyBytes = Double(max(0, replyTokens)) * perToken
        let room = Double(availableBytes) - Double(admissionReserveBytes) - replyBytes
        guard room > 0 else { return 0 }
        return Int(room / (perToken * prefillOverheadFactor))
    }

    /// Whether a turn may start. iOS terminates the process outright when it runs out, with
    /// nothing logged and the user's message lost, so refusing up front is the better failure.
    static func promptFits(
        promptTokens: Int,
        replyTokens: Int,
        availableBytes: UInt64,
        kvBytesPerToken: Int = assumedKVBytesPerToken
    ) -> Bool {
        bytesRequired(
            promptTokens: promptTokens,
            replyTokens: replyTokens,
            kvBytesPerToken: kvBytesPerToken
        ) <= availableBytes
    }
}

// MARK: - Reasoning Output

/// Separates a thinking model's reasoning from its answer, for streaming and for the result.
///
/// MedPsy's template does not prefill the tag: the model writes `<think>`, reasons, writes
/// `</think>`, then answers. Partial output is therefore one of three shapes — nothing yet
/// (or the first characters of `<think>`), an open block still reasoning, or a closed block
/// followed by the answer so far. Plain value logic, testable without MLX.
enum MLXReasoningOutput {
    static let openingTag = "<think>"
    static let closingTag = "</think>"

    struct Split: Equatable {
        /// The answer so far, with any reasoning removed.
        let answer: String
        /// True while the model is still inside its reasoning block.
        let isReasoning: Bool
    }

    static func split(_ raw: String) -> Split {
        if let close = raw.range(of: closingTag, options: .backwards) {
            let answer = raw[close.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return Split(answer: answer, isReasoning: false)
        }

        let leading = raw.drop { $0.isWhitespace }
        if let open = raw.range(of: openingTag) {
            let before = raw[..<open.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return Split(answer: before, isReasoning: true)
        }
        // "<th" arriving in the first chunk is the start of the tag, not of an answer.
        if !leading.isEmpty, openingTag.hasPrefix(leading) {
            return Split(answer: "", isReasoning: true)
        }
        return Split(answer: raw.trimmingCharacters(in: .whitespacesAndNewlines), isReasoning: false)
    }
}

// MARK: - Context Budget

/// How a fixed context window is divided between the parts of a prompt.
///
/// The on-device window is small and hard. `GenerateParameters.maxKVSize` builds a
/// `RotatingKVCache(maxSize:keep: 4)`, which holds the first four tokens and evicts the
/// *oldest* of the rest. Eviction therefore starts at the head of the prompt and works
/// forwards — persona, then `PATIENT_DATA`, then the operational rules at the end of the
/// system block — while the newest conversation turns are always kept, and nothing anywhere
/// reports that it happened.
///
/// Sizing patient data at a flat fraction of the window guaranteed that overflow. A
/// 16,384-token window allowed ~14,700 tokens of patient data, leaving ~1,600 for the
/// persona, the rules, the question and a reply of up to 4,096 tokens: the first or second
/// exchange pushed past the window, and the safety rules — treat patient data as facts, do
/// not tell the user to change a medicine or dose — were evicted with everything else at the
/// head. Budgeting the fixed costs *first* is what keeps them resident.
///
/// Deliberately a plain value type with no dependencies: MLX itself is compiled out of the
/// simulator, so arithmetic that lives here is the only part of this fix a simulator test
/// run can check.
struct MLXContextBudget: Equatable {
    /// The whole usable window, in tokens (`maxKVSize` for the on-device provider).
    let window: Int
    /// Tokens the model may spend on its answer (`maxTokens`).
    let replyReserve: Int
    /// Persona plus the operational rules block.
    let instructionReserve: Int
    /// Room kept for the question and at least one previous exchange.
    let historyReserve: Int

    /// Persona and rules together. `MLXContextBudgetTests` asserts the real strings fit,
    /// so growing the rules fails a test rather than silently squeezing patient data.
    static let defaultInstructionReserve = 768
    /// The question plus one prior exchange.
    static let defaultHistoryReserve = 512
    /// A window this tight cannot honour the reserves; patient data still gets this much,
    /// because an assistant with no record at all is of no use to anyone.
    static let minimumPatientDataAllowance = 512

    init(
        window: Int,
        replyReserve: Int,
        instructionReserve: Int = MLXContextBudget.defaultInstructionReserve,
        historyReserve: Int = MLXContextBudget.defaultHistoryReserve
    ) {
        self.window = window
        self.replyReserve = replyReserve
        self.instructionReserve = instructionReserve
        self.historyReserve = historyReserve
    }

    /// Tokens patient data may occupy before it has to be compressed.
    var patientDataAllowance: Int {
        let fixedCosts = replyReserve + instructionReserve + historyReserve
        return max(Self.minimumPatientDataAllowance, window - fixedCosts)
    }

    /// True when a window this size cannot seat its own fixed costs, so the allowance is
    /// the floor rather than a real budget and some eviction is unavoidable.
    var isOversubscribed: Bool {
        window - (replyReserve + instructionReserve + historyReserve) < Self.minimumPatientDataAllowance
    }

    /// True when the turn just finished leaves no room for the next one, so the cached
    /// session should be dropped and its instructions re-prefilled instead of evicted.
    func nextTurnWouldOverflow(promptTokens: Int, generatedTokens: Int) -> Bool {
        promptTokens + generatedTokens + replyReserve > window
    }
}

// MARK: - Turn Interruption

/// Whether an in-flight on-device turn should stop now, and what to do with the text it has
/// produced so far.
///
/// Backgrounding is the case that matters. A suspended app holding ~2.4GB of model weights is
/// the first thing the OS reclaims, so `MLXOnDeviceClient.suspendForBackground()` gives the
/// model back — but it has to take ``MLXGPUGate`` to tear down safely, and a running reply
/// holds that gate for its whole generation. Stopping at the next token boundary is what
/// bounds that wait: without it the unload queues behind up to the full `maxTokens` budget.
///
/// Deliberately a plain value type with no dependencies, for the same reason as
/// ``MLXContextBudget``: MLX is compiled out of the simulator, so this rule is the only part
/// of the cancellation path a simulator test run can check.
struct MLXTurnInterruption: Equatable {

    /// Why the turn stopped. Both stop the same way; they read differently in the log.
    enum Reason: Equatable {
        /// The app went to the background and the model is being unloaded.
        case backgrounded
        /// The surrounding task was cancelled.
        case cancelled
    }

    /// What the caller does with the partial reply.
    enum Disposition: Equatable {
        /// Enough of an answer to be worth showing, with a notice that it was cut short.
        case keepPartial
        /// Too little to be an answer — fail the turn instead, which drops the empty
        /// assistant placeholder and leaves the user's message retryable.
        case discard
    }

    let reason: Reason
    let disposition: Disposition

    /// Below this, a partial reply is preamble rather than an answer ("Based on your
    /// records," is 22 characters) and showing it reads as a bug.
    static let minimumUsefulCharacterCount = 40

    /// Appended to a kept partial reply, matching the other two truncation notices. Both
    /// cuts are surfaced rather than silently applied, for the same reason the repetition
    /// one is: the user is otherwise left reading a half-finished answer.
    var notice: String {
        switch reason {
        case .backgrounded:
            return "_This response stopped early because the app went to the background. Ask “continue” to continue from here._"
        case .cancelled:
            return "_This response was stopped before it finished. Ask “continue” to continue from here._"
        }
    }

    /// The decision made at every token boundary. `nil` means carry on generating.
    static func evaluate(
        isSuspendedForBackground: Bool,
        isTaskCancelled: Bool,
        accumulatedContent: String
    ) -> MLXTurnInterruption? {
        let reason: Reason
        if isSuspendedForBackground {
            reason = .backgrounded
        } else if isTaskCancelled {
            reason = .cancelled
        } else {
            return nil
        }

        let usable = accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return MLXTurnInterruption(
            reason: reason,
            disposition: usable.count >= minimumUsefulCharacterCount ? .keepPartial : .discard
        )
    }
}

// MARK: - Model Info

/// Represents an MLX on-device model available for download
public struct MLXModelInfo: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let huggingFaceId: String
    public let modelType: MLXModelType
    public let estimatedSizeBytes: Int64
    public let contextWindow: Int
    public let defaultSettings: MLXModelDefaultSettings

    /// Extra end-of-turn tokens required by model-specific chat templates.
    /// These tokens close an assistant turn but are not always declared as the
    /// tokenizer's primary EOS token.
    public var extraEOSTokens: Set<String> {
        switch id {
        case Self.mediPhi4B.id:
            // MediPhi's Phi-3 template terminates every assistant message with
            // `<|end|>`, while generation_config.json declares only
            // `<|endoftext|>` as EOS. Without this extra stop token, generation
            // can continue into fabricated user/assistant turns until maxTokens.
            return ["<|end|>"]
        case Self.medGemma27BTextIT4Bit.id, Self.medGemma15_4B.id:
            return ["<end_of_turn>"]
        default:
            return []
        }
    }

    /// KV-cache bytes each token of context costs, from the model's published config
    /// (2 × layers holding a full-length cache × KV heads × head dim × 2 bytes for fp16).
    /// Models not listed fall back to MediPhi's figure, the worst in the catalog, so an
    /// unmeasured model is over-estimated rather than allowed to run out of memory.
    public var kvBytesPerToken: Int {
        switch id {
        case Self.mediPhi4B.id:
            return 2 * 32 * 32 * 96 * 2        // 384 KiB: 32 layers, no GQA
        case Self.medPsy4B.id:
            return 2 * 36 * 8 * 128 * 2        // 144 KiB: 36 layers, 8 KV heads
        case Self.medGemma15_4B.id:
            // 5 global layers grow with the context; the 29 sliding-window layers are
            // capped at 1,024 tokens, which the admission reserve covers.
            return 2 * 5 * 4 * 256 * 2         // 20 KiB
        case Self.qwen35_4B_VLM.id:
            return 2 * 8 * 4 * 256 * 2         // 32 KiB: 8 of 32 layers are full attention
        default:
            return MLXMemoryBudget.assumedKVBytesPerToken
        }
    }

    /// The model writes a `<think>…</think>` block before every answer. Only the text after
    /// `</think>` is shown or saved; see `MLXReasoningOutput`.
    public var emitsReasoning: Bool {
        id == Self.medPsy4B.id
    }

    /// Whether this model should be exposed on the current device.
    public var isAvailable: Bool {
        id != Self.medGemma27BTextIT4Bit.id || PlatformCapabilities.supportsMedGemma27BChat
    }

    /// Human-readable download size
    public var estimatedSize: String {
        let sizeInGB = Double(estimatedSizeBytes) / 1_000_000_000.0
        if sizeInGB >= 1.0 {
            return String(format: "%.2f GB", sizeInGB)
        } else {
            let sizeInMB = Double(estimatedSizeBytes) / 1_000_000.0
            return String(format: "%.0f MB", sizeInMB)
        }
    }
}

// MARK: - Predefined Models

extension MLXModelInfo {

    /// MediPhi Instruct - Medical Phi model in MLX 4-bit format
    public static let mediPhi4B = MLXModelInfo(
        id: "mediphi-instruct-mlx",
        displayName: "MediPhi Instruct",
        description: "Medical Phi model for clinical Q&A and patient communication. Optimized for medical reasoning on-device.",
        huggingFaceId: "bisonnetworking/MediPhi-Instruct-mlx-4bit",
        modelType: .llm,
        estimatedSizeBytes: 2_150_000_000,
        contextWindow: 32768,
        defaultSettings: MLXModelDefaultSettings(
            temperature: 0.4,
            topP: 0.9,
            maxTokens: 1200,
            repetitionPenalty: 1.1
        )
    )

    /// MedGemma 27B text-only instruct model for private doctor chat on high-memory Macs.
    public static let medGemma27BTextIT4Bit = MLXModelInfo(
        id: "medgemma-27b-text-it-4bit",
        displayName: "MedGemma 27B Chat",
        description: "Medical text model for private doctor chat. Requires a Mac with at least 24 GB of installed physical memory and is not a diagnostic tool.",
        huggingFaceId: "mlx-community/medgemma-27b-text-it-4bit",
        modelType: .llm,
        // Three safetensors shards plus the JSON/Jinja files downloaded by MLXLMCommon.
        // Verified against the Hub revision on 2026-08-18; keep this as an estimate because
        // repository contents can change without an app release.
        estimatedSizeBytes: 16_022_116_230,
        contextWindow: 32768,
        defaultSettings: MLXModelDefaultSettings(
            temperature: 0.2,
            topP: 0.9,
            maxTokens: 1024,
            repetitionPenalty: nil
        )
    )

    /// Qwen 3.5 4B VLM - Vision-Language model supporting text and images
    public static let qwen35_4B_VLM = MLXModelInfo(
        id: "qwen3.5-4b-vlm-mlx",
        displayName: "Qwen 3.5 4B Vision",
        description: "Vision-language model supporting text and image understanding. Can analyze medical images and documents.",
        huggingFaceId: "mlx-community/Qwen3.5-4B-MLX-4bit",
        modelType: .vlm,
        estimatedSizeBytes: 3_030_000_000,
        contextWindow: 32768,
        defaultSettings: MLXModelDefaultSettings(
            temperature: 0.6,
            topP: 0.9,
            maxTokens: 800,
            repetitionPenalty: nil
        )
    )

    /// MedPsy 4B - medical fine-tune of Qwen3-4B-Thinking-2507 (Apache-2.0).
    ///
    /// Chosen as a long-context chat candidate: grouped-query attention (8 KV heads) puts its
    /// cache at 144 KiB per token against MediPhi's 384 KiB, so a 16K window costs ~2.25 GB
    /// rather than ~6 GB. It is a thinking-only model: every answer is preceded by a
    /// reasoning block, which the reply budget below has to leave room for.
    ///
    /// The MLX build is a third-party conversion; move it to a repository we control (as
    /// MediPhi was) before shipping it as a default.
    public static let medPsy4B = MLXModelInfo(
        id: "medpsy-4b-mlx-4bit",
        displayName: "MedPsy 4B",
        description: "Medical reasoning model for clinical Q&A. Thinks before it answers, so replies take longer to start. Not a diagnostic tool.",
        huggingFaceId: "Irfanuruchi/MedPsy-4B-MLX-4bit",
        modelType: .llm,
        // Hub tree total on 2026-11-15.
        estimatedSizeBytes: 2_274_640_246,
        contextWindow: 32768,
        defaultSettings: MLXModelDefaultSettings(
            // Qwen3 thinking models degrade into loops under greedy-ish sampling and under a
            // repetition penalty; these are the upstream recommendations.
            temperature: 0.6,
            topP: 0.95,
            // Reasoning and answer share this budget.
            maxTokens: 3072,
            repetitionPenalty: nil
        )
    )

    /// MedGemma 1.5 4B - Google's January 2026 medical Gemma 3, used here for text chat only.
    ///
    /// Gemma 3 keeps a full-length cache on only 5 of its 34 layers; the other 29 hold a
    /// 1,024-token sliding window. A 16K window therefore costs well under 0.5 GB of cache.
    /// The checkpoint is multimodal, but `Gemma3TextModel.sanitize` keeps only the
    /// `language_model` weights, so the vision tower is downloaded but never loaded. Its
    /// licence is Google's Health AI Developer Foundations terms, not Apache.
    public static let medGemma15_4B = MLXModelInfo(
        id: "medgemma-1.5-4b-it-4bit",
        displayName: "MedGemma 1.5 4B",
        description: "Google's medical Gemma model for clinical Q&A. Answers directly, with low memory use for long context. Not a diagnostic tool.",
        huggingFaceId: "mlx-community/medgemma-1.5-4b-it-4bit",
        modelType: .llm,
        // Hub tree total on 2026-11-15, including the unused vision weights.
        estimatedSizeBytes: 3_439_897_648,
        contextWindow: 32768,
        defaultSettings: MLXModelDefaultSettings(
            temperature: 0.4,
            topP: 0.95,
            maxTokens: 1200,
            repetitionPenalty: nil
        )
    )

    // MARK: - All Available Models

    private static let catalogModels: [MLXModelInfo] = [
        mediPhi4B,
        medPsy4B,
        medGemma15_4B,
        medGemma27BTextIT4Bit,
        qwen35_4B_VLM
    ]

    public static var allModels: [MLXModelInfo] {
        catalogModels.filter(\.isAvailable)
    }

    public static var visionModels: [MLXModelInfo] {
        allModels.filter { $0.modelType == .vlm }
    }

    /// Default model for health assistant
    public static let defaultModel = mediPhi4B

    /// Find a model by its ID
    public static func model(withId id: String) -> MLXModelInfo? {
        allModels.first { $0.id == id }
    }
}

// MARK: - UserDefaults Keys & Configuration

extension MLXModelInfo {

    struct SettingsKeys {
        static let enableOnDeviceLLM = "enableOnDeviceLLM"
        static let selectedModelId = "onDeviceLLMSelectedModel"
        static let selectedExtractionModelId = "onDeviceLLMExtractionModel"
        static let temperature = "onDeviceLLMTemperature"
        static let topP = "onDeviceLLMTopP"
        static let maxTokens = "onDeviceLLMMaxTokens"
        static let contextSize = "onDeviceLLMContextSize"
        static let repetitionPenalty = "onDeviceLLMRepeatPenalty"
    }

    // MARK: - Context Size Constants

    public static let defaultContextSize: Int = 16384
    public static let minContextSize: Int = 4096
    public static let maxContextSize: Int = 65536

    // MARK: - Computed Configuration from UserDefaults

    public static var selectedModel: MLXModelInfo {
        let modelId = UserDefaults.standard.string(forKey: SettingsKeys.selectedModelId) ?? defaultModel.id
        return model(withId: modelId) ?? defaultModel
    }

    public static var selectedExtractionModel: MLXModelInfo? {
        guard let modelId = UserDefaults.standard.string(forKey: SettingsKeys.selectedExtractionModelId),
              let model = model(withId: modelId),
              model.modelType == .vlm else {
            return nil
        }
        return model
    }

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enableOnDeviceLLM)
    }

    public static var configuredTemperature: Float {
        configuredTemperature(for: selectedModel)
    }

    public static func configuredTemperature(for model: MLXModelInfo) -> Float {
        if UserDefaults.standard.object(forKey: SettingsKeys.temperature) != nil {
            return UserDefaults.standard.float(forKey: SettingsKeys.temperature)
        }
        return model.defaultSettings.temperature
    }

    public static var configuredTopP: Float {
        configuredTopP(for: selectedModel)
    }

    public static func configuredTopP(for model: MLXModelInfo) -> Float {
        let topP = UserDefaults.standard.float(forKey: SettingsKeys.topP)
        return topP > 0 ? topP : model.defaultSettings.topP
    }

    public static var configuredMaxTokens: Int {
        configuredMaxTokens(for: selectedModel)
    }

    public static func configuredMaxTokens(for model: MLXModelInfo) -> Int {
        let tokens = UserDefaults.standard.integer(forKey: SettingsKeys.maxTokens)
        return tokens > 0 ? tokens : model.defaultSettings.maxTokens
    }

    public static var configuredContextSize: Int {
        let size = UserDefaults.standard.integer(forKey: SettingsKeys.contextSize)
        if size > 0 {
            return min(max(size, minContextSize), deviceMaximumContextSize)
        }
        return defaultContextSize
    }

    /// `maxContextSize` narrowed to what this device can plausibly hold.
    ///
    /// A previously-saved 64K setting is clamped by this too, not just the slider — someone
    /// who raised it on a Mac and then opened the app on a phone would otherwise keep the
    /// setting that gets the process killed. See `MLXMemoryBudget` for why this never falls
    /// below the shipping default.
    public static var deviceMaximumContextSize: Int {
        MLXMemoryBudget.maximumContextSize(
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            modelSizeBytes: selectedModel.estimatedSizeBytes,
            ceiling: maxContextSize
        )
    }

    public static var configuredRepetitionPenalty: Float? {
        configuredRepetitionPenalty(for: selectedModel)
    }

    public static func configuredRepetitionPenalty(for model: MLXModelInfo) -> Float? {
        if UserDefaults.standard.object(forKey: SettingsKeys.repetitionPenalty) != nil {
            let value = UserDefaults.standard.float(forKey: SettingsKeys.repetitionPenalty)
            return value > 0 ? value : nil
        }
        return model.defaultSettings.repetitionPenalty
    }

    /// Apply default settings for a model to UserDefaults
    public static func applyDefaultSettings(for model: MLXModelInfo) {
        let defaults = model.defaultSettings
        UserDefaults.standard.set(defaults.temperature, forKey: SettingsKeys.temperature)
        UserDefaults.standard.set(defaults.topP, forKey: SettingsKeys.topP)
        UserDefaults.standard.set(defaults.maxTokens, forKey: SettingsKeys.maxTokens)
        if let penalty = defaults.repetitionPenalty {
            UserDefaults.standard.set(penalty, forKey: SettingsKeys.repetitionPenalty)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.repetitionPenalty)
        }
    }
}
