import XCTest
@testable import HealthApp

@MainActor
final class NetworkingTests: XCTestCase {

    // MARK: - NetworkManager Tests

    func testNetworkManagerSingleton() {
        let manager1 = NetworkManager.shared
        let manager2 = NetworkManager.shared

        XCTAssertTrue(manager1 === manager2, "NetworkManager should be a singleton")
    }

    func testNetworkManagerStartsMonitoring() {
        let manager = NetworkManager.shared

        XCTAssertTrue(manager.isMonitoring, "NetworkManager should start monitoring automatically")
    }

    func testNetworkStatusPublisher() async {
        let manager = NetworkManager.shared
        let expectation = XCTestExpectation(description: "Network status published")

        let cancellable = manager.statusPublisher
            .sink { status in
                XCTAssertNotNil(status)
                expectation.fulfill()
            }

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()
    }

    // MARK: - NetworkError Tests

    func testNetworkErrorFromURLError() {
        let urlError = URLError(.notConnectedToInternet)
        let networkError = NetworkError.from(urlError: urlError)

        XCTAssertEqual(networkError.errorDescription, "No internet connection")
        XCTAssertTrue(networkError.isRetryable)
    }

    func testNetworkErrorFromHTTPStatusCode() {
        let error404 = NetworkError.from(httpStatusCode: 404)
        XCTAssertEqual(error404.errorDescription, "Resource not found")
        XCTAssertFalse(error404.isRetryable)

        let error500 = NetworkError.from(httpStatusCode: 500)
        XCTAssertTrue(error500.isRetryable)
    }

    func testNetworkErrorRetryDelay() {
        let rateLimitError = NetworkError.rateLimited
        XCTAssertEqual(rateLimitError.suggestedRetryDelay, 30.0)

        let timeoutError = NetworkError.connectionTimeout
        XCTAssertEqual(timeoutError.suggestedRetryDelay, 5.0)
    }

    func testNetworkErrorRecoverySuggestions() {
        let notConnectedError = NetworkError.notConnected
        XCTAssertNotNil(notConnectedError.recoverySuggestion)
        XCTAssertTrue(notConnectedError.recoverySuggestion!.contains("internet"))

        let unauthorizedError = NetworkError.unauthorized
        XCTAssertNotNil(unauthorizedError.recoverySuggestion)
        XCTAssertTrue(unauthorizedError.recoverySuggestion!.contains("credentials"))
    }

    // MARK: - PendingOperationsManager Tests

    func testPendingOperationsManagerSingleton() {
        let manager1 = PendingOperationsManager.shared
        let manager2 = PendingOperationsManager.shared

        XCTAssertTrue(manager1 === manager2, "PendingOperationsManager should be a singleton")
    }

    func testQueueChatMessage() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test message",
            context: "Test context",
            useStreaming: false,
            model: "test-model",
            systemPrompt: nil
        )

        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.type.displayName, "Chat Message")
    }

    func testQueueDocumentProcessing() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        await manager.queueDocumentProcessing(
            documentId: UUID(),
            immediately: false
        )

        XCTAssertEqual(manager.pendingOperations.count, 1)
        XCTAssertEqual(manager.pendingOperations.first?.type.displayName, "Document Processing")
    }

    func testCancelOperation() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test message",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        let operationId = manager.pendingOperations.first!.id
        manager.cancelOperation(operationId)

        XCTAssertEqual(manager.pendingOperations.count, 0)
    }

    func testCancelAllOperations() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        // Add multiple operations
        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test 1",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        await manager.queueDocumentProcessing(
            documentId: UUID(),
            immediately: false
        )

        XCTAssertEqual(manager.pendingOperations.count, 2)

        manager.cancelAllOperations()
        XCTAssertEqual(manager.pendingOperations.count, 0)
    }

    func testPendingCountByType() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        // Add chat messages
        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test 1",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test 2",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        // Add document processing
        await manager.queueDocumentProcessing(
            documentId: UUID(),
            immediately: false
        )

        let chatCount = manager.pendingCount(for: .chatMessage(
            conversationId: UUID(),
            message: "",
            context: "",
            useStreaming: false,
            model: "",
            systemPrompt: nil
        ))

        let docCount = manager.pendingCount(for: .documentProcessing(
            documentId: UUID(),
            immediately: false
        ))

        XCTAssertEqual(chatCount, 2)
        XCTAssertEqual(docCount, 1)
    }

    func testOperationRetryCount() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        let operation = manager.pendingOperations.first!
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertEqual(operation.status, .pending)
    }

    func testOperationPersistence() async {
        let manager = PendingOperationsManager.shared

        // Clear any existing operations
        manager.cancelAllOperations()

        // Add an operation
        await manager.queueChatMessage(
            conversationId: UUID(),
            message: "Test persistence",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        XCTAssertEqual(manager.pendingOperations.count, 1)

        // Verify operation was persisted
        // Note: In a real test, you'd want to create a new instance of the manager
        // to verify persistence, but that requires dependency injection
    }

    // MARK: - Error Extension Tests

    func testErrorAsNetworkError() {
        let urlError = URLError(.notConnectedToInternet)
        let networkError = urlError.asNetworkError

        XCTAssertTrue(networkError.isRetryable)
    }

    func testErrorIsNetworkError() {
        let urlError = URLError(.notConnectedToInternet)
        XCTAssertTrue(urlError.isNetworkError)

        let genericError = NSError(domain: "test", code: 1)
        XCTAssertFalse(genericError.isNetworkError)
    }

    func testErrorIsRetryable() {
        let networkError = NetworkError.notConnected
        XCTAssertTrue(networkError.isRetryable)

        let authError = NetworkError.unauthorized
        XCTAssertFalse(authError.isRetryable)
    }

    // MARK: - Integration Tests

    func testNetworkManagerIntegrationWithPendingOperations() async {
        let networkManager = NetworkManager.shared
        let pendingOpsManager = PendingOperationsManager.shared

        // Clear pending operations
        pendingOpsManager.cancelAllOperations()

        // Add operation while "offline" (simulated)
        await pendingOpsManager.queueChatMessage(
            conversationId: UUID(),
            message: "Test",
            context: "",
            useStreaming: false,
            model: "test",
            systemPrompt: nil
        )

        XCTAssertEqual(pendingOpsManager.pendingOperations.count, 1)

        // Note: In a real integration test, you'd mock network connectivity changes
        // and verify that operations are retried when network is restored
    }

    // MARK: - Connection Type Tests

    func testConnectionTypeDisplayName() {
        XCTAssertEqual(ConnectionType.wifi.displayName, "Wi-Fi")
        XCTAssertEqual(ConnectionType.cellular.displayName, "Cellular")
        XCTAssertEqual(ConnectionType.ethernet.displayName, "Ethernet")
        XCTAssertEqual(ConnectionType.unknown.displayName, "Unknown")
    }

    func testConnectionTypeIcon() {
        XCTAssertEqual(ConnectionType.wifi.icon, "wifi")
        XCTAssertEqual(ConnectionType.cellular.icon, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(ConnectionType.ethernet.icon, "cable.connector")
        XCTAssertEqual(ConnectionType.unknown.icon, "network")
    }

    // MARK: - Network Quality Tests

    func testNetworkQualityDisplayName() {
        XCTAssertEqual(NetworkQuality.good.displayName, "Good")
        XCTAssertEqual(NetworkQuality.moderate.displayName, "Moderate")
        XCTAssertEqual(NetworkQuality.poor.displayName, "Poor")
    }

    // MARK: - Operation Status Tests

    func testOperationStatusDisplayName() {
        XCTAssertEqual(OperationStatus.pending.displayName, "Pending")
        XCTAssertEqual(OperationStatus.retrying.displayName, "Retrying")
        XCTAssertEqual(OperationStatus.failed.displayName, "Failed")
        XCTAssertEqual(OperationStatus.completed.displayName, "Completed")
    }

    func testOperationStatusIcon() {
        XCTAssertEqual(OperationStatus.pending.icon, "clock")
        XCTAssertEqual(OperationStatus.retrying.icon, "arrow.clockwise")
        XCTAssertEqual(OperationStatus.failed.icon, "exclamationmark.triangle")
        XCTAssertEqual(OperationStatus.completed.icon, "checkmark.circle")
    }
}
