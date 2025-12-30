import Foundation
import UIKit
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - MLX Client

/// Client for running local LLMs using Apple's MLX framework
/// All operations run on MainActor to prevent Metal background execution errors
@MainActor
class MLXClient: ObservableObject, AIProviderInterface {

    // MARK: - Shared Instance
    static let shared = MLXClient()

    // MARK: - Published Properties
    @Published var isConnected: Bool = false
    @Published var connectionStatus: OllamaConnectionStatus = .disconnected
    @Published var lastError: Error?
    @Published var isLoading: Bool = false
    @Published var currentModelId: String?
    @Published var downloadedModelIds: Set<String> = []

    // MARK: - Private Properties
    private var chatEngine: ChatEngine?
    private var loadedModel: ModelContext?  // Store model separately for reuse
    private var currentConfig: MLXGenerationConfig = .default
    private let logger = Logger.shared
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isAppActive: Bool = true
    private var activeStreamingTask: Task<Void, Error>?

    // GPU Initialization State
    // Note: We need both pieces of state because:
    // - gpuInitializationTask: Represents the async initialization work (await its completion)
    // - isGPUInitialized: Represents the result (success/failure) - can't be derived from Task<Void, Never>
    // Both are MainActor-isolated, preventing race conditions
    // Using implicitly unwrapped optional to allow deferred initialization after self is fully initialized
    private var gpuInitializationTask: Task<Void, Never>!
    private var isGPUInitialized: Bool = false

    // Reduced from 2GB to 256MB to prevent Jetsam (OOM) crashes
    // The cache sits ON TOP of the model weights (~2GB). 
    // A 2GB cache + 2GB model = 4GB+ baseline, which kills the app.
    private static let gpuCacheLimit: UInt64 = 256 * 1024 * 1024  // 256MB GPU cache
    private static let backgroundCancellationDelay: UInt64 = 50_000_000 // 50ms delay before GPU cache clear

    // Idle resource management
    private var lastActivityTime: Date = Date()
    private var idleCleanupTask: Task<Void, Never>?
    // modelUnloadTask removed - model stays loaded
    private static let idleCleanupDelay: TimeInterval = 30.0 // Clear GPU cache after 30 seconds of inactivity
    // modelUnloadDelay removed

    // Conversation tracking
    private var currentConversationId: UUID?
    private var conversationTokenCount: Int = 0

    // Loading lock to prevent concurrent model loads
    private var isLoadingModel: Bool = false

    // MARK: - Initialization
    private init() {
        // Initialize GPU on MainActor to ensure Metal resources are properly bound
        // Task captures self implicitly - safe because it executes after initialization completes
        gpuInitializationTask = Task { @MainActor in
            let cacheLimit = Self.gpuCacheLimit
            // MLX.GPU.set is not a throwing function, so no try-catch needed
            MLX.GPU.set(cacheLimit: Int(cacheLimit))

            // Verify initialization by checking GPU memory stats
            let activeMemory = GPU.activeMemory
            let cacheMemory = GPU.cacheMemory

            if activeMemory >= 0 && cacheMemory >= 0 {
                logger.info("🔧 MLX initialized with \(cacheLimit / 1024 / 1024)MB GPU cache")
                logger.debug("📊 GPU verification - Active: \(activeMemory / 1024 / 1024)MB, Cache: \(cacheMemory / 1024 / 1024)MB")
                isGPUInitialized = true
            } else {
                logger.error("❌ GPU initialization verification failed - memory stats unavailable")
                isGPUInitialized = false
            }

            // Setup lifecycle observers after GPU is fully initialized
            // This avoids race condition where app could background during GPU init
            setupLifecycleObservers()

            // Scan for downloaded models
            scanDownloadedModels()
        }
    }

    /// Scan for downloaded models by loading persisted list
    /// Since MLX manages its own cache internally, we track successfully loaded models
    func scanDownloadedModels() {
        // Load persisted list of downloaded models from UserDefaults
        if let savedModels = UserDefaults.standard.array(forKey: "MLXDownloadedModels") as? [String] {
            downloadedModelIds = Set(savedModels)
        } else {
            downloadedModelIds = Set()
        }
        logger.info("📦 Found \(downloadedModelIds.count) downloaded MLX models: \(downloadedModelIds)")
    }

    /// Persist the downloaded models list to UserDefaults
    private func saveDownloadedModels() {
        UserDefaults.standard.set(Array(downloadedModelIds), forKey: "MLXDownloadedModels")
    }

    deinit {
        lifecycleObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        idleCleanupTask?.cancel()
    }

    // MARK: - GPU Management

    /// Retry GPU initialization if it failed
    /// This can be called if GPU initialization fails and you want to retry
    func retryGPUInitialization() async {
        guard !isGPUInitialized else {
            logger.info("ℹ️ GPU already initialized, skipping retry")
            return
        }

        logger.info("🔄 Retrying GPU initialization...")
        let cacheLimit = Self.gpuCacheLimit
        MLX.GPU.set(cacheLimit: Int(cacheLimit))

        // Verify initialization by checking GPU memory stats
        // If GPU is working, these values should be non-negative
        let activeMemory = GPU.activeMemory
        let cacheMemory = GPU.cacheMemory

        if activeMemory >= 0 && cacheMemory >= 0 {
            logger.info("🔧 MLX initialized with \(cacheLimit / 1024 / 1024)MB GPU cache")
            logger.info("📊 GPU verification - Active: \(activeMemory / 1024 / 1024)MB, Cache: \(cacheMemory / 1024 / 1024)MB")
            isGPUInitialized = true
        } else {
            logger.error("❌ GPU initialization verification failed - memory stats unavailable")
            isGPUInitialized = false
        }
    }

    // MARK: - Lifecycle Management

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default

        let resignActiveObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillResignActive()
            }
        }

        let backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleDidEnterBackground()
            }
        }

        let foregroundObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidBecomeActive()
            }
        }

        let memoryWarningObserver = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }

        lifecycleObservers.append(contentsOf: [resignActiveObserver, backgroundObserver, foregroundObserver, memoryWarningObserver])
    }

    private func handleWillResignActive() {
        logger.info("⚠️ App resigning active state - preparing to cancel streaming")
        isAppActive = false
        // Don't clear cache yet, just set state
    }

    private func handleDidEnterBackground() async {
        logger.warning("📴 App entered background - cancelling MLX streaming to avoid Metal errors")
        isAppActive = false
        cancelActiveStreaming(reason: "App entered background")

        // Wait briefly for cancellation to complete before clearing cache
        try? await Task.sleep(nanoseconds: Self.backgroundCancellationDelay)

        // Only clear cache if still in background (prevents race condition)
        if !isAppActive {
            GPU.clearCache()
            // Sync GPU to ensure cleanup completes
            eval(MLXArray(0))
            logger.info("🗑️ GPU cache cleared after background transition")
        } else {
            logger.info("⏩ Skipped cache clear - app became active during transition")
        }
    }

    private func handleDidBecomeActive() {
        logger.info("▶️ App became active - MLX streaming enabled")
        isAppActive = true
        // Only schedule idle cleanup if a model is currently loaded
        if loadedModel != nil {
            scheduleIdleCleanup()
        }
    }

    private func handleMemoryWarning() {
        logger.warning("⚠️ Received memory warning - aggressively clearing MLX cache")
        GPU.clearCache()
        // Force synchronization to ensure memory is actually freed
        Stream.gpu.synchronize()
        logMemoryStats(label: "After Memory Warning")
    }

    private func cancelActiveStreaming(reason: String) {
        guard let task = activeStreamingTask else { return }
        logger.warning("🛑 Cancelling active MLX streaming task (\(reason))")
        task.cancel()
        activeStreamingTask = nil
    }

    // MARK: - Idle Resource Management

    /// Schedule one-stage cleanup: cache clear at 30s
    /// This reduces GPU/CPU usage progressively as inactivity continues
    /// NOTE: Stage 2 (Model Unload) has been removed to keep the model loaded indefinitely
    /// until the user explicitly changes the AI provider or model.
    private func scheduleIdleCleanup() {
        // Cancel any existing cleanup tasks
        idleCleanupTask?.cancel()
        // modelUnloadTask is deprecated/removed

        // Don't schedule cleanup if no model is loaded
        guard loadedModel != nil else {
            logger.debug("⏩ Skipping idle cleanup scheduling - no model loaded")
            return
        }

        // Update last activity time
        lastActivityTime = Date()

        // Stage 1: Clear GPU cache after 30 seconds (keep model loaded)
        idleCleanupTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Wait for idle period
            try? await Task.sleep(nanoseconds: UInt64(Self.idleCleanupDelay * 1_000_000_000))

            // Check if still idle, task wasn't cancelled, and model still loaded
            guard !Task.isCancelled, self.loadedModel != nil else { return }

            // Don't cleanup if actively streaming
            guard self.activeStreamingTask == nil else {
                logger.debug("⏩ Skipping idle cleanup - streaming is active")
                return
            }

            let timeSinceLastActivity = Date().timeIntervalSince(self.lastActivityTime)
            if timeSinceLastActivity >= Self.idleCleanupDelay {
                logger.info("🧹 MLX Stage 1: Cleaning GPU cache after \(Int(timeSinceLastActivity))s of inactivity")
                logMemoryStats(label: "Before Idle Cleanup")

                // Clear GPU cache to reduce GPU power usage
                // Keep the model loaded for quick resumption
                GPU.clearCache()

                logMemoryStats(label: "After Idle Cleanup")
                logger.info("✅ MLX Stage 1 complete - GPU cache cleared, model still loaded")
            }
        }
    }

    /// Mark activity to prevent idle cleanup and model unload
    private func markActivity() {
        lastActivityTime = Date()
        scheduleIdleCleanup()
    }

    // MARK: - Memory Monitoring

    /// Log current GPU memory usage for debugging
    private func logMemoryStats(label: String) {
        let activeMemory = GPU.activeMemory
        let cacheMemory = GPU.cacheMemory
        let peakMemory = GPU.peakMemory

        let activeMB = Double(activeMemory) / 1024 / 1024
        let cacheMB = Double(cacheMemory) / 1024 / 1024
        let peakMB = Double(peakMemory) / 1024 / 1024

        logger.info("📊 [\(label)] GPU Memory - Active: \(String(format: "%.1f", activeMB))MB, Cache: \(String(format: "%.1f", cacheMB))MB, Peak: \(String(format: "%.1f", peakMB))MB")
    }

    // MARK: - AIProviderInterface

    func testConnection() async throws -> Bool {
        // For MLX, "connection" means having a model loaded and ready
        connectionStatus = .connecting

        if chatEngine != nil {
            connectionStatus = .connected
            isConnected = true
            return true
        } else {
            connectionStatus = .disconnected
            isConnected = false
            return false
        }
    }

    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        // MLX doesn't support one-off generation due to memory constraints
        // For title generation, use the dedicated generateTitle() method
        throw MLXError.invalidConfiguration
    }

    /// Generate a conversation title based on the first exchange
    /// This resets the session first to get a clean state, then generates the title
    /// - Parameters:
    ///   - userMessage: The first message from the user
    ///   - assistantResponse: The first response from the assistant
    /// - Returns: A generated title (max 5 words)
    func generateTitle(userMessage: String, assistantResponse: String) async throws -> String {
        logger.info("🏷️ Generating conversation title using MLX")

        guard chatEngine != nil else {
            logger.warning("⚠️ No active chat engine for title generation")
            throw MLXError.invalidConfiguration
        }

        // Reset the engine to ensure clean state for title generation
        logger.info("🔄 Resetting engine before title generation")
        try await resetSession()

        guard let engine = chatEngine else {
            logger.error("❌ Engine lost after reset")
            throw MLXError.invalidConfiguration
        }

        // Create a concise prompt for title generation
        let titlePrompt = """
        Based on this conversation, generate a short title that captures the main topic. \
        The title must be exactly 5 words or less. Do not use quotes. Just output the title.

        User: \(userMessage.prefix(200))
        Assistant: \(assistantResponse.prefix(200))

        Title:
        """

        logger.debug("🏷️ Title generation prompt: \(titlePrompt)")

        do {
            var generatedText = ""
            var tokenCount = 0
            let maxTokens = 20  // Very short - we only need a few words

            // Stream the title generation (but collect the full result)
            for try await token in engine.streamResponse(to: titlePrompt, maxTokens: maxTokens) {
                try Task.checkCancellation()

                guard isAppActive else {
                    logger.warning("🛑 Title generation cancelled - app moved to background")
                    throw CancellationError()
                }

                tokenCount += 1
                generatedText += token

                // Stop after getting enough tokens for a title
                if tokenCount >= maxTokens {
                    logger.debug("🏷️ Reached max tokens for title generation")
                    break
                }

                // Stop at newline (title should be single line)
                if generatedText.contains("\n") {
                    logger.debug("🏷️ Detected newline, stopping title generation")
                    break
                }
            }

            logger.info("🏷️ Generated title text (\(tokenCount) tokens): '\(generatedText)'")

            // Clean up the generated title
            var title = generatedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")

            // Remove end-of-turn tokens if present
            title = title.replacingOccurrences(of: "<end_of_turn>", with: "")
            title = title.replacingOccurrences(of: "<|eot_id|>", with: "")
            title = title.replacingOccurrences(of: "</s>", with: "")
            title = title.replacingOccurrences(of: "<|end|>", with: "")  // Phi-3 template
            title = title.replacingOccurrences(of: "<|assistant|>", with: "")  // Strip role tags too
            title = title.replacingOccurrences(of: "<|user|>", with: "")
            title = title.replacingOccurrences(of: "<|system|>", with: "")
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove quotes if present
            if title.hasPrefix("\"") && title.hasSuffix("\"") {
                title = String(title.dropFirst().dropLast())
            }
            if title.hasPrefix("'") && title.hasSuffix("'") {
                title = String(title.dropFirst().dropLast())
            }

            // Limit to 5 words as requested
            let words = title.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if words.count > 5 {
                title = words.prefix(5).joined(separator: " ")
            }

            // Ensure title is reasonable
            if title.isEmpty || title.count > 50 {
                logger.warning("⚠️ Generated title is invalid (empty or too long), using default")
                // Reset again to clear title generation attempt
                try await resetSession()
                return "New Conversation"
            }

            logger.info("✅ Final title: '\(title)'")

            // Reset the session again to clear the title generation interaction
            // This ensures the next user message starts with a fresh session
            logger.info("🔄 Resetting session after title generation to prepare for next message")
            try await resetSession()

            return title

        } catch {
            logger.error("❌ Title generation failed", error: error)
            // Reset session even on failure to keep state clean for next message
            try? await resetSession()
            throw MLXError.generationFailed("Title generation failed: \(error.localizedDescription)")
        }
    }

    func getCapabilities() async throws -> AICapabilities {
        return AICapabilities(
            supportedModels: currentModelId.map { [$0] } ?? [],
            maxTokens: currentConfig.maxTokens,
            supportsStreaming: true,
            supportsImages: false, // Text-only for now
            supportsDocuments: true,
            supportedLanguages: ["en"] // MedGemma primarily English
        )
    }

    func updateConfiguration(_ config: AIProviderConfig) async throws {
        // MLX doesn't use network config, but we can update generation parameters
        logger.info("🔧 MLX configuration updated")
    }

    // MARK: - Model Management

    /// Load a model into memory using MLX's built-in download/cache system
    func loadModel(modelId: String) async throws {
        guard isAppActive else {
            logger.warning("❌ Cannot load model while app is inactive")
            throw MLXError.generationFailed("Cannot load model in background")
        }

        // Mark activity
        markActivity()

        // Prevent concurrent loads - if already loading, wait for it to complete
        if isLoadingModel {
            logger.info("⏳ MLX: Model load already in progress, waiting...")
            // Wait for current load to complete (poll every 100ms, max 30 seconds)
            for _ in 0..<300 {
                try await Task.sleep(nanoseconds: 100_000_000)
                if !isLoadingModel {
                    logger.info("✅ MLX: Previous load completed, using existing engine")
                    if chatEngine != nil {
                        return // Model is now loaded
                    }
                    break // Load failed, try again
                }
            }
            if isLoadingModel {
                throw MLXError.modelLoadFailed("Timed out waiting for model to load")
            }
        }

        // If model is already loaded with this ID, skip reload
        // Check loadedModel (not chatEngine) since engine may be nil after reset
        if loadedModel != nil && currentModelId == modelId {
            logger.info("✅ MLX: Model already loaded, skipping reload")
            // Ensure we have a chat engine even if model is loaded
            if chatEngine == nil, let model = loadedModel {
                chatEngine = ChatEngine(
                    context: model,
                    prefillStepSize: 256,
                    temperature: Float(currentConfig.temperature),
                    topP: Float(currentConfig.topP),
                    maxTokens: currentConfig.maxTokens
                )
            }
            return
        }

        // If a different model is currently loaded, unload it first
        if loadedModel != nil && currentModelId != modelId {
            logger.info("🔄 Unloading current model before loading new model")
            unloadModel()
        }

        isLoadingModel = true
        logger.info("📂 Loading MLX model: \(modelId)")
        isLoading = true
        defer {
            isLoading = false
            isLoadingModel = false
        }

        // Get the HuggingFace repo ID from the model registry
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }

        let huggingFaceRepo = modelConfig.huggingFaceRepo
        logger.info("📦 Loading from HuggingFace: \(huggingFaceRepo)")

        do {
            // Ensure GPU initialization completes on the MainActor before loading
            await gpuInitializationTask.value

            // Verify GPU initialization succeeded
            guard isGPUInitialized else {
                logger.error("❌ GPU initialization failed - cannot load model. Try calling retryGPUInitialization()")
                throw MLXError.modelLoadFailed("GPU initialization failed. The GPU cache could not be configured. Try restarting the app or calling retryGPUInitialization().")
            }

            // Use MLX's built-in loading (downloads if needed, uses cache if available)
            // Already on MainActor due to class-level isolation
            let model = try await MLXLMCommon.loadModel(id: huggingFaceRepo)

            // Store the model reference for reuse when resetting sessions
            self.loadedModel = model

            // Create chat engine with the loaded model
            // Uses prefillStepSize=256 to reduce peak scratch memory
            chatEngine = ChatEngine(
                context: model,
                prefillStepSize: 256,
                temperature: Float(currentConfig.temperature),
                topP: Float(currentConfig.topP),
                maxTokens: currentConfig.maxTokens
            )
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            // Update downloaded models tracking
            downloadedModelIds.insert(modelId)
            saveDownloadedModels()  // Persist to UserDefaults

            logger.info("✅ Successfully loaded MLX model: \(modelId)")
            logMemoryStats(label: "After Model Load")

        } catch {
            logger.error("❌ Failed to load MLX model", error: error)
            loadedModel = nil
            chatEngine = nil
            currentModelId = nil
            isConnected = false
            connectionStatus = .disconnected
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model from memory with aggressive GPU resource release
    func unloadModel() {
        logger.info("🗑️ Unloading MLX model")
        logMemoryStats(label: "Before Model Unload")

        // Cancel any pending tasks
        idleCleanupTask?.cancel()
        idleCleanupTask = nil
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        // Step 1: Synchronize GPU stream to ensure all pending operations complete
        // This forces any lazy evaluations to finish before we release resources
        logger.debug("🔄 Synchronizing GPU stream...")
        Stream.gpu.synchronize()

        // Step 2: Set cache limit to 0 to force IMMEDIATE deallocation when buffers are freed
        // By default, MLX keeps freed buffers in cache for reuse - setting to 0 disables this
        let previousCacheLimit = GPU.cacheLimit
        GPU.set(cacheLimit: 0)
        logger.debug("🔧 Set GPU cache limit to 0 (was \(previousCacheLimit / 1024 / 1024)MB)")

        // Step 3: Clear references inside autoreleasepool to encourage immediate ARC deallocation
        // This helps ensure Swift releases the objects promptly rather than waiting for next run loop
        autoreleasepool {
            chatEngine = nil
            loadedModel = nil
        }
        // Do NOT clear currentModelId here - we want to remember it for auto-reload
        isConnected = false
        connectionStatus = .disconnected

        // Step 4: Synchronize again after clearing references
        // This ensures any cleanup operations from deallocation complete
        Stream.gpu.synchronize()

        // Step 5: Clear the GPU cache to deallocate any remaining cached buffers
        GPU.clearCache()

        // Step 6: Final synchronize to ensure all cache clearing operations complete
        Stream.gpu.synchronize()

        // Step 7: Restore cache limit for future operations
        // Use a smaller cache limit (256MB) to reduce memory footprint
        let newCacheLimit = min(previousCacheLimit, 256 * 1024 * 1024)
        GPU.set(cacheLimit: newCacheLimit)
        logger.debug("🔧 Restored GPU cache limit to \(newCacheLimit / 1024 / 1024)MB")

        // Step 8: Reset peak memory counter for cleaner diagnostics
        GPU.resetPeakMemory()

        logMemoryStats(label: "After Model Unload")
        logger.info("✅ MLX model unloaded")
    }

    /// Delete a downloaded model from cache
    func deleteModel(modelId: String) async throws {
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }

        // Unload if this is the current model
        if currentModelId == modelId {
            unloadModel()
            currentModelId = nil // Clear selection since we are deleting it
        }

        logger.info("🗑️ Deleting model: \(modelId)")

        var deletedFromAnyLocation = false

        // Try to delete from HuggingFace cache directory (iOS compatible)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let cacheDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        // Model directories follow pattern: models--<org>--<model>
        let repoPath = modelConfig.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelDirectory = cacheDirectory.appendingPathComponent("models--\(repoPath)")

        logger.debug("🔍 Checking for model at: \(modelDirectory.path)")

        // MLX stores models in Library/Caches/models/{org}/{model}
        // Parse the repo to get org and model name
        let repoParts = modelConfig.huggingFaceRepo.split(separator: "/")
        guard repoParts.count == 2 else {
            logger.warning("⚠️ Invalid repo format: \(modelConfig.huggingFaceRepo)")
            return
        }

        let org = String(repoParts[0])
        let modelName = String(repoParts[1])

        // Check the MLX-specific cache location
        let mlxCacheDir = homeDirectory
            .appendingPathComponent("Library/Caches/models")
            .appendingPathComponent(org)
            .appendingPathComponent(modelName)

        logger.info("🔍 Checking MLX cache at: \(mlxCacheDir.path)")

        if FileManager.default.fileExists(atPath: mlxCacheDir.path) {
            do {
                try FileManager.default.removeItem(at: mlxCacheDir)
                logger.info("✅ Deleted model from MLX cache at: \(mlxCacheDir.path)")
                deletedFromAnyLocation = true
            } catch {
                logger.warning("⚠️ Failed to delete MLX cache: \(error)")
            }
        }

        // Also check the standard location
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
            logger.info("✅ Deleted model from HuggingFace cache at: \(modelDirectory.path)")
            deletedFromAnyLocation = true
        }

        // Also try to delete from MLXModels directory (if it was downloaded via MLXModelManager)
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mlxModelsDir = documentsDir.appendingPathComponent("MLXModels", isDirectory: true)
        let mlxModelDirectory = mlxModelsDir.appendingPathComponent(modelId, isDirectory: true)

        if FileManager.default.fileExists(atPath: mlxModelDirectory.path) {
            try FileManager.default.removeItem(at: mlxModelDirectory)
            logger.info("✅ Deleted model from MLXModels directory at: \(mlxModelDirectory.path)")
            deletedFromAnyLocation = true
        }

        if !deletedFromAnyLocation {
            logger.warning("⚠️ Model \(modelId) was not found in any known cache location")
        }

        // Update downloaded models tracking and persist
        downloadedModelIds.remove(modelId)
        saveDownloadedModels()  // Persist to UserDefaults
        logger.info("📦 Model \(modelId) removed from downloaded list")
    }

    /// Check if a model is downloaded by checking if we can successfully load it
    /// MLX caches models internally, so we just check if the model was recently loaded
    func isModelDownloaded(modelId: String) -> Bool {
        // If this model is currently loaded, it's definitely downloaded
        if currentModelId == modelId && loadedModel != nil {
            logger.debug("✅ Model \(modelId) is currently loaded")
            return true
        }

        // Check if it's in our tracked downloaded models
        // This gets updated when we successfully load a model
        let isTracked = downloadedModelIds.contains(modelId)
        logger.debug("🔍 Model \(modelId) tracked as downloaded: \(isTracked)")

        return isTracked
    }

    /// Reset the chat engine to clear conversation history
    /// This creates a fresh ChatEngine without reloading the model from disk
    /// Note: ChatEngine resets KV cache on every request, so this mainly frees GPU resources
    func resetSession() async throws {
        guard let model = loadedModel else {
            // No model loaded - need to load it first
            guard let modelId = currentModelId else {
                throw MLXError.invalidConfiguration
            }
            logger.info("🔄 No loaded model found, loading model: \(modelId)")
            try await loadModel(modelId: modelId)
            return
        }

        logger.info("🔄 Resetting chat engine (reusing loaded model)")
        logMemoryStats(label: "Before Engine Reset")

        // Clear the current engine to free resources
        chatEngine = nil

        // Force GPU cache cleanup to release any cached buffers
        // This is critical to prevent memory accumulation
        GPU.clearCache()
        // Sync GPU to ensure cleanup completes before continuing
        eval(MLXArray(0))
        logMemoryStats(label: "After Cache Clear")

        // Longer delay to ensure memory is fully freed before allocating new engine
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Create a fresh ChatEngine with the already-loaded model
        // This avoids reloading ~2GB of model weights from disk
        chatEngine = ChatEngine(
            context: model,
            prefillStepSize: 256,
            temperature: Float(currentConfig.temperature),
            topP: Float(currentConfig.topP),
            maxTokens: currentConfig.maxTokens
        )
        logMemoryStats(label: "After New Engine")

        logger.info("✅ Chat engine reset complete")
    }

    /// Set generation configuration
    func setGenerationConfig(_ config: MLXGenerationConfig) {
        logger.info("🔧 Updating generation config - temp: \(config.temperature), maxTokens: \(config.maxTokens), contextWindow: \(config.contextWindow)")
        currentConfig = config
    }

    // MARK: - Streaming Support

    /// Public entry point for MLX streaming.
    /// Wraps the core streaming logic in a cancellable task so we can stop GPU work when the app backgrounds.
    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        systemPrompt: String?,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        guard isAppActive else {
            logger.warning("❌ MLX streaming blocked - app is not active")
            throw MLXError.generationFailed("Cannot generate while the app is in the background.")
        }

        cancelActiveStreaming(reason: "Starting new MLX stream")

        let streamingTask = Task { @MainActor [weak self] () throws -> Void in
            guard let self else { throw CancellationError() }
            try Task.checkCancellation()
            try await self.performStreamingChatMessage(
                message,
                context: context,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                conversationId: conversationId,
                onUpdate: onUpdate,
                onComplete: onComplete
            )
        }

        activeStreamingTask = streamingTask
        defer {
            activeStreamingTask = nil
        }

        do {
            try await streamingTask.value
        } catch is CancellationError {
            logger.warning("⚠️ MLX streaming cancelled (likely app background)")
            throw MLXError.generationFailed("MLX streaming cancelled because the app is not active.")
        } catch {
            throw error
        }
    }

    /// Send streaming chat message
    /// - Parameters:
    ///   - message: The user's current message
    ///   - context: Health data context string
    ///   - systemPrompt: Doctor's system prompt/instructions
    ///   - conversationHistory: Previous messages in the conversation for context
    ///   - conversationId: UUID of the current conversation
    ///   - onUpdate: Callback for streaming updates
    ///   - onComplete: Callback when generation completes
    private func performStreamingChatMessage(
        _ message: String,
        context: String,
        systemPrompt: String?,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        // Mark activity to prevent idle cleanup during generation
        markActivity()

        guard let modelId = currentModelId else {
            logger.error("❌ MLX: No model selected - currentModelId is nil")
            throw MLXError.invalidConfiguration
        }

        guard isAppActive else {
            logger.warning("❌ MLX streaming blocked - app is not active")
            throw MLXError.generationFailed("Cannot generate while the app is in the background.")
        }

        try Task.checkCancellation()

        // Check if model is actually loaded
        if chatEngine == nil {
            logger.info("🔄 MLX: Model not loaded, attempting to auto-load: \(modelId)")
            do {
                try await loadModel(modelId: modelId)
            } catch {
                logger.error("❌ MLX: Failed to auto-load model: \(modelId)", error: error)
                throw MLXError.modelLoadFailed("Failed to load model: \(error.localizedDescription)")
            }
        }

        // Check if this model requires special handling (like MedGemma)
        let requiresSpecialFormatting = SystemPromptExceptionList.shared.requiresInstructionInjection(for: modelId)

        // Check if we need to reset for conversation switching
        let (shouldReset, isNewConversation) = shouldResetSession(
            for: conversationId,
            systemPrompt: systemPrompt,
            context: context,
            conversationHistory: conversationHistory
        )

        if shouldReset {
            logger.info("🔄 Resetting engine - switching conversation")
            try await resetSession()
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else if isNewConversation {
            logger.info("📝 New conversation - updating conversation ID")
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else {
            logger.debug("📝 Continuing conversation - token count: \(conversationTokenCount)")
        }

        guard let engine = chatEngine else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        logger.info("🤖 Streaming response with ChatEngine (prefillStepSize: 256)")

        // Prepare the token stream from ChatEngine
        // For models with special formatting (MedGemma), build raw prompt
        // For standard models, use message-based API
        let tokenStream: AsyncThrowingStream<String, Error>

        if requiresSpecialFormatting {
            // For MedGemma: build special format prompt and use raw streamResponse
            let specialPrompt = SystemPromptExceptionList.shared.formatMessageWithHistory(
                userMessage: message,
                systemPrompt: systemPrompt,
                context: context,
                conversationHistory: conversationHistory,
                maxTokens: currentConfig.contextWindow
            )
            let historyCount = conversationHistory.filter { $0.role == .user || $0.role == .assistant }.count
            logger.info("📋 MedGemma format - including \(historyCount) history messages")
            logger.debug("📋 Prompt preview: \(String(specialPrompt.prefix(200)))...")
            tokenStream = engine.streamResponse(to: specialPrompt, maxTokens: currentConfig.maxTokens)
        } else {
            // For standard models: use message-based API with conversation history
            // CRITICAL FIX: Add the current user message to the history!
            // conversationHistory contains PAST messages only, we need to append the current question
            var messagesIncludingCurrent = conversationHistory
            let currentUserMessage = ChatMessage(content: message, role: .user)
            messagesIncludingCurrent.append(currentUserMessage)

            logger.info("📋 Standard format - \(conversationHistory.count) history messages + current message")
            logger.debug("📋 Current user message: \(String(message.prefix(200)))\(message.count > 200 ? "..." : "")")
            tokenStream = engine.streamResponse(
                messages: messagesIncludingCurrent,
                systemPrompt: systemPrompt,
                context: context
            )
        }

        logMemoryStats(label: "Before Generation")
        let startTime = Date()

        // Note: We rely on Swift ARC to clean up temporary tensors
        // Explicit autoreleasepool isn't available for async/await contexts
        do {
            var finalText = ""
            var tokenCount = 0
            let maxTokens = currentConfig.maxTokens

            // Track last N characters to detect repetition
            var previousChunk = ""
            var repetitionCount = 0

            // Throttle UI updates to prevent performance degradation
            var lastUpdateTime = Date()
            let updateInterval: TimeInterval = 0.1 // Update UI every 100ms max
            var tokensPerUpdate = 0

            // Stream tokens using ChatEngine
            // Note: We're already on MainActor (class-level isolation), so we can call
            // streamResponse directly without MainActor.run wrapper
            // The iteration may happen on a background thread (AsyncSequence behavior),
            // which is why we use deliverUpdate() to marshal callbacks back to MainActor
            for try await token in tokenStream {
                try Task.checkCancellation()

                guard isAppActive else {
                    logger.warning("🛑 MLX streaming cancelled - app moved to background")
                    let response = MLXResponse(
                        content: finalText,
                        responseTime: Date().timeIntervalSince(startTime),
                        tokenCount: estimateTokenCount(finalText),
                        metadata: ["cancelled": true, "reason": "background"]
                    )
                    deliverCompletion(response, onComplete: onComplete)
                    throw CancellationError()
                }

                tokenCount += 1
                tokensPerUpdate += 1

                // Append the token to build the complete response
                finalText += token

                // Check for Gemma end-of-turn tokens
                // MedGemma reliably emits <end_of_turn> only at the actual end of its intended generation
                // We trust this signal and stop immediately when detected
                // IMPORTANT: Only check the SUFFIX (last 15 chars) to avoid false positives from conversation history
                let recentSuffix = String(finalText.suffix(15))
                let hasEndToken = recentSuffix.contains("<end_of_turn>") ||
                                  recentSuffix.contains("<|eot_id|>") ||
                                  recentSuffix.contains("</s>")

                if hasEndToken {
                    logger.info("🛑 Detected end-of-turn token, stopping stream (token #\(tokenCount))")
                    // Remove the end token from final text (skip_special_tokens behavior)
                    finalText = finalText.replacingOccurrences(of: "<end_of_turn>", with: "")
                    finalText = finalText.replacingOccurrences(of: "<|eot_id|>", with: "")
                    finalText = finalText.replacingOccurrences(of: "</s>", with: "")
                    finalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Send final update before breaking
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    break
                }

                // Detect repetition (same content being generated repeatedly)
                let recentChunk = String(finalText.suffix(100))
                if recentChunk == previousChunk {
                    repetitionCount += 1
                    if repetitionCount > 3 {
                        logger.warning("⚠️ Detected repetition loop, stopping stream")
                        // Send final update before breaking
                        deliverUpdate(finalText, onUpdate: onUpdate)
                        break
                    }
                } else {
                    repetitionCount = 0
                    previousChunk = recentChunk
                }

                // Safety check: respect maxTokens limit
                if tokenCount >= maxTokens {
                    logger.warning("⚠️ Reached max tokens limit (\(maxTokens)), stopping stream")
                    // Send final update before breaking
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    break
                }

                // Log every 100th token to track progress without noise
                if tokenCount % 100 == 0 {
                    logger.debug("📝 MLX streaming: \(tokenCount) tokens, \(finalText.count) chars")
                    // Mark activity every 100 tokens to prevent idle cleanup during long generations
                    markActivity()
                }

                // Throttle UI updates: only update every 100ms to prevent performance issues
                // This prevents CPU spikes from constant SwiftUI re-renders of growing text
                let now = Date()
                let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
                if timeSinceLastUpdate >= updateInterval {
                    deliverUpdate(finalText, onUpdate: onUpdate)
                    lastUpdateTime = now
                    tokensPerUpdate = 0
                }
            }

            // Send final update to ensure UI has the complete text
            deliverUpdate(finalText, onUpdate: onUpdate)

            logger.info("✅ MLX streaming completed: \(tokenCount) tokens, \(finalText.count) characters")
            logMemoryStats(label: "After Generation")

            // Smart cache clearing: Only clear when necessary to avoid re-allocation overhead
            // Clear if: large generation (>1000 tokens), or cache exceeds threshold (512MB)
            let shouldClearCache = tokenCount > 1000 || shouldClearGPUCache()
            if shouldClearCache {
                logger.info("🧹 Clearing GPU cache (large generation or memory pressure detected)")
                GPU.clearCache()
                // Sync GPU to ensure cleanup completes
                eval(MLXArray(0))
                logMemoryStats(label: "After Cache Clear")
            }

            // Schedule idle cleanup for next period of inactivity
            scheduleIdleCleanup()

            // Update conversation token count
            conversationTokenCount += tokenCount

            let processingTime = Date().timeIntervalSince(startTime)
            let cleanedText = AIResponseCleaner.cleanConversational(finalText)

            let response = MLXResponse(
                content: cleanedText,
                responseTime: processingTime,
                tokenCount: estimateTokenCount(cleanedText),
                metadata: [
                    "model": currentModelId ?? "unknown",
                    "temperature": currentConfig.temperature,
                    "streaming": true,
                    "conversationTokens": conversationTokenCount
                ]
            )

            deliverCompletion(response, onComplete: onComplete)

        } catch {
            logger.error("❌ MLX streaming failed", error: error)
            throw MLXError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Delivers streaming update to MainActor
    ///
    /// Verified to always be called on main thread from AsyncSequence iteration.
    /// We call the callback directly to avoid unnecessary Task overhead.
    ///
    /// - Parameters:
    ///   - text: The accumulated response text
    ///   - onUpdate: Callback to deliver the update (will be called on MainActor)
    private func deliverUpdate(_ text: String, onUpdate: @escaping (String) -> Void) {
        // Direct call - AsyncSequence iteration happens on MainActor for @MainActor class
        onUpdate(text)
    }

    /// Delivers completion response to MainActor
    ///
    /// Verified to always be called on main thread from AsyncSequence iteration.
    /// We call the callback directly to avoid unnecessary Task overhead.
    ///
    /// - Parameters:
    ///   - response: The final MLX response
    ///   - onComplete: Callback to deliver completion (will be called on MainActor)
    private func deliverCompletion(_ response: MLXResponse, onComplete: @escaping (MLXResponse) -> Void) {
        // Direct call - AsyncSequence iteration happens on MainActor for @MainActor class
        onComplete(response)
    }

    /// Determine if we should reset the session
    /// Returns: (shouldReset, isNewConversation)
    private func shouldResetSession(
        for conversationId: UUID?,
        systemPrompt: String? = nil,
        context: String? = nil,
        conversationHistory: [ChatMessage] = []
    ) -> (shouldReset: Bool, isNewConversation: Bool) {
        // No engine exists - don't reset, just load
        guard chatEngine != nil else {
            return (shouldReset: false, isNewConversation: true)
        }

        // Conversation ID changed (switching to a different conversation)
        if let conversationId = conversationId, conversationId != currentConversationId {
            logger.debug("🔄 Conversation changed: \(String(describing: currentConversationId)) → \(conversationId)")
            // Only reset if we've actually had a conversation (token count > 0)
            if conversationTokenCount > 0 {
                return (shouldReset: true, isNewConversation: true)
            } else {
                return (shouldReset: false, isNewConversation: true)
            }
        }

        // Estimate total context usage (Input + History + Max Generation)
        // Note: This is an estimation since we don't have the tokenizer here
        // ~4 chars per token is a safe upper bound for English text
        let systemTokens = estimateTokenCount(systemPrompt ?? "")
        let contextTokens = estimateTokenCount(context ?? "")
        let historyTokens = conversationHistory.reduce(0) { $0 + estimateTokenCount($1.content) }
        let maxGenTokens = currentConfig.maxTokens

        let totalEstimatedUsage = systemTokens + contextTokens + historyTokens + maxGenTokens
        let contextLimit = Int(Double(currentConfig.contextWindow) * 0.9)

        if totalEstimatedUsage >= contextLimit {
            logger.warning("⚠️ Approaching context limit: \(totalEstimatedUsage)/\(currentConfig.contextWindow) (History: \(historyTokens), Context: \(contextTokens))")
            return (shouldReset: true, isNewConversation: false)
        }

        return (shouldReset: false, isNewConversation: false)
    }

    /// Build prompt using proper chat template format for Phi-3/MediPhi models
    /// Phi-3.5 uses the format: <|system|>...<|end|><|user|>...<|end|><|assistant|>
    private func buildChatTemplatePrompt(
        message: String,
        context: String,
        systemPrompt: String?,
        conversationHistory: [ChatMessage] = []
    ) -> String {
        var prompt = ""

        // Build the full system prompt by combining doctor instructions with health context
        var fullSystemPrompt = ""

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            fullSystemPrompt = systemPrompt
        }

        if !context.isEmpty {
            if !fullSystemPrompt.isEmpty {
                fullSystemPrompt += "\n\n"
            }
            fullSystemPrompt += "PATIENT HEALTH INFORMATION:\n\(context)"
        }

        // Add system message using Phi-3.5 format
        if !fullSystemPrompt.isEmpty {
            prompt += "<|system|>\n\(fullSystemPrompt)<|end|>\n"
        }

        // Add conversation history using Phi-3.5 format
        for historyMessage in conversationHistory {
            if historyMessage.role == .user {
                prompt += "<|user|>\n\(historyMessage.content)<|end|>\n"
            } else if historyMessage.role == .assistant {
                prompt += "<|assistant|>\n\(historyMessage.content)<|end|>\n"
            }
        }

        // Add current user message
        prompt += "<|user|>\n\(message)<|end|>\n"

        // Add assistant prompt to signal the model should start generating
        prompt += "<|assistant|>\n"

        logger.debug("📝 Chat template prompt length: \(prompt.count) characters")
        logger.debug("📋 Messages: system + \(conversationHistory.count) history + current user")

        return prompt
    }

    /// Legacy prompt builder for models that don't support chat templates
    /// Falls back to simple text concatenation
    private func buildPrompt(message: String, context: String, systemPrompt: String? = nil) -> String {
        var prompt = ""

        // Include system instructions as part of the message content
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            prompt += systemPrompt + "\n\n"
        }

        if !context.isEmpty {
            prompt += "Patient Health Information:\n\(context)\n\n"
        }

        // Simple, direct question format
        prompt += message

        logger.debug("📝 Legacy prompt length: \(prompt.count) characters")

        return prompt
    }

    /// Check if GPU cache should be cleared based on memory pressure
    /// Returns true if cache exceeds 512MB threshold
    private func shouldClearGPUCache() -> Bool {
        let cacheMemory = GPU.cacheMemory
        let cacheSizeMB = Double(cacheMemory) / 1_048_576.0
        let cacheThresholdMB: Double = 512.0

        if cacheSizeMB > cacheThresholdMB {
            logger.info("⚠️ GPU cache (\(Int(cacheSizeMB))MB) exceeds threshold (\(Int(cacheThresholdMB))MB)")
            return true
        }
        return false
    }

    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token
        return text.count / 4
    }
}

// MARK: - MLX Response

struct MLXResponse: AIResponse {
    let content: String
    let responseTime: TimeInterval
    let tokenCount: Int?
    let metadata: [String: Any]?

    init(
        content: String,
        responseTime: TimeInterval,
        tokenCount: Int?,
        metadata: [String: Any]? = nil
    ) {
        self.content = content
        self.responseTime = responseTime
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}
