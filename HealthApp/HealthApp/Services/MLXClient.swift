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

    // MARK: - Private Properties
    private var chatSession: ChatSession?
    private var loadedModel: ModelContext?  // Store model separately from session for reuse
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

    // Reduced from 4GB to 2GB to minimize GPU power usage when idle
    // The model itself is ~2GB, so 2GB cache is sufficient for generation
    private static let gpuCacheLimit: UInt64 = 2 * 1024 * 1024 * 1024  // 2GB GPU cache
    private static let backgroundCancellationDelay: UInt64 = 50_000_000 // 50ms delay before GPU cache clear

    // Idle resource management
    private var lastActivityTime: Date = Date()
    private var idleCleanupTask: Task<Void, Never>?
    private var modelUnloadTask: Task<Void, Never>?
    private static let idleCleanupDelay: TimeInterval = 30.0 // Clear GPU cache after 30 seconds of inactivity
    private static let modelUnloadDelay: TimeInterval = 120.0 // Unload model completely after 120 seconds of inactivity

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
        }
    }

    deinit {
        lifecycleObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        idleCleanupTask?.cancel()
        modelUnloadTask?.cancel()
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

        lifecycleObservers.append(contentsOf: [resignActiveObserver, backgroundObserver, foregroundObserver])
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

    private func cancelActiveStreaming(reason: String) {
        guard let task = activeStreamingTask else { return }
        logger.warning("🛑 Cancelling active MLX streaming task (\(reason))")
        task.cancel()
        activeStreamingTask = nil
    }

    // MARK: - Idle Resource Management

    /// Schedule two-stage cleanup: cache clear at 30s, model unload at 120s
    /// This reduces GPU/CPU usage progressively as inactivity continues
    private func scheduleIdleCleanup() {
        // Cancel any existing cleanup tasks
        idleCleanupTask?.cancel()
        modelUnloadTask?.cancel()

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

        // Stage 2: Unload model completely after 120 seconds (more aggressive)
        modelUnloadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Wait for longer idle period
            try? await Task.sleep(nanoseconds: UInt64(Self.modelUnloadDelay * 1_000_000_000))

            // Check if still idle, task wasn't cancelled, and model still loaded
            guard !Task.isCancelled, self.loadedModel != nil else { return }

            let timeSinceLastActivity = Date().timeIntervalSince(self.lastActivityTime)
            if timeSinceLastActivity >= Self.modelUnloadDelay {
                logger.info("🗑️ MLX Stage 2: Unloading model after \(Int(timeSinceLastActivity))s of inactivity")
                logMemoryStats(label: "Before Model Unload")

                // Unload the entire model to free all GPU resources
                unloadModel()

                logger.info("✅ MLX Stage 2 complete - Model fully unloaded, GPU resources freed")
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

        if chatSession != nil {
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

        guard chatSession != nil else {
            logger.warning("⚠️ No active chat session for title generation")
            throw MLXError.invalidConfiguration
        }

        // CRITICAL: Reset the session BEFORE title generation to avoid KV cache shape mismatches
        // The session has conversation context from the first exchange, which would cause
        // broadcast_shapes errors if we try to append a title generation prompt to it
        logger.info("🔄 Resetting session before title generation to clear conversation history")
        try await resetSession()

        guard let session = chatSession else {
            logger.error("❌ Session lost after reset")
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
            for try await token in session.streamResponse(to: titlePrompt) {
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
                    logger.info("✅ MLX: Previous load completed, using existing session")
                    if chatSession != nil {
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
        // Check loadedModel (not chatSession) since session may be nil after reset
        if loadedModel != nil && currentModelId == modelId {
            logger.info("✅ MLX: Model already loaded, skipping reload")
            // Ensure we have a chat session even if model is loaded
            if chatSession == nil, let model = loadedModel {
                chatSession = ChatSession(model)
            }
            return
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

            // Create chat session with the loaded model
            chatSession = ChatSession(model)
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected

            logger.info("✅ Successfully loaded MLX model: \(modelId)")
            logMemoryStats(label: "After Model Load")

        } catch {
            logger.error("❌ Failed to load MLX model", error: error)
            loadedModel = nil
            chatSession = nil
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
        modelUnloadTask?.cancel()
        modelUnloadTask = nil
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
            chatSession = nil
            loadedModel = nil
        }
        currentModelId = nil
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
        }

        logger.info("🗑️ Deleting model: \(modelId)")

        // Get the HuggingFace cache directory (iOS compatible)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let cacheDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        // Model directories follow pattern: models--<org>--<model>
        let repoPath = modelConfig.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelDirectory = cacheDirectory.appendingPathComponent("models--\(repoPath)")

        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
            logger.info("✅ Deleted model cache at: \(modelDirectory.path)")
        } else {
            logger.warning("⚠️ Model cache not found at: \(modelDirectory.path)")
        }
    }

    /// Check if a model is downloaded
    func isModelDownloaded(modelId: String) -> Bool {
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            return false
        }

        // Get the HuggingFace cache directory (iOS compatible)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let cacheDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        let repoPath = modelConfig.huggingFaceRepo.replacingOccurrences(of: "/", with: "--")
        let modelDirectory = cacheDirectory.appendingPathComponent("models--\(repoPath)")

        return FileManager.default.fileExists(atPath: modelDirectory.path)
    }

    /// Reset the chat session to clear conversation history and KV cache
    /// This creates a fresh ChatSession without reloading the model from disk
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

        logger.info("🔄 Resetting chat session (reusing loaded model)")
        logMemoryStats(label: "Before Session Reset")

        // Clear the current session to free KV cache memory
        chatSession = nil

        // Force GPU cache cleanup to release KV cache memory
        // This is critical to prevent memory accumulation across turns
        GPU.clearCache()
        logMemoryStats(label: "After Cache Clear")

        // Longer delay to ensure memory is fully freed before allocating new session
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Create a fresh ChatSession with the already-loaded model
        // This avoids reloading ~2GB of model weights from disk
        chatSession = ChatSession(model)
        logMemoryStats(label: "After New Session")

        logger.info("✅ Chat session reset complete")
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
        if chatSession == nil {
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

        // Check if we need to reset the session
        let (shouldReset, isNewConversation) = shouldResetSession(for: conversationId)

        // For MedGemma and similar models: reset session on EVERY turn
        // These models don't properly maintain KV cache across turns, so we
        // send the full context each time and reset to avoid shape mismatches.
        // LIMITATION: This means MedGemma doesn't have conversation history -
        // each turn is treated independently with only the health context.
        // TODO: To support conversation history, we would need to build previous
        // messages into the CONTEXT section of the prompt.
        let needsReset = shouldReset || (requiresSpecialFormatting && conversationTokenCount > 0)
        let isFirstTurn = isNewConversation || chatSession == nil || needsReset

        if needsReset && chatSession != nil {
            if requiresSpecialFormatting {
                logger.info("🔄 Resetting session for MedGemma - each turn gets fresh context")
            } else {
                logger.info("🔄 Resetting session - switching conversation or context limit reached")
            }
            try await resetSession()
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else if isNewConversation {
            // New conversation but no reset needed (session is fresh)
            logger.info("📝 New conversation, session is fresh - updating conversation ID")
            currentConversationId = conversationId
            conversationTokenCount = 0
        } else {
            logger.debug("📝 Continuing conversation - token count: \(conversationTokenCount)")
        }

        guard let session = chatSession else {
            throw MLXError.modelLoadFailed("Model failed to load")
        }

        // Build the prompt
        // Note: requiresSpecialFormatting already calculated above, modelId from guard statement

        let fullPrompt: String
        if requiresSpecialFormatting {
            // For MedGemma and similar models: ALWAYS use INSTRUCTIONS/CONTEXT/QUESTION format
            // These models don't properly maintain KV cache across turns with varying formats,
            // so we include the full context on every turn for consistency
            // Also include conversation history so the model has context from previous exchanges
            fullPrompt = SystemPromptExceptionList.shared.formatMessageWithHistory(
                userMessage: message,
                systemPrompt: systemPrompt,
                context: context,
                conversationHistory: conversationHistory,
                maxTokens: currentConfig.contextWindow
            )
            let historyCount = conversationHistory.filter { $0.role == .user || $0.role == .assistant }.count
            logger.info("📋 MedGemma format - including \(historyCount) history messages, context window: \(currentConfig.contextWindow)")
        } else if isFirstTurn {
            // Standard models: include context on first turn only
            fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)
            logger.debug("📋 First turn - using standard format with full context")
        } else {
            // Standard models: just the message on subsequent turns (ChatSession maintains history)
            fullPrompt = message
            logger.debug("📋 Subsequent turn - message only")
        }

        logger.info("🤖 Streaming response with MLX model")
        logger.debug("📋 Full prompt:\n\(fullPrompt.prefix(200))...")

        // Debug logging for instruction injection
        logger.info("🔍 MLXClient: isFirstTurn=\(isFirstTurn), shouldReset=\(shouldReset), promptLength=\(fullPrompt.count)")
        if fullPrompt.count > 200 {
            logger.debug("🔍 MLXClient: Prompt preview: \(String(fullPrompt.prefix(200)))...")
        } else {
            logger.debug("🔍 MLXClient: Full prompt: \(fullPrompt)")
        }

        logMemoryStats(label: "Before Generation")
        let startTime = Date()

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

            // Stream tokens using ChatSession
            // Note: We're already on MainActor (class-level isolation), so we can call
            // streamResponse directly without MainActor.run wrapper
            // The iteration may happen on a background thread (AsyncSequence behavior),
            // which is why we use deliverUpdate() to marshal callbacks back to MainActor
            for try await token in session.streamResponse(to: fullPrompt) {
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

            // Clear GPU cache after generation to free memory
            // Since we reset session each turn for MedGemma anyway, cached tensors aren't reused
            GPU.clearCache()
            logMemoryStats(label: "After Cache Clear")

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
    private func shouldResetSession(for conversationId: UUID?) -> (shouldReset: Bool, isNewConversation: Bool) {
        // No session exists - don't reset, just load
        guard chatSession != nil else {
            return (shouldReset: false, isNewConversation: true)
        }

        // Conversation ID changed (switching to a different conversation)
        if let conversationId = conversationId, conversationId != currentConversationId {
            logger.debug("🔄 Conversation changed: \(String(describing: currentConversationId)) → \(conversationId)")
            // Only reset if we've actually had a conversation (token count > 0)
            // If token count is 0, the session is already fresh
            if conversationTokenCount > 0 {
                return (shouldReset: true, isNewConversation: true)
            } else {
                // Just update the conversation ID, no reset needed
                return (shouldReset: false, isNewConversation: true)
            }
        }

        // Reset if approaching context window limit (90% of max)
        let contextLimit = Int(Double(currentConfig.contextWindow) * 0.9)
        if conversationTokenCount >= contextLimit {
            logger.warning("⚠️ Approaching context limit: \(conversationTokenCount)/\(currentConfig.contextWindow)")
            return (shouldReset: true, isNewConversation: false)
        }

        return (shouldReset: false, isNewConversation: false)
    }

    private func buildPrompt(message: String, context: String, systemPrompt: String? = nil) -> String {
        // MedGemma uses Gemma's chat template format
        // ChatSession handles turn markers, so we provide a clean user message
        // Avoid mentioning turn markers or special tokens in the prompt itself

        var prompt = ""

        // Include system instructions as part of the message content
        // Don't use special formatting that might confuse the model
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            prompt += systemPrompt + "\n\n"
        }

        if !context.isEmpty {
            prompt += "Patient Health Information:\n\(context)\n\n"
        }

        // Simple, direct question format
        prompt += message

        logger.debug("📝 Prompt length: \(prompt.count) characters")

        return prompt
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
