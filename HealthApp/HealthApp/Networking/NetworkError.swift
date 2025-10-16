import Foundation

// MARK: - Network Error
/// Centralized network error handling with user-friendly messages and recovery suggestions
enum NetworkError: LocalizedError {
    case notConnected
    case connectionTimeout
    case hostUnreachable(String)
    case requestFailed(Int)
    case invalidResponse
    case timeout
    case cancelled
    case serverError(Int, String?)
    case clientError(Int, String?)
    case rateLimited
    case unauthorized
    case forbidden
    case notFound
    case tooManyRequests
    case serviceUnavailable
    case underlying(Error)

    // MARK: - Error Description
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No internet connection"
        case .connectionTimeout:
            return "Connection timed out"
        case .hostUnreachable(let host):
            return "Cannot reach \(host)"
        case .requestFailed(let code):
            return "Request failed with status code \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .serverError(let code, let message):
            if let message = message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error (\(code))"
        case .clientError(let code, let message):
            if let message = message {
                return "Request error (\(code)): \(message)"
            }
            return "Request error (\(code))"
        case .rateLimited:
            return "Too many requests - please wait"
        case .unauthorized:
            return "Authentication required"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .tooManyRequests:
            return "Too many requests - please slow down"
        case .serviceUnavailable:
            return "Service temporarily unavailable"
        case .underlying(let error):
            return error.localizedDescription
        }
    }

    // MARK: - Recovery Suggestion
    var recoverySuggestion: String? {
        switch self {
        case .notConnected:
            return "Check your internet connection and try again"
        case .connectionTimeout:
            return "Check your internet connection or try again later"
        case .hostUnreachable:
            return "Verify the server is running and accessible from your network"
        case .requestFailed(let code):
            if (500...599).contains(code) {
                return "The server is experiencing issues. Please try again later"
            } else if (400...499).contains(code) {
                return "There was a problem with the request. Please check your settings"
            } else {
                return "Request failed. Please try again"
            }
        case .invalidResponse:
            return "Check if the server is running the correct version"
        case .timeout:
            return "The request is taking longer than expected. Try again or use a smaller file"
        case .cancelled:
            return "Operation was cancelled by user or system"
        case .serverError:
            return "The server is experiencing issues. Please try again later"
        case .clientError:
            return "Check your request and try again"
        case .rateLimited:
            return "Wait a moment before trying again"
        case .unauthorized:
            return "Check your credentials in Settings"
        case .forbidden:
            return "You don't have permission to access this resource"
        case .notFound:
            return "The requested resource was not found"
        case .tooManyRequests:
            return "Wait a few moments before trying again"
        case .serviceUnavailable:
            return "The service is temporarily down. Please try again in a few minutes"
        case .underlying:
            return "Please try again or contact support if the problem persists"
        }
    }

    // MARK: - Is Retryable
    /// Indicates whether this error can be retried
    var isRetryable: Bool {
        switch self {
        case .notConnected, .connectionTimeout, .timeout, .hostUnreachable,
             .serverError, .serviceUnavailable, .rateLimited, .tooManyRequests:
            return true
        case .requestFailed(let code):
            // Retry on server errors (5xx), not client errors (4xx)
            return (500...599).contains(code)
        case .cancelled, .unauthorized, .forbidden, .notFound, .clientError:
            return false
        case .invalidResponse, .underlying:
            return true // Conservative: allow retry for unknown errors
        }
    }

    // MARK: - Suggested Retry Delay
    /// Suggested delay in seconds before retrying
    var suggestedRetryDelay: TimeInterval {
        switch self {
        case .rateLimited, .tooManyRequests:
            return 30.0 // Wait longer for rate limiting
        case .serverError, .serviceUnavailable:
            return 10.0
        case .notConnected, .connectionTimeout, .timeout, .hostUnreachable:
            return 5.0
        default:
            return 2.0
        }
    }

    // MARK: - Factory Methods

    /// Create a NetworkError from a URLError
    static func from(urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .notConnected
        case .timedOut:
            return .connectionTimeout
        case .cannotFindHost, .cannotConnectToHost:
            return .hostUnreachable(urlError.failureURLString ?? "unknown host")
        case .cancelled:
            return .cancelled
        default:
            return .underlying(urlError)
        }
    }

    /// Create a NetworkError from an HTTP status code
    static func from(httpStatusCode: Int, message: String? = nil) -> NetworkError {
        switch httpStatusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .tooManyRequests
        case 400...499:
            return .clientError(httpStatusCode, message)
        case 500:
            return .serverError(httpStatusCode, message ?? "Internal server error")
        case 503:
            return .serviceUnavailable
        case 500...599:
            return .serverError(httpStatusCode, message)
        default:
            return .requestFailed(httpStatusCode)
        }
    }

    /// Create a NetworkError from any Error
    static func from(error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        } else if let urlError = error as? URLError {
            return from(urlError: urlError)
        } else {
            return .underlying(error)
        }
    }
}

// MARK: - Error Extension
extension Error {
    /// Convert any error to a NetworkError
    var asNetworkError: NetworkError {
        return NetworkError.from(error: self)
    }

    /// Check if error is network-related
    var isNetworkError: Bool {
        if self is NetworkError {
            return true
        }
        if let urlError = self as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost,
                    .cannotFindHost, .cannotConnectToHost, .timedOut]
                .contains(urlError.code)
        }
        return false
    }

    /// Check if error is retryable
    var isRetryable: Bool {
        if let networkError = self as? NetworkError {
            return networkError.isRetryable
        }
        return isNetworkError
    }
}
