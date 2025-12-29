import Foundation

// MARK: - MLX Model Configuration

/// Configuration for an MLX model
struct MLXModelConfig: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let huggingFaceRepo: String
    let description: String
    let modelType: MLXModelType
    let quantization: String
    let estimatedSize: Int64 // in bytes
    let contextWindow: Int
    let recommended: Bool
    let specialization: String?
    let requiredFiles: [String]?  // Optional: specific files to download

    var sizeInMB: Double {
        Double(estimatedSize) / 1_048_576.0
    }

    var sizeInGB: Double {
        Double(estimatedSize) / 1_073_741_824.0
    }

    var formattedSize: String {
        if sizeInGB >= 1.0 {
            return String(format: "%.2f GB", sizeInGB)
        } else {
            return String(format: "%.0f MB", sizeInMB)
        }
    }

    /// Get list of files to download (uses requiredFiles if specified, otherwise defaults)
    var filesToDownload: [String] {
        requiredFiles ?? [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "model.safetensors"
        ]
    }
}

/// Type of MLX model
enum MLXModelType: String, Codable {
    case textOnly = "text_only"
    case vision = "vision"
    case embedding = "embedding"

    var displayName: String {
        switch self {
        case .textOnly: return "Text"
        case .vision: return "Vision"
        case .embedding: return "Embedding"
        }
    }
}

/// Status of a downloaded model
enum MLXModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
    case loading
    case loaded

    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        if case .loaded = self { return true }
        if case .loading = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Local model information
struct MLXLocalModel: Codable, Equatable, Identifiable {
    let id: String
    let config: MLXModelConfig
    var downloadedAt: Date
    var lastUsed: Date?
    var localPath: URL
    var fileSize: Int64

    var isActive: Bool {
        // Check if model files still exist
        FileManager.default.fileExists(atPath: localPath.path)
    }
}

/// MLX generation parameters
struct MLXGenerationConfig: Codable, Equatable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var repetitionPenalty: Double
    var repetitionContextSize: Int
    var contextWindow: Int

    static let `default` = MLXGenerationConfig(
        temperature: 0.7,
        topP: 0.9,
        maxTokens: 2048,
        repetitionPenalty: 1.1,
        repetitionContextSize: 20,
        contextWindow: 8192
    )

    static let creative = MLXGenerationConfig(
        temperature: 0.9,
        topP: 0.95,
        maxTokens: 2048,
        repetitionPenalty: 1.0,
        repetitionContextSize: 20,
        contextWindow: 8192
    )

    static let precise = MLXGenerationConfig(
        temperature: 0.3,
        topP: 0.8,
        maxTokens: 2048,
        repetitionPenalty: 1.2,
        repetitionContextSize: 20,
        contextWindow: 8192
    )
}

/// Predefined MLX models available for download
struct MLXModelRegistry {
    static let availableModels: [MLXModelConfig] = [
        MLXModelConfig(
            id: "mediphi-instruct-4bit",
            name: "MediPhi Instruct (4-bit)",
            huggingFaceRepo: "bisonnetworking/MediPhi-Instruct-mlx-4bit",
            description: "Medical AI based on Phi-3.5 with improved system message handling and clinical reasoning",
            modelType: .textOnly,
            quantization: "4-bit",
            estimatedSize: 1_800_000_000, // ~1.8 GB
            contextWindow: 8192,
            recommended: true,
            specialization: "Clinical reasoning with better system prompt support",
            requiredFiles: nil  // Use default files
        ),
        MLXModelConfig(
            id: "medgemma-4b-it-4bit",
            name: "MedGemma 4B (4-bit)",
            huggingFaceRepo: "mlx-community/medgemma-4b-it-4bit",
            description: "Medical AI assistant based on Google's Gemma, optimized for health conversations",
            modelType: .textOnly,
            quantization: "4-bit",
            estimatedSize: 2_500_000_000, // ~2.5 GB
            contextWindow: 8192,
            recommended: false,
            specialization: "Medical knowledge and health conversations",
            requiredFiles: nil  // Use default files
        )
    ]

    static func model(withId id: String) -> MLXModelConfig? {
        availableModels.first { $0.id == id }
    }

    static func recommendedModel() -> MLXModelConfig {
        availableModels.first { $0.recommended } ?? availableModels[0]
    }
}

/// MLX Settings stored in database
struct MLXSettings: Codable, Equatable {
    var selectedModelId: String?
    var generationConfig: MLXGenerationConfig
    var autoLoadModel: Bool
    var maxConcurrentRequests: Int

    static let `default` = MLXSettings(
        selectedModelId: nil,
        generationConfig: .default,
        autoLoadModel: false,
        maxConcurrentRequests: 1
    )
}
