//
//  MLXModelDownloadManager.swift
//  HealthApp
//
//  Manages MLX model downloads via HuggingFace Hub integration
//

import Foundation
import SwiftUI

#if !targetEnvironment(simulator)
import HuggingFace
import MLXLMCommon
#endif

enum MLXDownloadPhase: Equatable {
    case connecting
    case downloading
    case waitingForData
    case retrying(attempt: Int)

    var title: String {
        switch self {
        case .connecting:
            return "Connecting to Hugging Face…"
        case .downloading:
            return "Receiving model bytes"
        case .waitingForData:
            return "Waiting for data"
        case .retrying(let attempt):
            return "Retrying connection (attempt \(attempt))…"
        }
    }

    var systemImage: String {
        switch self {
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .downloading:
            return "arrow.down.circle.fill"
        case .waitingForData:
            return "clock"
        case .retrying:
            return "arrow.clockwise"
        }
    }
}

private enum MLXDownloadTransferError: LocalizedError {
    case invalidResponse(file: String)
    case httpStatus(file: String, statusCode: Int)
    case incompleteFile(file: String, expectedBytes: Int64, actualBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let file):
            return "Hugging Face returned an invalid response for \(file)."
        case .httpStatus(let file, let statusCode):
            return "Hugging Face returned HTTP \(statusCode) for \(file)."
        case .incompleteFile(let file, let expectedBytes, let actualBytes):
            return "The download for \(file) ended at \(actualBytes) of \(expectedBytes) bytes."
        }
    }
}

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
    @Published var downloadPhase: MLXDownloadPhase = .connecting
    @Published var isDownloadStalled: Bool = false
    @Published var currentlyDownloadingModel: MLXModelInfo?
    @Published var downloadError: String?
    @Published var downloadedModelIds: Set<String> = []
    @Published var selectedModelId: String = MLXModelInfo.selectedModel.id
    @Published var selectedExtractionModelId: String? = MLXModelInfo.selectedExtractionModel?.id

    // MARK: - Private State

    private var downloadTask: Task<Void, Never>?
    private var progressMonitorTask: Task<Void, Never>?
    private var stallRetryTask: Task<Void, Never>?
    private var cancelledByUser = false
    private var activeDownloadID: UUID?
    private var automaticStallRetryCount = 0

    /// No byte progress for this long while downloading is surfaced as a stall.
    private nonisolated static let stallThreshold: TimeInterval = 60
    private nonisolated static let maxAutomaticStallRetries = 2
    /// MedGemma is published as three multi-GB weight shards. Keep all shards eligible to
    /// progress so a stalled CDN connection for one shard cannot block the remaining files.
    private nonisolated static let maxConcurrentFileDownloads = 3
    private nonisolated static let progressLogInterval: TimeInterval = 30
    /// Size of each ranged request when transferring a file. Small enough that a slice
    /// completes well inside `stallThreshold` on a slow connection (so the watchdog sees
    /// regular byte progress) and that the mapped slice never costs much memory, large
    /// enough that a multi-gigabyte shard does not need an excessive number of requests.
    private nonisolated static let downloadSliceBytes: Int64 = 4 * 1024 * 1024

    #if !targetEnvironment(simulator)
    /// The default URLSession can wait for connectivity and retain a dead connection longer
    /// than the UI's stall watchdog. Use a bounded, non-waiting session for Hub transfers.
    private nonisolated static let realtimeURLSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = stallThreshold
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpMaximumConnectionsPerHost = maxConcurrentFileDownloads + 1
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: configuration)
    }()

    private nonisolated static let realtimeHubClient = HuggingFace.HubClient(
        session: realtimeURLSession,
        cache: nil
    )
    #endif

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

        automaticStallRetryCount = 0
        stallRetryTask?.cancel()
        stallRetryTask = nil
        startDownloadAttempt(for: model)
    }

    private func startDownloadAttempt(for model: MLXModelInfo) {
        isDownloading = true
        downloadProgress = 0.0
        downloadedBytes = 0
        downloadSpeedBytesPerSecond = nil
        downloadPhase = .connecting
        isDownloadStalled = false
        currentlyDownloadingModel = model
        downloadError = nil
        cancelledByUser = false
        let downloadID = UUID()
        activeDownloadID = downloadID
        let progressBox = DownloadProgressBox()
        startProgressMonitor(for: model, progressBox: progressBox)

        downloadTask = Task {
            do {
                #if targetEnvironment(simulator)
                throw MLXOnDeviceError.simulatorNotSupported
                #else
                AppLog.shared.mlx("[MLXDownload] Starting download for \(model.displayName) (\(model.huggingFaceId)), expecting \(formatSize(model.estimatedSizeBytes)) across up to \(Self.maxConcurrentFileDownloads) files")

                let configuration = ModelConfiguration(
                    id: model.huggingFaceId,
                    extraEOSTokens: model.extraEOSTokens
                )
                // Download the weights only. Instantiating the model is the chat client's job,
                // and doing it here would pull the whole model into memory for no benefit.
                // HubClient reports byte-weighted parent progress, unlike the older MLX helper's
                // file-weighted progress (which can sit at 33% for an entire multi-GB shard).
                let modelDirectory = try await downloadModelWithRealtimeProgress(
                    model: model,
                    configuration: configuration,
                    progressBox: progressBox
                )

                // A cancellation can race the final filesystem validation. Do not let an old
                // task complete a new download or repopulate state after the user cancelled it.
                guard activeDownloadID == downloadID, !Task.isCancelled else { return }

                // MLXLMCommon treats an authorization failure as a local-only fallback.
                // Do not mark that fallback as downloaded unless the complete model is on disk;
                // MedGemma's index must resolve all three safetensors shards.
                guard isModelCacheValid(at: modelDirectory) else {
                    throw MLXOnDeviceError.modelDownloadIncomplete
                }

                guard activeDownloadID == downloadID, !Task.isCancelled else { return }

                AppLog.shared.mlx("[MLXDownload] Download complete for \(model.displayName)")

                stopProgressMonitor()
                isDownloading = false
                downloadProgress = 1.0
                downloadSpeedBytesPerSecond = nil
                isDownloadStalled = false
                currentlyDownloadingModel = nil
                downloadTask = nil
                activeDownloadID = nil
                automaticStallRetryCount = 0
                markModelDownloaded(model)
                ensureValidExtractionModelSelection()
                #endif
            } catch {
                finishFailedDownload(for: model, downloadID: downloadID, error: error)
            }
        }
    }

    /// Cancel the current download
    func cancelDownload() {
        let model = currentlyDownloadingModel
        let bytesAtCancellation = downloadedBytes
        AppLog.shared.mlx("[MLXDownload] Cancel requested by user for \(model?.displayName ?? "unknown model")")
        cancelledByUser = true
        stallRetryTask?.cancel()
        stallRetryTask = nil
        automaticStallRetryCount = 0
        activeDownloadID = nil
        stopProgressMonitor()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        downloadSpeedBytesPerSecond = nil
        downloadPhase = .connecting
        isDownloadStalled = false
        currentlyDownloadingModel = nil
        // Reset the visible byte count after cancellation.
        downloadedBytes = 0
        if let model {
            cleanupIncompleteDownload(for: model)
            removeDownloadedModel(model)
        }
        AppLog.shared.mlx("[MLXDownload] Download cancelled for \(model?.displayName ?? "unknown model") after \(formatSize(bytesAtCancellation))")
        cancelledByUser = false
        refreshModelStatus()
    }

    /// Tear down download state after a thrown error, keeping user cancellation out of the error UI.
    ///
    /// `URLSession`'s async APIs surface task cancellation as `URLError.cancelled` rather than
    /// `CancellationError`, so cancellation is identified by the flag `cancelDownload()` sets.
    private func finishFailedDownload(for model: MLXModelInfo, downloadID: UUID, error: Error) {
        guard activeDownloadID == downloadID else { return }

        let wasCancelled = cancelledByUser || error is CancellationError || (error as? URLError)?.code == .cancelled

        if !wasCancelled, retryDownloadAfterTransferFailure(for: model, error: error) {
            return
        }

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
        downloadPhase = .connecting
        isDownloadStalled = false
        currentlyDownloadingModel = nil
        downloadTask = nil
        activeDownloadID = nil
        stallRetryTask?.cancel()
        stallRetryTask = nil
        automaticStallRetryCount = 0
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

    private func formatTransferRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond > 0 else {
            return "waiting for byte progress"
        }

        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    #if !targetEnvironment(simulator)
    /// Download the model files directly to the MLX model directory. The Hub snapshot helper
    /// protects each ETag with an indefinitely blocking FileLock; when a cancelled URLSession
    /// task is still unwinding, a retry can wait on that lock forever before it receives a byte.
    /// Direct per-file transfers avoid that lock and keep resumable partial files beside the
    /// final artifacts.
    private func downloadModelWithRealtimeProgress(
        model: MLXModelInfo,
        configuration: ModelConfiguration,
        progressBox: DownloadProgressBox
    ) async throws -> URL {
        let repositoryParts = model.huggingFaceId.split(separator: "/", maxSplits: 1).map(String.init)
        guard repositoryParts.count == 2 else {
            throw MLXOnDeviceError.modelDownloadIncomplete
        }

        let repository = HuggingFace.Repo.ID(
            namespace: repositoryParts[0],
            name: repositoryParts[1]
        )

        AppLog.shared.mlx("[MLXDownload] Resolving file list for \(model.displayName)")
        let entries = try await Self.realtimeHubClient.listFiles(
            in: repository,
            kind: .model,
            revision: "main",
            recursive: true
        )
        .filter { entry in
            entry.type == .file && Self.isDownloadableModelFile(entry.path)
        }
        .sorted { left, right in
            (left.size ?? 0) > (right.size ?? 0)
        }

        guard !entries.isEmpty else {
            throw MLXOnDeviceError.modelDownloadIncomplete
        }

        let shardCount = entries.count(where: { $0.path.hasSuffix(".safetensors") })
        AppLog.shared.mlx(
            "[MLXDownload] Found \(entries.count) model files (\(shardCount) weight shards); direct streaming enabled"
        )

        let modelDirectory = configuration.modelDirectory(hub: defaultHubApi)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let fileSizes = Dictionary(uniqueKeysWithValues: entries.map { entry in
            (entry.path, max(Int64(entry.size ?? 0), 1))
        })
        progressBox.configure(fileSizes: fileSizes)

        for entry in entries {
            let destination = modelDirectory.appendingPathComponent(entry.path)
            let expectedBytes = Int64(entry.size ?? 0)
            if expectedBytes > 0, Self.fileSize(at: destination) == expectedBytes {
                progressBox.update(file: entry.path, completedBytes: expectedBytes)
            }
        }

        let bearerToken = await Self.realtimeHubClient.bearerToken
        try await downloadModelFilesConcurrently(
            entries,
            repository: repository,
            revision: "main",
            modelDirectory: modelDirectory,
            bearerToken: bearerToken,
            progressBox: progressBox
        )

        return modelDirectory
    }

    private func downloadModelFilesConcurrently(
        _ entries: [HuggingFace.Git.TreeEntry],
        repository: HuggingFace.Repo.ID,
        revision: String,
        modelDirectory: URL,
        bearerToken: String?,
        progressBox: DownloadProgressBox
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for entry in entries {
                while activeCount >= Self.maxConcurrentFileDownloads {
                    _ = try await group.next()
                    activeCount -= 1
                }

                group.addTask {
                    try await Self.downloadModelFile(
                        entry,
                        repository: repository,
                        revision: revision,
                        modelDirectory: modelDirectory,
                        bearerToken: bearerToken,
                        progressBox: progressBox
                    )
                }
                activeCount += 1
            }

            while activeCount > 0 {
                _ = try await group.next()
                activeCount -= 1
            }
        }
    }

    private nonisolated static func downloadModelFile(
        _ entry: HuggingFace.Git.TreeEntry,
        repository: HuggingFace.Repo.ID,
        revision: String,
        modelDirectory: URL,
        bearerToken: String?,
        progressBox: DownloadProgressBox
    ) async throws {
        let destination = modelDirectory.appendingPathComponent(entry.path)
        let partialDestination = destination.appendingPathExtension("incomplete")
        let expectedBytes = Int64(entry.size ?? 0)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if expectedBytes > 0, Self.fileSize(at: destination) == expectedBytes {
            progressBox.update(file: entry.path, completedBytes: expectedBytes)
            return
        }

        var resumeOffset = Self.fileSize(at: partialDestination)
        if expectedBytes > 0, resumeOffset >= expectedBytes {
            try? FileManager.default.removeItem(at: partialDestination)
            resumeOffset = 0
        }
        progressBox.update(file: entry.path, completedBytes: resumeOffset)

        if entry.path.hasSuffix(".safetensors") {
            let action = resumeOffset > 0 ? "Resuming" : "Opening"
            AppLog.shared.mlx(
                "[MLXDownload] \(action) shard \(entry.path) at \(resumeOffset) of \(expectedBytes) bytes"
            )
        }

        let fileURL = Self.realtimeHubClient.host
            .appendingPathComponent(repository.namespace)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("resolve")
            .appendingPathComponent(revision)
            .appendingPathComponent(entry.path)

        if resumeOffset == 0 {
            FileManager.default.createFile(atPath: partialDestination.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: partialDestination)
        defer { try? fileHandle.close() }
        // Drop anything past the resume point so a short partial write from a previous
        // attempt cannot leave a gap in the middle of the file.
        try fileHandle.truncate(atOffset: UInt64(resumeOffset))
        try fileHandle.seek(toOffset: UInt64(resumeOffset))

        var completedBytes = resumeOffset

        // Transfer in bounded byte ranges rather than iterating `URLSession.bytes`. A
        // per-byte `AsyncBytes` loop costs one async resumption per byte, which is
        // orders of magnitude slower than the network on a multi-gigabyte shard, and
        // `download(for:)` streams to a temporary file so a response that ignores the
        // Range header cannot buffer gigabytes in memory.
        while expectedBytes == 0 || completedBytes < expectedBytes {
            try Task.checkCancellation()

            var request = URLRequest(url: fileURL)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            if let bearerToken {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            }

            let sliceUpperBound = expectedBytes > 0
                ? min(completedBytes + Self.downloadSliceBytes, expectedBytes) - 1
                : completedBytes + Self.downloadSliceBytes - 1
            request.setValue("bytes=\(completedBytes)-\(sliceUpperBound)", forHTTPHeaderField: "Range")

            let (temporaryURL, response) = try await Self.realtimeURLSession.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw MLXDownloadTransferError.invalidResponse(file: entry.path)
            }

            // Nothing further to read: the previous slice already reached the end, or the
            // artifact is legitimately empty and its size was not advertised.
            if httpResponse.statusCode == 416, completedBytes > 0 || expectedBytes == 0 {
                try? FileManager.default.removeItem(at: temporaryURL)
                break
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw MLXDownloadTransferError.httpStatus(
                    file: entry.path,
                    statusCode: httpResponse.statusCode
                )
            }

            // Mapped rather than read into memory: if the server ignored the Range header
            // this file is the entire multi-gigabyte artifact. The temporary file is
            // removed only after the bytes have been written through.
            let sliceData = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            if httpResponse.statusCode != 206 {
                // The server ignored the Range header and sent the whole file, so this
                // single response is the complete artifact.
                try fileHandle.truncate(atOffset: 0)
                try fileHandle.seek(toOffset: 0)
                try fileHandle.write(contentsOf: sliceData)
                completedBytes = Int64(sliceData.count)
                progressBox.update(file: entry.path, completedBytes: completedBytes)
                break
            }

            guard !sliceData.isEmpty else { break }

            try fileHandle.write(contentsOf: sliceData)
            completedBytes += Int64(sliceData.count)
            progressBox.update(file: entry.path, completedBytes: completedBytes)
        }

        // Flush before the rename so the promoted file is complete on disk.
        try fileHandle.synchronize()

        if expectedBytes > 0, completedBytes != expectedBytes {
            throw MLXDownloadTransferError.incompleteFile(
                file: entry.path,
                expectedBytes: expectedBytes,
                actualBytes: completedBytes
            )
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partialDestination, to: destination)
        progressBox.update(file: entry.path, completedBytes: max(completedBytes, expectedBytes))
        if entry.path.hasSuffix(".safetensors") {
            AppLog.shared.mlx("[MLXDownload] Finished shard \(entry.path) (\(completedBytes) bytes)")
        }
    }

    /// Tokenizer artifacts that are not JSON. Gemma/MedGemma ship a SentencePiece
    /// `tokenizer.model`, and BPE tokenizers ship `merges.txt`/`vocab.txt`. These are matched
    /// by exact name so ordinary repo text (README.md, LICENSE.txt) is still skipped.
    private nonisolated static let auxiliaryTokenizerFiles: Set<String> = [
        "tokenizer.model",
        "spiece.model",
        "merges.txt",
        "vocab.txt",
        "vocab.bpe",
        "added_tokens.txt",
        "special_tokens_map.txt"
    ]

    private nonisolated static func isDownloadableModelFile(_ path: String) -> Bool {
        if path.hasSuffix(".safetensors") || path.hasSuffix(".json") || path.hasSuffix(".jinja") {
            return true
        }

        // `isModelCacheValid` only checks for config.json plus the weight shards, so a model
        // missing its tokenizer would still be marked downloaded and only fail at first chat.
        let fileName = (path as NSString).lastPathComponent
        return Self.auxiliaryTokenizerFiles.contains(fileName)
    }
    #endif

    // MARK: - Progress Monitoring

    /// Publish active-transfer progress for the running download.
    ///
    /// The per-file reporter is the source of truth for an active transfer. It includes bytes
    /// written to resumable `.incomplete` files; completed cache size is only a fallback while
    /// the repository file list is being fetched.
    private func startProgressMonitor(for model: MLXModelInfo, progressBox: DownloadProgressBox) {
        progressMonitorTask?.cancel()
        let expectedBytes = model.estimatedSizeBytes

        progressMonitorTask = Task { @MainActor [weak self] in
            var lastBytes: Int64 = 0
            var lastMovement = Date()
            var lastHubMovement = Date.distantPast
            var lastProgressLog = Date()
            var lastLoggedBytes: Int64 = 0
            var hasBaseline = false
            var isTrackingTransfer = false
            var lastSpeedSampleTime = Date()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }

                let cachedBytes = await Self.measureDownloadedBytes(for: model)
                let now = Date()
                let progress = progressBox.get()
                let hasReportedProgress = progress.totalUnitCount > 0
                let bytes = hasReportedProgress
                    ? max(0, progress.completedUnitCount)
                    : cachedBytes

                if hasReportedProgress, !isTrackingTransfer {
                    // Do not treat time spent resolving the repository file list as a stalled
                    // transfer. The watchdog starts when the direct file list is ready.
                    isTrackingTransfer = true
                    lastMovement = now
                    lastSpeedSampleTime = now
                }

                if !hasBaseline {
                    hasBaseline = true
                    lastBytes = bytes
                    lastLoggedBytes = bytes
                    lastSpeedSampleTime = now
                } else if bytes > lastBytes {
                    let elapsed = now.timeIntervalSince(lastSpeedSampleTime)
                    if lastBytes > 0, elapsed > 0 {
                        self.downloadSpeedBytesPerSecond = Double(bytes - lastBytes) / elapsed
                    }
                    self.downloadPhase = .downloading
                    lastBytes = bytes
                    lastSpeedSampleTime = now
                    lastMovement = now
                    self.isDownloadStalled = false
                } else if now.timeIntervalSince(lastMovement) > 5 {
                    // Never leave a stale 2 KB/s (or similar) callback visible while the
                    // underlying Progress has stopped moving.
                    self.downloadSpeedBytesPerSecond = nil
                    self.downloadPhase = .waitingForData
                }

                if progress.lastMeaningfulUpdate > lastHubMovement {
                    lastHubMovement = progress.lastMeaningfulUpdate
                    lastMovement = now
                    self.downloadPhase = .downloading
                    self.isDownloadStalled = false
                }

                if isTrackingTransfer, now.timeIntervalSince(lastMovement) > Self.stallThreshold {
                    self.downloadSpeedBytesPerSecond = nil
                    if !self.isDownloadStalled {
                        let progress = Int(self.downloadProgress * 100)
                        AppLog.shared.mlx("[MLXDownload] No byte progress for \(Int(Self.stallThreshold))s downloading \(model.displayName) — stalled at \(progress)% and \(self.formatSize(bytes)) downloaded", level: .warning)
                        self.isDownloadStalled = true
                        self.retryDownloadAfterStall(for: model)
                    }
                }

                self.downloadedBytes = bytes
                if hasReportedProgress {
                    self.downloadProgress = min(max(progress.fractionCompleted, 0), 0.999)
                } else if expectedBytes > 0, bytes > 0 {
                    self.downloadProgress = min(Double(bytes) / Double(expectedBytes), 0.999)
                } else {
                    self.downloadProgress = 0
                }

                if now.timeIntervalSince(lastProgressLog) >= Self.progressLogInterval,
                   hasBaseline,
                   bytes > lastLoggedBytes {
                    lastProgressLog = now
                    lastLoggedBytes = bytes
                    let progress = Int(self.downloadProgress * 100)
                    let speed = self.formatTransferRate(self.downloadSpeedBytesPerSecond)
                    AppLog.shared.mlx("[MLXDownload] \(model.displayName): \(progress)% realtime transfer · \(self.formatSize(bytes)) of \(self.formatSize(expectedBytes)) (\(speed))")
                }
            }
        }
    }

    /// Restart a transfer after a bounded period without Hub or filesystem movement.
    /// Completed shards and `.incomplete` files are intentionally preserved so the next attempt
    /// can skip finished files and resume partial shards.
    private func retryDownloadAfterStall(for model: MLXModelInfo) {
        guard isDownloading,
              currentlyDownloadingModel?.id == model.id,
              stallRetryTask == nil else {
            return
        }

        guard automaticStallRetryCount < Self.maxAutomaticStallRetries else {
            AppLog.shared.mlx("[MLXDownload] Giving up after \(Self.maxAutomaticStallRetries) stalled retries for \(model.displayName)", level: .warning)
            activeDownloadID = nil
            downloadTask?.cancel()
            downloadTask = nil
            stopProgressMonitor()
            isDownloading = false
            downloadProgress = 0.0
            downloadedBytes = 0
            downloadSpeedBytesPerSecond = nil
            downloadPhase = .connecting
            isDownloadStalled = false
            currentlyDownloadingModel = nil
            cleanupIncompleteDownload(for: model)
            removeDownloadedModel(model)
            downloadError = "Download stalled. Check your network connection and tap Download to retry."
            automaticStallRetryCount = 0
            refreshModelStatus()
            return
        }

        automaticStallRetryCount += 1
        let retryNumber = automaticStallRetryCount
        downloadPhase = .retrying(attempt: retryNumber)
        AppLog.shared.mlx("[MLXDownload] Retrying stalled transfer for \(model.displayName) (attempt \(retryNumber)/\(Self.maxAutomaticStallRetries))", level: .warning)

        // Invalidate this attempt before cancelling it. Its eventual cancellation callback must
        // not clear or overwrite state belonging to the retry attempt.
        let previousTask = downloadTask
        activeDownloadID = nil
        previousTask?.cancel()
        downloadTask = nil
        stopProgressMonitor()

        stallRetryTask = Task { @MainActor [weak self] in
            // HubClient's cache uses an indefinitely blocking file lock. Do not start the retry
            // until the cancelled task has unwound and released any lock it acquired.
            if let previousTask {
                await previousTask.value
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  let self,
                  self.isDownloading,
                  self.currentlyDownloadingModel?.id == model.id else {
                return
            }

            self.stallRetryTask = nil
            self.startDownloadAttempt(for: model)
        }
    }

    /// Retry a transfer that failed before the stall watchdog had to intervene. This is
    /// especially important when one of several concurrent shards hits URLSession's request
    /// inactivity timeout: sibling transfers are cancelled, but their completed files and partial
    /// byte ranges remain reusable by the next attempt.
    private func retryDownloadAfterTransferFailure(for model: MLXModelInfo, error: Error) -> Bool {
        guard isDownloading,
              currentlyDownloadingModel?.id == model.id,
              stallRetryTask == nil,
              automaticStallRetryCount < Self.maxAutomaticStallRetries else {
            return false
        }

        automaticStallRetryCount += 1
        let retryNumber = automaticStallRetryCount
        let reason = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
        downloadPhase = .retrying(attempt: retryNumber)
        isDownloadStalled = false
        AppLog.shared.mlx(
            "[MLXDownload] Transfer error for \(model.displayName); retrying (attempt \(retryNumber)/\(Self.maxAutomaticStallRetries)): \(reason)",
            level: .warning
        )

        // Invalidate this attempt before cancelling it. Its cancellation callback must not clear
        // state belonging to the retry attempt.
        let previousTask = downloadTask
        activeDownloadID = nil
        previousTask?.cancel()
        downloadTask = nil
        stopProgressMonitor()

        stallRetryTask = Task { @MainActor [weak self] in
            if let previousTask {
                await previousTask.value
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  let self,
                  self.isDownloading,
                  self.currentlyDownloadingModel?.id == model.id else {
                return
            }

            self.stallRetryTask = nil
            self.startDownloadAttempt(for: model)
        }
        return true
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

    /// Delete a model cache that will not be completed.
    ///
    /// Every caller is a terminal path — the user cancelled, or the automatic retries were
    /// exhausted. Automatic retries deliberately do *not* call this, which is what preserves
    /// completed shards and `.incomplete` files for the next attempt. Once the download is
    /// over, the model is no longer in `downloadedModelIds`, so `totalStorageUsed` stops
    /// counting these bytes and no UI can reclaim them: keeping them would strand multiple
    /// gigabytes with no way for the user to get the space back.
    private func cleanupIncompleteDownload(for model: MLXModelInfo) {
        let cacheDir = huggingFaceCacheDirectory(for: model)
        guard FileManager.default.fileExists(atPath: cacheDir.path), !isModelCacheValid(for: model) else {
            return
        }

        let reclaimedBytes = Self.directorySize(at: cacheDir)

        do {
            try FileManager.default.removeItem(at: cacheDir)
            AppLog.shared.mlx(
                "[MLXDownload] Removed incomplete cache for \(model.displayName), reclaiming \(formatSize(reclaimedBytes))"
            )
        } catch {
            AppLog.shared.mlx(
                "[MLXDownload] Failed to remove incomplete cache for \(model.displayName): \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return 0
        }
        return Int64(size)
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

// MARK: - Download Progress Box

private struct DownloadProgressSnapshot: Sendable {
    let fractionCompleted: Double
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let lastMeaningfulUpdate: Date
}

/// Thread-safe holder for direct per-file progress, written from transfer tasks and read by the
/// main-actor progress monitor. Progress is weighted by the repository's actual file sizes.
private final class DownloadProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fileSizes: [String: Int64] = [:]
    private var completedByFile: [String: Int64] = [:]
    private var snapshot = DownloadProgressSnapshot(
        fractionCompleted: 0,
        completedUnitCount: 0,
        totalUnitCount: 0,
        lastMeaningfulUpdate: .distantPast
    )

    func configure(fileSizes: [String: Int64]) {
        lock.lock()
        self.fileSizes = fileSizes
        completedByFile = Dictionary(uniqueKeysWithValues: fileSizes.keys.map { ($0, 0) })
        let totalUnitCount = max(fileSizes.values.reduce(0, +), 1)
        snapshot = DownloadProgressSnapshot(
            fractionCompleted: 0,
            completedUnitCount: 0,
            totalUnitCount: totalUnitCount,
            lastMeaningfulUpdate: .distantPast
        )
        lock.unlock()
    }

    func update(file: String, completedBytes: Int64) {
        lock.lock()
        defer { lock.unlock() }

        guard let fileSize = fileSizes[file] else { return }
        let cappedBytes = min(max(completedBytes, 0), fileSize)
        let previousBytes = completedByFile[file, default: 0]
        guard cappedBytes > previousBytes else { return }

        completedByFile[file] = cappedBytes
        let completedUnitCount = completedByFile.values.reduce(0, +)
        let totalUnitCount = max(fileSizes.values.reduce(0, +), 1)
        snapshot = DownloadProgressSnapshot(
            fractionCompleted: min(Double(completedUnitCount) / Double(totalUnitCount), 1),
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            lastMeaningfulUpdate: Date()
        )
    }

    func get() -> DownloadProgressSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}
