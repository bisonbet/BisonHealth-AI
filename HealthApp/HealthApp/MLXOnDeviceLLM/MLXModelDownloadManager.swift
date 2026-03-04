//
//  MLXModelDownloadManager.swift
//  HealthApp
//
//  Manages MLX model downloads via HuggingFace Hub integration
//

import Foundation
import SwiftUI

#if !targetEnvironment(simulator)
import MLXLMCommon
import MLXLLM
import MLXVLM
#endif

// MARK: - Download Manager

@MainActor
class MLXModelDownloadManager: ObservableObject {
    static let shared = MLXModelDownloadManager()

    // MARK: - Published State

    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var currentlyDownloadingModel: MLXModelInfo?
    @Published var downloadError: String?
    @Published var downloadedModelIds: Set<String> = []

    // MARK: - Private State

    private var downloadTask: Task<Void, Never>?
    private let logger = Logger.shared

    // MARK: - Initialization

    init() {
        refreshModelStatus()
    }

    // MARK: - Download Management

    /// Start downloading an MLX model from HuggingFace Hub
    func startDownload(for model: MLXModelInfo) {
        guard !isDownloading else {
            logger.warning("[MLXDownload] Already downloading a model")
            return
        }

        isDownloading = true
        downloadProgress = 0.0
        currentlyDownloadingModel = model
        downloadError = nil

        downloadTask = Task {
            do {
                #if targetEnvironment(simulator)
                throw MLXOnDeviceError.simulatorNotSupported
                #else
                logger.info("[MLXDownload] Starting download for \(model.displayName) (\(model.huggingFaceId))")

                let configuration = ModelConfiguration(id: model.huggingFaceId)

                // Use the appropriate factory based on model type
                switch model.modelType {
                case .llm:
                    _ = try await LLMModelFactory.shared.loadContainer(
                        configuration: configuration
                    ) { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress.fractionCompleted
                        }
                    }
                case .vlm:
                    _ = try await VLMModelFactory.shared.loadContainer(
                        configuration: configuration
                    ) { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress.fractionCompleted
                        }
                    }
                }

                logger.info("[MLXDownload] Download complete for \(model.displayName)")

                isDownloading = false
                downloadProgress = 1.0
                currentlyDownloadingModel = nil
                downloadedModelIds.insert(model.id)
                #endif
            } catch is CancellationError {
                logger.info("[MLXDownload] Download cancelled for \(model.displayName)")
                isDownloading = false
                downloadProgress = 0.0
                currentlyDownloadingModel = nil
            } catch {
                logger.error("[MLXDownload] Download failed for \(model.displayName)", error: error)
                isDownloading = false
                downloadProgress = 0.0
                currentlyDownloadingModel = nil
                downloadError = error.localizedDescription
            }
        }
    }

    /// Cancel the current download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        currentlyDownloadingModel = nil
    }

    /// Check if a model is downloaded by looking for its files in the HuggingFace cache
    func isModelDownloaded(_ model: MLXModelInfo) -> Bool {
        return downloadedModelIds.contains(model.id) || checkHuggingFaceCacheExists(for: model)
    }

    /// Delete a downloaded model's cached files
    func deleteModel(_ model: MLXModelInfo) {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            do {
                try FileManager.default.removeItem(at: cacheDir)
                downloadedModelIds.remove(model.id)
                logger.info("[MLXDownload] Deleted model cache for \(model.displayName)")
            } catch {
                logger.error("[MLXDownload] Failed to delete model cache", error: error)
            }
        }
        refreshModelStatus()
    }

    /// Select a model (update UserDefaults)
    func selectModel(_ model: MLXModelInfo) {
        UserDefaults.standard.set(model.id, forKey: MLXModelInfo.SettingsKeys.selectedModelId)
    }

    /// Refresh the download status of all models
    func refreshModelStatus() {
        var downloaded = Set<String>()
        for model in MLXModelInfo.allModels {
            if checkHuggingFaceCacheExists(for: model) {
                downloaded.insert(model.id)
            }
        }
        downloadedModelIds = downloaded
    }

    // MARK: - Storage Info

    /// Get the total storage used by downloaded models
    var totalStorageUsed: Int64 {
        var total: Int64 = 0
        for model in MLXModelInfo.allModels where downloadedModelIds.contains(model.id) {
            let cacheDir = huggingFaceCacheDirectory(for: model)
            total += directorySize(at: cacheDir)
        }
        return total
    }

    /// Get downloaded models
    var downloadedModels: [MLXModelInfo] {
        MLXModelInfo.allModels.filter { downloadedModelIds.contains($0.id) }
    }

    /// Format storage size for display
    func formatSize(_ bytes: Int64) -> String {
        let sizeInGB = Double(bytes) / 1_000_000_000.0
        if sizeInGB >= 1.0 {
            return String(format: "%.2f GB", sizeInGB)
        } else {
            let sizeInMB = Double(bytes) / 1_000_000.0
            return String(format: "%.0f MB", sizeInMB)
        }
    }

    // MARK: - Private Helpers

    /// Get the HuggingFace cache directory for a model
    /// MLX/HuggingFace Hub caches models in the app's cache directory under huggingface/
    private func huggingFaceCacheDirectory(for model: MLXModelInfo) -> URL {
        // HuggingFace Hub Swift caches to:
        // ~/Library/Caches/<bundle>/huggingface/hub/models--<org>--<name>
        let cacheBase: URL
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheBase = cachesDir
        } else {
            cacheBase = FileManager.default.temporaryDirectory
        }

        // HuggingFace model IDs use "/" which are converted to "--" in cache paths
        let sanitizedId = model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
        return cacheBase.appendingPathComponent("huggingface/hub/models--\(sanitizedId)")
    }

    /// Check if a model's cache directory exists and has files
    private func checkHuggingFaceCacheExists(for model: MLXModelInfo) -> Bool {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory)
        guard exists && isDirectory.boolValue else { return false }

        // Check if the directory has meaningful content (safetensors files)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path) {
            return !contents.isEmpty
        }
        return false
    }

    /// Calculate the size of a directory recursively
    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
