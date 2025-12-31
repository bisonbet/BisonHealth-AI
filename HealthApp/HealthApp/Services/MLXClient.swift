import Foundation
import UIKit
import os
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

// MARK: - MLX Client

/// Unified Client for running local LLMs and VLMs using Apple's MLX framework
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
    // We use a generic container to hold the active model (LLM or VLM)
    // Note: In a real implementation, you might need specific types for LLM vs VLM
    // For now, we assume ModelContext is the wrapper or we hold references to specific containers
    private var llmContainer: ModelContext?
    private var vlmContainer: ModelContext? // Placeholder: In reality this would be VLMModelContext
    
    private var currentConfig: MLXGenerationConfig = .default
    private let logger = Logger.shared
    private var activeStreamingTask: Task<Void, Error>?
    
    // GPU State
    private var gpuInitializationTask: Task<Void, Never>!
    private var isGPUInitialized: Bool = false
    
    // Memory Management - Critical for iOS
    private static let gpuCacheLimit: UInt64 = 256 * 1024 * 1024  // 256MB GPU cache
    private var idleCleanupTask: Task<Void, Never>?
    private var lastActivityTime: Date = Date()
    private static let idleCleanupDelay: TimeInterval = 30.0

    // MARK: - Initialization
    private init() {
        // Initialize GPU asynchronously
        gpuInitializationTask = Task { @MainActor in
            MLX.GPU.set(cacheLimit: Int(Self.gpuCacheLimit))
            isGPUInitialized = true
            setupLifecycleObservers()
            scanDownloadedModels()
        }
    }

    // MARK: - Model Management

    /// Load a model (Text or Vision)
    func loadModel(modelId: String) async throws {
        guard let modelConfig = MLXModelRegistry.model(withId: modelId) else {
            throw MLXError.modelNotFound
        }
        
        // Prevent reloading if already loaded
        if currentModelId == modelId && (llmContainer != nil || vlmContainer != nil) {
            return
        }
        
        // Unload current model
        unloadModel()
        
        // Give ARC and GPU a moment to reclaim memory
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        isLoading = true
        defer { isLoading = false }
        
        await gpuInitializationTask.value
        
        logger.info("📂 Loading MLX model: \(modelId) type: \(modelConfig.modelType)")
        
        do {
            if modelConfig.modelType == .vision {
                // Vision Model Loading
                // We use MLXVLM to load vision-capable models (like Granite Docling, LLaVA, Qwen-VL)
                // Note: Ensure 'MLXVLM' is added to your Package.swift dependencies
                let container = try await MLXLMCommon.loadModel(id: modelConfig.huggingFaceRepo)
                self.vlmContainer = container
                self.llmContainer = nil // Ensure we don't have mixed state
            } else {
                // Text Model Loading (Standard)
                // MLXLMCommon.loadModel automatically handles downloading & caching
                let container = try await MLXLMCommon.loadModel(id: modelConfig.huggingFaceRepo)
                self.llmContainer = container
                self.vlmContainer = nil
            }
            
            currentModelId = modelId
            isConnected = true
            connectionStatus = .connected
            
            // Persist
            downloadedModelIds.insert(modelId)
            saveDownloadedModels()
            
            logger.info("✅ Successfully loaded: \(modelId)")
            
        } catch {
            logger.error("❌ Failed to load model", error: error)
            throw MLXError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Update generation configuration
    func setGenerationConfig(_ config: MLXGenerationConfig) {
        self.currentConfig = config
    }
    
    /// Generate a title for a conversation
    func generateTitle(userMessage: String, assistantResponse: String) async throws -> String {
        // Auto-load logic if needed
        if llmContainer == nil, let id = currentModelId {
            try await loadModel(modelId: id)
        }
        
        guard let container = llmContainer else {
             // If no model is loaded, return a default
             return "New Conversation"
        }
        
        // Construct prompt
        let prompt = """
        Generate a short, concise title (max 5 words) for the following conversation. Do not use quotes.
        
        User: \(userMessage)
        Assistant: \(assistantResponse)
        
        Title:
        """
        
        // Prepare input
        // Using direct tokenizer/processor access similar to chat
        let userInput = UserInput(prompt: prompt, images: [] as [UserInput.Image])
        let promptTokens = try await container.processor.prepare(input: userInput)
        
        // Generate with limited tokens
        let params = GenerateParameters(maxTokens: 20)
        let result = try MLXLMCommon.generate(
            input: promptTokens,
            parameters: params,
            context: container
        )
        
        var title = ""
        for try await output in result {
            switch output {
            case .chunk(let text):
                title += text
            default: break
            }
        }
        
        return AIResponseCleaner.cleanTitle(title)
    }
    
    /// Delete a downloaded model
    func deleteModel(modelId: String) async throws {
        // If deleting current model, unload it first
        if currentModelId == modelId {
            unloadModel()
        }
        
        // Use ModelManager to delete files
        // Note: MLXModelManager.shared is available in the project
        try await MLXModelManager.shared.deleteModel(modelId)
        
        // Update local state
        downloadedModelIds.remove(modelId)
        saveDownloadedModels()
        
        logger.info("🗑️ Deleted MLX model: \(modelId)")
    }

    /// Unload all models and free memory
    func unloadModel() {
        // Cancel tasks
        activeStreamingTask?.cancel()
        idleCleanupTask?.cancel()
        
        // Force GPU Cleanup
        Stream.gpu.synchronize()
        
        // Temporarily disable cache to force dealloc
        let oldLimit = GPU.cacheLimit
        GPU.set(cacheLimit: 0)
        
        autoreleasepool {
            llmContainer = nil
            vlmContainer = nil
        }
        
        // Clear connection state but KEEP currentModelId for auto-reload
        isConnected = false
        connectionStatus = .disconnected
        
        Stream.gpu.synchronize()
        GPU.clearCache()
        Stream.gpu.synchronize()
        
        // Restore cache limit
        GPU.set(cacheLimit: oldLimit)
        logger.info("🗑️ Model unloaded and GPU cache cleared")
    }

    // MARK: - Generation (Text)

    func sendStreamingChatMessage(
        _ message: String,
        context: String,
        systemPrompt: String?,
        conversationHistory: [ChatMessage] = [],
        conversationId: UUID? = nil,
        onUpdate: @escaping (String) -> Void,
        onComplete: @escaping (MLXResponse) -> Void
    ) async throws {
        
        // Auto-load logic
        if llmContainer == nil, let id = currentModelId {
            try await loadModel(modelId: id)
        }
        
        guard let container = llmContainer else {
            throw MLXError.modelLoadFailed("No model loaded")
        }
        
        // Use Standard MLX Generation
        // This replaces the custom ChatEngine
        
        // 1. Prepare Messages (Standard Format)
        var messages: [[String: String]] = []
        
        // System Prompt (Instructions only - Persona)
        if let system = systemPrompt, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        
        // History
        for msg in conversationHistory {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        
        // Current Message (Context + Question)
        var userContent = ""
        if !context.isEmpty {
            userContent += "CONTEXT (JSON Format):\n\(context)\n\n"
        }
        userContent += message
        
        messages.append(["role": "user", "content": userContent])
        
        // 2. Apply Chat Template (The "Correct" Way)
        // Format messages into a prompt string using the model's chat template
        let tokens = try container.tokenizer.applyChatTemplate(messages: messages)
        let promptString = container.tokenizer.decode(tokens: tokens)

        // 3. Prepare input using the processor
        let userInput = UserInput(prompt: promptString, images: [] as [UserInput.Image])
        let promptTokens = try await container.processor.prepare(input: userInput)
        
        logger.info("🤖 MLXClient: Starting generation")

        // 4. Generate
        let startTime = Date()
        var fullText = ""
        var tokenCount = 0

        // Generation Parameters
        let params = GenerateParameters(
            maxTokens: currentConfig.maxTokens,
            temperature: Float(currentConfig.temperature),
            topP: Float(currentConfig.topP),
            repetitionPenalty: 1.1
        )
        
        // Stream
        let result = try MLXLMCommon.generate(
            input: promptTokens,
            parameters: params,
            context: container
        )
        
        for try await output in result {
            switch output {
            case .chunk(let text):
                fullText += text
                tokenCount += 1
                let cleanedText = AIResponseCleaner.removeSpecialTokens(from: fullText)
                onUpdate(cleanedText)
            default: break
            }
        }
        
        // Finalize
        let finalText = AIResponseCleaner.removeSpecialTokens(from: fullText)
        let response = MLXResponse(
            content: finalText,
            responseTime: Date().timeIntervalSince(startTime),
            tokenCount: tokenCount
        )
        onComplete(response)
    }
    
    // MARK: - Vision Processing (Docling/OCR)
    
    /// Process an image using the loaded Vision model
    func processImage(image: UIImage, prompt: String = "Describe this image in detail.") async throws -> String {
        // Auto-load logic specific to VLM
        if vlmContainer == nil, let id = currentModelId, MLXModelRegistry.model(withId: id)?.modelType == .vision {
            try await loadModel(modelId: id)
        }
        
        guard let container = vlmContainer else {
            // If user has LLM loaded but tries vision, error out
            throw MLXError.invalidConfiguration
        }
        
        // VLM Generation Loop
        // 1. Prepare Input (Prompt + Image)
        // Convert UIImage to CIImage as expected by MLX image processor
        guard let ciImage = CIImage(image: image) else {
            throw MLXError.generationFailed("Failed to convert UIImage to CIImage")
        }
        
        let userInput = UserInput(prompt: prompt, images: [.ciImage(ciImage)])
        let input = try await container.processor.prepare(input: userInput)
        
        // 2. Generate
        let startTime = Date()
        var fullText = ""

        let params = GenerateParameters(
            maxTokens: 2048,   // Enough for a full page
            temperature: 0.1   // Low temp for OCR accuracy
        )
        
        let result = try MLXLMCommon.generate(
            input: input,
            parameters: params,
            context: container
        )
        
        for try await output in result {
            switch output {
            case .chunk(let text):
                fullText += text
            default: break
            }
        }
        
        logger.info("👁️ Vision processing complete in \(Date().timeIntervalSince(startTime))s")
        
        return fullText
    }

    // MARK: - Lifecycle & Utils
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("⚠️ Memory Warning - Clearing Cache")
        GPU.clearCache()
        Stream.gpu.synchronize()
    }
    
    func scanDownloadedModels() {
        if let saved = UserDefaults.standard.array(forKey: "MLXDownloadedModels") as? [String] {
            downloadedModelIds = Set(saved)
        }
    }
    
    private func saveDownloadedModels() {
        UserDefaults.standard.set(Array(downloadedModelIds), forKey: "MLXDownloadedModels")
    }
    
    // Protocol Stubs
    func testConnection() async throws -> Bool { return isConnected }
    
    func sendMessage(_ message: String, context: String) async throws -> AIResponse {
        var finalResponse: MLXResponse?
        
        // Log start memory
        let startActive = Double(GPU.activeMemory) / 1024 / 1024
        let startCache = Double(GPU.cacheMemory) / 1024 / 1024
        Logger.shared.info("🧠 MLX Start: Active: \(String(format: "%.1f", startActive))MB, Cache: \(String(format: "%.1f", startCache))MB")
        
        // Ensure cleanup happens after this operation to prevent memory accumulation (e.g. during batch processing)
        defer {
            let endActive = Double(GPU.activeMemory) / 1024 / 1024
            let endCache = Double(GPU.cacheMemory) / 1024 / 1024
            Logger.shared.info("🧠 MLX End: Active: \(String(format: "%.1f", endActive))MB, Cache: \(String(format: "%.1f", endCache))MB")
            
            Task { @MainActor in
                Stream.gpu.synchronize()
                GPU.clearCache()
            }
        }
        
        try await sendStreamingChatMessage(
            message,
            context: context,
            systemPrompt: nil,
            conversationHistory: [],
            conversationId: nil,
            onUpdate: { _ in },
            onComplete: { response in
                finalResponse = response
                if let count = response.tokenCount {
                    let speed = Double(count) / response.responseTime
                    Logger.shared.info("⚡️ MLX Speed: \(String(format: "%.2f", speed)) tok/s (\(count) tokens in \(String(format: "%.1f", response.responseTime))s)")
                }
            }
        )
        
        guard let response = finalResponse else {
            throw MLXError.generationFailed("No response generated")
        }
        
        return response
    }
    
    func getCapabilities() async throws -> AICapabilities {
        return AICapabilities(supportedModels: ["mlx"], maxTokens: 4096, supportsStreaming: true, supportsImages: true, supportsDocuments: true, supportedLanguages: ["en"])
    }
    func updateConfiguration(_ config: AIProviderConfig) async throws {}
}

// MARK: - MLX Docling Client

/// A local alternative to the remote DoclingClient, running granite-docling on-device via MLXClient.
@MainActor
class MLXDoclingClient: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = MLXDoclingClient()
    
    // MARK: - Configuration
    // The specific model ID for Granite Docling
    let modelId = "granite-docling-258M-mlx"
    
    // MARK: - Public API
    
    /// Process a document locally using MLX
    /// - Parameters:
    ///   - documentData: The raw PDF or Image data
    ///   - type: The file type
    /// - Returns: A ProcessedDocumentResult compatible with the rest of the app
    func processDocument(_ documentData: Data, type: DocumentType) async throws -> ProcessedDocumentResult {
        guard type == .pdf || type.isImage else {
            throw DoclingError.unsupportedFormat
        }
        
        // 1. Ensure the correct model is loaded in MLXClient
        // This will trigger the auto-load logic in MLXClient if not already loaded
        // We explicitly ask for the docling model ID
        if MLXClient.shared.currentModelId != modelId {
            print("🔄 MLXDocling: Switching to model \(modelId)")
            try await MLXClient.shared.loadModel(modelId: modelId)
        }
        
        // 2. Convert input to images
        let images = try convertToImages(data: documentData, type: type)
        
        var combinedMarkdown = ""
        let structuredData: [String: Any] = [: ]
        let startTime = Date()
        
        // 3. Process each page
        // Docling Prompt: "Convert this document image into clean Markdown tables."
        let prompt = "Convert this document image into clean Markdown tables."
        
        for (index, image) in images.enumerated() {
            print("📄 MLXDocling: Processing page \(index + 1)/\(images.count)")
            
            // Call the Unified MLX Client
            let pageText = try await MLXClient.shared.processImage(image: image, prompt: prompt)
            
            combinedMarkdown += pageText + "\n\n"
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return ProcessedDocumentResult(
            extractedText: combinedMarkdown,
            structuredData: structuredData,
            confidence: 0.95, // Placeholder
            processingTime: processingTime,
            metadata: [
                "processor": "local-mlx-granite",
                "model": modelId,
                "pages": String(images.count)
            ]
        )
    }
    
    // MARK: - Private Helpers
    
    private func convertToImages(data: Data, type: DocumentType) throws -> [UIImage] {
        if type.isImage {
            guard let image = UIImage(data: data) else {
                throw DoclingError.invalidRequest
            }
            return [image]
        } else if type == .pdf {
            // Use PDFKit to render pages to UIImages
            guard let provider = CGDataProvider(data: data as CFData),
                  let pdfDoc = CGPDFDocument(provider) else {
                throw DoclingError.invalidRequest
            }
            
            var images: [UIImage] = []
            let pageCount = pdfDoc.numberOfPages
            
            for pageIndex in 1...pageCount {
                guard let page = pdfDoc.page(at: pageIndex) else { continue }
                
                let pageRect = page.getBoxRect(.mediaBox)
                let renderer = UIGraphicsImageRenderer(size: pageRect.size)
                
                let image = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(pageRect)
                    
                    ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                    ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                    
                    ctx.cgContext.drawPDFPage(page)
                }
                images.append(image)
            }
            
            return images
        }
        return []
    }
}

// MARK: - Device Memory Utility

/// Utility for detecting device memory and calculating appropriate MLX cache limits
enum DeviceMemory {

    /// Get total physical memory in bytes
    static func getTotalMemory() -> UInt64 {
        return ProcessInfo.processInfo.physicalMemory
    }

    /// Get total memory in gigabytes
    static func getTotalMemoryGB() -> Double {
        return Double(getTotalMemory()) / 1_073_741_824.0 // 1024^3
    }

    /// Get recommended GPU cache limit based on device memory
    /// - Returns: Cache limit in bytes
    static func getRecommendedGPUCacheLimit() -> Int {
        let totalMemoryGB = getTotalMemoryGB()

        // Conservative allocation strategy:
        // - Lower memory devices (< 4GB): 128MB cache
        // - Mid-range devices (4-6GB): 256MB cache
        // - Higher memory devices (6-8GB): 384MB cache
        // - High-end devices (> 8GB): 512MB cache

        let cacheMB: Int
        if totalMemoryGB < 4.0 {
            cacheMB = 128
        } else if totalMemoryGB < 6.0 {
            cacheMB = 256
        } else if totalMemoryGB < 8.0 {
            cacheMB = 384
        } else {
            cacheMB = 512
        }

        os_log(.info, "📊 Device memory: %.2f GB, setting GPU cache to %d MB", totalMemoryGB, cacheMB)

        return cacheMB * 1024 * 1024  // Convert to bytes
    }

    /// Check if device has sufficient memory for MLX inference
    /// - Parameter minimumGB: Minimum memory required in GB (default: 3.0)
    /// - Returns: True if device has sufficient memory
    static func hasSufficientMemory(minimumGB: Double = 3.0) -> Bool {
        let totalMemoryGB = getTotalMemoryGB()
        return totalMemoryGB >= minimumGB
    }

    /// Get available memory warning threshold
    /// - Returns: Memory threshold in bytes for triggering warnings
    static func getLowMemoryThreshold() -> UInt64 {
        return 500 * 1024 * 1024  // 500MB
    }
}
