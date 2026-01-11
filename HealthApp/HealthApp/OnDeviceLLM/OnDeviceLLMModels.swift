//
//  OnDeviceLLMModels.swift
//  HealthApp
//
//  Predefined on-device LLM models available for download
//  Adapted from BisonNotes AI
//

import Foundation

// MARK: - Model Template Type

/// Supported template types for different model architectures
public enum OnDeviceLLMTemplateType: String, Codable, CaseIterable {
    case chatML
    case phi3
    case llama
    case llama3
    case mistral
    case alpaca
    case olmoe
    case qwen
    case qwen3
    case gemma3
    case simple

    /// Get the LLMTemplate for this type
    public func template(systemPrompt: String?) -> LLMTemplate {
        switch self {
        case .chatML:
            return .chatML(systemPrompt)
        case .phi3:
            return .phi3(systemPrompt)
        case .llama:
            return .llama(systemPrompt)
        case .llama3:
            return .llama3(systemPrompt)
        case .mistral:
            return .mistral
        case .alpaca:
            return .alpaca(systemPrompt)
        case .olmoe:
            return .olmoe(systemPrompt)
        case .qwen:
            return .qwen(systemPrompt)
        case .qwen3:
            return .qwen3(systemPrompt)
        case .gemma3:
            return .gemma3(systemPrompt)
        case .simple:
            return .simple(systemPrompt)
        }
    }
}

// MARK: - Model Purpose

/// The intended use case for a model
public enum OnDeviceLLMModelPurpose: String, Codable {
    case chat
    case healthAssistant
    case documentAnalysis
    case generalPurpose
}

// MARK: - Default Model Settings

/// Default sampling parameters for a model
public struct OnDeviceLLMDefaultSettings: Equatable, Codable {
    public let temperature: Float
    public let topK: Int32
    public let topP: Float
    public let minP: Float
    public let repeatPenalty: Float

    public init(
        temperature: Float = 0.7,
        topK: Int32 = 40,
        topP: Float = 0.95,
        minP: Float = 0.0,
        repeatPenalty: Float = 1.1
    ) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.repeatPenalty = repeatPenalty
    }
}

// MARK: - Model Info Structure

/// Represents a downloadable on-device LLM model
public struct OnDeviceLLMModelInfo: Identifiable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let description: String
    public let filename: String
    public let downloadURL: String
    public let downloadSizeBytes: Int64
    public let templateType: OnDeviceLLMTemplateType
    public let purpose: OnDeviceLLMModelPurpose
    public let contextWindow: Int
    public let defaultSettings: OnDeviceLLMDefaultSettings

    /// Human-readable download size
    public var downloadSize: String {
        let sizeInGB = Double(downloadSizeBytes) / 1_000_000_000.0
        if sizeInGB >= 1.0 {
            return String(format: "%.2f GB", sizeInGB)
        } else {
            let sizeInMB = Double(downloadSizeBytes) / 1_000_000.0
            return String(format: "%.0f MB", sizeInMB)
        }
    }

    /// URL where the model file is stored locally
    public var fileURL: URL {
        URL.onDeviceLLMModelsDirectory.appendingPathComponent(filename).appendingPathExtension("gguf")
    }

    /// Check if this model is already downloaded
    public var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get the file size of the downloaded model (if available)
    public var downloadedFileSize: Int64? {
        guard isDownloaded else { return nil }
        return fileURL.fileSize
    }

    /// Validate that the downloaded file is complete
    public var isDownloadComplete: Bool {
        guard let actualSize = downloadedFileSize else { return false }
        // Allow 1% tolerance for file size differences
        let tolerance = Int64(Double(downloadSizeBytes) * 0.01)
        return abs(actualSize - downloadSizeBytes) <= tolerance
    }
}

// MARK: - Predefined Models

extension OnDeviceLLMModelInfo {

    // MARK: - Medical-Optimized Models

    /// MedGemma 4B - Google's medical AI model based on Gemma 3
    /// Trained on medical data for clinical reasoning, radiology, dermatology, pathology
    public static let medGemma4B = OnDeviceLLMModelInfo(
        id: "medgemma-4b",
        displayName: "MedGemma 4B",
        description: "Google's medical AI model. Trained for clinical reasoning, radiology, and pathology analysis.",
        filename: "medgemma-4b-it-Q4_K_M",
        downloadURL: "https://huggingface.co/unsloth/medgemma-4b-it-GGUF/resolve/main/medgemma-4b-it-Q4_K_M.gguf?download=true",
        downloadSizeBytes: 2_490_000_000,
        templateType: .gemma3,
        purpose: .healthAssistant,
        contextWindow: 32768,
        defaultSettings: OnDeviceLLMDefaultSettings(
            temperature: 0.3,
            topK: 40,
            topP: 0.9,
            minP: 0.0,
            repeatPenalty: 1.1
        )
    )

    /// MediPhi Instruct - Medical Phi model for interactive health conversations
    /// Fine-tuned for medical Q&A, health discussions, and patient communication
    public static let mediPhiInstruct = OnDeviceLLMModelInfo(
        id: "mediphi-instruct",
        displayName: "MediPhi Instruct",
        description: "Medical Phi model for interactive health conversations. Optimized for medical Q&A and patient communication.",
        filename: "MediPhi-Instruct.i1-Q4_K_M",
        downloadURL: "https://huggingface.co/mradermacher/MediPhi-Instruct-i1-GGUF/resolve/main/MediPhi-Instruct.i1-Q4_K_M.gguf?download=true",
        downloadSizeBytes: 2_390_000_000,
        templateType: .phi3,
        purpose: .healthAssistant,
        contextWindow: 32768,
        defaultSettings: OnDeviceLLMDefaultSettings(
            temperature: 0.4,
            topK: 40,
            topP: 0.9,
            minP: 0.0,
            repeatPenalty: 1.1
        )
    )

    // MARK: - All Available Models

    /// All models available for download
    public static let allModels: [OnDeviceLLMModelInfo] = [
        medGemma4B,
        mediPhiInstruct
    ]

    /// Models optimized for health assistant tasks
    public static var healthAssistantModels: [OnDeviceLLMModelInfo] {
        allModels.filter { $0.purpose == .healthAssistant }
    }

    /// Default model for health assistant
    public static let defaultModel = medGemma4B

    /// Find a model by its ID
    public static func model(withId id: String) -> OnDeviceLLMModelInfo? {
        allModels.first { $0.id == id }
    }
}

// MARK: - UserDefaults Keys

extension OnDeviceLLMModelInfo {

    struct SettingsKeys {
        static let enableOnDeviceLLM = "enableOnDeviceLLM"
        static let selectedModelId = "onDeviceLLMSelectedModel"
        static let temperature = "onDeviceLLMTemperature"
        static let maxTokens = "onDeviceLLMMaxTokens"
        static let contextSize = "onDeviceLLMContextSize"
        static let topK = "onDeviceLLMTopK"
        static let topP = "onDeviceLLMTopP"
        static let minP = "onDeviceLLMMinP"
        static let repeatPenalty = "onDeviceLLMRepeatPenalty"
    }

    // MARK: - Context Size Constants

    /// Default context size for medical models (16K tokens)
    public static let defaultContextSize: Int = 16384

    /// Minimum context size (4K tokens)
    public static let minContextSize: Int = 4096

    /// Maximum context size (64K tokens)
    public static let maxContextSize: Int = 65536

    /// Get the currently selected model from UserDefaults
    public static var selectedModel: OnDeviceLLMModelInfo {
        let modelId = UserDefaults.standard.string(forKey: SettingsKeys.selectedModelId) ?? defaultModel.id
        return model(withId: modelId) ?? defaultModel
    }

    /// Check if on-device LLM is enabled
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enableOnDeviceLLM)
    }

    /// Get the configured temperature (or use model default)
    public static var configuredTemperature: Float {
        // Special handling: 0 is a valid temperature for medical models
        if UserDefaults.standard.object(forKey: SettingsKeys.temperature) != nil {
            return UserDefaults.standard.float(forKey: SettingsKeys.temperature)
        }
        return selectedModel.defaultSettings.temperature
    }

    /// Get the configured context size (default 16K, range 4K-32K)
    public static var configuredContextSize: Int {
        let size = UserDefaults.standard.integer(forKey: SettingsKeys.contextSize)
        if size > 0 {
            return min(max(size, minContextSize), maxContextSize)
        }
        return defaultContextSize
    }

    /// Get the configured max tokens (alias for context size)
    public static var configuredMaxTokens: Int {
        return configuredContextSize
    }

    /// Get sampling parameters
    public static var configuredTopK: Int32 {
        let topK = UserDefaults.standard.integer(forKey: SettingsKeys.topK)
        return topK > 0 ? Int32(topK) : selectedModel.defaultSettings.topK
    }

    public static var configuredTopP: Float {
        let topP = UserDefaults.standard.float(forKey: SettingsKeys.topP)
        return topP > 0 ? topP : selectedModel.defaultSettings.topP
    }

    public static var configuredMinP: Float {
        let minP = UserDefaults.standard.object(forKey: SettingsKeys.minP) as? Float
        return minP ?? selectedModel.defaultSettings.minP
    }

    public static var configuredRepeatPenalty: Float {
        let penalty = UserDefaults.standard.float(forKey: SettingsKeys.repeatPenalty)
        return penalty > 0 ? penalty : selectedModel.defaultSettings.repeatPenalty
    }

    /// Apply default settings for a model to UserDefaults
    public static func applyDefaultSettings(for model: OnDeviceLLMModelInfo) {
        let defaults = model.defaultSettings
        UserDefaults.standard.set(defaults.temperature, forKey: SettingsKeys.temperature)
        UserDefaults.standard.set(Int(defaults.topK), forKey: SettingsKeys.topK)
        UserDefaults.standard.set(defaults.topP, forKey: SettingsKeys.topP)
        UserDefaults.standard.set(defaults.minP, forKey: SettingsKeys.minP)
        UserDefaults.standard.set(defaults.repeatPenalty, forKey: SettingsKeys.repeatPenalty)
    }
}
