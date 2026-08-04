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
        XCTAssertNotNil(manager.currentStatus)
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

    // MARK: - Offline Privacy Migration Tests

    func testLegacyPendingOperationsKeyIsRemovedDuringMigration() {
        let suiteName = "NetworkingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let syntheticQueueData = Data("synthetic chat message and synthetic health context".utf8)
        defaults.set(syntheticQueueData, forKey: HealthAppApp.legacyPendingOperationsKey)
        XCTAssertNotNil(defaults.data(forKey: HealthAppApp.legacyPendingOperationsKey))

        HealthAppApp.removeLegacyPendingOperations(from: defaults)

        XCTAssertNil(defaults.object(forKey: HealthAppApp.legacyPendingOperationsKey))
    }

    func testOfflinePathDoesNotRetainChatContentOrHealthContext() {
        let suiteName = "NetworkingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let syntheticChatContent = "synthetic chat message"
        let syntheticHealthContext = "synthetic health context"
        let syntheticQueueData = Data("\(syntheticChatContent)\n\(syntheticHealthContext)".utf8)
        defaults.set(syntheticQueueData, forKey: HealthAppApp.legacyPendingOperationsKey)

        HealthAppApp.removeLegacyPendingOperations(from: defaults)

        let persistedData = defaults.data(forKey: HealthAppApp.legacyPendingOperationsKey)
        XCTAssertNil(persistedData)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { value in
            guard let data = value as? Data else { return false }
            return data == syntheticQueueData
        })
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

}
