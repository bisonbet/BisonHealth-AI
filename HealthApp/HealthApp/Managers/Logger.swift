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

    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
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
}

// MARK: - Logger
/// Centralized logging system with file persistence and console output
class Logger {
    static let shared = Logger()

    // MARK: - Properties
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.bisonhealth", category: "app")
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.bisonhealth.logger", qos: .utility)
    private var logFileURL: URL?
    private let maxLogFileSize: Int = 5 * 1024 * 1024 // 5MB
    private let maxLogFiles: Int = 3

    #if DEBUG
    private let minimumLogLevel: LogLevel = .debug
    #else
    private let minimumLogLevel: LogLevel = .info
    #endif

    // MARK: - Initialization
    private init() {
        setupLogFile()
    }

    // MARK: - Setup
    private func setupLogFile() {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Logger: Could not access documents directory")
            return
        }

        let logsDirectory = documentsDirectory.appendingPathComponent("Logs", isDirectory: true)

        // Create logs directory if needed
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            do {
                try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                print("✅ Logger: Created logs directory at \(logsDirectory.path)")
            } catch {
                print("❌ Logger: Could not create logs directory: \(error)")
                return
            }
        }

        // Set current log file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        logFileURL = logsDirectory.appendingPathComponent("app-\(dateString).log")

        // Rotate logs if needed
        rotateLogsIfNeeded()

        print("✅ Logger: Initialized with log file at \(logFileURL?.path ?? "unknown")")
    }

    // MARK: - Logging Methods

    /// Log a debug message
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    /// Log an info message
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    /// Log a warning message
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    /// Log an error message
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .error, file: file, function: function, line: line)
    }

    /// Log a critical message
    func critical(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - Error: \(error.localizedDescription)"
        }
        log(fullMessage, level: .critical, file: file, function: function, line: line)
    }

    // MARK: - Core Logging
    private func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) {
        // Check minimum log level
        guard level >= minimumLogLevel else { return }

        // Format message
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "\(level.icon) [\(timestamp)] [\(fileName):\(line)] \(message)"

        // Log to console
        print(formattedMessage)

        // Log to OSLog
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)

        // Log to file (async)
        logQueue.async { [weak self] in
            self?.writeToFile(formattedMessage)
        }
    }

    // MARK: - File Logging
    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        let logEntry = message + "\n"

        if fileManager.fileExists(atPath: logFileURL.path) {
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                if let data = logEntry.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } else {
            // Create new file
            try? logEntry.write(to: logFileURL, atomically: true, encoding: .utf8)
        }

        // Check if rotation is needed
        rotateLogsIfNeeded()
    }

    // MARK: - Log Rotation
    private func rotateLogsIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        // Check current log file size
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize >= maxLogFileSize else {
            return
        }

        // Rotate: Rename current file with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let logsDirectory = logFileURL.deletingLastPathComponent()
        let rotatedURL = logsDirectory.appendingPathComponent("app-\(timestamp).log")

        do {
            try fileManager.moveItem(at: logFileURL, to: rotatedURL)
            print("✅ Logger: Rotated log file to \(rotatedURL.lastPathComponent)")

            // Clean up old logs
            cleanupOldLogs()
        } catch {
            print("❌ Logger: Could not rotate log file: \(error)")
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
                    return date1 > date2 // Newest first
                }

            // Keep only the most recent logs
            if logFiles.count > maxLogFiles {
                let filesToDelete = logFiles.suffix(from: maxLogFiles)
                for file in filesToDelete {
                    try? fileManager.removeItem(at: file)
                    print("🗑️ Logger: Deleted old log file \(file.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Logger: Could not cleanup old logs: \(error)")
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
            print("❌ Logger: Could not get log files: \(error)")
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

            print("✅ Logger: Cleared all log files")

            // Reinitialize log file
            setupLogFile()
        } catch {
            print("❌ Logger: Could not clear logs: \(error)")
        }
    }
}
