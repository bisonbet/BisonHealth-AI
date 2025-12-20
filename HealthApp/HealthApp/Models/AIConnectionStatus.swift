import Foundation

// MARK: - AI Connection Status

/// Generic connection status for AI providers
public enum AIConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    public var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Ollama-specific Connection Status (for backward compatibility)

/// Ollama connection status - wraps generic AIConnectionStatus
public enum OllamaConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)

    public static func == (lhs: OllamaConnectionStatus, rhs: OllamaConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }

    /// Convert to generic AIConnectionStatus
    public var toGeneric: AIConnectionStatus {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .failed(let error):
            return .error(error.localizedDescription)
        }
    }

    /// Create from generic AIConnectionStatus
    public static func from(_ status: AIConnectionStatus) -> OllamaConnectionStatus {
        switch status {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .error(let message):
            return .failed(NSError(domain: "AI", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}
