import Foundation
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
    case icloud = "iCloud"
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
class AppLog {
    static let shared = AppLog()

    // MARK: - Properties
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bisonhealth"
    private static let cleanShutdownKey = "AppLog_CleanShutdown"
    private static let maxErrorBufferLines = 500

    private let loggers: [LogCategory: os.Logger]
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.bisonhealth.applog", qos: .utility)
    private var logFileURL: URL?
    private let maxLogFileSize: Int = 5 * 1024 * 1024 // 5MB
    private let maxLogFiles: Int = 3

    /// Whether the previous app session ended in a crash (unclean shutdown)
    private(set) var previousSessionCrashed: Bool = false

    /// URL for the persistent error buffer file
    private var errorBufferURL: URL? {
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDir.appendingPathComponent("persistent_error_log.txt")
    }

    #if DEBUG
    private let minimumLogLevel: LogLevel = .debug
    #else
    private let minimumLogLevel: LogLevel = .info
    #endif

    // MARK: - Initialization
    private init() {
        // Create os.Logger instances for each category
        var map = [LogCategory: os.Logger]()
        for category in LogCategory.allCases {
            map[category] = os.Logger(subsystem: AppLog.subsystem, category: category.rawValue)
        }
        loggers = map

        setupLogFile()
        setupErrorBuffer()
    }

    // MARK: - Setup

    private func setupLogFile() {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        var logsDirectory = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)

        if !fileManager.fileExists(atPath: logsDirectory.path) {
            do {
                try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            } catch {
                return
            }
        }

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

    private func setupErrorBuffer() {
        guard var url = errorBufferURL else { return }
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Exclude error buffer from iCloud/iTunes backup to protect privacy
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }

    // MARK: - Crash Detection

    /// Call this at app launch (in app init or didFinishLaunching) to detect crashes.
    func markLaunch() {
        let hasKey = UserDefaults.standard.object(forKey: AppLog.cleanShutdownKey) != nil
        previousSessionCrashed = hasKey && !UserDefaults.standard.bool(forKey: AppLog.cleanShutdownKey)
        UserDefaults.standard.set(false, forKey: AppLog.cleanShutdownKey)

        if previousSessionCrashed {
            log("Previous session ended with an unclean shutdown (possible crash)", level: .warning, category: .general)
        }
        log("App launched", level: .info, category: .general)
    }

    /// Call this when the app enters background or resigns active.
    func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: AppLog.cleanShutdownKey)
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

    func icloud(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: level, category: .icloud, file: file, function: function, line: line)
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
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, category: category, file: file, function: function, line: line)
    }

    func critical(_ message: String, error: Error? = nil, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .critical, category: category, file: file, function: function, line: line)
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

        // Log to os.Logger (appears in Xcode console and Console.app)
        // Sensitive categories use .private so data is redacted in Console.app on non-debug devices
        if let logger = loggers[category] {
            if AppLog.sensitiveCategories.contains(category) {
                switch level {
                case .debug:    logger.debug("\(formattedMessage, privacy: .private)")
                case .info:     logger.info("\(formattedMessage, privacy: .private)")
                case .warning:  logger.notice("\(formattedMessage, privacy: .private)")
                case .error:    logger.error("\(formattedMessage, privacy: .private)")
                case .critical: logger.fault("\(formattedMessage, privacy: .private)")
                }
            } else {
                switch level {
                case .debug:    logger.debug("\(formattedMessage, privacy: .public)")
                case .info:     logger.info("\(formattedMessage, privacy: .public)")
                case .warning:  logger.notice("\(formattedMessage, privacy: .public)")
                case .error:    logger.error("\(formattedMessage, privacy: .public)")
                case .critical: logger.fault("\(formattedMessage, privacy: .public)")
                }
            }
        }

        // Log to file (async)
        logQueue.async { [weak self] in
            self?.writeToFile(formattedMessage)
        }

        // Persist errors to crash-surviving buffer
        if level == .error || level == .critical {
            let levelStr = level == .critical ? "FAULT" : "ERROR"
            let bufferLine = "[\(timestamp)] [\(levelStr)] [\(category.rawValue)] \(message)"
            logQueue.async { [weak self] in
                self?.persistToErrorBuffer(bufferLine)
            }
        }
    }

    // MARK: - File Logging

    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        let logEntry = message + "\n"

        if fileManager.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    fileHandle.write(data)
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

    /// Get the current log file content
    func getCurrentLogContent() -> String? {
        guard let logFileURL = logFileURL else { return nil }
        return try? String(contentsOf: logFileURL, encoding: .utf8)
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

            // Reinitialize log file
            setupLogFile()
        } catch {
            // Silent failure — nothing to log to
        }
    }
}

// MARK: - Backward Compatibility
typealias Logger = AppLog
