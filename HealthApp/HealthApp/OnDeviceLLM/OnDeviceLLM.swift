//
//  OnDeviceLLM.swift
//  HealthApp
//
//  Core on-device LLM inference engine using llama.cpp
//  Adapted from BisonNotes AI
//

import Foundation
import llama

// MARK: - On-Device LLM Class

/// Base class for on-device Large Language Model inference
open class OnDeviceLLM: ObservableObject {

    // MARK: - Public Properties

    /// The underlying LLaMA model pointer
    public var model: LLMModel

    /// Array of chat messages
    public var history: [LLMChat]

    /// Closure to preprocess input before sending to the model
    public var preprocess: (_ input: String, _ history: [LLMChat], _ llmInstance: OnDeviceLLM) -> String = { input, _, _ in return input }

    /// Closure called when generation is complete with the final output
    public var postprocess: (_ output: String) -> Void = { _ in }

    /// Closure called during generation with incremental output
    public var update: (_ outputDelta: String?) -> Void = { _ in }

    /// Template controlling model input/output formatting
    public var template: LLMTemplate? = nil {
        didSet {
            guard let template else {
                preprocess = { input, _, _ in return input }
                stopSequences = []
                stopSequenceLengths = []
                return
            }
            preprocess = template.preprocess
            stopSequences = template.stopSequences.map {
                let cString = $0.utf8CString
                return ContiguousArray(cString.dropLast())
            }
            stopSequenceLengths = stopSequences.map { $0.count - 1 }
        }
    }

    /// Sampling parameters
    public var topK: Int32
    public var topP: Float
    public var minP: Float
    public var temp: Float
    public var repeatPenalty: Float

    /// Path to the model file
    public var path: [CChar]

    /// Cached model state for continuation
    public var savedState: Data?

    /// Metrics for tracking inference performance
    public var metrics = InferenceMetrics()

    /// Current generated output text
    @Published public private(set) var output = ""

    @MainActor public func setOutput(to newOutput: consuming String) {
        output = newOutput
    }

    // MARK: - Private Properties

    private var batch: llama_batch!
    private var context: LLMContext!
    private var decoded = ""
    private var inferenceTask: Task<Void, Never>?
    private var input: String = ""
    private var isAvailable = true
    private let newlineToken: Token
    private let maxTokenCount: Int
    private var multibyteCharacter: [CUnsignedChar] = []
    private var params: llama_context_params
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var stopSequences: [ContiguousArray<CChar>] = []
    private var stopSequenceLengths: [Int] = []
    private let totalTokenCount: Int
    private var updateProgress: (Double) -> Void = { _ in }
    private var nPast: Int32 = 0
    private var inputTokenCount: Int32 = 0

    /// Maximum tokens to generate in a single response (prevents runaway generation)
    private let maxOutputTokens: Int32 = 2048

    // MARK: - Initialization

    public init(
        from path: String,
        stopSequences: [String] = [],
        stopSequence: String? = nil,
        history: [LLMChat] = [],
        seed: UInt32 = .random(in: .min ... .max),
        topK: Int32 = 40,
        topP: Float = 0.95,
        minP: Float = 0.0,
        temp: Float = 0.7,
        repeatPenalty: Float = 1.1,
        maxTokenCount: Int32 = 2048
    ) {
        self.path = path.cString(using: .utf8)!
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
            modelParams.n_gpu_layers = 0
            print("[OnDeviceLLM] Running on simulator - GPU layers disabled")
        #else
            modelParams.n_gpu_layers = 999
            print("[OnDeviceLLM] Requesting all layers on GPU (n_gpu_layers=999)")
        #endif
        guard let model = llama_model_load_from_file(self.path, modelParams) else {
            fatalError("[OnDeviceLLM] Failed to load model from: \(path)")
        }

        let modelSize = llama_model_size(model)
        let modelParams_n = llama_model_n_params(model)
        print("[OnDeviceLLM] Model loaded - size: \(modelSize / 1_000_000)MB, params: \(modelParams_n / 1_000_000)M")
        self.params = llama_context_default_params()
        let processorCount = Int32(ProcessInfo().processorCount)
        let modelTrainCtx = llama_model_n_ctx_train(model)
        self.maxTokenCount = Int(min(maxTokenCount, modelTrainCtx))
        self.params.n_ctx = UInt32(self.maxTokenCount)
        self.params.n_batch = 512
        self.params.n_threads = processorCount
        self.params.n_threads_batch = processorCount

        // Enable quantized KV cache to reduce memory usage
        // Q4_1 reduces KV cache memory by ~75% with acceptable quality trade-off
        // This is critical for running on iPhone with limited memory
        self.params.type_k = GGML_TYPE_Q4_1  // Quantize K cache to Q4_1
        self.params.type_v = GGML_TYPE_Q4_1  // Quantize V cache to Q4_1

        print("[OnDeviceLLM] Context: n_ctx=\(self.maxTokenCount), n_batch=512, model_train_ctx=\(modelTrainCtx), threads=\(processorCount), kv_cache=Q4_1")
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.temp = temp
        self.repeatPenalty = repeatPenalty
        self.model = model
        self.history = history
        self.totalTokenCount = Int(llama_vocab_n_tokens(llama_model_get_vocab(model)))
        self.newlineToken = model.newLineToken

        var sequences = stopSequences
        if let s = stopSequence, !sequences.contains(s) {
            sequences.append(s)
        }
        self.stopSequences = sequences.map {
            let cString = $0.utf8CString
            return ContiguousArray(cString.dropLast())
        }
        self.stopSequenceLengths = self.stopSequences.map { $0.count - 1 }

        self.batch = llama_batch_init(Int32(self.maxTokenCount), 0, 1)

        let sparams = llama_sampler_chain_default_params()
        self.sampler = llama_sampler_chain_init(sparams)

        if let sampler = self.sampler {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(topK))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(topP, 1))
            if minP > 0 {
                llama_sampler_chain_add(sampler, llama_sampler_init_min_p(minP, 1))
            }
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, repeatPenalty, 0.0, 0.0))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed))
        }
    }

    public convenience init(
        from url: URL,
        template: LLMTemplate,
        history: [LLMChat] = [],
        seed: UInt32 = .random(in: .min ... .max),
        topK: Int32 = 40,
        topP: Float = 0.95,
        minP: Float = 0.0,
        temp: Float = 0.7,
        repeatPenalty: Float = 1.1,
        maxTokenCount: Int32 = 2048
    ) {
        self.init(
            from: url.path,
            stopSequences: template.stopSequences,
            history: history,
            seed: seed,
            topK: topK,
            topP: topP,
            minP: minP,
            temp: temp,
            repeatPenalty: repeatPenalty,
            maxTokenCount: maxTokenCount
        )
        self.preprocess = template.preprocess
        self.template = template
    }

    deinit {
        // Cancel any ongoing inference
        inferenceTask?.cancel()
        inferenceTask = nil

        // Clean up in correct order: sampler → batch → context → model
        // Context must be freed BEFORE model (context references model)
        if let sampler = self.sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }
        llama_batch_free(self.batch)
        self.context = nil  // LLMContext deinit calls llama_free(pointer)
        llama_model_free(self.model)
    }

    // MARK: - Public Methods

    /// Stops ongoing text generation
    @InferenceActor
    public func stop() {
        guard self.inferenceTask != nil else { return }
        self.inferenceTask?.cancel()
        self.inferenceTask = nil
        self.batch.clear()
    }

    /// Properly shut down the LLM, waiting for any ongoing inference to complete.
    /// Call this before releasing the OnDeviceLLM instance to ensure clean shutdown.
    @InferenceActor
    public func shutdown() async {
        // Cancel any ongoing inference and wait for it to complete
        if let task = self.inferenceTask {
            task.cancel()
            _ = await task.result
            self.inferenceTask = nil
        }

        // Clear the batch
        self.batch.clear()

        // Free the context while we're on the InferenceActor
        // This ensures no concurrent access during cleanup
        self.context = nil
    }

    /// Clears conversation history and resets model state
    @InferenceActor
    public func clearHistory() async {
        history.removeAll()
        nPast = 0
        await setOutput(to: "")
        context = nil
        savedState = nil
        self.batch.clear()
    }

    /// Generates a response to the given input
    open func respond(to input: String) async {
        if let savedState = OnDeviceLLMFeatureFlags.useLLMCaching ? self.savedState : nil {
            await restoreState(from: savedState)
        }

        await performInference(to: input) { [self] response in
            await setOutput(to: "")
            for await responseDelta in response {
                update(responseDelta)
                await setOutput(to: output + responseDelta)
            }
            update(nil)
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

            self.rollbackLastUserInputIfEmptyResponse(trimmedOutput)

            await setOutput(to: trimmedOutput.isEmpty ? "..." : trimmedOutput)
            return output
        }
    }

    /// Single-shot generation without streaming
    public func generate(from input: String) async -> String {
        await respond(to: input)
        return output
    }

    // MARK: - Token Encoding/Decoding

    @inlinable
    public func encode(_ text: borrowing String) -> [Token] {
        model.encode(text)
    }

    private func decode(_ token: Token) -> String {
        multibyteCharacter.removeAll(keepingCapacity: true)
        return model.decode(token, with: &multibyteCharacter)
    }

    // MARK: - Private Inference Methods

    @InferenceActor
    private func predictNextToken() async -> Token {
        guard let context = self.context else { return self.model.endToken }
        guard !Task.isCancelled else { return self.model.endToken }
        guard self.inferenceTask != nil else { return self.model.endToken }
        guard self.batch.n_tokens > 0 else {
            print("Error: Batch is empty or invalid.")
            return model.endToken
        }
        guard self.batch.n_tokens < self.maxTokenCount else {
            print("Error: Batch token limit exceeded.")
            return model.endToken
        }
        guard let sampler = self.sampler else {
            fatalError("Sampler not initialized")
        }

        let token = llama_sampler_sample(sampler, context.pointer, self.batch.n_tokens - 1)
        metrics.recordToken()

        self.batch.clear()
        self.batch.add(token, self.nPast, [0], true)
        self.nPast += 1

        if !context.decode(self.batch) {
            print("[OnDeviceLLM] Decode failed during token prediction, ending generation")
            return self.model.endToken
        }
        return token
    }

    @InferenceActor
    private func tokenizeAndBatchInput(message input: borrowing String) -> Bool {
        guard self.inferenceTask != nil else { return false }
        guard !input.isEmpty else { return false }
        context = context ?? LLMContext(model, params)
        self.batch.clear()
        var tokens = encode(input)

        let outputReserve = min(2048, max(256, maxTokenCount / 10))
        let maxInputTokens = maxTokenCount - outputReserve
        if tokens.count > maxInputTokens {
            print("[OnDeviceLLM] Input too long (\(tokens.count) tokens), truncating to \(maxInputTokens) (reserving \(outputReserve) for output)")
            tokens = Array(tokens.prefix(maxInputTokens))
        }

        self.inputTokenCount = Int32(tokens.count)
        metrics.inputTokenCount = self.inputTokenCount

        if self.maxTokenCount <= self.nPast + self.inputTokenCount {
            self.trimKvCache()
        }

        let batchSize = Int(self.params.n_batch)
        let totalTokens = tokens.count
        var tokenIndex = 0

        print("[OnDeviceLLM] Processing \(totalTokens) input tokens in batches of \(batchSize)")

        while tokenIndex < totalTokens {
            self.batch.clear()

            let remainingTokens = totalTokens - tokenIndex
            let currentBatchSize = min(batchSize, remainingTokens)
            let isLastBatch = tokenIndex + currentBatchSize >= totalTokens

            for i in 0..<currentBatchSize {
                let token = tokens[tokenIndex + i]
                let isLastTokenInInput = isLastBatch && (i == currentBatchSize - 1)
                self.batch.add(token, self.nPast, [0], isLastTokenInInput)
                self.nPast += 1
            }

            guard self.batch.n_tokens > 0 else { return false }

            if !self.context.decode(self.batch) {
                print("[OnDeviceLLM] Batch decode failed at token \(tokenIndex)")
                return false
            }

            tokenIndex += currentBatchSize

            if OnDeviceLLMFeatureFlags.verboseLogging {
                print("[OnDeviceLLM] Processed batch: \(tokenIndex)/\(totalTokens) tokens")
            }
        }

        print("[OnDeviceLLM] Prefill complete: \(totalTokens) tokens processed")
        return true
    }

    @InferenceActor
    private func emitDecoded(token: Token, to output: borrowing AsyncStream<String>.Continuation) -> Bool {
        struct saved {
            static var matchIndices: [Int] = []
            static var letters: [CChar] = []
            static var tokenCount: Int = 0  // Track tokens emitted for early flushing
        }
        guard self.inferenceTask != nil else { return false }

        // Check for any end token (EOS, EOT, or any EOG token)
        // Uses llama_vocab_is_eog() to handle models with multiple end tokens
        guard !model.isEndToken(token) else {
            // Reset static state when we hit an end token
            saved.matchIndices = []
            saved.letters = []
            saved.tokenCount = 0  // Reset for next generation
            if OnDeviceLLMFeatureFlags.verboseLogging {
                print("[OnDeviceLLM] Hit EOG token \(token), stopping generation")
            }
            return false
        }

        let word = decode(token)

        // Some models output empty tokens at the end - treat as completion
        if word.isEmpty {
            saved.matchIndices = []
            saved.letters = []
            saved.tokenCount = 0  // Reset for next generation
            return false
        }

        guard !stopSequences.isEmpty else {
            output.yield(word)
            return true
        }

        if saved.matchIndices.count != stopSequences.count {
            saved.matchIndices = Array(repeating: 0, count: stopSequences.count)
        }

        // Maximum characters to buffer while checking for stop sequences (prevents excessive buffering)
        // Use VERY aggressive flushing for first few tokens to ensure immediate streaming feedback
        // First 3 tokens: flush immediately (1 char buffer)
        // Next 5 tokens: flush quickly (5 char buffer)
        // Later tokens: normal flushing (50 char buffer)
        let maxBufferSize: Int
        if saved.tokenCount < 3 {
            maxBufferSize = 1  // Immediate feedback for first 3 tokens
        } else if saved.tokenCount < 8 {
            maxBufferSize = 5  // Quick feedback for next 5 tokens
        } else {
            maxBufferSize = 50  // Normal buffering after that
        }

        saved.tokenCount += 1  // Increment token count

        for letter in word.utf8CString {
            guard letter != 0 else { break }

            var anyMatch = false
            var fullMatch = false

            for (index, sequence) in stopSequences.enumerated() {
                let matchIndex = saved.matchIndices[index]
                if letter == sequence[matchIndex] {
                    saved.matchIndices[index] += 1
                    if saved.matchIndices[index] > stopSequenceLengths[index] {
                        fullMatch = true
                        break
                    }
                    anyMatch = true
                } else {
                    saved.matchIndices[index] = 0
                    if letter == sequence[0] {
                        saved.matchIndices[index] = 1
                        if 0 == stopSequenceLengths[index] {
                            fullMatch = true
                            break
                        }
                        anyMatch = true
                    }
                }
            }

            if fullMatch {
                saved.matchIndices = Array(repeating: 0, count: stopSequences.count)
                saved.letters.removeAll()
                saved.tokenCount = 0  // Reset for next generation
                return false
            }

            if anyMatch {
                saved.letters.append(letter)

                // STREAMING FIX: If buffer gets too large, flush it to prevent UI lag
                // This prevents excessive buffering when text happens to partially match stop sequences
                // Use smaller threshold for first few tokens to ensure immediate visual feedback
                if saved.letters.count >= maxBufferSize {
                    if OnDeviceLLMFeatureFlags.verboseLogging {
                        print("[OnDeviceLLM] Stop sequence buffer limit reached (\(saved.letters.count) chars), flushing to stream")
                    }
                    let bufferedContent = String(cString: saved.letters + [0])
                    output.yield(bufferedContent)
                    saved.letters.removeAll()
                    saved.matchIndices = Array(repeating: 0, count: stopSequences.count)
                }
            } else {
                if !saved.letters.isEmpty {
                    let prefix = String(cString: saved.letters + [0])
                    output.yield(prefix)
                    saved.letters.removeAll()
                }
                output.yield(String(cString: [letter, 0]))
            }
        }
        return true
    }

    @InferenceActor
    private func generateResponseStream(from input: String) -> AsyncStream<String> {
        AsyncStream<String> { output in
            Task { @InferenceActor [weak self] in
                guard let self = self else { return output.finish() }
                guard self.inferenceTask != nil else { return output.finish() }

                defer {
                    if !OnDeviceLLMFeatureFlags.useLLMCaching {
                        // Context cleanup now runs on InferenceActor
                        self.context = nil
                    }
                }

                guard self.tokenizeAndBatchInput(message: input) else {
                    return output.finish()
                }

                metrics.start()
                print("[OnDeviceLLM] Prefill done, starting generation...")
                var outputTokenCount: Int32 = 0
                var token = await self.predictNextToken()

                while self.emitDecoded(token: token, to: output) {
                    outputTokenCount += 1

                    // Log first token for streaming diagnostics
                    if outputTokenCount == 1 {
                        print("[OnDeviceLLM] First token emitted, streaming started")
                    }

                    // Check if we've hit the max output token limit
                    if outputTokenCount >= self.maxOutputTokens {
                        print("[OnDeviceLLM] Hit max output tokens limit (\(self.maxOutputTokens)), stopping generation")
                        break
                    }

                    if self.nPast >= self.maxTokenCount {
                        self.trimKvCache()
                    }
                    token = await self.predictNextToken()
                }

                metrics.stop()
                let tokensPerSec = metrics.inferenceTokensPerSecond
                print("[OnDeviceLLM] Generation complete: \(outputTokenCount) output tokens at \(String(format: "%.1f", tokensPerSec)) tokens/sec")
                output.finish()
            }
        }
    }

    @InferenceActor
    private func trimKvCache() {
        let seq_id: Int32 = 0
        let beginning: Int32 = 0
        let middle = Int32(self.maxTokenCount / 2)

        let memory = llama_get_memory(self.context.pointer)
        _ = llama_memory_seq_rm(memory, seq_id, beginning, middle)
        llama_memory_seq_add(memory, seq_id, middle, Int32(self.maxTokenCount), -middle)

        let kvCacheTokenCount: Int32 = llama_memory_seq_pos_max(memory, seq_id)
        self.nPast = kvCacheTokenCount + 1
        if OnDeviceLLMFeatureFlags.verboseLogging {
            print("kv cache trimmed: llama_kv_cache(\(kvCacheTokenCount) nPast(\(self.nPast))")
        }
    }

    @InferenceActor
    public func performInference(to input: String, with makeOutputFrom: @escaping (AsyncStream<String>) async -> String) async {
        self.inferenceTask?.cancel()
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            self.input = input
            let processedInput = self.preprocess(input, self.history, self)
            let responseStream = self.generateResponseStream(from: processedInput)

            let output = (await makeOutputFrom(responseStream)).trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                if !output.isEmpty {
                    self.history.append(LLMChat(role: .bot, content: output))
                }
                self.postprocess(output)
            }

            self.inputTokenCount = 0
            if OnDeviceLLMFeatureFlags.useLLMCaching {
                self.savedState = saveState()
            }

            if Task.isCancelled {
                return
            }
        }

        await inferenceTask?.value
    }

    private func rollbackLastUserInputIfEmptyResponse(_ response: String) {
        if response.isEmpty && self.inputTokenCount > 0 {
            let seq_id = Int32(0)
            let startIndex = self.nPast - self.inputTokenCount
            let endIndex = self.nPast
            let memory = llama_get_memory(self.context.pointer)
            _ = llama_memory_seq_rm(memory, seq_id, startIndex, endIndex)
            self.nPast = startIndex
        }
    }
}

// MARK: - State Management Extension

extension OnDeviceLLM {

    @InferenceActor
    public func saveState() -> Data? {
        guard let contextPointer = self.context?.pointer else {
            print("Error: llama_context pointer is nil.")
            return nil
        }

        let stateSize = llama_state_get_size(contextPointer)
        guard stateSize > 0 else {
            print("Error: Unable to retrieve state size.")
            return nil
        }

        var stateData = Data(count: stateSize)
        stateData.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            if let baseAddress = pointer.baseAddress {
                let bytesWritten = llama_state_get_data(contextPointer, baseAddress.assumingMemoryBound(to: UInt8.self), stateSize)
                assert(bytesWritten == stateSize, "Error: Written state size does not match expected size.")
            }
        }
        return stateData
    }

    @InferenceActor
    public func restoreState(from stateData: Data) {
        guard let contextPointer = self.context?.pointer else {
            print("Error: llama_context pointer is nil.")
            return
        }

        stateData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            if let baseAddress = pointer.baseAddress {
                let bytesRead = llama_state_set_data(contextPointer, baseAddress.assumingMemoryBound(to: UInt8.self), stateData.count)
                assert(bytesRead == stateData.count, "Error: Read state size does not match expected size.")
            }
        }

        let beginningOfSequenceOffset: Int32 = 1
        let memory = llama_get_memory(self.context.pointer)
        let maxPos = llama_memory_seq_pos_max(memory, 0)
        self.nPast = maxPos + beginningOfSequenceOffset
    }

    /// Restore the savedState property without restoring to context
    /// Used to preserve conversation state after non-conversational tasks
    @InferenceActor
    public func restoreSavedState(_ state: Data) {
        self.savedState = state
    }
}
