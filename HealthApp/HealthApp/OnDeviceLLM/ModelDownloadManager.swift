//
//  ModelDownloadManager.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.bisonhealth.ai", category: "ModelDownload")

@MainActor
class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    @Published var downloadStates: [String: ModelDownloadState] = [:]
    @Published var networkType: NWInterface.InterfaceType?
    @Published var isConnected: Bool = false

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var urlSession: URLSession!
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bisonhealth.networkMonitor")

    override private init() {
        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: "com.bisonhealth.modeldownload")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        setupNetworkMonitoring()
        loadDownloadedModels()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied

                if let interface = path.availableInterfaces.first {
                    self?.networkType = interface.type
                } else {
                    self?.networkType = nil
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    var isOnWiFi: Bool {
        networkType == .wifi
    }

    var isOnCellular: Bool {
        networkType == .cellular
    }

    // MARK: - Model Storage

    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("OnDeviceLLM/Models")

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    func modelFilePath(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) -> URL {
        let filename = "\(model.name)-\(quantization.rawValue).gguf"
        return modelsDirectory.appendingPathComponent(filename)
    }

    // MARK: - Download State Management

    private func downloadKey(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) -> String {
        "\(model.id)-\(quantization.rawValue)"
    }

    private func loadDownloadedModels() {
        let downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()

        for downloadedModel in downloadedModels {
            let key = "\(downloadedModel.modelID)-\(downloadedModel.quantization.rawValue)"
            if FileManager.default.fileExists(atPath: downloadedModel.filePath) {
                downloadStates[key] = .downloaded(model: downloadedModel)
            } else {
                // File missing, remove from downloaded list
                logger.warning("Downloaded model file missing: \(downloadedModel.filePath)")
            }
        }

        // Clean up any orphaned entries
        var validModels = downloadedModels.filter { FileManager.default.fileExists(atPath: $0.filePath) }
        if validModels.count != downloadedModels.count {
            OnDeviceLLMConfig.saveDownloadedModels(validModels)
        }
    }

    func isModelDownloaded(model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) -> Bool {
        let key = downloadKey(for: model, quantization: quantization)
        if case .downloaded = downloadStates[key] {
            return true
        }
        return false
    }

    // MARK: - Model Download

    func downloadModel(_ model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization, allowCellular: Bool = false) async throws {
        let key = downloadKey(for: model, quantization: quantization)

        // Check network type
        if !allowCellular && isOnCellular {
            throw OnDeviceLLMError.cellularNotAllowed
        }

        // Check if already downloading
        if case .downloading = downloadStates[key] {
            logger.info("Model already downloading: \(key)")
            return
        }

        // Check storage
        try checkStorageSpace(for: quantization)

        // Build download URL
        let downloadURL = try buildDownloadURL(for: model, quantization: quantization)

        logger.info("Starting download: \(downloadURL.absoluteString)")

        downloadStates[key] = .downloading(progress: 0.0)

        let downloadTask = urlSession.downloadTask(with: downloadURL)
        downloadTasks[key] = downloadTask
        downloadTask.resume()
    }

    private func buildDownloadURL(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) throws -> URL {
        // HuggingFace GGUF download URL format
        // https://huggingface.co/{repo}/resolve/main/{filename}
        let filename = "\(model.name)-\(quantization.rawValue).gguf"
        let urlString = "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(filename)"

        guard let url = URL(string: urlString) else {
            throw OnDeviceLLMError.downloadFailed("Invalid download URL")
        }

        return url
    }

    private func checkStorageSpace(for quantization: OnDeviceLLMQuantization) throws {
        // Estimate required space based on quantization
        let estimatedSize: Int64
        switch quantization {
        case .q4_K_M: estimatedSize = 2_500_000_000  // 2.5 GB
        case .q5_K_M: estimatedSize = 3_000_000_000  // 3.0 GB
        case .q8_0: estimatedSize = 4_000_000_000    // 4.0 GB
        }

        // Get available storage
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attributes[.systemFreeSize] as? Int64 {
            if freeSize < estimatedSize {
                throw OnDeviceLLMError.insufficientStorage(required: estimatedSize, available: freeSize)
            }
        }
    }

    // MARK: - Download Control

    func cancelDownload(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) {
        let key = downloadKey(for: model, quantization: quantization)

        if let task = downloadTasks[key] {
            task.cancel()
            downloadTasks.removeValue(forKey: key)
            downloadStates[key] = .notDownloaded
            logger.info("Cancelled download: \(key)")
        }
    }

    func pauseDownload(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) {
        let key = downloadKey(for: model, quantization: quantization)

        if let task = downloadTasks[key] {
            task.cancel(byProducingResumeData: { resumeData in
                // Store resume data for later
                if let data = resumeData {
                    UserDefaults.standard.set(data, forKey: "resumeData-\(key)")
                }
            })
            downloadStates[key] = .paused(progress: 0.0)
            logger.info("Paused download: \(key)")
        }
    }

    func deleteModel(_ model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) throws {
        let key = downloadKey(for: model, quantization: quantization)
        let filePath = modelFilePath(for: model, quantization: quantization)

        // Delete file
        if FileManager.default.fileExists(atPath: filePath.path) {
            try FileManager.default.removeItem(at: filePath)
            logger.info("Deleted model file: \(filePath.path)")
        }

        // Update state
        downloadStates[key] = .notDownloaded

        // Update downloaded models list
        var downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()
        downloadedModels.removeAll { $0.modelID == model.id && $0.quantization == quantization }
        OnDeviceLLMConfig.saveDownloadedModels(downloadedModels)
    }

    func deleteAllModels() throws {
        let downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()

        for downloadedModel in downloadedModels {
            if FileManager.default.fileExists(atPath: downloadedModel.filePath) {
                try FileManager.default.removeItem(atPath: downloadedModel.filePath)
            }
        }

        downloadStates.removeAll()
        OnDeviceLLMConfig.saveDownloadedModels([])
        logger.info("Deleted all models")
    }

    // MARK: - Storage Info

    var totalStorageUsed: Int64 {
        let downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()
        return downloadedModels.reduce(0) { $0 + $1.fileSize }
    }

    var totalStorageUsedFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalStorageUsed)
    }
}

// MARK: - Download State

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(model: DownloadedModel)
    case failed(error: String)
    case paused(progress: Double)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }

    var progress: Double {
        switch self {
        case .downloading(let progress), .paused(let progress):
            return progress
        case .downloaded:
            return 1.0
        default:
            return 0.0
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let originalURL = downloadTask.originalRequest?.url,
                  let filename = originalURL.lastPathComponent.removingPercentEncoding else {
                logger.error("Failed to get filename from download task")
                return
            }

            // Parse model info from filename
            // Format: {model-name}-{quantization}.gguf
            let components = filename.replacingOccurrences(of: ".gguf", with: "").components(separatedBy: "-")
            guard components.count >= 2,
                  let quantization = OnDeviceLLMQuantization(rawValue: components.last!) else {
                logger.error("Failed to parse model info from filename: \(filename)")
                return
            }

            // Find matching model
            let modelName = components.dropLast().joined(separator: "-")
            guard let model = OnDeviceLLMModel.availableModels.first(where: { $0.name == modelName }) else {
                logger.error("Failed to find model for name: \(modelName)")
                return
            }

            let key = downloadKey(for: model, quantization: quantization)
            let destinationPath = modelFilePath(for: model, quantization: quantization)

            do {
                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }

                // Move downloaded file to destination
                try FileManager.default.moveItem(at: location, to: destinationPath)

                // Get file size
                let attributes = try FileManager.default.attributesOfItem(atPath: destinationPath.path)
                let fileSize = attributes[.size] as? Int64 ?? 0

                // Validate file size (should be at least 500MB for a valid model)
                if fileSize < 500_000_000 {
                    try FileManager.default.removeItem(at: destinationPath)
                    downloadStates[key] = .failed(error: "Downloaded file too small, may be corrupted")
                    logger.error("Downloaded model file too small: \(fileSize) bytes")
                    return
                }

                // Create downloaded model record
                let downloadedModel = DownloadedModel(
                    id: UUID().uuidString,
                    modelID: model.id,
                    quantization: quantization,
                    filePath: destinationPath.path,
                    fileSize: fileSize,
                    downloadDate: Date()
                )

                // Update state
                downloadStates[key] = .downloaded(model: downloadedModel)

                // Save to persistent storage
                var downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()
                downloadedModels.append(downloadedModel)
                OnDeviceLLMConfig.saveDownloadedModels(downloadedModels)

                downloadTasks.removeValue(forKey: key)

                logger.info("Successfully downloaded model: \(model.displayName) (\(quantization.rawValue))")

            } catch {
                downloadStates[key] = .failed(error: error.localizedDescription)
                logger.error("Failed to save downloaded model: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            guard let originalURL = downloadTask.originalRequest?.url,
                  let filename = originalURL.lastPathComponent.removingPercentEncoding else {
                return
            }

            let components = filename.replacingOccurrences(of: ".gguf", with: "").components(separatedBy: "-")
            guard components.count >= 2,
                  let quantization = OnDeviceLLMQuantization(rawValue: components.last!) else {
                return
            }

            let modelName = components.dropLast().joined(separator: "-")
            guard let model = OnDeviceLLMModel.availableModels.first(where: { $0.name == modelName }) else {
                return
            }

            let key = downloadKey(for: model, quantization: quantization)
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0

            downloadStates[key] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error as? NSError {
                guard let originalURL = task.originalRequest?.url,
                      let filename = originalURL.lastPathComponent.removingPercentEncoding else {
                    return
                }

                let components = filename.replacingOccurrences(of: ".gguf", with: "").components(separatedBy: "-")
                guard components.count >= 2,
                      let quantization = OnDeviceLLMQuantization(rawValue: components.last!) else {
                    return
                }

                let modelName = components.dropLast().joined(separator: "-")
                guard let model = OnDeviceLLMModel.availableModels.first(where: { $0.name == modelName }) else {
                    return
                }

                let key = downloadKey(for: model, quantization: quantization)

                // Check if it's a cancellation
                if error.code == NSURLErrorCancelled {
                    downloadStates[key] = .notDownloaded
                    logger.info("Download cancelled: \(key)")
                } else {
                    downloadStates[key] = .failed(error: error.localizedDescription)
                    logger.error("Download failed: \(key) - \(error.localizedDescription)")
                }

                downloadTasks.removeValue(forKey: key)
            }
        }
    }
}
