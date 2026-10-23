import Foundation
import SwiftUI
import Combine

// MARK: - Error Severity
/// Severity levels for errors to determine display priority and user notification
enum ErrorSeverity: Int, Comparable {
    case info = 0       // Informational, background operations
    case warning = 1    // Issues that don't block functionality
    case error = 2      // Errors that block specific operations
    case critical = 3   // Critical errors requiring immediate attention

    static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Handled Error
/// Wrapper for errors with additional metadata for handling
struct HandledError: Identifiable, Equatable {
    let id: UUID
    let error: Error
    let severity: ErrorSeverity
    let context: String // Where the error occurred
    let timestamp: Date
    let isRetryable: Bool
    let retryAction: (() -> Void)?
    let dismissAction: (() -> Void)?

    init(
        error: Error,
        severity: ErrorSeverity = .error,
        context: String,
        isRetryable: Bool = false,
        retryAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        self.id = UUID()
        self.error = error
        self.severity = severity
        self.context = context
        self.timestamp = Date()
        self.isRetryable = isRetryable
        self.retryAction = retryAction
        self.dismissAction = dismissAction
    }

    var message: String {
        if let localizedError = error as? LocalizedError {
            return localizedError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    var recoverySuggestion: String? {
        (error as? LocalizedError)?.recoverySuggestion
    }

    // Equatable - compare by error type, message, and context
    static func == (lhs: HandledError, rhs: HandledError) -> Bool {
        lhs.id == rhs.id
    }

    /// Check if two errors are similar (for deduplication)
    func isSimilar(to other: HandledError) -> Bool {
        // Same context and same error message within 5 seconds
        return self.context == other.context &&
               self.message == other.message &&
               abs(self.timestamp.timeIntervalSince(other.timestamp)) < 5.0
    }
}

// MARK: - Error Handler
/// Global error handler for centralized error management and user feedback
@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()

    // MARK: - Published Properties
    @Published private(set) var currentError: HandledError?
    @Published private(set) var errorQueue: [HandledError] = []
    @Published var showErrorAlert: Bool = false

    // MARK: - Private Properties
    private var errorHistory: [HandledError] = []
    private let maxHistorySize = 50
    /// When the user last tapped Retry. Errors raised within `retryGracePeriod` of it
    /// bypass deduplication — see `shouldDeduplicateError`.
    private var lastRetryAt: Date?
    private static let retryGracePeriod: TimeInterval = 10.0

    /// Not private: tests construct an isolated handler rather than asserting against the
    /// shared one, which the parallelized suite would race on.
    /// (internal for regression tests; @testable access)
    init() {}

    // MARK: - Error Handling

    /// Handle an error with automatic severity detection and deduplication
    func handle(
        _ error: Error,
        context: String,
        severity: ErrorSeverity? = nil,
        retryAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        let detectedSeverity = severity ?? detectSeverity(for: error)
        let isRetryable = error.isRetryable || retryAction != nil

        let handledError = HandledError(
            error: error,
            severity: detectedSeverity,
            context: context,
            isRetryable: isRetryable,
            retryAction: retryAction,
            dismissAction: dismissAction
        )

        // Check for duplicate errors
        if shouldDeduplicateError(handledError) {
            AppLog.shared.general("Deduplicated error: \(handledError.message) in \(context)", level: .debug)
            return
        }

        // Log the error
        AppLog.shared.error("[\(context)] \(handledError.message)", error: error, category: .general)

        // Add to history
        addToHistory(handledError)

        // Handle based on severity.
        //
        // Warnings used to go straight to the queue, and the queue is drained only when
        // some *other* alert is dismissed — so a warning raised while nothing was on
        // screen was never shown at all. Every URLError classifies as a warning, which
        // meant chat network failures silently never reached the user. Anything above
        // `.info` is now presented: immediately if the screen is free, queued behind
        // whatever is already there otherwise.
        switch detectedSeverity {
        case .critical, .error, .warning:
            present(handledError)
        case .info:
            // Just log, don't display
            break
        }
    }

    /// Handle an error with a simple message
    func handle(
        _ error: Error,
        context: String,
        message: String,
        retryAction: (() -> Void)? = nil
    ) {
        // Create a custom error with the provided message
        struct CustomError: LocalizedError {
            let message: String
            let underlyingError: Error

            var errorDescription: String? { message }
            var recoverySuggestion: String? {
                (underlyingError as? LocalizedError)?.recoverySuggestion
            }
        }

        let customError = CustomError(message: message, underlyingError: error)
        handle(customError, context: context, retryAction: retryAction)
    }

    // MARK: - Error Display

    /// Presents an error, or queues it behind one the user has not acknowledged yet.
    ///
    /// Previously this overwrote `currentError` unless the error on screen was critical,
    /// so a second failure replaced an unacknowledged first and the first was simply
    /// lost. Nothing on screen is now replaced; a strictly more severe error takes the
    /// slot and the displaced one goes back on the queue rather than being discarded.
    private func present(_ handledError: HandledError) {
        guard let current = currentError else {
            showError(handledError)
            return
        }

        if handledError.severity > current.severity {
            queueError(current)
            showError(handledError)
        } else {
            queueError(handledError)
        }
    }

    private func showError(_ handledError: HandledError) {
        currentError = handledError
        showErrorAlert = true
    }

    private func queueError(_ handledError: HandledError) {
        errorQueue.append(handledError)
        // Sort by severity (highest first)
        errorQueue.sort { $0.severity > $1.severity }
    }

    /// Dismiss the current error and show next in queue
    func dismissCurrentError() {
        currentError?.dismissAction?()
        currentError = nil
        showErrorAlert = false

        // Show next error in queue
        if !errorQueue.isEmpty {
            let nextError = errorQueue.removeFirst()
            showError(nextError)
        }
    }

    /// Retry the current error's action
    func retryCurrentError() {
        lastRetryAt = Date()
        currentError?.retryAction?()
        dismissCurrentError()
    }

    /// Clear all errors
    func clearAll() {
        currentError = nil
        errorQueue.removeAll()
        showErrorAlert = false
    }

    // MARK: - Error Analysis

    private func detectSeverity(for error: Error) -> ErrorSeverity {
        // Network errors are usually warnings (can retry)
        if let networkError = error as? NetworkError {
            switch networkError {
            case .notConnected, .connectionTimeout, .timeout:
                return .warning
            case .unauthorized, .forbidden:
                return .error
            case .serverError:
                return .error
            default:
                return .warning
            }
        }

        // Check error domain for iOS errors
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return .warning // Network issues
        case NSCocoaErrorDomain:
            return .error // File system, data errors
        default:
            return .error // Unknown errors default to error level
        }
    }

    private func shouldDeduplicateError(_ handledError: HandledError) -> Bool {
        // An error arriving just after the user tapped Retry is the answer to that tap,
        // not noise. Deduplicating it means the retry appears to do nothing — which is
        // the worst possible response to someone actively trying again.
        if let lastRetry = lastRetryAt, lastRetry.timeIntervalSinceNow > -Self.retryGracePeriod {
            return false
        }

        // Check recent errors (last 10 seconds)
        let recentErrors = errorHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -10.0
        }

        // Check if similar error exists
        return recentErrors.contains { $0.isSimilar(to: handledError) }
    }

    private func addToHistory(_ handledError: HandledError) {
        errorHistory.append(handledError)

        // Trim history if needed
        if errorHistory.count > maxHistorySize {
            errorHistory.removeFirst(errorHistory.count - maxHistorySize)
        }
    }

    // MARK: - Error Statistics

    /// Get error count by context
    func errorCount(for context: String, since: Date = Date().addingTimeInterval(-3600)) -> Int {
        errorHistory.filter { $0.context == context && $0.timestamp >= since }.count
    }

    /// Get most common errors
    func mostCommonErrors(limit: Int = 5) -> [(context: String, count: Int)] {
        let grouped = Dictionary(grouping: errorHistory) { $0.context }
        return grouped
            .map { (context: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Error Alert View
/// Reusable error alert view for displaying handled errors
struct ErrorAlertView: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandler

    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.context ?? "Error",
                isPresented: $errorHandler.showErrorAlert,
                presenting: errorHandler.currentError
            ) { handledError in
                // Dismiss button
                Button("Dismiss") {
                    errorHandler.dismissCurrentError()
                }

                // Retry button if available
                if handledError.isRetryable {
                    Button("Retry") {
                        errorHandler.retryCurrentError()
                    }
                }
            } message: { handledError in
                VStack(alignment: .leading, spacing: 8) {
                    Text(handledError.message)

                    if let suggestion = handledError.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
    }
}

// MARK: - View Extension
extension View {
    /// Add global error handling to a view
    func withErrorHandling() -> some View {
        modifier(ErrorAlertView(errorHandler: .shared))
    }
}
