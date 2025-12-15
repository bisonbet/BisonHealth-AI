//
//  OnDeviceLLMModels.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import Foundation

#if canImport(LocalLLMClient)
import LocalLLMClient
#endif

// MARK: - Model Quantization

/// Quantization levels for on-device LLM models
/// Lower quantization = smaller file size but lower quality
/// Higher quantization = larger file size but better quality
enum OnDeviceLLMQuantization: String, CaseIterable, Codable {
    case q4_K_M = "Q4_K_M"    // ~2.0-2.5 GB - Recommended for iPhone
    case q5_K_M = "Q5_K_M"    // ~2.5-3.0 GB - Higher quality
    case q8_0 = "Q8_0"        // ~3.5-4.0 GB - Best quality

    var displayName: String {
        switch self {
        case .q4_K_M: return "Q4_K_M (Recommended)"
        case .q5_K_M: return "Q5_K_M (High Quality)"
        case .q8_0: return "Q8_0 (Best Quality)"
        }
    }

    var estimatedSize: String {
        switch self {
        case .q4_K_M: return "~2.0-2.5 GB"
        case .q5_K_M: return "~2.5-3.0 GB"
        case .q8_0: return "~3.5-4.0 GB"
        }
    }

    var description: String {
        switch self {
        case .q4_K_M: return "Balanced performance and size, ideal for most devices"
        case .q5_K_M: return "Higher quality responses with moderate size increase"
        case .q8_0: return "Maximum quality, requires significant storage and memory"
        }
    }
}

// MARK: - Model Specialization

enum ModelSpecialization: String, Codable {
    case medical = "medical"
    case vision = "vision"
    case general = "general"
    case reasoning = "reasoning"

    var displayName: String {
        switch self {
        case .medical: return "Medical"
        case .vision: return "Vision + Medical"
        case .general: return "General Purpose"
        case .reasoning: return "Reasoning"
        }
    }
}

// MARK: - Prompt Templates

enum PromptTemplate: String, Codable {
    case gemma = "gemma"
    case qwen = "qwen"
    case mistral = "mistral"
    case llama = "llama"
    case chatML = "chatml"

    func formatPrompt(system: String, user: String) -> String {
        switch self {
        case .gemma:
            return """
            <start_of_turn>system
            \(system)<end_of_turn>
            <start_of_turn>user
            \(user)<end_of_turn>
            <start_of_turn>model
            """

        case .qwen:
            return """
            <|im_start|>system
            \(system)<|im_end|>
            <|im_start|>user
            \(user)<|im_end|>
            <|im_start|>assistant
            """

        case .mistral:
            return """
            [INST] \(system)
            \(user) [/INST]
            """

        case .llama:
            return """
            <|begin_of_text|><|start_header_id|>system<|end_header_id|>
            \(system)<|eot_id|><|start_header_id|>user<|end_header_id|>
            \(user)<|eot_id|><|start_header_id|>assistant<|end_header_id|>
            """

        case .chatML:
            return """
            <|im_start|>system
            \(system)<|im_end|>
            <|im_start|>user
            \(user)<|im_end|>
            <|im_start|>assistant
            """
        }
    }
}

// MARK: - Model Definition

struct OnDeviceLLMModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let huggingFaceRepo: String
    let parameters: String
    let contextWindow: Int
    let quantizations: [OnDeviceLLMQuantization]
    let defaultQuantization: OnDeviceLLMQuantization
    let specialization: ModelSpecialization
    let promptTemplate: PromptTemplate
    let isVisionModel: Bool
    let checksums: [String: String]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: OnDeviceLLMModel, rhs: OnDeviceLLMModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Downloaded Model

struct DownloadedModel: Codable, Identifiable {
    let id: String
    let modelID: String
    let quantization: OnDeviceLLMQuantization
    let filePath: String
    let fileSize: Int64
    let downloadDate: Date

    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Available Models

extension OnDeviceLLMModel {
    static let availableModels: [OnDeviceLLMModel] = [
        // MedGemma-4B - Medical specialized model
        OnDeviceLLMModel(
            id: "medgemma-4b",
            name: "medgemma-4b-it",
            displayName: "MedGemma 4B",
            description: "Medical domain specialized model based on Google's Gemma, trained on medical literature and clinical notes. Optimized for health data analysis, medical terminology, and clinical reasoning.",
            huggingFaceRepo: "unsloth/medgemma-4b-it-GGUF",
            parameters: "4B",
            contextWindow: 8192,
            quantizations: [.q4_K_M, .q5_K_M, .q8_0],
            defaultQuantization: .q4_K_M,
            specialization: .medical,
            promptTemplate: .gemma,
            isVisionModel: false,
            checksums: nil
        ),

        // Qwen3-VL-4B - Vision + Medical model
        OnDeviceLLMModel(
            id: "qwen3-vl-4b",
            name: "qwen3-vl-4b-instruct",
            displayName: "Qwen3-VL 4B",
            description: "Vision-language model with extended context window (32K tokens). Note: Vision capabilities for image analysis are planned for a future update. Currently optimized for text-based medical conversations.",
            huggingFaceRepo: "unsloth/Qwen3-VL-4B-Instruct-GGUF",
            parameters: "4B",
            contextWindow: 32768,
            quantizations: [.q4_K_M, .q5_K_M, .q8_0],
            defaultQuantization: .q4_K_M,
            specialization: .vision,
            promptTemplate: .qwen,
            isVisionModel: false,
            checksums: nil
        )
    ]

    static func model(withID id: String) -> OnDeviceLLMModel? {
        availableModels.first { $0.id == id }
    }
}

// MARK: - Configuration

struct OnDeviceLLMConfig: Equatable, Codable {
    var modelID: String
    var quantization: OnDeviceLLMQuantization
    var temperature: Double
    var maxTokens: Int
    var contextWindow: Int
    var allowCellularDownload: Bool

    static let `default` = OnDeviceLLMConfig(
        modelID: "medgemma-4b",
        quantization: .q4_K_M,
        temperature: 0.1,
        maxTokens: 2048,
        contextWindow: 8192,
        allowCellularDownload: false
    )

    // UserDefaults keys
    private enum Keys {
        static let enableOnDeviceLLM = "enableOnDeviceLLM"
        static let modelID = "onDeviceLLMModelID"
        static let quantization = "onDeviceLLMQuantization"
        static let temperature = "onDeviceLLMTemperature"
        static let maxTokens = "onDeviceLLMMaxTokens"
        static let contextWindow = "onDeviceLLMContextWindow"
        static let allowCellularDownload = "onDeviceLLMAllowCellular"
        static let downloadedModels = "onDeviceLLMDownloadedModels"
    }

    static func load() -> OnDeviceLLMConfig {
        let defaults = UserDefaults.standard
        return OnDeviceLLMConfig(
            modelID: defaults.string(forKey: Keys.modelID) ?? OnDeviceLLMConfig.default.modelID,
            quantization: OnDeviceLLMQuantization(rawValue: defaults.string(forKey: Keys.quantization) ?? "") ?? OnDeviceLLMConfig.default.quantization,
            temperature: defaults.double(forKey: Keys.temperature) != 0 ? defaults.double(forKey: Keys.temperature) : OnDeviceLLMConfig.default.temperature,
            maxTokens: defaults.integer(forKey: Keys.maxTokens) != 0 ? defaults.integer(forKey: Keys.maxTokens) : OnDeviceLLMConfig.default.maxTokens,
            contextWindow: defaults.integer(forKey: Keys.contextWindow) != 0 ? defaults.integer(forKey: Keys.contextWindow) : OnDeviceLLMConfig.default.contextWindow,
            allowCellularDownload: defaults.bool(forKey: Keys.allowCellularDownload)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(modelID, forKey: Keys.modelID)
        defaults.set(quantization.rawValue, forKey: Keys.quantization)
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(maxTokens, forKey: Keys.maxTokens)
        defaults.set(contextWindow, forKey: Keys.contextWindow)
        defaults.set(allowCellularDownload, forKey: Keys.allowCellularDownload)
    }

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: Keys.enableOnDeviceLLM)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.enableOnDeviceLLM)
        }
    }

    static func loadDownloadedModels() -> [DownloadedModel] {
        guard let data = UserDefaults.standard.data(forKey: Keys.downloadedModels),
              let models = try? JSONDecoder().decode([DownloadedModel].self, from: data) else {
            return []
        }
        return models
    }

    static func saveDownloadedModels(_ models: [DownloadedModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: Keys.downloadedModels)
        }
    }
}

// MARK: - Error Handling

enum OnDeviceLLMError: LocalizedError {
    case modelNotDownloaded
    case modelNotFound(String)
    case downloadFailed(String)
    case downloadCancelled
    case cellularNotAllowed
    case insufficientStorage(required: Int64, available: Int64)
    case inferenceError(String)
    case modelLoadFailed(String)
    case contextTooLong(Int, max: Int)
    case invalidResponse
    case checksumMismatch
    case modelTooLarge(Int64)
    case visionNotSupported
    case imageProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Model not downloaded. Please download the model in settings first."
        case .modelNotFound(let id):
            return "Model '\(id)' not found. Please select a valid model."
        case .downloadFailed:
            return "Model download failed. Please check your connection and try again."
        case .downloadCancelled:
            return "Model download was cancelled."
        case .cellularNotAllowed:
            return "Cellular download not allowed. Please connect to WiFi or enable cellular downloads in settings."
        case .insufficientStorage(let required, let available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return String(format: "Insufficient storage. Required: %.1f GB, Available: %.1f GB", requiredGB, availableGB)
        case .inferenceError:
            return "Model inference failed. Please try again."
        case .modelLoadFailed:
            return "Failed to load model. Please try redownloading the model."
        case .contextTooLong(let length, let max):
            return "Input too long (\(length) tokens). Maximum: \(max) tokens."
        case .invalidResponse:
            return "Received invalid response from model."
        case .checksumMismatch:
            return "Model file checksum mismatch. Please redownload the model."
        case .modelTooLarge(let size):
            let sizeGB = Double(size) / 1_000_000_000
            return String(format: "Model too large (%.1f GB). Maximum supported size is 5 GB.", sizeGB)
        case .visionNotSupported:
            return "Selected model does not support vision/image processing."
        case .imageProcessingFailed:
            return "Failed to process image. Please try a different image."
        }
    }
}
