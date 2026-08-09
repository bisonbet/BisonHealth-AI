import Foundation
#if canImport(MetricKit)
import MetricKit
#endif
import OSLog

// MARK: - Log Level
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}

// MARK: - Log Category
enum LogCategory: String, CaseIterable {
    case database = "Database"
    case documents = "Documents"
    case networking = "Networking"
    case ai = "AI"
    case healthData = "HealthData"
    case fileManagement = "FileManagement"
    case settings = "Settings"
    case mlx = "MLX"
    case ui = "UI"
    case general = "General"
}

// MARK: - AppLog
/// Always-on logging via Apple's Unified Logging System (OSLog).
/// Zero overhead in production — the OS handles persistence, compression, and pruning.
/// Also provides file-based persistence, a crash-surviving error buffer, and crash detection.
///
/// `@unchecked Sendable` rather than actor-isolated: `log()` is called synchronously from
/// every isolation domain in the app, so isolating it would force every call site async.
/// The two mutable properties are safe under the following invariants — preserve them:
/// - `logFileURL` is assigned only by `setupLogFile()`, which runs during `init` before the
///   instance escapes. Its only other caller, `clearAllLogs()`, currently has no callers;
///   invoking it from off the main actor would break this invariant.
/// - `previousSessionCrashed` is written once by `markLaunch()` at startup and read only on
///   the main actor.
/// Everything else is `let`, and file writes are already serialized through `logQueue`.
final class AppLog: NSObject, @unchecked Sendable {
    static let shared = AppLog(receivesMetricKitDiagnostics: true)

    // MARK: - Properties
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bisonhealth"
    private static let cleanShutdownKey = "AppLog_CleanShutdown"
    private static let maxErrorBufferLines = 500
    private static let maxMetricKitLogBytes = 512 * 1024
    private static let maxLoggedErrorDescriptionLength = 512

    private let loggers: [LogCategory: os.Logger]
    private let fileManager: FileManager
    private let logQueue = DispatchQueue(label: "com.bisonhealth.applog", qos: .utility)
    private let logQueueKey = DispatchSpecificKey<String>()
    private let logDirectoryOverride: URL?
    private let errorBufferURLOverride: URL?
    private let metricKitDiagnosticsURLOverride: URL?
    private var logFileURL: URL?
    private let maxLogFileSize: Int = 5 * 1024 * 1024 // 5MB
    private let maxLogFiles: Int = 3

    /// Whether the previous app session ended in a crash (unclean shutdown)
    private(set) var previousSessionCrashed: Bool = false

    /// URL for the persistent error buffer file
    private var errorBufferURL: URL? {
        if let errorBufferURLOverride {
            return errorBufferURLOverride
        }
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDir.appendingPathComponent("persistent_error_log.txt")
    }

    private var metricKitDiagnosticsURL: URL? {
        if let metricKitDiagnosticsURLOverride {
            return metricKitDiagnosticsURLOverride
        }
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDir.appendingPathComponent("metric_kit_diagnostics.log")
    }

    #if DEBUG
    private let minimumLogLevel: LogLevel = .debug
    #else
    private let minimumLogLevel: LogLevel = .info
    #endif

    // MARK: - Initialization
    /// Creates a logger. The URL overrides are intentionally injectable so tests can
    /// verify persisted/exported redaction in an isolated temporary directory.
    ///
    /// `receivesMetricKitDiagnostics` defaults to `false` because MXMetricManager
    /// retains its subscribers for the process lifetime: only the long-lived shared
    /// logger should register, or every throwaway instance leaks.
    init(
        fileManager: FileManager = .default,
        logDirectory: URL? = nil,
        errorBufferURL: URL? = nil,
        metricKitDiagnosticsURL: URL? = nil,
        receivesMetricKitDiagnostics: Bool = false
    ) {
        self.fileManager = fileManager
        self.logDirectoryOverride = logDirectory
        self.errorBufferURLOverride = errorBufferURL
        self.metricKitDiagnosticsURLOverride = metricKitDiagnosticsURL

        // Create os.Logger instances for each category
        var map = [LogCategory: os.Logger]()
        for category in LogCategory.allCases {
            map[category] = os.Logger(subsystem: AppLog.subsystem, category: category.rawValue)
        }
        loggers = map
        super.init()

        logQueue.setSpecific(key: logQueueKey, value: "AppLogQueue")
        setupLogFile()
        setupCrashSupportFile(at: errorBufferURL)
        setupCrashSupportFile(at: metricKitDiagnosticsURL)
        if receivesMetricKitDiagnostics {
            registerMetricKitSubscriber()
        }
    }

    // MARK: - Setup

    private func setupLogFile() {
        if let logDirectoryOverride {
            if !fileManager.fileExists(atPath: logDirectoryOverride.path) {
                try? fileManager.createDirectory(at: logDirectoryOverride, withIntermediateDirectories: true)
            }

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = logDirectoryOverride
            try? mutableURL.setResourceValues(resourceValues)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())
            logFileURL = logDirectoryOverride.appendingPathComponent("app-\(dateString).log")
            rotateLogsIfNeeded()
            return
        }

        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let appDirectory = documentsDirectory.appendingPathComponent("HealthApp", isDirectory: true)
        var logsDirectory = appDirectory.appendingPathComponent("Logs", isDirectory: true)

        if !fileManager.fileExists(atPath: logsDirectory.path) {
            do {
                try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            } catch {
                return
            }
        }
        migrateLegacyLogsIfNeeded(from: documentsDirectory.appendingPathComponent("Logs", isDirectory: true), to: logsDirectory)

        // Exclude logs directory from iCloud/iTunes backup to protect privacy
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? logsDirectory.setResourceValues(resourceValues)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logsDirectory.appendingPathComponent("app-\(dateString).log")

        rotateLogsIfNeeded()
    }

    private func setupCrashSupportFile(at url: URL?) {
        guard let url else { return }
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }

        // Exclude diagnostic support files from iCloud/iTunes backup to protect privacy.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func migrateLegacyLogsIfNeeded(from legacyLogsDirectory: URL, to logsDirectory: URL) {
        guard legacyLogsDirectory.path != logsDirectory.path,
              fileManager.fileExists(atPath: legacyLogsDirectory.path),
              let legacyFiles = try? fileManager.contentsOfDirectory(
                at: legacyLogsDirectory,
                includingPropertiesForKeys: nil
              ) else {
            return
        }

        for file in legacyFiles where file.pathExtension == "log" {
            let destination = logsDirectory.appendingPathComponent("legacy-\(file.lastPathComponent)")
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: file, to: destination)
        }
    }

    private func registerMetricKitSubscriber() {
        #if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        #endif
    }

    // MARK: - Crash Detection

    /// Call this at app launch (in app init or didFinishLaunching) to detect crashes.
    func markLaunch() {
        let hasKey = UserDefaults.standard.object(forKey: AppLog.cleanShutdownKey) != nil
        previousSessionCrashed = hasKey && !UserDefaults.standard.bool(forKey: AppLog.cleanShutdownKey)
        markSessionDirty()

        if previousSessionCrashed {
            log("Previous session ended with an unclean shutdown (possible crash)", level: .warning, category: .general)
        }
        log("App launched", level: .info, category: .general)
    }

    /// Call when the app becomes active so foreground crashes after a prior background are detected.
    func markSessionActive() {
        markSessionDirty()
    }

    /// Call when the app reaches background cleanly.
    func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: AppLog.cleanShutdownKey)
        UserDefaults.standard.synchronize()
    }

    private func markSessionDirty() {
        UserDefaults.standard.set(false, forKey: AppLog.cleanShutdownKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Category-First Convenience Methods

    func database(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .database, file: file, function: function, line: line)
    }

    func documents(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .documents, file: file, function: function, line: line)
    }

    func networking(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .networking, file: file, function: function, line: line)
    }

    func ai(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .ai, file: file, function: function, line: line)
    }

    func healthData(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .healthData, file: file, function: function, line: line)
    }

    func fileManagement(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .fileManagement, file: file, function: function, line: line)
    }

    func settings(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .settings, file: file, function: function, line: line)
    }

    func mlx(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .mlx, file: file, function: function, line: line)
    }

    func ui(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .ui, file: file, function: function, line: line)
    }

    func general(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .general, file: file, function: function, line: line)
    }

    // MARK: - Level-First Convenience Methods

    func debug(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String, error: Error? = nil, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = AppLog.redactForSupport(message)
        if let error = error {
            fullMessage += " - Error: \(AppLog.sanitizedErrorDescription(error))"
        }
        log(fullMessage, level: .error, category: category, file: file, function: function, line: line)
    }

    func critical(_ message: String, error: Error? = nil, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = AppLog.redactForSupport(message)
        if let error = error {
            fullMessage += " - Error: \(AppLog.sanitizedErrorDescription(error))"
        }
        log(fullMessage, level: .critical, category: category, file: file, function: function, line: line)
    }

    /// Returns an error description that is safe to place in durable logs.
    /// Provider errors expose their own structured, sanitized description; other
    /// errors are represented by stable type/code information rather than arbitrary
    /// localized text that may contain prompts, health context, or response bodies.
    static func sanitizedErrorDescription(_ error: Error) -> String {
        if let providerError = error as? OpenAICompatibleError {
            // Deliberately not localizedDescription: that carries the provider-supplied
            // request ID, which is untrusted response data and must not be persisted.
            return boundedLogText(providerError.loggableDescription)
        }

        if let urlError = error as? URLError {
            return "Network error (\(urlError.code.rawValue))"
        }

        if error is DecodingError {
            return "Response decoding failed"
        }

        return boundedLogText("Underlying error type: \(String(describing: type(of: error)))")
    }

    private static func boundedLogText(_ text: String) -> String {
        let compactText = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(compactText.prefix(maxLoggedErrorDescriptionLength))
    }

    // MARK: - Core Logging

    /// Categories that may contain sensitive health/personal data — logged as private in OSLog
    private static let sensitiveCategories: Set<LogCategory> = [
        .healthData, .ai, .documents, .database
    ]

    func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        guard level >= minimumLogLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(fileName):\(line)] \(message)"
        let redactedFormattedMessage = AppLog.redactForSupport(formattedMessage)

        // Log to os.Logger (appears in Xcode console and Console.app)
        // Sensitive categories use .private so data is redacted in Console.app on non-debug devices
        if let logger = loggers[category] {
            if AppLog.sensitiveCategories.contains(category) {
                switch level {
                case .debug:    logger.debug("\(redactedFormattedMessage, privacy: .private)")
                case .info:     logger.info("\(redactedFormattedMessage, privacy: .private)")
                case .warning:  logger.notice("\(redactedFormattedMessage, privacy: .private)")
                case .error:    logger.error("\(redactedFormattedMessage, privacy: .private)")
                case .critical: logger.fault("\(redactedFormattedMessage, privacy: .private)")
                }
            } else {
                switch level {
                case .debug:    logger.debug("\(redactedFormattedMessage, privacy: .public)")
                case .info:     logger.info("\(redactedFormattedMessage, privacy: .public)")
                case .warning:  logger.notice("\(redactedFormattedMessage, privacy: .public)")
                case .error:    logger.error("\(redactedFormattedMessage, privacy: .public)")
                case .critical: logger.fault("\(redactedFormattedMessage, privacy: .public)")
                }
            }
        }

        let isDurableEvent = level == .error || level == .critical
        let durableBufferLine: String?
        if isDurableEvent {
            let levelStr = level == .critical ? "FAULT" : "ERROR"
            durableBufferLine = AppLog.redactForSupport("[\(timestamp)] [\(levelStr)] [\(category.rawValue)] \(message)")
        } else {
            durableBufferLine = nil
        }

        let writeBlock = { [weak self] in
            self?.writeToFile(redactedFormattedMessage, synchronize: isDurableEvent)
            if let durableBufferLine {
                self?.persistToErrorBuffer(durableBufferLine)
            }
        }

        if isDurableEvent {
            if DispatchQueue.getSpecific(key: logQueueKey) != nil {
                writeBlock()
            } else {
                logQueue.sync(execute: writeBlock)
            }
        } else {
            logQueue.async { [weak self] in
                self?.writeToFile(redactedFormattedMessage)
            }
        }
    }

    // MARK: - File Logging

    private func writeToFile(_ message: String, synchronize: Bool = false) {
        guard let logFileURL = logFileURL else { return }

        let logEntry = message + "\n"

        if fileManager.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    fileHandle.write(data)
                }
                if synchronize {
                    fileHandle.synchronizeFile()
                }
                fileHandle.closeFile()
            }
        } else {
            try? logEntry.write(to: logFileURL, atomically: true, encoding: .utf8)
        }

        rotateLogsIfNeeded()
    }

    // MARK: - Persistent Error Buffer

    private func persistToErrorBuffer(_ line: String) {
        guard let url = errorBufferURL else { return }

        // Read existing lines
        var lines: [String] = []
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n").filter { !$0.isEmpty }
        }

        // Append new line and trim to max
        lines.append(line)
        if lines.count > AppLog.maxErrorBufferLines {
            lines = Array(lines.suffix(AppLog.maxErrorBufferLines))
        }

        // Write back
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Read the persistent error buffer contents
    func getErrorBufferContent() -> String? {
        guard let url = errorBufferURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func getMetricKitDiagnosticsContent() -> String? {
        guard let url = metricKitDiagnosticsURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Log Rotation

    private func rotateLogsIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize >= maxLogFileSize else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let logsDirectory = logFileURL.deletingLastPathComponent()
        let rotatedURL = logsDirectory.appendingPathComponent("app-\(timestamp).log")

        do {
            try fileManager.moveItem(at: logFileURL, to: rotatedURL)
            cleanupOldLogs()
        } catch {
            // Can't use self.log here to avoid recursion
        }
    }

    private func cleanupOldLogs() {
        guard let logFileURL = logFileURL else { return }
        let logsDirectory = logFileURL.deletingLastPathComponent()

        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "log" }
                .sorted { (url1, url2) -> Bool in
                    guard let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                          let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                        return false
                    }
                    return date1 > date2
                }

            if logFiles.count > maxLogFiles {
                let filesToDelete = logFiles.suffix(from: maxLogFiles)
                for file in filesToDelete {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            // Can't use self.log here to avoid recursion
        }
    }

    // MARK: - Log Retrieval

    /// Get all log files sorted by date (newest first)
    func getLogFiles() -> [URL] {
        guard let logFileURL = logFileURL else { return [] }
        let logsDirectory = logFileURL.deletingLastPathComponent()

        do {
            return try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "log" }
                .sorted { (url1, url2) -> Bool in
                    guard let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                          let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
                        return false
                    }
                    return date1 > date2
                }
        } catch {
            return []
        }
    }

    /// Get all retained file logs in chronological order.
    func getCombinedLogFileContent() -> String? {
        let logFiles = getLogFiles().reversed()
        let sections = logFiles.compactMap { url -> String? in
            guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else {
                return nil
            }
            return "--- \(url.lastPathComponent) ---\n\(AppLog.redactForSupport(content))"
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    /// Get the current log file content
    func getCurrentLogContent() -> String? {
        guard let logFileURL = logFileURL else { return nil }
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return nil }
        return AppLog.redactForSupport(content)
    }

    /// Clear all logs
    func clearAllLogs() {
        guard let logFileURL = logFileURL else { return }
        let logsDirectory = logFileURL.deletingLastPathComponent()

        do {
            let logFiles = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "log" }

            for file in logFiles {
                try fileManager.removeItem(at: file)
            }

            // Clear error buffer
            if let url = errorBufferURL {
                try? fileManager.removeItem(at: url)
            }
            if let url = metricKitDiagnosticsURL {
                try? fileManager.removeItem(at: url)
            }

            // Reinitialize log file
            setupLogFile()
            setupCrashSupportFile(at: errorBufferURL)
            setupCrashSupportFile(at: metricKitDiagnosticsURL)
        } catch {
            // Silent failure — nothing to log to
        }
    }

    // MARK: - Support Redaction

    static func redactForSupport(_ text: String) -> String {
        var output = text
        let replacements: [(pattern: String, template: String, options: NSRegularExpression.Options)] = [
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [REDACTED_TOKEN]", []),
            (#"(?i)\b((?:authorization|x-api-key|api[-_ ]?key|access[-_ ]?token|secret|password))\s*[:=]\s*(?:Bearer\s+)?[^,;\s}\]]+"#, "$1[REDACTED_CREDENTIAL]", []),
            (#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED_EMAIL]", [.caseInsensitive]),
            (#"\b(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)\d{3}[-.\s]?\d{4}\b"#, "[REDACTED_PHONE]", []),
            (#"\b\d{3}-\d{2}-\d{4}\b"#, "[REDACTED_SSN]", []),
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#, "[REDACTED_ID]", []),
            (#"(?:/private)?/var/[^\s]+"#, "[REDACTED_PATH]", []),
            (#"/Users/[^\s]+"#, "[REDACTED_PATH]", []),
            (#"(['"])[^'"\n]*(?:\.pdf|\.png|\.jpg|\.jpeg|\.heic|\.docx|\.txt|\.csv)\1"#, "\"[REDACTED_FILENAME]\"", [.caseInsensitive]),
            (#"\b((?:patient|name|full name|date of birth|dob|mrn|medical record number|member id|insurance id)\s*[:=]\s*)[^,\n;]+"#, "$1[REDACTED]", [.caseInsensitive]),
            // The value delimiter is captured so the closing quote must match the
            // opening one; \2 is a backreference, not a literal.
            (#"(?i)([\"']?(?:message|error|detail|prompt|context|content|response)[\"']?\s*[:=]\s*)([\"'])[^\"'\n]*\2"#, "$1$2[REDACTED]$2", []),
            (#"(User selected '[^']+' = )[^ ]+"#, "$1[REDACTED_VALUE]", []),
            (#"\b\d+(?:\.\d+)?\s?(?:bpm|br/min|lbs|kg|F|mg/dL|mmHg|%)\b"#, "[REDACTED_VALUE]", [.caseInsensitive])
        ]

        for replacement in replacements {
            output = replacingMatches(
                in: output,
                pattern: replacement.pattern,
                with: replacement.template,
                options: replacement.options
            )
        }
        return output
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        with template: String,
        options: NSRegularExpression.Options
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    fileprivate func persistMetricKitDiagnostic(_ diagnostic: String) {
        guard let url = metricKitDiagnosticsURL else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\n--- MetricKit Diagnostic \(timestamp) ---\n\(AppLog.redactForSupport(diagnostic))\n"

        if fileManager.fileExists(atPath: url.path),
           let fileHandle = try? FileHandle(forWritingTo: url) {
            fileHandle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                fileHandle.write(data)
                fileHandle.synchronizeFile()
            }
            fileHandle.closeFile()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
        trimTextFile(at: url, maxBytes: AppLog.maxMetricKitLogBytes)
    }

    private func trimTextFile(at url: URL, maxBytes: Int) {
        guard let data = try? Data(contentsOf: url), data.count > maxBytes else { return }
        let suffix = data.suffix(maxBytes)
        try? Data(suffix).write(to: url, options: .atomic)
    }
}

// MARK: - Backward Compatibility
typealias Logger = AppLog

#if canImport(MetricKit)
extension AppLog: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let diagnosticJSON = String(data: payload.jsonRepresentation(), encoding: .utf8)
                ?? payload.description
            persistMetricKitDiagnostic(diagnosticJSON)
        }
    }
}
#endif
