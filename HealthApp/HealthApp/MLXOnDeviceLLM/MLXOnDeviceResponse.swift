//
//  MLXOnDeviceResponse.swift
//  HealthApp
//
//  AIResponse type for MLX on-device LLM responses
//

import Foundation

// MARK: - MLX On-Device Response

struct MLXOnDeviceResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(
        content: String,
        responseTime: TimeInterval,
        tokenCount: Int? = nil,
        tokensPerSecond: Double? = nil,
        promptTokenCount: Int? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount

        var mergedMetadata = metadata ?? [:]
        if let tokensPerSecond {
            mergedMetadata["tokensPerSecond"] = tokensPerSecond
        }
        if let promptTokenCount {
            mergedMetadata["promptTokens"] = promptTokenCount
        }
        self.metadata = mergedMetadata.isEmpty ? nil : mergedMetadata
    }
}

// MARK: - MLX On-Device Error

enum MLXOnDeviceError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case generationFailed(String)
    case simulatorNotSupported
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No model is loaded. Please download and select a model in Settings."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .simulatorNotSupported:
            return "On-device LLM requires a physical device. MLX is not available in the iOS Simulator."
        case .modelNotDownloaded:
            return "Model is not downloaded. Please download a model in Settings."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotLoaded, .modelNotDownloaded:
            return "Go to Settings > On-Device LLM to download and select a model."
        case .modelLoadFailed:
            return "Try restarting the app or re-downloading the model."
        case .generationFailed:
            return "Try sending your message again."
        case .simulatorNotSupported:
            return "Deploy the app to a physical iPhone or iPad to use on-device AI."
        }
    }
}
