//
//  MLXOnDeviceModels.swift
//  HealthApp
//
//  Model catalog for MLX on-device LLM models
//

import Foundation

// MARK: - Model Type

/// Whether a model is a text-only LLM or a Vision-Language Model
public enum MLXModelType: String, Codable, CaseIterable {
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
public struct MLXModelDefaultSettings: Equatable, Codable {
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

// MARK: - Model Info

/// Represents an MLX on-device model available for download
public struct MLXModelInfo: Identifiable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let description: String
    public let huggingFaceId: String
    public let modelType: MLXModelType
    public let estimatedSizeBytes: Int64
    public let contextWindow: Int
    public let defaultSettings: MLXModelDefaultSettings

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
            maxTokens: 800,
            repetitionPenalty: 1.1
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

    public static let allModels: [MLXModelInfo] = [
        mediPhi4B,
        qwen35_4B_VLM
    ]

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

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enableOnDeviceLLM)
    }

    public static var configuredTemperature: Float {
        if UserDefaults.standard.object(forKey: SettingsKeys.temperature) != nil {
            return UserDefaults.standard.float(forKey: SettingsKeys.temperature)
        }
        return selectedModel.defaultSettings.temperature
    }

    public static var configuredTopP: Float {
        let topP = UserDefaults.standard.float(forKey: SettingsKeys.topP)
        return topP > 0 ? topP : selectedModel.defaultSettings.topP
    }

    public static var configuredMaxTokens: Int {
        let tokens = UserDefaults.standard.integer(forKey: SettingsKeys.maxTokens)
        return tokens > 0 ? tokens : selectedModel.defaultSettings.maxTokens
    }

    public static var configuredContextSize: Int {
        let size = UserDefaults.standard.integer(forKey: SettingsKeys.contextSize)
        if size > 0 {
            return min(max(size, minContextSize), maxContextSize)
        }
        return defaultContextSize
    }

    public static var configuredRepetitionPenalty: Float? {
        if UserDefaults.standard.object(forKey: SettingsKeys.repetitionPenalty) != nil {
            let value = UserDefaults.standard.float(forKey: SettingsKeys.repetitionPenalty)
            return value > 0 ? value : nil
        }
        return selectedModel.defaultSettings.repetitionPenalty
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
