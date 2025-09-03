import SwiftUI
import Combine

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @EnvironmentObject var appState: AppState
    
    @State private var showingResetAlert = false
    @State private var resetType: ResetType?
    @State private var showingValidationError = false
    @State private var validationError = ""
    
    @Environment(\.dismiss) private var dismiss
    
    enum ResetType {
        case servers, backup, preferences, all
        
        var title: String {
            switch self {
            case .servers: return "Reset Server Settings"
            case .backup: return "Reset Backup Settings"
            case .preferences: return "Reset App Preferences"
            case .all: return "Reset All Settings"
            }
        }
        
        var message: String {
            switch self {
            case .servers: return "This will reset server configurations to defaults."
            case .backup: return "This will reset backup settings to defaults."
            case .preferences: return "This will reset app preferences to defaults."
            case .all: return "This will reset all settings to their default values."
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                serverConfigurationSection
                modelSelectionSection
                backupSection
                appPreferencesSection
                dataManagementSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
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
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
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
            .task {
                // Load models when view appears
                await settingsManager.refreshModelsIfNeeded()
            }
        }
    }
    
    // MARK: - Server Configuration Section
    
    private var serverConfigurationSection: some View {
        Section("AI Services") {
            VStack(alignment: .leading, spacing: 12) {
                serverConfigCard(
                    title: "Ollama Server",
                    icon: "brain.head.profile",
                    config: $settingsManager.ollamaConfig,
                    status: settingsManager.ollamaStatus,
                    testAction: {
                        Task {
                            await settingsManager.testOllamaConnection()
                        }
                    }
                )
                
                Divider()
                
                serverConfigCard(
                    title: "Docling Server",
                    icon: "doc.text.magnifyingglass",
                    config: $settingsManager.doclingConfig,
                    status: settingsManager.doclingStatus,
                    testAction: {
                        Task {
                            await settingsManager.testDoclingConnection()
                        }
                    }
                )
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Model Selection Section
    
    private var modelSelectionSection: some View {
        Section("AI Model Selection") {
            VStack(spacing: 16) {
                // Refresh button and status
                HStack {
                    Button("Refresh Models") {
                        Task {
                            await settingsManager.fetchAvailableModels()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(settingsManager.modelSelection.isLoading)
                    
                    Spacer()
                    
                    if settingsManager.modelSelection.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = settingsManager.modelSelection.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // Chat model selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat Model")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Picker("Chat Model", selection: $settingsManager.modelPreferences.chatModel) {
                        ForEach(chatModels, id: \.id) { model in
                            Text(model.displayName)
                                .tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Used for health conversations. Vision models (👁️) can also handle images and documents in chat.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Vision model selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Document Scanning Model")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    if visionModels.isEmpty && !settingsManager.modelSelection.isLoading {
                        Text("No vision-capable models found. Install models like llava or moondream for document scanning.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.vertical, 8)
                    } else {
                        Picker("Vision Model", selection: $settingsManager.modelPreferences.visionModel) {
                            ForEach(visionModels, id: \.id) { model in
                                Text(model.displayName)
                                    .tag(model.name)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Text("Used for analyzing documents, images, and visual health data")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // Helper computed properties for model lists
    private var chatModels: [OllamaModel] {
        // All models can be used for chat, but prioritize text-only models first
        let textModels = settingsManager.modelSelection.availableModels.filter { !$0.supportsVision }
        let visionModels = settingsManager.modelSelection.availableModels.filter { $0.supportsVision }
        return textModels + visionModels
    }
    
    private var visionModels: [OllamaModel] {
        settingsManager.modelSelection.availableModels.filter { $0.supportsVision }
    }
    
    // MARK: - Backup Section
    
    private var backupSection: some View {
        Section("iCloud Backup") {
            Toggle("Enable iCloud Backup", isOn: $settingsManager.backupSettings.iCloudEnabled)
                .onChange(of: settingsManager.backupSettings.iCloudEnabled) { _, enabled in
                    if enabled {
                        // Request iCloud permission if needed
                        // This is a placeholder for actual iCloud integration
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
                }
            }
        }
    }
    
    // MARK: - App Preferences Section
    
    private var appPreferencesSection: some View {
        Section("App Preferences") {
            HStack {
                Label("Theme", systemImage: "paintbrush")
                Spacer()
                Picker("Theme", selection: $settingsManager.appPreferences.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
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
        testAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                
                Spacer()
                
                Label(status.displayText, systemImage: status.systemImage)
                    .font(.caption)
                    .foregroundColor(status.color)
            }
            
            // Fields using Form-style layout
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hostname")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("localhost", text: config.hostname, onEditingChanged: { isEditing in
                        if !isEditing {
                            validateConfiguration()
                        }
                    })
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
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
                }
            }
            
            // Test button
            Button(action: testAction) {
                HStack {
                    if status == .testing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "network")
                    }
                    
                    Text("Test Connection")
                }
            }
            .buttonStyle(.bordered)
            .disabled(status == .testing)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    
    // MARK: - Helper Functions
    
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
        // Only validate when user finishes editing, not while typing
        
        // Validate Ollama configuration
        if let error = settingsManager.validateServerConfiguration(settingsManager.ollamaConfig) {
            validationError = "Ollama: \(error)"
            showingValidationError = true
            return
        }
        
        // Validate Docling configuration  
        if let error = settingsManager.validateServerConfiguration(settingsManager.doclingConfig) {
            validationError = "Docling: \(error)"
            showingValidationError = true
            return
        }
    }
    
    private func performReset() {
        guard let resetType = resetType else { return }
        
        switch resetType {
        case .servers:
            settingsManager.resetServerSettings()
        case .backup:
            settingsManager.resetBackupSettings()
        case .preferences:
            settingsManager.resetAppPreferences()
        case .all:
            settingsManager.resetAllSettings()
        }
        
        // Update app state if preferences were reset
        if resetType == .preferences || resetType == .all {
            appState.colorScheme = settingsManager.appPreferences.theme.colorScheme
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
                    // Could show a toast or alert here
                }
            } catch {
                await MainActor.run {
                    validationError = "Failed to clear cache: \(error.localizedDescription)"
                    showingValidationError = true
                }
            }
        }
    }
    
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}