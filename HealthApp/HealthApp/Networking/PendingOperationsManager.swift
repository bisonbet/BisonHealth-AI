import Foundation
import Combine

// MARK: - Pending Operations Manager
/// Manages queuing and retry logic for operations that fail due to network issues
@MainActor
class PendingOperationsManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = PendingOperationsManager()

    // MARK: - Published Properties
    @Published var pendingOperations: [PendingOperation] = []
    @Published var isProcessingQueue: Bool = false
    @Published var lastError: Error?

    // MARK: - Private Properties
    private let maxRetryAttempts = 5
    private let persistenceKey = "com.bisonhealth.pendingoperations"
    private var cancellables = Set<AnyCancellable>()
    private var retryTimers: [UUID: Task<Void, Never>] = [:]

    // MARK: - Initialization
    private init() {
        loadPersistedOperations()
        setupNetworkMonitoring()
    }

    // MARK: - Public Methods

    /// Add a chat message operation to the queue
    func queueChatMessage(
        conversationId: UUID,
        message: String,
        context: String,
        useStreaming: Bool,
        model: String,
        systemPrompt: String?
    ) async {
        let operation = PendingOperation(
            type: .chatMessage(
                conversationId: conversationId,
                message: message,
                context: context,
                useStreaming: useStreaming,
                model: model,
                systemPrompt: systemPrompt
            )
        )

        await addOperation(operation)
    }

    /// Add a document processing operation to the queue
    func queueDocumentProcessing(documentId: UUID, immediately: Bool) async {
        let operation = PendingOperation(
            type: .documentProcessing(documentId: documentId, immediately: immediately)
        )

        await addOperation(operation)
    }

    /// Manually retry a specific operation
    func retryOperation(_ operation: PendingOperation) async {
        guard let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) else {
            return
        }

        var updatedOperation = pendingOperations[index]
        updatedOperation.retryCount += 1
        updatedOperation.lastAttempt = Date()
        pendingOperations[index] = updatedOperation

        await executeOperation(updatedOperation)
    }

    /// Retry all pending operations
    func retryAllOperations() async {
        guard !isProcessingQueue else {
            print("⚠️ PendingOperationsManager: Already processing queue")
            return
        }

        print("🔄 PendingOperationsManager: Retrying all \(pendingOperations.count) pending operations")
        await processQueue()
    }

    /// Cancel a specific operation
    func cancelOperation(_ operationId: UUID) {
        pendingOperations.removeAll { $0.id == operationId }
        retryTimers[operationId]?.cancel()
        retryTimers.removeValue(forKey: operationId)
        persistOperations()
    }

    /// Cancel all pending operations
    func cancelAllOperations() {
        pendingOperations.removeAll()
        retryTimers.values.forEach { $0.cancel() }
        retryTimers.removeAll()
        persistOperations()
    }

    /// Get count of pending operations by type
    func pendingCount(for type: OperationType) -> Int {
        return pendingOperations.filter { operation in
            switch (operation.type, type) {
            case (.chatMessage, .chatMessage),
                 (.documentProcessing, .documentProcessing):
                return true
            default:
                return false
            }
        }.count
    }

    // MARK: - Private Methods

    private func addOperation(_ operation: PendingOperation) async {
        // Check for duplicates
        let isDuplicate = pendingOperations.contains { pending in
            pending.type.isSimilar(to: operation.type)
        }

        guard !isDuplicate else {
            print("⚠️ PendingOperationsManager: Skipping duplicate operation")
            return
        }

        pendingOperations.append(operation)
        print("📥 PendingOperationsManager: Queued operation \(operation.type.displayName)")
        persistOperations()

        // Schedule retry with exponential backoff
        await scheduleRetry(for: operation)
    }

    private func scheduleRetry(for operation: PendingOperation) async {
        // Calculate backoff delay: 2^retryCount seconds (2s, 4s, 8s, 16s, 32s)
        let baseDelay = 2.0
        let delay = min(baseDelay * pow(2.0, Double(operation.retryCount)), 60.0) // Max 60s

        print("⏰ PendingOperationsManager: Scheduling retry for \(operation.type.displayName) in \(delay)s")

        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await executeOperation(operation)
        }

        retryTimers[operation.id] = task
    }

    private func executeOperation(_ operation: PendingOperation) async {
        guard NetworkManager.shared.isConnected else {
            print("⚠️ PendingOperationsManager: Network not available, will retry when connected")
            return
        }

        guard let index = pendingOperations.firstIndex(where: { $0.id == operation.id }) else {
            return
        }

        print("🚀 PendingOperationsManager: Executing operation \(operation.type.displayName)")

        do {
            switch operation.type {
            case .chatMessage(let conversationId, let message, let context, let useStreaming, let model, let systemPrompt):
                try await executeChatMessage(
                    conversationId: conversationId,
                    message: message,
                    context: context,
                    useStreaming: useStreaming,
                    model: model,
                    systemPrompt: systemPrompt
                )

            case .documentProcessing(let documentId, let immediately):
                try await executeDocumentProcessing(documentId: documentId, immediately: immediately)
            }

            // Success - remove from queue
            pendingOperations.remove(at: index)
            retryTimers.removeValue(forKey: operation.id)
            persistOperations()
            print("✅ PendingOperationsManager: Operation completed successfully")

        } catch {
            print("❌ PendingOperationsManager: Operation failed: \(error.localizedDescription)")

            let networkError = NetworkError.from(error: error)

            // Check if retryable
            if networkError.isRetryable && operation.retryCount < maxRetryAttempts {
                // Update retry count
                var updatedOperation = pendingOperations[index]
                updatedOperation.retryCount += 1
                updatedOperation.lastAttempt = Date()
                updatedOperation.lastError = error
                pendingOperations[index] = updatedOperation
                persistOperations()

                // Schedule next retry
                await scheduleRetry(for: updatedOperation)
            } else {
                // Max retries reached or not retryable - mark as failed
                var updatedOperation = pendingOperations[index]
                updatedOperation.status = .failed
                updatedOperation.lastError = error
                pendingOperations[index] = updatedOperation
                persistOperations()

                print("💀 PendingOperationsManager: Operation failed permanently after \(operation.retryCount) retries")
            }
        }
    }

    private func executeChatMessage(
        conversationId: UUID,
        message: String,
        context: String,
        useStreaming: Bool,
        model: String,
        systemPrompt: String?
    ) async throws {
        // Get the chat manager and retry the message
        // This is a placeholder - actual implementation would need dependency injection
        print("🔄 PendingOperationsManager: Retrying chat message for conversation \(conversationId)")
        throw NetworkError.notConnected // Placeholder
    }

    private func executeDocumentProcessing(documentId: UUID, immediately: Bool) async throws {
        // Get the document manager and retry processing
        // This is a placeholder - actual implementation would need dependency injection
        print("🔄 PendingOperationsManager: Retrying document processing for \(documentId)")
        throw NetworkError.notConnected // Placeholder
    }

    private func processQueue() async {
        guard !isProcessingQueue else { return }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        let operationsToRetry = pendingOperations.filter { $0.status == .pending }

        for operation in operationsToRetry {
            await executeOperation(operation)
        }
    }

    private func setupNetworkMonitoring() {
        NetworkManager.shared.statusPublisher
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    if status.isConnected && !self.pendingOperations.isEmpty {
                        print("✅ PendingOperationsManager: Network restored, processing \(self.pendingOperations.count) pending operations")
                        await self.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func persistOperations() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pendingOperations)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            print("❌ PendingOperationsManager: Failed to persist operations: \(error)")
        }
    }

    private func loadPersistedOperations() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            pendingOperations = try decoder.decode([PendingOperation].self, from: data)
            print("📥 PendingOperationsManager: Loaded \(pendingOperations.count) persisted operations")
        } catch {
            print("❌ PendingOperationsManager: Failed to load persisted operations: \(error)")
        }
    }
}

// MARK: - Pending Operation Model

struct PendingOperation: Identifiable, Codable, Equatable {
    let id: UUID
    let type: OperationType
    var status: OperationStatus
    var retryCount: Int
    var createdAt: Date
    var lastAttempt: Date?
    var lastError: Error?

    init(type: OperationType) {
        self.id = UUID()
        self.type = type
        self.status = .pending
        self.retryCount = 0
        self.createdAt = Date()
        self.lastAttempt = nil
        self.lastError = nil
    }

    // Custom Codable implementation to handle Error
    enum CodingKeys: String, CodingKey {
        case id, type, status, retryCount, createdAt, lastAttempt, lastErrorDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(OperationType.self, forKey: .type)
        status = try container.decode(OperationStatus.self, forKey: .status)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastAttempt = try container.decodeIfPresent(Date.self, forKey: .lastAttempt)
        // Error is not decoded, just description
        lastError = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastAttempt, forKey: .lastAttempt)
        try container.encodeIfPresent(lastError?.localizedDescription, forKey: .lastErrorDescription)
    }

    static func == (lhs: PendingOperation, rhs: PendingOperation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Operation Type

enum OperationType: Codable, Equatable {
    case chatMessage(
        conversationId: UUID,
        message: String,
        context: String,
        useStreaming: Bool,
        model: String,
        systemPrompt: String?
    )
    case documentProcessing(documentId: UUID, immediately: Bool)

    var displayName: String {
        switch self {
        case .chatMessage:
            return "Chat Message"
        case .documentProcessing:
            return "Document Processing"
        }
    }

    func isSimilar(to other: OperationType) -> Bool {
        switch (self, other) {
        case (.chatMessage(let id1, let msg1, _, _, _, _), .chatMessage(let id2, let msg2, _, _, _, _)):
            return id1 == id2 && msg1 == msg2
        case (.documentProcessing(let id1, _), .documentProcessing(let id2, _)):
            return id1 == id2
        default:
            return false
        }
    }
}

// MARK: - Operation Status

enum OperationStatus: String, Codable {
    case pending
    case retrying
    case failed
    case completed

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .retrying:
            return "Retrying"
        case .failed:
            return "Failed"
        case .completed:
            return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .pending:
            return "clock"
        case .retrying:
            return "arrow.clockwise"
        case .failed:
            return "exclamationmark.triangle"
        case .completed:
            return "checkmark.circle"
        }
    }
}
