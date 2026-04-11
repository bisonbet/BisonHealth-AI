import Foundation
import OSLog
import UIKit

// MARK: - Log Exporter
/// Collects logs from OSLogStore, persistent error buffer, and file-based logs,
/// then exports them as a single shareable text file.
struct LogExporter {

    // MARK: - Export

    /// Generates a combined log export and presents a share sheet.
    /// Call from a SwiftUI view by passing the current UIWindow's rootViewController.
    @MainActor
    static func exportLogs(from viewController: UIViewController) {
        let content = gatherLogs()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("HealthApp-Logs-\(dateStamp()).txt")

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            AppLog.shared.error("Failed to write log export file", error: error, category: .general)
            return
        }

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

        // iPad requires a popover source
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                        y: viewController.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        viewController.present(activityVC, animated: true)
    }

    // MARK: - Log Gathering

    private static func gatherLogs() -> String {
        var sections: [String] = []

        sections.append("=== HealthApp Log Export ===")
        sections.append("Exported: \(ISO8601DateFormatter().string(from: Date()))")
        sections.append("Device: \(UIDevice.current.name)")
        sections.append("iOS: \(UIDevice.current.systemVersion)")
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            sections.append("App: \(version) (\(build))")
        }
        sections.append("Previous session crashed: \(AppLog.shared.previousSessionCrashed)")
        sections.append("")

        // Section 1: OSLogStore (last 24 hours)
        sections.append("--- OS Log Store (last 24 hours) ---")
        sections.append(fetchOSLogEntries())
        sections.append("")

        // Section 2: Persistent error buffer
        sections.append("--- Persistent Error Buffer ---")
        if let errorBuffer = AppLog.shared.getErrorBufferContent(), !errorBuffer.isEmpty {
            sections.append(errorBuffer)
        } else {
            sections.append("(empty)")
        }
        sections.append("")

        // Section 3: File-based logs
        sections.append("--- File-Based Logs ---")
        if let fileContent = AppLog.shared.getCurrentLogContent(), !fileContent.isEmpty {
            sections.append(fileContent)
        } else {
            sections.append("(empty)")
        }

        return sections.joined(separator: "\n")
    }

    private static func fetchOSLogEntries() -> String {
        guard #available(iOS 15.0, *) else {
            return "(OSLogStore requires iOS 15+)"
        }

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-86400)) // 24 hours ago
            let subsystem = Bundle.main.bundleIdentifier ?? "com.bisonhealth"

            let entries = try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == subsystem }

            if entries.isEmpty {
                return "(no entries found)"
            }

            let formatter = ISO8601DateFormatter()
            return entries.map { entry in
                let ts = formatter.string(from: entry.date)
                let level = logLevelLabel(for: entry.level)
                return "[\(ts)] [\(level)] [\(entry.category)] \(entry.composedMessage)"
            }.joined(separator: "\n")
        } catch {
            return "(failed to read OSLogStore: \(error.localizedDescription))"
        }
    }

    private static func logLevelLabel(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "UNKNOWN"
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
