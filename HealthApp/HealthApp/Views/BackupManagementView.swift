import SwiftUI
import Combine

struct BackupManagementView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingBackupError = false
    @State private var backupError: BackupError?
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackupForRestore: BackupMetadata?
    @State private var showingStorageWarning = false

    var body: some View {
        NavigationStack {
            List {
                backupStatusSection
                backupControlsSection
                availableBackupsSection
                storageInfoSection
                troubleshootingSection
            }
            .navigationTitle("Backup Management")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Storage Warning", isPresented: $showingStorageWarning) {
                Button("Manage Storage", role: .none) {
                    // Open iOS Settings for iCloud storage management
                    if let url = URL(string: "prefs:root=APPLE_ACCOUNT&path=ICLOUD_SERVICE") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Dismiss") {
                    settingsManager.backupManager?.dismissStorageWarning()
                }
            } message: {
                Text("Your iCloud storage is full. Backups have been disabled until you free up space.")
            }
            .alert("Backup Error", isPresented: $showingBackupError) {
                Button("OK") {
                    backupError = nil
                }
                if backupError != nil {
                    Button("Help") {
                        // Show more detailed error information
                    }
                }
            } message: {
                if let error = backupError {
                    Text("\(error.localizedDescription)\n\n\(error.recoveryMessage)")
                }
            }
            .confirmationDialog(
                "Restore Backup",
                isPresented: $showingRestoreConfirmation,
                presenting: selectedBackupForRestore
            ) { backup in
                Button("Restore", role: .destructive) {
                    Task {
                        await performRestore(backup)
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedBackupForRestore = nil
                }
            } message: { backup in
                Text("This will replace all current data with backup from \(backup.backupDate.formatted()). This action cannot be undone.")
            }
            .task {
                await settingsManager.fetchAvailableBackups()
            }
        }
    }

    // MARK: - Backup Status Section

    private var backupStatusSection: some View {
        Section("Backup Status") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        statusIcon
                        Text(backupStatusText)
                            .font(.headline)
                        Spacer()
                    }

                    if let backupManager = settingsManager.backupManager,
                       backupManager.status.isActive {
                        ProgressView(value: backupProgress)
                            .progressViewStyle(.linear)
                            .animation(.easeInOut, value: backupProgress)
                    }

                    if !settingsManager.backupSettings.iCloudEnabled {
                        Text("iCloud backup is disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if case .completed(_) = settingsManager.backupManager?.status {
                        Text("Last successful backup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Backup Controls Section

    private var backupControlsSection: some View {
        Section("Backup Controls") {
            if settingsManager.backupSettings.iCloudEnabled {
                Button("Backup Now") {
                    Task {
                        await performManualBackup()
                    }
                }
                .disabled(settingsManager.backupManager?.status.isActive ?? false)

                if !(settingsManager.backupManager?.availableBackups.isEmpty ?? true) {
                    NavigationLink("Manage Backups") {
                        BackupListView()
                    }
                }
            } else {
                Button("Enable iCloud Backup") {
                    Task {
                        await enableBackup()
                    }
                }
            }
        }
    }

    // MARK: - Available Backups Section

    private var availableBackupsSection: some View {
        Section("Available Backups") {
            if let backups = settingsManager.backupManager?.availableBackups, !backups.isEmpty {
                ForEach(backups.prefix(5), id: \.id) { backup in
                    backupRow(backup)
                }

                if backups.count > 5 {
                    NavigationLink("View All Backups (\(backups.count))") {
                        BackupListView()
                    }
                }
            } else {
                Text("No backups available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Storage Info Section

    private var troubleshootingSection: some View {
        Section("Troubleshooting") {
            Button("Clean Corrupted Backups", role: .destructive) {
                Task {
                    await settingsManager.backupManager?.cleanupCorruptedMetadata()
                    await settingsManager.fetchAvailableBackups()
                }
            }
        }
    }

    private var storageInfoSection: some View {
        Section("Storage Information") {
            VStack(alignment: .leading, spacing: 8) {
                if settingsManager.backupManager?.lastBackupSize ?? 0 > 0 {
                    HStack {
                        Text("Last Backup Size")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: settingsManager.backupManager?.lastBackupSize ?? 0, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Backup Content")
                    Spacer()
                    Text(enabledBackupTypes)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func backupRow(_ backup: BackupMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.deviceName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(backup.backupDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: backup.totalSize, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Restore") {
                        selectedBackupForRestore = backup
                        showingRestoreConfirmation = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            Text(backup.dataTypes.joined(separator: ", ").capitalized)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Computed Properties

    private var statusIcon: some View {
        Group {
            switch settingsManager.backupManager?.status {
            case .disabled:
                Image(systemName: "icloud.slash")
                    .foregroundColor(.secondary)
            case .idle:
                Image(systemName: "icloud")
                    .foregroundColor(.blue)
            case .backingUp:
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.blue)
            case .restoring:
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundColor(.blue)
            case .completed:
                Image(systemName: "checkmark.icloud")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "exclamationmark.icloud")
                    .foregroundColor(.red)
            case .none:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var backupStatusText: String {
        settingsManager.backupManager?.status.displayText ?? "Unknown"
    }

    private var backupProgress: Double {
        switch settingsManager.backupManager?.status {
        case .backingUp(let progress), .restoring(let progress):
            return progress
        default:
            return 0.0
        }
    }

    private var enabledBackupTypes: String {
        var types: [String] = []
        let settings = settingsManager.backupSettings

        if settings.backupHealthData { types.append("Health Data") }
        if settings.backupChatHistory { types.append("Chat History") }
        if settings.backupDocuments { types.append("Documents") }
        if settings.backupAppSettings { types.append("App Settings") }

        return types.isEmpty ? "None" : types.joined(separator: ", ")
    }

    // MARK: - Actions

    private func enableBackup() async {
        do {
            try await settingsManager.enableiCloudBackup()
        } catch let error as BackupError {
            backupError = error
            showingBackupError = true
        } catch {
            backupError = .cloudKitError(error.localizedDescription)
            showingBackupError = true
        }
    }

    private func performManualBackup() async {
        await settingsManager.performManualBackup()
    }

    private func performRestore(_ backup: BackupMetadata) async {
        await settingsManager.restoreFromBackup(backup)
    }

    private func handleBackupStatusChange(_ status: BackupStatus) {
        switch status {
        case .failed(let error):
            if case .insufficientStorage = error {
                if !(settingsManager.backupManager?.storageWarningDismissed ?? true) {
                    showingStorageWarning = true
                }
            } else {
                backupError = error
                showingBackupError = true
            }
        default:
            break
        }
    }
}

// MARK: - Backup List View

struct BackupListView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingRestoreConfirmation = false
    @State private var selectedBackupForRestore: BackupMetadata?

    var body: some View {
        NavigationStack {
            List {
                if let backups = settingsManager.backupManager?.availableBackups {
                    ForEach(backups, id: \.id) { backup in
                        BackupDetailRow(
                            backup: backup,
                            onRestore: { backup in
                                selectedBackupForRestore = backup
                                showingRestoreConfirmation = true
                            }
                        )
                    }
                    .onDelete(perform: deleteBackups)
                } else {
                    Text("No backups available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .navigationTitle("All Backups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Restore Backup",
                isPresented: $showingRestoreConfirmation,
                presenting: selectedBackupForRestore
            ) { backup in
                Button("Restore", role: .destructive) {
                    Task {
                        await settingsManager.restoreFromBackup(backup)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedBackupForRestore = nil
                }
            } message: { backup in
                Text("This will replace all current data with backup from \(backup.backupDate.formatted()). This action cannot be undone.")
            }
            .refreshable {
                await settingsManager.fetchAvailableBackups()
            }
        }
    }

    private func deleteBackups(at offsets: IndexSet) {
        guard let backups = settingsManager.backupManager?.availableBackups else { return }
        
        let backupsToDelete = offsets.map { backups[$0] }
        
        Task {
            for backup in backupsToDelete {
                await settingsManager.backupManager?.deleteBackupRecord(backup)
            }
        }
    }
}


// MARK: - Backup Detail Row

struct BackupDetailRow: View {
    let backup: BackupMetadata
    let onRestore: (BackupMetadata) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.deviceName)
                        .font(.headline)

                    Text("App Version \(backup.appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(backup.backupDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text(ByteCountFormatter.string(fromByteCount: backup.totalSize, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Contains: \(backup.dataTypes.joined(separator: ", ").capitalized)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Restore") {
                    onRestore(backup)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BackupManagementView()
        .environmentObject(AppState())
}
