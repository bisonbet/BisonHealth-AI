import Foundation

// MARK: - Retry Configuration
struct RetryConfiguration {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    let jitter: Bool

    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 2.0,
        maxDelay: 60.0,
        multiplier: 2.0,
        jitter: true
    )

    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 1.0,
        maxDelay: 30.0,
        multiplier: 2.0,
        jitter: true
    )

    static let conservative = RetryConfiguration(
        maxAttempts: 2,
        initialDelay: 5.0,
        maxDelay: 60.0,
        multiplier: 2.0,
        jitter: true
    )
}

// MARK: - Retry Result
enum RetryResult<T> {
    case success(T)
    case failure(Error, attemptsMade: Int)
    case cancelled
}

// MARK: - Network Retry Manager
/// Manages retry logic with exponential backoff and jitter for network operations
class NetworkRetryManager {
    static let shared = NetworkRetryManager()

    private let logger = Logger.shared

    private init() {}

    // MARK: - Retry with Async/Await

    /// Retry an async operation with exponential backoff
    func retry<T>(
        operation: @escaping () async throws -> T,
        configuration: RetryConfiguration = .default,
        shouldRetry: ((Error) -> Bool)? = nil,
        onRetry: ((Int, Error, TimeInterval) -> Void)? = nil
    ) async -> RetryResult<T> {
        var lastError: Error?

        for attempt in 1...configuration.maxAttempts {
            do {
                let result = try await operation()
                if attempt > 1 {
                    logger.info("✅ Operation succeeded after \(attempt) attempts")
                }
                return .success(result)
            } catch {
                lastError = error

                // Check if we should retry this error
                let shouldRetryError = shouldRetry?(error) ?? error.isRetryable

                // If this is the last attempt or error is not retryable, fail
                if attempt == configuration.maxAttempts || !shouldRetryError {
                    logger.error("❌ Operation failed after \(attempt) attempts", error: error)
                    return .failure(error, attemptsMade: attempt)
                }

                // Calculate delay for next attempt
                let delay = calculateDelay(
                    attempt: attempt,
                    configuration: configuration
                )

                logger.warning("⏳ Retry attempt \(attempt)/\(configuration.maxAttempts) after \(delay)s - Error: \(error.localizedDescription)")

                // Notify caller
                onRetry?(attempt, error, delay)

                // Wait before retrying
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // Should never reach here, but handle it
        if let error = lastError {
            return .failure(error, attemptsMade: configuration.maxAttempts)
        } else {
            let unknownError = NSError(domain: "RetryManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown retry failure"])
            return .failure(unknownError, attemptsMade: configuration.maxAttempts)
        }
    }

    /// Retry an async throwing operation with exponential backoff
    func retryThrowing<T>(
        operation: @escaping () async throws -> T,
        configuration: RetryConfiguration = .default,
        shouldRetry: ((Error) -> Bool)? = nil,
        onRetry: ((Int, Error, TimeInterval) -> Void)? = nil
    ) async throws -> T {
        let result = await retry(
            operation: operation,
            configuration: configuration,
            shouldRetry: shouldRetry,
            onRetry: onRetry
        )

        switch result {
        case .success(let value):
            return value
        case .failure(let error, _):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }

    // MARK: - Delay Calculation

    /// Calculate delay for next retry attempt using exponential backoff with optional jitter
    private func calculateDelay(attempt: Int, configuration: RetryConfiguration) -> TimeInterval {
        // Calculate exponential backoff: delay = initial * (multiplier ^ (attempt - 1))
        var delay = configuration.initialDelay * pow(configuration.multiplier, Double(attempt - 1))

        // Cap at max delay
        delay = min(delay, configuration.maxDelay)

        // Add jitter if enabled (randomize by ±25%)
        if configuration.jitter {
            let jitterRange = delay * 0.25
            let jitterValue = Double.random(in: -jitterRange...jitterRange)
            delay += jitterValue
        }

        return max(0, delay)
    }

    // MARK: - Retry Policy Helpers

    /// Check if an error is worth retrying
    static func isRetryableError(_ error: Error) -> Bool {
        // Network errors are retryable
        if error.isNetworkError {
            return true
        }

        // Check NetworkError type
        if let networkError = error as? NetworkError {
            return networkError.isRetryable
        }

        // Check NSError domain
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            // Most URL errors are retryable
            return true
        case NSCocoaErrorDomain:
            // File system errors - some are retryable
            return [NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError].contains(nsError.code)
        default:
            return false
        }
    }
}

// MARK: - Convenience Extensions
extension NetworkRetryManager {
    /// Quick retry for network operations
    func retryNetworkOperation<T>(
        _ operation: @escaping () async throws -> T,
        onRetry: ((Int, Error, TimeInterval) -> Void)? = nil
    ) async -> RetryResult<T> {
        await retry(
            operation: operation,
            configuration: .default,
            shouldRetry: { Self.isRetryableError($0) },
            onRetry: onRetry
        )
    }

    /// Quick retry for critical operations (more attempts)
    func retryCriticalOperation<T>(
        _ operation: @escaping () async throws -> T,
        onRetry: ((Int, Error, TimeInterval) -> Void)? = nil
    ) async -> RetryResult<T> {
        await retry(
            operation: operation,
            configuration: .aggressive,
            shouldRetry: { Self.isRetryableError($0) },
            onRetry: onRetry
        )
    }
}
