import Foundation
import Network
import Combine

// MARK: - Network Manager
/// Centralized network monitoring and connectivity management for the entire app
@MainActor
class NetworkManager: ObservableObject {

    // MARK: - Shared Instance
    static let shared = NetworkManager()

    // MARK: - Published Properties
    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .wifi
    @Published var networkQuality: NetworkQuality = .good
    @Published var isMonitoring: Bool = false

    // MARK: - Private Properties
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.bisonhealth.networkmonitor")
    private var statusUpdateSubject = PassthroughSubject<NetworkStatus, Never>()

    // MARK: - Public Properties
    var statusPublisher: AnyPublisher<NetworkStatus, Never> {
        statusUpdateSubject.eraseToAnyPublisher()
    }

    var currentStatus: NetworkStatus {
        NetworkStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            quality: networkQuality
        )
    }

    // MARK: - Initialization
    private init() {
        setupNetworkMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring network connectivity
    func startMonitoring() {
        guard !isMonitoring else { return }

        monitor.start(queue: queue)
        isMonitoring = true
        print("🌐 NetworkManager: Started monitoring network connectivity")
    }

    /// Stop monitoring network connectivity
    func stopMonitoring() {
        guard isMonitoring else { return }

        monitor.cancel()
        isMonitoring = false
        print("🌐 NetworkManager: Stopped monitoring network connectivity")
    }

    /// Check if a specific host is reachable
    func checkReachability(for host: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: port)
            )

            let connection = NWConnection(to: endpoint, using: .tcp)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .waiting:
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            // Set timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                connection.cancel()
                continuation.resume(returning: false)
            }

            connection.start(queue: queue)
        }
    }

    /// Wait for network to become available
    func waitForConnection(timeout: TimeInterval = 30.0) async throws {
        if isConnected {
            return
        }

        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var hasResumed = false

            cancellable = statusPublisher
                .sink { [weak self] status in
                    guard !hasResumed else { return }

                    if status.isConnected {
                        hasResumed = true
                        cancellable?.cancel()
                        continuation.resume()
                    } else if Date().timeIntervalSince(startTime) >= timeout {
                        hasResumed = true
                        cancellable?.cancel()
                        continuation.resume(throwing: NetworkError.connectionTimeout)
                    }
                }
        }
    }

    // MARK: - Private Methods

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }

                let wasConnected = self.isConnected
                let newIsConnected = path.status == .satisfied

                self.isConnected = newIsConnected
                self.connectionType = self.determineConnectionType(from: path)
                self.networkQuality = self.determineNetworkQuality(from: path)

                // Log connection changes
                if wasConnected != newIsConnected {
                    if newIsConnected {
                        print("✅ NetworkManager: Network connection restored (\(self.connectionType.displayName))")
                    } else {
                        print("❌ NetworkManager: Network connection lost")
                    }
                }

                // Publish status update
                let status = NetworkStatus(
                    isConnected: newIsConnected,
                    connectionType: self.connectionType,
                    quality: self.networkQuality
                )
                self.statusUpdateSubject.send(status)
            }
        }

        // Start monitoring automatically
        startMonitoring()
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }

    private func determineNetworkQuality(from path: NWPath) -> NetworkQuality {
        // In a production app, you might want to measure actual latency/bandwidth
        // For now, we'll use connection type as a proxy
        if !path.status.isConnected {
            return .poor
        }

        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .good
        } else if path.usesInterfaceType(.cellular) {
            return .moderate
        } else {
            return .poor
        }
    }

    // MARK: - Cleanup
    deinit {
        monitor.cancel()
    }
}

// MARK: - Supporting Types

struct NetworkStatus: Equatable {
    let isConnected: Bool
    let connectionType: ConnectionType
    let quality: NetworkQuality
    let timestamp: Date

    init(isConnected: Bool, connectionType: ConnectionType, quality: NetworkQuality) {
        self.isConnected = isConnected
        self.connectionType = connectionType
        self.quality = quality
        self.timestamp = Date()
    }
}

enum ConnectionType: String, Codable {
    case wifi
    case cellular
    case ethernet
    case unknown

    var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .ethernet:
            return "Ethernet"
        case .unknown:
            return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .ethernet:
            return "cable.connector"
        case .unknown:
            return "network"
        }
    }
}

enum NetworkQuality: String, Codable {
    case good
    case moderate
    case poor

    var displayName: String {
        switch self {
        case .good:
            return "Good"
        case .moderate:
            return "Moderate"
        case .poor:
            return "Poor"
        }
    }

    var color: String {
        switch self {
        case .good:
            return "green"
        case .moderate:
            return "orange"
        case .poor:
            return "red"
        }
    }
}

// MARK: - NWPath Extension
extension NWPath.Status {
    var isConnected: Bool {
        return self == .satisfied
    }
}
