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
    private static let downloadedModelsDefaultsKey = "mlxDownloadedModelIds"

    // MARK: - Published State

    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var currentlyDownloadingModel: MLXModelInfo?
    @Published var downloadError: String?
    @Published var downloadedModelIds: Set<String> = []

    // MARK: - Private State

    private var downloadTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        downloadedModelIds = loadPersistedDownloadedModelIds()
        // Defer filesystem validation to avoid mutating @Published during view evaluation
        Task { @MainActor in
            self.refreshModelStatus()
        }
    }

    // MARK: - Download Management

    /// Start downloading an MLX model from HuggingFace Hub
    func startDownload(for model: MLXModelInfo) {
        guard !isDownloading else {
            AppLog.shared.mlx("[MLXDownload] Already downloading a model", level: .warning)
            return
        }
        guard !isModelDownloaded(model) else {
            AppLog.shared.mlx("[MLXDownload] Model already downloaded: \(model.displayName)")
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
                AppLog.shared.mlx("[MLXDownload] Starting download for \(model.displayName) (\(model.huggingFaceId))")

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

                AppLog.shared.mlx("[MLXDownload] Download complete for \(model.displayName)")

                isDownloading = false
                downloadProgress = 1.0
                currentlyDownloadingModel = nil
                downloadTask = nil
                markModelDownloaded(model)
                #endif
            } catch is CancellationError {
                AppLog.shared.mlx("[MLXDownload] Download cancelled for \(model.displayName)")
                isDownloading = false
                downloadProgress = 0.0
                currentlyDownloadingModel = nil
                downloadTask = nil
                cleanupIncompleteDownload(for: model)
                removeDownloadedModel(model)
            } catch {
                AppLog.shared.error("[MLXDownload] Download failed for \(model.displayName)", error: error, category: .mlx)
                isDownloading = false
                downloadProgress = 0.0
                currentlyDownloadingModel = nil
                downloadTask = nil
                cleanupIncompleteDownload(for: model)
                removeDownloadedModel(model)
                downloadError = error.localizedDescription
            }
        }
    }

    /// Cancel the current download
    func cancelDownload() {
        let model = currentlyDownloadingModel
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        currentlyDownloadingModel = nil
        if let model {
            cleanupIncompleteDownload(for: model)
            removeDownloadedModel(model)
        }
        refreshModelStatus()
    }

    /// Check if a model is downloaded.
    /// This is a pure read — no side effects, safe to call from SwiftUI view bodies.
    func isModelDownloaded(_ model: MLXModelInfo) -> Bool {
        downloadedModelIds.contains(model.id)
    }

    /// Delete a downloaded model's cached files
    func deleteModel(_ model: MLXModelInfo) {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            do {
                try FileManager.default.removeItem(at: cacheDir)
                removeDownloadedModel(model)
                AppLog.shared.mlx("[MLXDownload] Deleted model cache for \(model.displayName)")
            } catch {
                AppLog.shared.error("[MLXDownload] Failed to delete model cache", error: error, category: .mlx)
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
            let cacheDir = huggingFaceCacheDirectory(for: model)
            let valid = isModelCacheValid(for: model)
            AppLog.shared.mlx("[MLXDownload] Model \(model.displayName) cache path: \(cacheDir.path), valid: \(valid)")
            if valid {
                downloaded.insert(model.id)
            }
        }
        downloadedModelIds = downloaded
        persistDownloadedModelIds()
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

    /// Get the HuggingFace Hub local directory for a model.
    /// MLX Swift's `defaultHubApi` uses cachesDirectory as downloadBase (not documentDirectory).
    /// HubApi.localRepoLocation then appends: models/<repoId>
    /// Uses .appending(component:) to match HubApi's URL construction.
    private func huggingFaceCacheDirectory(for model: MLXModelInfo) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cachesDir
            .appending(component: "models")
            .appending(component: model.huggingFaceId)
    }

    private func persistDownloadedModelIds() {
        UserDefaults.standard.set(Array(downloadedModelIds).sorted(), forKey: Self.downloadedModelsDefaultsKey)
    }

    private func loadPersistedDownloadedModelIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.downloadedModelsDefaultsKey) ?? [])
    }

    private func markModelDownloaded(_ model: MLXModelInfo) {
        downloadedModelIds.insert(model.id)
        persistDownloadedModelIds()
    }

    private func removeDownloadedModel(_ model: MLXModelInfo) {
        downloadedModelIds.remove(model.id)
        persistDownloadedModelIds()
    }

    /// Check if a model's local directory contains the required MLX artifacts (config + weights).
    private func isModelCacheValid(for model: MLXModelInfo) -> Bool {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory)
        guard exists && isDirectory.boolValue else { return false }

        return directoryContainsRequiredArtifacts(at: cacheDir)
    }

    /// Recursively check for config.json and at least one .safetensors file.
    private func directoryContainsRequiredArtifacts(at directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        var hasConfig = false
        var hasWeights = false

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename == "config.json" {
                hasConfig = true
            }

            if fileURL.pathExtension == "safetensors" || filename.hasSuffix(".safetensors.index.json") {
                hasWeights = true
            }

            if hasConfig && hasWeights {
                return true
            }
        }

        return false
    }

    private func cleanupIncompleteDownload(for model: MLXModelInfo) {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return }
        guard !isModelCacheValid(for: model) else { return }

        do {
            try FileManager.default.removeItem(at: cacheDir)
            AppLog.shared.mlx("[MLXDownload] Removed incomplete cache for \(model.displayName)")
        } catch {
            AppLog.shared.mlx("[MLXDownload] Failed to remove incomplete cache for \(model.displayName): \(error.localizedDescription)", level: .warning)
        }
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
