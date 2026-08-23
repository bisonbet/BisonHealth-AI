import SwiftUI
import UIKit

// MARK: - Database Unavailable View
/// Shown in place of the app's UI when `DatabaseManager.shared` could not open the
/// database. This state used to trap at launch, so the only evidence a user had was
/// an app that closed instantly; here the cause is on screen and the diagnostic logs
/// are one tap away.
struct DatabaseUnavailableView: View {
    let error: Error

    @State private var didCopyDetails = false
    @State private var copyConfirmationTask: Task<Void, Never>?
    @State private var isConfirmingErase = false
    @State private var eraseFailureMessage: String?

    private var isFileSystemUnavailable: Bool {
        error is FileSystemError
    }

    private var title: String {
        isFileSystemUnavailable ? "Secure File Storage Didn't Open" : "Your Health Data Didn't Open"
    }

    private var dataSafetyMessage: String {
        if isFileSystemUnavailable {
            return "Nothing was changed, deleted, or sent anywhere. The app stopped before using secure file storage."
        }
        return "Nothing was changed, deleted, or sent anywhere. The app stopped before touching your records."
    }

    private var summary: String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private var recoverySuggestion: String {
        if let databaseError = error as? DatabaseError {
            return databaseError.launchRecoverySuggestion
        }
        if let fileSystemError = error as? FileSystemError {
            return fileSystemError.launchRecoverySuggestion
        }
        return "Close and reopen BisonHealth AI. If it keeps happening, share the diagnostic logs."
    }

    /// Erasing is offered wherever the records are genuinely unreachable and a rebuild is
    /// possible. Note the default: most launch failures surface as a raw SQLite error rather
    /// than a `DatabaseError` — a corrupt file is the common case — and those are exactly the
    /// ones only a rebuild clears. Two cases are excluded: a version mismatch, where the data
    /// is intact and a newer build opens it, and a file-storage failure, which erasing the
    /// database would not fix.
    private var canOfferErase: Bool {
        guard !isFileSystemUnavailable else { return false }
        if let databaseError = error as? DatabaseError, !databaseError.isRecoverableByErasingData {
            return false
        }
        return DatabaseManager.shared.canResetDatabase
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                card(
                    title: "What to do",
                    icon: "arrow.clockwise.circle.fill",
                    color: BisonTheme.gold,
                    content: recoverySuggestion
                )
                card(
                    title: "Your data is intact",
                    icon: "lock.fill",
                    color: BisonTheme.sage,
                    content: dataSafetyMessage
                )
                technicalDetails
                actions
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .background(BisonTheme.appBackground)
        .accessibilityIdentifier("databaseUnavailableView")
        .alert("Erase Health Data?", isPresented: $isConfirmingErase) {
            Button("Erase Everything", role: .destructive) { eraseAndRebuild() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes every record stored on this device and starts with an empty database. It cannot be undone, and there is no backup to restore from. Share the diagnostic logs first if you want the failure investigated.")
        }
        .alert(
            "Erase Failed",
            isPresented: Binding(
                get: { eraseFailureMessage != nil },
                set: { if !$0 { eraseFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { eraseFailureMessage = nil }
        } message: {
            Text(eraseFailureMessage ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .fontWeight(.semibold)

            Text(summary)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Technical details: \(summary)")
        .accessibilityIdentifier("databaseUnavailableDetails")
    }

    private var actions: some View {
        VStack(spacing: 16) {
            Button {
                exportLogs()
            } label: {
                Text("Share Diagnostic Logs")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(BisonTheme.gold)
                    .cornerRadius(12)
            }
            .accessibilityLabel("Share diagnostic logs")
            .accessibilityHint("Prepares a support email with this device's logs attached")
            .accessibilityIdentifier("databaseUnavailableShareLogsButton")

            Button {
                copyDetails()
            } label: {
                Text(didCopyDetails ? "Copied" : "Copy Details")
                    .fontWeight(.medium)
                    .foregroundColor(BisonTheme.gold)
            }
            .accessibilityLabel(didCopyDetails ? "Details copied" : "Copy details")
            .accessibilityHint("Copies the technical error text to the clipboard")
            .accessibilityIdentifier("databaseUnavailableCopyDetailsButton")

            if canOfferErase {
                Button(role: .destructive) {
                    isConfirmingErase = true
                } label: {
                    Text("Erase and Start Over")
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Erase health data and start over")
                .accessibilityHint("Permanently deletes every record on this device and rebuilds an empty database")
                .accessibilityIdentifier("databaseUnavailableEraseButton")
            }
        }
    }

    // MARK: - Helpers

    private func card(title: String, icon: String, color: Color, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }

            Text(content)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(content)")
    }

    private func copyDetails() {
        UIPasteboard.general.string = summary
        didCopyDetails = true

        // Without this the button reads "Copied" for the rest of the screen's life, so a
        // later tap gives no sign that it did anything.
        copyConfirmationTask?.cancel()
        copyConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            didCopyDetails = false
        }
    }

    /// The one action that can get a user past an unopenable database. Everything else on
    /// this screen explains; without this the advice to close and reopen loops forever.
    private func eraseAndRebuild() {
        do {
            try DatabaseManager.shared.resetDatabase()
            AppStartupHealth.shared.refresh()
        } catch {
            AppLog.shared.database("Database erase-and-rebuild failed: \(error)", level: .critical)
            eraseFailureMessage = "The data could not be erased: \(error.localizedDescription)"
        }
    }

    private func exportLogs() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        LogExporter.exportLogs(from: rootVC, context: .crashReport)
    }
}

#Preview {
    DatabaseUnavailableView(
        error: DatabaseError.incompatibleVersion(
            "Database version 10 is newer than app version 8. Please update the app."
        )
    )
}
