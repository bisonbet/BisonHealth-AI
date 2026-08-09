import Foundation
import MessageUI
import OSLog
import UIKit

// MARK: - Log Exporter
/// Collects logs from OSLogStore, persistent error buffer, and file-based logs,
/// then prepares a support email with the logs attached.
struct LogExporter {
    private static let supportEmail = "support@bisonnetworking.com"

    // MARK: - Export

    /// Generates a combined log export and presents a prefilled support email.
    /// Call from a SwiftUI view by passing the current UIWindow's rootViewController.
    @MainActor
    static func exportLogs(from viewController: UIViewController, context: LogExportContext = .diagnosticLogs) {
        let content = gatherLogs()
        let fileName = "BisonHealth-Logs-\(dateStamp()).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            AppLog.shared.error("Failed to write log export file", error: error, category: .general)
            return
        }

        if MFMailComposeViewController.canSendMail() {
            let mailVC = MFMailComposeViewController()
            mailVC.mailComposeDelegate = MailComposeDelegate.shared
            mailVC.setToRecipients([supportEmail])
            mailVC.setSubject(emailSubject(for: context))
            mailVC.setMessageBody(emailBody(for: context), isHTML: false)
            mailVC.addAttachmentData(Data(content.utf8), mimeType: "text/plain", fileName: fileName)
            viewController.present(mailVC, animated: true)
            return
        }

        openMailApp(for: context)
    }

    // MARK: - Email

    private static func emailSubject(for context: LogExportContext) -> String {
        "\(appDisplayName()) \(appVersionString()) \(context.subjectLabel) - \(displayDate())"
    }

    private static func emailBody(for context: LogExportContext) -> String {
        """
        This is a \(context.bodyLabel) for \(appDisplayName()).

        App: \(appDisplayName()) \(appVersionString())
        Date: \(displayDate())

        Diagnostic logs are attached with personal health information redacted by default.

        Please add any details that may help reproduce or diagnose the issue:
        """
    }

    @MainActor
    private static func openMailApp(for context: LogExportContext) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject(for: context)),
            URLQueryItem(name: "body", value: emailBody(for: context))
        ]

        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Log Gathering

    /// `@MainActor` for the `UIDevice.current` reads below. The only caller,
    /// `exportLogs(from:context:)`, is already main-actor isolated.
    @MainActor
    private static func gatherLogs() -> String {
        var sections: [String] = []

        sections.append("=== HealthApp Log Export ===")
        sections.append("Personal health information is redacted by default before export.")
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
            sections.append(AppLog.redactForSupport(errorBuffer))
        } else {
            sections.append("(empty)")
        }
        sections.append("")

        // Section 3: MetricKit diagnostics delivered by iOS after crashes/hangs.
        sections.append("--- MetricKit Diagnostics ---")
        if let diagnostics = AppLog.shared.getMetricKitDiagnosticsContent(), !diagnostics.isEmpty {
            sections.append(AppLog.redactForSupport(diagnostics))
        } else {
            sections.append("(empty)")
        }
        sections.append("")

        // Section 4: File-based logs
        sections.append("--- File-Based Logs ---")
        if let fileContent = AppLog.shared.getCombinedLogFileContent(), !fileContent.isEmpty {
            sections.append(fileContent)
        } else {
            sections.append("(empty)")
        }

        return sections.joined(separator: "\n")
    }

    private static func fetchOSLogEntries() -> String {
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
                return AppLog.redactForSupport("[\(ts)] [\(level)] [\(entry.category)] \(entry.composedMessage)")
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

    private static func displayDate() -> String {
        Date().formatted(date: .long, time: .shortened)
    }

    private static func appDisplayName() -> String {
        let dictionary = Bundle.main.infoDictionary
        return dictionary?["CFBundleDisplayName"] as? String
            ?? dictionary?["CFBundleName"] as? String
            ?? "BisonHealth AI"
    }

    private static func appVersionString() -> String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "Unknown Version"
        let build = dictionary?["CFBundleVersion"] as? String

        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }
}

enum LogExportContext {
    case diagnosticLogs
    case crashReport

    var subjectLabel: String {
        switch self {
        case .diagnosticLogs:
            return "Diagnostic Logs"
        case .crashReport:
            return "Crash Report"
        }
    }

    var bodyLabel: String {
        switch self {
        case .diagnosticLogs:
            return "diagnostic log report"
        case .crashReport:
            return "crash report"
        }
    }
}

/// `@preconcurrency` on the conformance: `MFMailComposeViewControllerDelegate` predates
/// strict concurrency and is not annotated, but UIKit delivers this callback on the main
/// thread, so the main-actor isolation this class needs (it dismisses a view controller)
/// is sound.
@MainActor
private final class MailComposeDelegate: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    static let shared = MailComposeDelegate()

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        if let error {
            AppLog.shared.error("Mail compose failed", error: error, category: .general)
        }
        controller.dismiss(animated: true)
    }
}
