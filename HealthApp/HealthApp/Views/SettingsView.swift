import SwiftUI
import Combine

struct SettingsView: View {
    enum SettingsRoute: Hashable {
        case ollamaSettings
        case awsBedrockSettings
        case openAICompatibleSettings
    }
    @StateObject private var settingsManager = SettingsManager.shared
    @EnvironmentObject var appState: AppState
    @State private var navigationPath = NavigationPath()
    
    @State private var showingResetAlert = false
    @State private var resetType: ResetType?
    @State private var showingValidationError = false
    @State private var validationError = ""
    @State private var showingConnectionError = false
    @State private var connectionError = ""
    @State private var showingSuccessMessage = false
    @State private var successMessage = ""
    @State private var isSyncingAppleHealth = false
    @State private var lastSyncDate: Date?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthDataManager = HealthDataManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    
    enum ResetType {
        case servers, backup, preferences, all, database, disclaimer
        
        var title: String {
            switch self {
            case .servers: return "Reset Server Settings"
            case .backup: return "Reset Backup Settings"
            case .preferences: return "Reset App Preferences"
            case .all: return "Reset All Settings"
            case .database: return "Reset Database"
            case .disclaimer: return "Reset Disclaimer Acceptance"
            }
        }
        
        var message: String {
            switch self {
            case .servers: return "This will reset server configurations to defaults."
            case .backup: return "This will reset backup settings to defaults."
            case .preferences: return "This will reset app preferences to defaults."
            case .all: return "This will reset all settings to their default values."
            case .database: return "⚠️ WARNING: This will permanently delete ALL your health data, documents, and chat history. This action cannot be undone. A backup will be created first."
            case .disclaimer: return "This will reset the disclaimer acceptance. You will need to accept the disclaimer again on next app launch."
            }
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            settingsForm
                .navigationTitle("Settings")
                .toolbar { toolbarContent }
                .modifier(AlertsModifier(
                    resetType: resetType,
                    showingResetAlert: $showingResetAlert,
                    showingValidationError: $showingValidationError,
                    showingConnectionError: $showingConnectionError,
                    showingSuccessMessage: $showingSuccessMessage,
                    validationError: validationError,
                    connectionError: connectionError,
                    successMessage: successMessage,
                    performReset: performReset
                ))
                .modifier(ChangeObserversModifier(
                    settingsManager: settingsManager,
                    appState: appState,
                    validateAndSave: validateAndSave
                ))
                .task {
                    await settingsManager.refreshModelsIfNeeded()
                }
                .navigationDestination(for: SettingsRoute.self) { destination in
                    navigationDestinationView(for: destination)
                }
        }
    }

    private var settingsForm: some View {
        Form {
            disclaimerSection
            aiProviderSection
            documentProcessingSection
            appleHealthSection
            backupSection
            appPreferencesSection
            dataManagementSection
            aboutSection
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Reset Server Settings") {
                    resetType = .servers
                    showingResetAlert = true
                }

                Button("Reset Backup Settings") {
                    resetType = .backup
                    showingResetAlert = true
                }

                Button("Reset App Preferences") {
                    resetType = .preferences
                    showingResetAlert = true
                }

                Divider()

                Button("Reset All Settings", role: .destructive) {
                    resetType = .all
                    showingResetAlert = true
                }

                Divider()

                Button("Reset Disclaimer Acceptance", role: .destructive) {
                    resetType = .disclaimer
                    showingResetAlert = true
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private func navigationDestinationView(for destination: SettingsRoute) -> some View {
        let _ = print("📍 navigationDestination called with: \(destination)")
        switch destination {
        case .ollamaSettings:
            let _ = print("📍 Creating OllamaSettingsView")
            OllamaSettingsView()
                .onAppear {
                    print("🟠 Navigated to Ollama Settings")
                }
        case .awsBedrockSettings:
            let _ = print("📍 Creating AWSBedrockSettingsView")
            AWSBedrockSettingsView()
                .onAppear {
                    print("🔵 Navigated to AWS Bedrock Settings")
                }
        case .openAICompatibleSettings:
            let _ = print("📍 Creating OpenAICompatibleSettingsView")
            OpenAICompatibleSettingsView(settingsManager: settingsManager)
                .onAppear {
                    print("🟢 Navigated to OpenAI Compatible Settings")
                }
        }
    }
    
    // MARK: - Provider Configuration Cards

    private var ollamaServerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ollama Server", systemImage: "brain.head.profile")
                    .font(.headline)

                Spacer()

                Button("Configure") {
                    print("🟠 Ollama Configure button tapped")
                    navigationPath.append(SettingsRoute.ollamaSettings)
                }
                .buttonStyle(.bordered)
            }

            Text("Local AI models for chat, document processing, and vision tasks")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var doclingServerCard: some View {
        serverConfigCard(
            title: "Docling Server",
            icon: "doc.text.magnifyingglass",
            config: $settingsManager.doclingConfig,
            status: settingsManager.doclingStatus,
            testAction: {
                Task {
                    await testDoclingConnection()
                }
            },
            onConfigChange: { newConfig in
                settingsManager.doclingConfig = newConfig
                settingsManager.saveSettings()
            }
        )
    }

    private var awsBedrockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AWS Bedrock", systemImage: "cloud.fill")
                    .font(.headline)

                Spacer()

                Button("Configure") {
                    print("🔵 AWS Bedrock Configure button tapped")
                    navigationPath.append(SettingsRoute.awsBedrockSettings)
                }
                .buttonStyle(.bordered)
            }

            Text("Claude Sonnet 4.5, Amazon Nova Premier, and Llama 4 Maverick models for advanced health data analysis")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var openAICompatibleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("OpenAI Compatible", systemImage: "network")
                    .font(.headline)

                Spacer()

                Button("Configure") {
                    print("🟢 OpenAI Compatible Configure button tapped")
                    navigationPath.append(SettingsRoute.openAICompatibleSettings)
                }
                .buttonStyle(.bordered)
            }

            Text("LiteLLM, LocalAI, vLLM, and other OpenAI-compatible servers")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - AI Provider Section

    private var aiProviderSection: some View {
        Section("AI Provider") {
            VStack(spacing: 16) {
                Picker("AI Provider", selection: $settingsManager.modelPreferences.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                Text("Choose your AI service provider")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Show only the selected provider's configuration card
                switch settingsManager.modelPreferences.aiProvider {
                case .ollama:
                    ollamaServerCard
                case .bedrock:
                    awsBedrockCard
                case .openAICompatible:
                    openAICompatibleCard
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Document Processing Section

    private var documentProcessingSection: some View {
        Section("Document Processing") {
            doclingServerCard
        }
    }

    // MARK: - Apple Health Section

    private var appleHealthSection: some View {
        Section("Apple Health Sync") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundColor(.pink)
                        .font(.title3)

                    Text("Sync with Apple Health")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()
                }

                Text("Automatically sync vitals (blood pressure, heart rate, weight), sleep data, and personal information from the Health app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Sync status
                if healthKitManager.isHealthKitAvailable() {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: healthKitManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(healthKitManager.isAuthorized ? .green : .orange)

                            Text(healthKitManager.isAuthorized ? "Connected to Apple Health" : "Not Authorized")
                                .font(.caption)
                                .foregroundColor(healthKitManager.isAuthorized ? .green : .orange)

                            Spacer()
                        }

                        if let lastSync = healthKitManager.lastSyncDate {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                    .font(.caption)

                                Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                        }

                        // Sync button
                        Button(action: { syncAppleHealth() }) {
                            HStack {
                                if isSyncingAppleHealth {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }

                                Text(isSyncingAppleHealth ? "Syncing..." : "Sync Now")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSyncingAppleHealth)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("Apple Health is not available on this device")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }


    // MARK: - Backup Section

    private var backupSection: some View {
        Section("iCloud Backup") {
            // iCloud backup disclaimer
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    
                    Text("iCloud Backup Notice")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Text("iCloud backup is an optional convenience for personal use. Apple does not provide a Business Associate Agreement (BAA) for iCloud services. If you need regulated storage, you should disable iCloud backup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
            }
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Main backup toggle with status
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable iCloud Backup", isOn: $settingsManager.backupSettings.iCloudEnabled)
                    .onChange(of: settingsManager.backupSettings.iCloudEnabled) { _, enabled in
                        Task {
                            if enabled {
                                do {
                                    try await settingsManager.enableiCloudBackup()
                                } catch {
                                    // Reset toggle if enabling failed
                                    settingsManager.backupSettings.iCloudEnabled = false
                                }
                            } else {
                                settingsManager.disableiCloudBackup()
                            }
                        }
                    }

                // Show backup status when enabled
                if settingsManager.backupSettings.iCloudEnabled {
                    HStack {
                        statusIndicator
                        Text(backupStatusText)
                            .font(.caption)
                            .foregroundColor(statusColor)
                        Spacer()
                        if let manager = settingsManager.backupManager, manager.status.isActive {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.leading, 4)
                }
            }

            if settingsManager.backupSettings.iCloudEnabled {
                Group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup Content")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(spacing: 4) {
                            Toggle("Health Data", isOn: $settingsManager.backupSettings.backupHealthData)
                            Toggle("Chat History", isOn: $settingsManager.backupSettings.backupChatHistory)
                            Toggle("Documents", isOn: $settingsManager.backupSettings.backupDocuments)
                            Toggle("App Settings", isOn: $settingsManager.backupSettings.backupAppSettings)
                        }
                    }
                    .padding(.leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup Frequency")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Frequency", selection: $settingsManager.backupSettings.backupFrequency) {
                            ForEach(BackupFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Auto Backup", isOn: $settingsManager.backupSettings.autoBackup)
                    }
                    .padding(.leading)

                    // Backup controls
                    VStack(spacing: 12) {
                        HStack {
                            Button("Backup Now") {
                                Task {
                                    await settingsManager.performManualBackup()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(settingsManager.backupManager?.status.isActive ?? true)

                            Spacer()

                            NavigationLink("Manage Backups") {
                                BackupManagementView()
                            }
                            .buttonStyle(.bordered)
                        }

                        // Show backup size info if available
                        if let backupSize = settingsManager.backupManager?.lastBackupSize, backupSize > 0 {
                            HStack {
                                Text("Last backup size:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: backupSize, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.leading)
                }
            }
        }
    }

    // MARK: - Backup Status Helpers

    private var statusIndicator: some View {
        Group {
            switch settingsManager.backupManager?.status {
            case .disabled:
                Image(systemName: "icloud.slash")
            case .idle:
                Image(systemName: "icloud")
            case .backingUp:
                Image(systemName: "icloud.and.arrow.up")
            case .restoring:
                Image(systemName: "icloud.and.arrow.down")
            case .completed:
                Image(systemName: "checkmark.icloud")
            case .failed:
                Image(systemName: "exclamationmark.icloud")
            case .none:
                Image(systemName: "questionmark.circle")
            }
        }
        .foregroundColor(statusColor)
        .font(.caption)
    }

    private var backupStatusText: String {
        settingsManager.backupManager?.status.displayText ?? "Unknown"
    }

    private var statusColor: Color {
        switch settingsManager.backupManager?.status {
        case .disabled:
            return .secondary
        case .idle:
            return .blue
        case .backingUp, .restoring:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .none:
            return .secondary
        }
    }
    
    // MARK: - App Preferences Section
    
    private var appPreferencesSection: some View {
        Section("App Preferences") {
            HStack {
                Label("Theme", systemImage: "paintbrush")
                Spacer()
                Picker(selection: $settingsManager.appPreferences.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
            }
            
            Toggle("Haptic Feedback", isOn: $settingsManager.appPreferences.hapticFeedback)
            
            Toggle("Show Tips", isOn: $settingsManager.appPreferences.showTips)
            
            Toggle("Analytics", isOn: $settingsManager.appPreferences.analyticsEnabled)
        }
    }
    
    // MARK: - Data Management Section
    
    private var dataManagementSection: some View {
        Section("Data Management") {
            NavigationLink("Export Health Data") {
                DataExportView()
            }

            NavigationLink("Storage Usage") {
                StorageUsageView()
            }

            Button("Clear Cache") {
                clearCache()
            }
            .foregroundColor(.orange)

            // Advanced/Dangerous Operations
            Section(footer: Text("⚠️ Advanced operations that may result in data loss")) {
                Button("Reset Database") {
                    resetType = .database
                    showingResetAlert = true
                }
                .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Disclaimer Section
    
    private var disclaimerSection: some View {
        Section("Important Notice") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    Text("Personal Use Only")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("BisonHealth AI is designed exclusively for individual, personal health tracking and management.")
                        .font(.body)
                    
                    Text("This application is NOT intended for use by:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• HIPAA Covered Entities")
                        Text("• Business Associates")
                        Text("• Healthcare providers or clinics")
                        Text("• Professional or enterprise environments")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    
                    Text("We do not provide Business Associate Agreements (BAAs) or HIPAA-compliant guarantees.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                        .padding(.top, 8)
                }
                
                NavigationLink("View Full Disclaimer") {
                    DetailedDisclaimerView()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text("1")
                    .foregroundColor(.secondary)
            }
            
            NavigationLink("Privacy Policy") {
                PrivacyPolicyView()
            }
            
            NavigationLink("Terms of Service") {
                TermsOfServiceView()
            }
            
            Link("Support", destination: URL(string: "mailto:support@bisonhealth.ai")!)
        }
    }
    
    // MARK: - Helper Views
    
    private func serverConfigCard(
        title: String,
        icon: String,
        config: Binding<ServerConfiguration>,
        status: ConnectionStatus,
        testAction: @escaping () -> Void,
        onConfigChange: @escaping (ServerConfiguration) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                
                Spacer()
                
                // Enhanced status display with animation
                HStack(spacing: 4) {
                    if status == .testing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: status.systemImage)
                            .foregroundColor(status.color)
                    }
                    
                    Text(status.displayText)
                        .font(.caption)
                        .foregroundColor(status.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.1))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.3), value: status)
            }
            
            // Fields using Form-style layout
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hostname")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField(ServerConfigurationConstants.defaultOllamaHostname, text: config.hostname, onEditingChanged: { isEditing in
                        if !isEditing {
                            validateConfiguration()
                        }
                    })
                    .onChange(of: config.hostname.wrappedValue) { _, newValue in
                        // Update the configuration when hostname changes
                        var updatedConfig = config.wrappedValue
                        updatedConfig.hostname = newValue
                        onConfigChange(updatedConfig)
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    
                    // Inline validation feedback for hostname
                    if !config.hostname.wrappedValue.isEmpty {
                        let serverConfig = ServerConfiguration(hostname: config.hostname.wrappedValue, port: config.port.wrappedValue)
                        if let validationError = settingsManager.validateServerConfiguration(serverConfig) {
                            Text(validationError)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.top, 2)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Port", value: config.port, format: IntegerFormatStyle().grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .onSubmit {
                            validateConfiguration()
                        }
                        .onChange(of: config.port.wrappedValue) { _, newValue in
                            // Update the configuration when port changes
                            var updatedConfig = config.wrappedValue
                            updatedConfig.port = newValue
                            onConfigChange(updatedConfig)
                        }
                    
                    // Inline validation feedback for port
                    if config.port.wrappedValue < 1 || config.port.wrappedValue > 65535 {
                        Text("Port must be between 1 and 65535")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.top, 2)
                    }
                }
            }
            
            // Test button with enhanced visual feedback
            Button(action: testAction) {
                HStack {
                    if status == .testing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: status == .connected ? "checkmark.circle" : "network")
                            .foregroundColor(status == .connected ? .green : .primary)
                    }
                    
                    Text(status == .testing ? "Testing..." : "Test Connection")
                }
            }
            .buttonStyle(.bordered)
            .disabled(status == .testing)
            .background(
                status == .connected ? 
                Color.green.opacity(0.1) : 
                (isFailedStatus(status) ? Color.red.opacity(0.1) : Color.clear)
            )
            .cornerRadius(6)
            .animation(.easeInOut(duration: 0.2), value: status)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    
    // MARK: - Helper Functions
    
    private func isFailedStatus(_ status: ConnectionStatus) -> Bool {
        if case .failed = status {
            return true
        }
        return false
    }
    
    private func validateAndSave() {
        // Save settings without validation errors during typing
        // Validation will be shown only when user finishes editing
        Task {
            settingsManager.saveSettings()
        }
        
        // Reset connection status when configuration changes
        settingsManager.ollamaStatus = .unknown
        settingsManager.doclingStatus = .unknown
    }
    
    private func validateConfiguration() {
        // Validation is now handled inline in the UI, so this function
        // can be simplified or used for other validation logic
        // The real-time validation happens in the UI components themselves
        
        // Reset connection status when configuration changes since it may no longer be valid
        settingsManager.ollamaStatus = .unknown
        settingsManager.doclingStatus = .unknown
    }
    
    private func performReset() {
        guard let resetType = resetType else { return }
        
        switch resetType {
        case .servers:
            settingsManager.resetServerSettings()
            successMessage = "Server settings have been reset to defaults"
        case .backup:
            settingsManager.resetBackupSettings()
            successMessage = "Backup settings have been reset to defaults"
        case .preferences:
            settingsManager.resetAppPreferences()
            successMessage = "App preferences have been reset to defaults"
        case .all:
            settingsManager.resetAllSettings()
            successMessage = "All settings have been reset to defaults"
        case .database:
            performDatabaseReset()
        case .disclaimer:
            AppSettingsManager.shared.resetDisclaimerAcceptance()
            successMessage = "Disclaimer acceptance has been reset. You will need to accept the disclaimer again on next app launch."
        }
        
        // Update app state if preferences were reset
        if resetType == .preferences || resetType == .all {
            appState.colorScheme = settingsManager.appPreferences.theme.colorScheme
        }
        
        // Show success message
        showingSuccessMessage = true
    }

    // MARK: - Database Reset

    private func performDatabaseReset() {
        Task {
            do {
                try DatabaseManager.shared.resetDatabase()
                await MainActor.run {
                    successMessage = "Database has been reset successfully. All health data has been permanently deleted."
                    showingSuccessMessage = true
                }
            } catch {
                await MainActor.run {
                    validationError = "Failed to reset database: \(error.localizedDescription)"
                    showingValidationError = true
                }
            }
        }
    }

    // MARK: - Connection Testing with Enhanced Feedback
    
    private func testOllamaConnection() async {
        await settingsManager.testOllamaConnection()
        
        // Provide user feedback based on connection result
        await MainActor.run {
            switch settingsManager.ollamaStatus {
            case .connected:
                successMessage = "Successfully connected to Ollama server"
                showingSuccessMessage = true
            case .failed(let error):
                connectionError = "Failed to connect to Ollama server: \(error)"
                showingConnectionError = true
            default:
                break
            }
        }
    }
    
    private func testDoclingConnection() async {
        await settingsManager.testDoclingConnection()
        
        // Provide user feedback based on connection result
        await MainActor.run {
            switch settingsManager.doclingStatus {
            case .connected:
                successMessage = "Successfully connected to Docling server"
                showingSuccessMessage = true
            case .failed(let error):
                connectionError = "Failed to connect to Docling server: \(error)"
                showingConnectionError = true
            default:
                break
            }
        }
    }
    
    private func testAllConnections() async {
        // Test both connections concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.testOllamaConnection()
            }
            group.addTask {
                await self.testDoclingConnection()
            }
        }
    }
    
    private func clearCache() {
        // Implement cache clearing logic
        // This would clear any temporary files, cached images, etc.
        Task {
            do {
                let fileManager = FileSystemManager.shared
                try await fileManager.clearCache()

                // Show success message
                await MainActor.run {
                    successMessage = "Cache cleared successfully"
                    showingSuccessMessage = true
                }
            } catch {
                await MainActor.run {
                    validationError = "Failed to clear cache: \(error.localizedDescription)"
                    showingValidationError = true
                }
            }
        }
    }

    // MARK: - Apple Health Sync

    private func syncAppleHealth() {
        isSyncingAppleHealth = true

        Task {
            do {
                try await healthDataManager.syncFromAppleHealth()

                await MainActor.run {
                    isSyncingAppleHealth = false
                    lastSyncDate = Date()
                    successMessage = "Successfully synced data from Apple Health"
                    showingSuccessMessage = true
                }
            } catch {
                await MainActor.run {
                    isSyncingAppleHealth = false
                    validationError = "Failed to sync from Apple Health: \(error.localizedDescription)"
                    showingValidationError = true
                }
            }
        }
    }

}

// MARK: - View Modifiers

struct AlertsModifier: ViewModifier {
    let resetType: SettingsView.ResetType?
    @Binding var showingResetAlert: Bool
    @Binding var showingValidationError: Bool
    @Binding var showingConnectionError: Bool
    @Binding var showingSuccessMessage: Bool
    let validationError: String
    let connectionError: String
    let successMessage: String
    let performReset: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(resetType?.title ?? "", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    performReset()
                }
            } message: {
                Text(resetType?.message ?? "")
            }
            .alert("Validation Error", isPresented: $showingValidationError) {
                Button("OK") { }
            } message: {
                Text(validationError)
            }
            .alert("Connection Error", isPresented: $showingConnectionError) {
                Button("OK") { }
            } message: {
                Text(connectionError)
            }
            .alert("Success", isPresented: $showingSuccessMessage) {
                Button("OK") { }
            } message: {
                Text(successMessage)
            }
    }
}

struct ChangeObserversModifier: ViewModifier {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var appState: AppState
    let validateAndSave: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(
                settingsManager.$ollamaConfig
                    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            ) { _ in
                settingsManager.invalidateClients()
                validateAndSave()
            }
            .onReceive(
                settingsManager.$doclingConfig
                    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            ) { _ in
                settingsManager.invalidateClients()
                validateAndSave()
            }
            .onChange(of: settingsManager.backupSettings) { _, _ in
                settingsManager.saveSettings()
            }
            .onChange(of: settingsManager.appPreferences) { _, newPreferences in
                appState.colorScheme = newPreferences.theme.colorScheme
                settingsManager.saveSettings()
            }
            .onChange(of: settingsManager.modelPreferences) { _, _ in
                settingsManager.saveSettings()
            }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
