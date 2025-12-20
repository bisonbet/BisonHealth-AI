import Foundation
import Combine

// MARK: - MLX Model Manager

/// Manages downloading, loading, and lifecycle of MLX models
@MainActor
class MLXModelManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = MLXModelManager()

    // MARK: - Published Properties
    @Published var downloadedModels: [MLXLocalModel] = []
    @Published var modelStatuses: [String: MLXModelStatus] = [:]
    @Published var currentDownload: (modelId: String, progress: Double)?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Configured URLSession with appropriate timeouts for large file downloads
    private let downloadSession: URLSession

    /// Directory where MLX models are stored
    private var modelsDirectory: URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mlxDir = documentsDir.appendingPathComponent("MLXModels", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: mlxDir.path) {
            try? fileManager.createDirectory(at: mlxDir, withIntermediateDirectories: true)
        }

        return mlxDir
    }

    // MARK: - Initialization
    private init() {
        // Configure URLSession with appropriate timeouts for large file downloads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60      // 60 seconds for individual requests
        config.timeoutIntervalForResource = 600    // 10 minutes for entire download
        config.waitsForConnectivity = true         // Wait for network if temporarily unavailable
        self.downloadSession = URLSession(configuration: config)

        Task {
            await loadDownloadedModels()
        }
    }

    deinit {
        // Invalidate download session to prevent memory leaks
        downloadSession.invalidateAndCancel()
    }

    // MARK: - Model Discovery

    /// Load all downloaded models from disk
    func loadDownloadedModels() async {
        logger.info("📁 Loading downloaded MLX models")

        do {
            let modelDirs = try fileManager.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var models: [MLXLocalModel] = []

            for modelDir in modelDirs {
                // Each model should have a metadata.json file
                let metadataPath = modelDir.appendingPathComponent("metadata.json")

                if fileManager.fileExists(atPath: metadataPath.path),
                   let data = try? Data(contentsOf: metadataPath),
                   let localModel = try? JSONDecoder().decode(MLXLocalModel.self, from: data) {

                    // Verify the model directory actually exists and has required files
                    if localModel.isActive {
                        models.append(localModel)
                        modelStatuses[localModel.id] = .downloaded
                        logger.info("📁 Found model: \(localModel.config.name)")
                    } else {
                        logger.warning("⚠️ Skipping model with missing files: \(localModel.config.name) at \(localModel.localPath.path)")
                        // Clean up orphaned metadata
                        try? fileManager.removeItem(at: modelDir)
                    }
                }
            }

            downloadedModels = models
            logger.info("📁 Loaded \(models.count) MLX models")

        } catch {
            logger.error("📁 Failed to load MLX models", error: error)
            errorMessage = "Failed to load models: \(error.localizedDescription)"
        }
    }

    // MARK: - Model Download

    /// Download a model from HuggingFace
    /// - Returns: Task handle for cancellation support
    @discardableResult
    func downloadModel(_ config: MLXModelConfig) -> Task<Void, Never> {
        let task = Task {
            do {
                try await performDownload(config: config)
            } catch is CancellationError {
                await MainActor.run {
                    self.logger.info("⏸️ Download cancelled: \(config.name)")
                    self.modelStatuses[config.id] = .failed(error: "Cancelled")
                    self.currentDownload = nil
                }
            } catch {
                await MainActor.run {
                    self.logger.error("❌ Download failed: \(config.name)", error: error)
                    self.modelStatuses[config.id] = .failed(error: error.localizedDescription)
                    self.currentDownload = nil
                }
            }
            _ = await MainActor.run {
                self.downloadTasks.removeValue(forKey: config.id)
            }
        }

        downloadTasks[config.id] = task
        return task
    }

    /// Perform the actual download (internal implementation)
    private func performDownload(config: MLXModelConfig) async throws {
        logger.info("📥 Starting download for model: \(config.name)")

        // Check if already downloaded
        if isModelDownloaded(config.id) {
            throw MLXError.modelAlreadyDownloaded
        }

        // Check if already downloading
        if case .downloading = modelStatuses[config.id] {
            throw MLXError.downloadInProgress
        }

        // Check available disk space (require 2x the model size for safety)
        if let availableSpace = getAvailableDiskSpace() {
            let requiredSpace = config.estimatedSize * 2  // 2x for temporary files during download
            if availableSpace < requiredSpace {
                let availableGB = Double(availableSpace) / 1_073_741_824.0
                let requiredGB = Double(requiredSpace) / 1_073_741_824.0
                logger.warning("⚠️ Insufficient storage: \(String(format: "%.2f", availableGB))GB available, \(String(format: "%.2f", requiredGB))GB required")
                throw MLXError.insufficientStorage
            }
            logger.info("✅ Storage check passed: \(String(format: "%.2f", Double(availableSpace) / 1_073_741_824.0))GB available")
        }

        // Set initial status
        modelStatuses[config.id] = .downloading(progress: 0.0)

        // Use HuggingFace Hub API to download the model
        let modelPath = try await downloadFromHuggingFace(config: config)

        // Create local model record
        let localModel = MLXLocalModel(
            id: config.id,
            config: config,
            downloadedAt: Date(),
            lastUsed: nil,
            localPath: modelPath,
            fileSize: calculateDirectorySize(modelPath)
        )

        // Save metadata
        try saveModelMetadata(localModel)

        // Update state
        downloadedModels.append(localModel)
        modelStatuses[config.id] = .downloaded
        currentDownload = nil

        logger.info("✅ Successfully downloaded model: \(config.name)")
    }

    /// Download model files from HuggingFace using their Hub API
    private func downloadFromHuggingFace(config: MLXModelConfig) async throws -> URL {
        logger.info("📡 Downloading from HuggingFace: \(config.huggingFaceRepo)")

        // Create model directory
        let modelDir = modelsDirectory.appendingPathComponent(config.id)
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Get required files from config (allows per-model customization)
        let requiredFiles = config.filesToDownload
        logger.info("📥 Will download \(requiredFiles.count) files: \(requiredFiles.joined(separator: ", "))")

        // Optional files
        let optionalFiles = [
            "special_tokens_map.json",
            "generation_config.json",
            "tokenizer.model"
        ]

        var totalProgress = 0.0
        let progressIncrement = 1.0 / Double(requiredFiles.count + optionalFiles.count)

        // Download required files
        for filename in requiredFiles {
            _ = try await downloadFile(
                repo: config.huggingFaceRepo,
                filename: filename,
                to: modelDir
            )
            logger.info("📥 Downloaded: \(filename)")

            totalProgress += progressIncrement
            modelStatuses[config.id] = .downloading(progress: totalProgress)
            currentDownload = (config.id, totalProgress)
        }

        // Download optional files (don't fail if missing)
        for filename in optionalFiles {
            do {
                _ = try await downloadFile(
                    repo: config.huggingFaceRepo,
                    filename: filename,
                    to: modelDir
                )
                logger.info("📥 Downloaded optional: \(filename)")
            } catch {
                logger.warning("⚠️ Optional file not found: \(filename)")
            }

            totalProgress += progressIncrement
            modelStatuses[config.id] = .downloading(progress: totalProgress)
            currentDownload = (config.id, totalProgress)
        }

        return modelDir
    }

    /// Download a single file from HuggingFace with retry logic
    private func downloadFile(repo: String, filename: String, to directory: URL) async throws -> URL {
        // HuggingFace CDN URL format
        let urlString = "https://huggingface.co/\(repo)/resolve/main/\(filename)"

        guard let url = URL(string: urlString) else {
            throw MLXError.invalidURL
        }

        let destinationURL = directory.appendingPathComponent(filename)

        // Retry logic for network failures
        var lastError: Error?
        let maxRetries = 3

        for attempt in 0..<maxRetries {
            // Check for task cancellation
            try Task.checkCancellation()

            do {
                logger.info("📥 Downloading \(filename) (attempt \(attempt + 1)/\(maxRetries))")

                // Create download task with progress tracking using configured session
                // IMPORTANT: Move file inside completion handler to prevent iOS from deleting temp file
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let task = downloadSession.downloadTask(with: url) { localURL, response, error in

                        // Handle download errors
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }

                        guard let localURL = localURL else {
                            continuation.resume(throwing: MLXError.downloadFailed(filename: filename))
                            return
                        }

                        guard let response = response else {
                            continuation.resume(throwing: MLXError.downloadFailed(filename: "No response"))
                            return
                        }

                        // Validate HTTP response
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.resume(throwing: MLXError.downloadFailed(filename: "Invalid HTTP response"))
                            return
                        }

                        guard (200...299).contains(httpResponse.statusCode) else {
                            continuation.resume(throwing: MLXError.downloadFailed(filename: "\(filename) (HTTP \(httpResponse.statusCode))"))
                            return
                        }

                        // Move file INSIDE completion handler before temp file is deleted
                        do {
                            // Use FileManager.default directly (thread-safe for these operations)
                            let fm = FileManager.default
                            let destinationDir = destinationURL.deletingLastPathComponent()

                            // Ensure destination directory exists
                            if !fm.fileExists(atPath: destinationDir.path) {
                                try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                            }

                            // Verify temp file exists
                            guard fm.fileExists(atPath: localURL.path) else {
                                continuation.resume(throwing: MLXError.downloadFailed(filename: "Temp file doesn't exist at \(localURL.path)"))
                                return
                            }

                            // Move to final location (remove existing file if present)
                            if fm.fileExists(atPath: destinationURL.path) {
                                try fm.removeItem(at: destinationURL)
                            }

                            try fm.moveItem(at: localURL, to: destinationURL)

                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                    task.resume()
                }

                return destinationURL

            } catch {
                lastError = error
                logger.warning("⚠️ Download attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if attempt < maxRetries - 1 {
                    // Exponential backoff: 2, 4, 8 seconds
                    let delay = pow(2.0, Double(attempt + 1))
                    logger.info("⏸️ Retrying in \(Int(delay)) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? MLXError.downloadFailed(filename: filename)
    }

    // MARK: - Model Management

    /// Check if a model is downloaded
    func isModelDownloaded(_ modelId: String) -> Bool {
        downloadedModels.contains { $0.id == modelId && $0.isActive }
    }

    /// Get available disk space in bytes
    func getAvailableDiskSpace() -> Int64? {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return freeSize.int64Value
            }
        } catch {
            logger.error("Failed to get available disk space", error: error)
        }
        return nil
    }

    /// Get local model by ID
    func getLocalModel(_ modelId: String) -> MLXLocalModel? {
        downloadedModels.first { $0.id == modelId }
    }

    /// Delete a downloaded model
    func deleteModel(_ modelId: String) async throws {
        logger.info("🗑️ Deleting model: \(modelId)")

        guard let localModel = getLocalModel(modelId) else {
            logger.error("❌ Model not found: \(modelId)")
            throw MLXError.modelNotFound
        }

        // Delete from disk - try both the stored path and the expected path
        let storedPath = localModel.localPath
        let expectedPath = modelsDirectory.appendingPathComponent(modelId)

        var deletedSomething = false

        // Try deleting from stored path
        do {
            logger.info("📁 Attempting to delete from stored path: \(storedPath.path)")
            if fileManager.fileExists(atPath: storedPath.path) {
                try fileManager.removeItem(at: storedPath)
                logger.info("✅ Deleted from stored path")
                deletedSomething = true
            } else {
                logger.warning("⚠️ Stored path doesn't exist: \(storedPath.path)")
            }
        } catch {
            logger.error("❌ Failed to delete from stored path", error: error)
        }

        // Also try expected path (in case metadata path is stale)
        do {
            logger.info("📁 Attempting to delete from expected path: \(expectedPath.path)")
            if fileManager.fileExists(atPath: expectedPath.path) {
                try fileManager.removeItem(at: expectedPath)
                logger.info("✅ Deleted from expected path")
                deletedSomething = true
            } else {
                logger.info("ℹ️ Expected path doesn't exist (OK if already deleted)")
            }
        } catch {
            logger.error("❌ Failed to delete from expected path", error: error)
        }

        // Remove from state regardless of disk deletion success
        downloadedModels.removeAll { $0.id == modelId }
        modelStatuses.removeValue(forKey: modelId)

        if deletedSomething {
            logger.info("✅ Successfully deleted model: \(modelId)")
        } else {
            logger.warning("⚠️ Model files not found but removed from state: \(modelId)")
        }
    }

    /// Update last used timestamp
    func markModelUsed(_ modelId: String) {
        if let index = downloadedModels.firstIndex(where: { $0.id == modelId }) {
            // Capture model before mutation to avoid race condition
            var model = downloadedModels[index]
            model.lastUsed = Date()

            // Update in array
            downloadedModels[index] = model

            // Save updated metadata asynchronously on main actor to prevent race conditions
            Task { @MainActor in
                do {
                    try self.saveModelMetadata(model)
                } catch {
                    self.logger.error("Failed to update model metadata", error: error)
                }
            }
        }
    }

    /// Cancel ongoing download
    func cancelDownload(_ modelId: String) {
        logger.info("⏸️ Cancelling download: \(modelId)")

        // Cancel the download task
        if let task = downloadTasks[modelId] {
            task.cancel()
            logger.info("✅ Download task cancelled")
        }

        downloadTasks.removeValue(forKey: modelId)
        modelStatuses.removeValue(forKey: modelId)
        currentDownload = nil

        // Clean up partial download
        let modelDir = modelsDirectory.appendingPathComponent(modelId)
        try? fileManager.removeItem(at: modelDir)
    }

    // MARK: - Helper Methods

    private func saveModelMetadata(_ model: MLXLocalModel) throws {
        let metadataPath = model.localPath.appendingPathComponent("metadata.json")
        let data = try JSONEncoder().encode(model)
        try data.write(to: metadataPath)
    }

    private func calculateDirectorySize(_ url: URL) -> Int64 {
        var size: Int64 = 0

        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }

        return size
    }

    /// Get total storage used by all models
    func getTotalStorageUsed() -> Int64 {
        downloadedModels.reduce(0) { $0 + $1.fileSize }
    }
}

// MARK: - MLX Errors

enum MLXError: LocalizedError {
    case modelAlreadyDownloaded
    case downloadInProgress
    case modelNotFound
    case invalidURL
    case downloadFailed(filename: String)
    case insufficientStorage
    case modelLoadFailed(String)
    case generationFailed(String)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .modelAlreadyDownloaded:
            return "Model is already downloaded"
        case .downloadInProgress:
            return "Download is already in progress for this model"
        case .modelNotFound:
            return "Model not found"
        case .invalidURL:
            return "Invalid model URL"
        case .downloadFailed(let filename):
            return "Failed to download file: \(filename)"
        case .insufficientStorage:
            return "Insufficient storage space to download model"
        case .modelLoadFailed(let message):
            return "Failed to load model: \(message)"
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .invalidConfiguration:
            return "Invalid model configuration"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelAlreadyDownloaded:
            return "The model is already available for use"
        case .downloadInProgress:
            return "Please wait for the current download to complete"
        case .modelNotFound:
            return "Try downloading the model first"
        case .invalidURL:
            return "Check the model repository name"
        case .downloadFailed:
            return "Check your internet connection and try again"
        case .insufficientStorage:
            return "Free up storage space and try again"
        case .modelLoadFailed:
            return "Try re-downloading the model or selecting a different model"
        case .generationFailed:
            return "Try reducing the message length or adjusting generation parameters"
        case .invalidConfiguration:
            return "Check model settings and try again"
        }
    }
}
