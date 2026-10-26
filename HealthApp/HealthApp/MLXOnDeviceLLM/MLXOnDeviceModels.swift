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
/// - It only ever lowers the *maximum selectable* window. The 16,384 default is left alone
///   because it demonstrably works on real hardware today; an unvalidated estimate is not
///   grounds for shrinking something known to work. `maximumContextSize` therefore never
///   returns less than the default.
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
        case Self.medGemma27BTextIT4Bit.id:
            return ["<end_of_turn>"]
        default:
            return []
        }
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

    // MARK: - All Available Models

    private static let catalogModels: [MLXModelInfo] = [
        mediPhi4B,
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
