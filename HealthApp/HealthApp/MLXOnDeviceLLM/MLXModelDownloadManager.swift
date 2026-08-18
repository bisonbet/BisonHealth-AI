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
#endif

// MARK: - Download Manager

@MainActor
class MLXModelDownloadManager: ObservableObject {
    static let shared = MLXModelDownloadManager()
    private static let downloadedModelsDefaultsKey = "mlxDownloadedModelIds"

    // MARK: - Published State

    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var downloadSpeedBytesPerSecond: Double?
    @Published var isDownloadStalled: Bool = false
    @Published var currentlyDownloadingModel: MLXModelInfo?
    @Published var downloadError: String?
    @Published var downloadedModelIds: Set<String> = []
    @Published var selectedModelId: String = MLXModelInfo.selectedModel.id
    @Published var selectedExtractionModelId: String? = MLXModelInfo.selectedExtractionModel?.id

    // MARK: - Private State

    private var downloadTask: Task<Void, Never>?
    private var progressMonitorTask: Task<Void, Never>?
    private var cancelledByUser = false

    /// Fraction reported by the Hub snapshot. Written from arbitrary download threads,
    /// read by the progress monitor, so it lives behind a lock instead of a per-callback hop.
    private let reportedFraction = FractionBox()

    /// No byte movement for this long while downloading is surfaced as a stall.
    private static let stallThreshold: TimeInterval = 90

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
        guard model.isAvailable else {
            downloadError = MLXOnDeviceError.modelUnavailableOnDevice.localizedDescription
            AppLog.shared.mlx("[MLXDownload] Refusing unavailable model: \(model.displayName)", level: .warning)
            return
        }
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
        downloadedBytes = 0
        downloadSpeedBytesPerSecond = nil
        isDownloadStalled = false
        currentlyDownloadingModel = model
        downloadError = nil
        cancelledByUser = false
        reportedFraction.set(0)
        startProgressMonitor(for: model)

        downloadTask = Task {
            do {
                #if targetEnvironment(simulator)
                throw MLXOnDeviceError.simulatorNotSupported
                #else
                AppLog.shared.mlx("[MLXDownload] Starting download for \(model.displayName) (\(model.huggingFaceId)), expecting \(formatSize(model.estimatedSizeBytes))")

                let configuration = ModelConfiguration(
                    id: model.huggingFaceId,
                    extraEOSTokens: model.extraEOSTokens
                )
                let fraction = reportedFraction

                // Download the weights only. Instantiating the model is the chat client's job,
                // and doing it here would pull the whole model into memory for no benefit.
                let modelDirectory = try await downloadModel(
                    hub: defaultHubApi,
                    configuration: configuration
                ) { progress in
                    fraction.set(progress.fractionCompleted)
                }

                // MLXLMCommon treats an authorization failure as a local-only fallback.
                // Do not mark that fallback as downloaded unless the complete model is on disk;
                // MedGemma's index must resolve all three safetensors shards.
                guard isModelCacheValid(at: modelDirectory) else {
                    throw MLXOnDeviceError.modelDownloadIncomplete
                }

                AppLog.shared.mlx("[MLXDownload] Download complete for \(model.displayName)")

                stopProgressMonitor()
                isDownloading = false
                downloadProgress = 1.0
                downloadSpeedBytesPerSecond = nil
                isDownloadStalled = false
                currentlyDownloadingModel = nil
                downloadTask = nil
                markModelDownloaded(model)
                ensureValidExtractionModelSelection()
                #endif
            } catch {
                finishFailedDownload(for: model, error: error)
            }
        }
    }

    /// Cancel the current download
    func cancelDownload() {
        let model = currentlyDownloadingModel
        AppLog.shared.mlx("[MLXDownload] Cancel requested by user for \(model?.displayName ?? "unknown model")")
        cancelledByUser = true
        stopProgressMonitor()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        downloadSpeedBytesPerSecond = nil
        isDownloadStalled = false
        currentlyDownloadingModel = nil
        // `downloadedBytes` is left for `finishFailedDownload` to report and reset.
        if let model {
            cleanupIncompleteDownload(for: model)
            removeDownloadedModel(model)
        }
        refreshModelStatus()
    }

    /// Tear down download state after a thrown error, keeping user cancellation out of the error UI.
    ///
    /// `URLSession`'s async APIs surface task cancellation as `URLError.cancelled` rather than
    /// `CancellationError`, so cancellation is identified by the flag `cancelDownload()` sets.
    private func finishFailedDownload(for model: MLXModelInfo, error: Error) {
        let wasCancelled = cancelledByUser || error is CancellationError || (error as? URLError)?.code == .cancelled

        if wasCancelled {
            AppLog.shared.mlx("[MLXDownload] Download cancelled for \(model.displayName) after \(formatSize(downloadedBytes))")
        } else {
            AppLog.shared.error("[MLXDownload] Download failed for \(model.displayName) after \(formatSize(downloadedBytes))", error: error, category: .mlx)
        }

        stopProgressMonitor()
        isDownloading = false
        downloadProgress = 0.0
        downloadedBytes = 0
        downloadSpeedBytesPerSecond = nil
        isDownloadStalled = false
        currentlyDownloadingModel = nil
        downloadTask = nil
        cleanupIncompleteDownload(for: model)
        removeDownloadedModel(model)
        if !wasCancelled {
            downloadError = error.localizedDescription
        }
        cancelledByUser = false
    }

    /// Check if a model is downloaded.
    /// This is a pure read — no side effects, safe to call from SwiftUI view bodies.
    func isModelDownloaded(_ model: MLXModelInfo) -> Bool {
        downloadedModelIds.contains(model.id)
    }

    /// Delete a downloaded model's cached files.
    ///
    /// Removes both the snapshot directory and the Hub blob store, which each hold a full copy
    /// of the weights — deleting only the snapshot would leave gigabytes stranded.
    func deleteModel(_ model: MLXModelInfo) {
        let directories = [huggingFaceCacheDirectory(for: model)] + Self.hubCacheRepositoryDirectories(for: model)
        var deletedAny = false

        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.removeItem(at: directory)
                deletedAny = true
            } catch {
                AppLog.shared.error("[MLXDownload] Failed to delete \(directory.lastPathComponent) for \(model.displayName)", error: error, category: .mlx)
            }
        }

        if deletedAny {
            removeDownloadedModel(model)
            ensureValidExtractionModelSelection()
            AppLog.shared.mlx("[MLXDownload] Deleted model cache for \(model.displayName)")
        }
        refreshModelStatus()
    }

    /// Select a model (update UserDefaults)
    func selectModel(_ model: MLXModelInfo) {
        selectedModelId = model.id
        UserDefaults.standard.set(model.id, forKey: MLXModelInfo.SettingsKeys.selectedModelId)
    }

    /// Select a downloaded vision-language model for on-device document extraction.
    func selectExtractionModel(_ model: MLXModelInfo) {
        guard model.modelType == .vlm, isModelDownloaded(model) else {
            AppLog.shared.mlx("[MLXDownload] Ignoring invalid extraction model selection: \(model.displayName)", level: .warning)
            return
        }
        selectedExtractionModelId = model.id
        UserDefaults.standard.set(model.id, forKey: MLXModelInfo.SettingsKeys.selectedExtractionModelId)
    }

    func clearExtractionModelSelection() {
        selectedExtractionModelId = nil
        UserDefaults.standard.removeObject(forKey: MLXModelInfo.SettingsKeys.selectedExtractionModelId)
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
        ensureValidExtractionModelSelection()
    }

    // MARK: - Storage Info

    /// Get the total storage used by downloaded models, counting both the snapshot directory
    /// and the Hub blob store that backs it.
    var totalStorageUsed: Int64 {
        var total: Int64 = 0
        for model in MLXModelInfo.allModels where downloadedModelIds.contains(model.id) {
            total += Self.directorySize(at: huggingFaceCacheDirectory(for: model))
            total += Self.hubBlobDirectories(for: model)
                .reduce(0) { $0 + Self.directorySize(at: $1) }
        }
        return total
    }

    /// Get downloaded models
    var downloadedModels: [MLXModelInfo] {
        MLXModelInfo.allModels.filter { downloadedModelIds.contains($0.id) }
    }

    var selectedModel: MLXModelInfo {
        MLXModelInfo.model(withId: selectedModelId) ?? MLXModelInfo.defaultModel
    }

    var selectedExtractionModel: MLXModelInfo? {
        guard let selectedExtractionModelId,
              let model = MLXModelInfo.model(withId: selectedExtractionModelId),
              model.modelType == .vlm,
              isModelDownloaded(model) else {
            return nil
        }
        return model
    }

    var downloadedVisionModels: [MLXModelInfo] {
        MLXModelInfo.visionModels.filter { downloadedModelIds.contains($0.id) }
    }

    @discardableResult
    func ensureValidExtractionModelSelection() -> MLXModelInfo? {
        if let selectedExtractionModel {
            return selectedExtractionModel
        }

        guard let firstVisionModel = downloadedVisionModels.first else {
            clearExtractionModelSelection()
            return nil
        }

        selectExtractionModel(firstVisionModel)
        return firstVisionModel
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

    // MARK: - Progress Monitoring

    /// Publish byte-level progress for the running download.
    ///
    /// The Hub reports snapshot progress in *files*, not bytes: a repo with seven files jumps
    /// straight to 3/7 once the small JSON files land, then creeps across a single unit for the
    /// entire multi-gigabyte weights file. That reads as "stuck at 43%". Measuring the bytes on
    /// disk instead gives a bar that actually tracks the download, and makes a real stall visible.
    private func startProgressMonitor(for model: MLXModelInfo) {
        progressMonitorTask?.cancel()
        let expectedBytes = model.estimatedSizeBytes

        progressMonitorTask = Task { @MainActor [weak self] in
            var lastBytes: Int64 = 0
            var lastSample = Date()
            var lastMovement = Date()
            var lastLog = Date.distantPast

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }

                let bytes = await Self.measureDownloadedBytes(for: model)
                let now = Date()
                let elapsed = now.timeIntervalSince(lastSample)

                if bytes > lastBytes {
                    if elapsed > 0 {
                        self.downloadSpeedBytesPerSecond = Double(bytes - lastBytes) / elapsed
                    }
                    lastMovement = now
                    self.isDownloadStalled = false
                } else if now.timeIntervalSince(lastMovement) > Self.stallThreshold {
                    self.downloadSpeedBytesPerSecond = nil
                    if !self.isDownloadStalled {
                        AppLog.shared.mlx("[MLXDownload] No bytes written for \(Int(Self.stallThreshold))s downloading \(model.displayName) — stalled at \(self.formatSize(bytes))", level: .warning)
                        self.isDownloadStalled = true
                    }
                }

                lastBytes = bytes
                lastSample = now

                self.downloadedBytes = bytes
                if bytes > 0, expectedBytes > 0 {
                    self.downloadProgress = min(Double(bytes) / Double(expectedBytes), 0.999)
                } else {
                    self.downloadProgress = self.reportedFraction.get()
                }

                if now.timeIntervalSince(lastLog) >= 15 {
                    lastLog = now
                    let speed = self.downloadSpeedBytesPerSecond.map { "\(self.formatSize(Int64($0)))/s" } ?? "stalled"
                    AppLog.shared.mlx("[MLXDownload] \(model.displayName): \(self.formatSize(bytes)) of \(self.formatSize(expectedBytes)) (\(speed))")
                }
            }
        }
    }

    private func stopProgressMonitor() {
        progressMonitorTask?.cancel()
        progressMonitorTask = nil
    }

    // MARK: - Private Helpers

    /// Get the HuggingFace Hub materialized snapshot directory for a model.
    /// MLX Swift's `defaultHubApi` uses cachesDirectory as downloadBase (not documentDirectory).
    /// HubApi.localRepoLocation then appends: models/<repoId>
    /// Uses .appending(component:) to match HubApi's URL construction.
    private nonisolated func huggingFaceCacheDirectory(for model: MLXModelInfo) -> URL {
        Self.cachesDirectory
            .appending(component: "models")
            .appending(component: model.huggingFaceId)
    }

    private nonisolated static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Hub cache roots used by swift-huggingface's `HubCache.default`.
    ///
    /// The package uses environment overrides first, then a sandbox cache on Apple apps. A
    /// non-sandboxed macOS build uses `~/.cache/huggingface/hub`, so include both possible
    /// defaults when reading or deleting an interrupted download.
    private nonisolated static func hubCacheRootDirectories() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var roots: [URL] = []

        func appendUnique(_ url: URL) {
            let normalized = url.standardizedFileURL
            if !roots.contains(normalized) {
                roots.append(normalized)
            }
        }

        if let override = environment["HF_HUB_CACHE"], !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            appendUnique(URL(fileURLWithPath: expanded))
        } else if let home = environment["HF_HOME"], !home.isEmpty {
            let expanded = NSString(string: home).expandingTildeInPath
            appendUnique(URL(fileURLWithPath: expanded).appending(component: "hub"))
        }

        appendUnique(
            cachesDirectory
                .appending(component: "huggingface")
                .appending(component: "hub")
        )
        appendUnique(
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appending(component: ".cache")
                .appending(component: "huggingface")
                .appending(component: "hub")
        )

        return roots
    }

    private nonisolated static func hubCacheRepositoryDirectories(for model: MLXModelInfo) -> [URL] {
        let repoDirectory = "models--" + model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
        return hubCacheRootDirectories().map { $0.appending(component: repoDirectory) }
    }

    private nonisolated static func hubBlobDirectories(for model: MLXModelInfo) -> [URL] {
        hubCacheRepositoryDirectories(for: model).map { $0.appending(component: "blobs") }
    }

    /// Bytes already on disk for a model, whether they are still landing in the blob store
    /// (including `.incomplete` partials) or have been copied into the snapshot directory.
    private nonisolated static func measureDownloadedBytes(for model: MLXModelInfo) async -> Int64 {
        let blobs = hubBlobDirectories(for: model)
            .map { directorySize(at: $0, includingHiddenFiles: true) }
            .max() ?? 0
        let snapshot = directorySize(
            at: cachesDirectory
                .appending(component: "models")
                .appending(component: model.huggingFaceId),
            includingHiddenFiles: true
        )
        return max(blobs, snapshot)
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
        isModelCacheValid(at: huggingFaceCacheDirectory(for: model))
    }

    private func isModelCacheValid(at cacheDir: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory)
        guard exists && isDirectory.boolValue else { return false }

        return directoryContainsRequiredArtifacts(at: cacheDir)
    }

    /// Recursively check for config.json and all weight shards named by an index file.
    /// Non-sharded models fall back to requiring at least one safetensors file.
    private func directoryContainsRequiredArtifacts(at directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        var hasConfig = false
        var hasSafetensors = false
        var indexFiles: [URL] = []
        var relativeFiles = Set<String>()
        let directoryPath = directory.standardizedFileURL.path

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            let filePath = fileURL.standardizedFileURL.path
            if filePath.hasPrefix(directoryPath + "/") {
                relativeFiles.insert(String(filePath.dropFirst(directoryPath.count + 1)))
            } else {
                relativeFiles.insert(filename)
            }

            if filename == "config.json" {
                hasConfig = true
            }

            if fileURL.pathExtension == "safetensors" {
                hasSafetensors = true
            }

            if filename.hasSuffix(".safetensors.index.json") {
                indexFiles.append(fileURL)
            }
        }

        guard hasConfig else { return false }
        guard !indexFiles.isEmpty else { return hasSafetensors }

        let relativeBasenames = Set(relativeFiles.map { URL(fileURLWithPath: $0).lastPathComponent })
        for indexFile in indexFiles {
            guard let data = try? Data(contentsOf: indexFile),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let weightMap = object["weight_map"] as? [String: String],
                  !weightMap.isEmpty else {
                continue
            }

            let shards = Set(weightMap.values)
            if shards.allSatisfy({
                relativeFiles.contains($0)
                    || relativeBasenames.contains(URL(fileURLWithPath: $0).lastPathComponent)
            }) {
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
    private nonisolated static func directorySize(at url: URL, includingHiddenFiles: Bool = false) -> Int64 {
        let options: FileManager.DirectoryEnumerationOptions = includingHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: options
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

// MARK: - Fraction Box

/// Thread-safe holder for the Hub's snapshot fraction, written from download threads and read
/// by the main-actor progress monitor.
private final class FractionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0

    func set(_ newValue: Double) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
