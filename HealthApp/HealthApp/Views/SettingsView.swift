import SwiftUI
import Combine

struct SettingsView: View {
    enum SettingsRoute: Hashable {
        case awsBedrockSettings
        case openAICompatibleSettings
        case onDeviceLLMSettings
    }
    @StateObject private var settingsManager = SettingsManager.shared
    @EnvironmentObject var appState: AppState
    // Use item-based navigation instead of path-based to prevent stacking issues on iPad
    @State private var selectedRoute: SettingsRoute?

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
        case servers, preferences, all, database, disclaimer
        
        var title: String {
            switch self {
            case .servers: return "Reset Server Settings"
            case .preferences: return "Reset App Preferences"
            case .all: return "Reset All Settings"
            case .database: return "Reset Database"
            case .disclaimer: return "Reset Disclaimer Acceptance"
            }
        }
        
        var message: String {
            switch self {
            case .servers: return "This will reset server configurations to defaults."
            case .preferences: return "This will reset app preferences to defaults."
            case .all: return "This will reset all settings to their default values."
            case .database: return "⚠️ WARNING: This will permanently delete ALL your health data, documents, and chat history. This action cannot be undone. A backup will be created first."
            case .disclaimer: return "This will reset the disclaimer acceptance. You will need to accept the disclaimer again on next app launch."
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .scrollDismissesKeyboard(.interactively)
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
                // Use item-based navigation to prevent stacking issues on iPad
                .navigationDestination(item: $selectedRoute) { destination in
                    navigationDestinationView(for: destination)
                }
        }
    }

    private var settingsForm: some View {
        Form {
            disclaimerSection
            aiProviderSection
            dataExtractionSection
            appleHealthSection
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

        // Keyboard toolbar - shows "Done" button above keyboard
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                // Dismiss keyboard
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .font(.headline)
        }
    }

    @ViewBuilder
    private func navigationDestinationView(for destination: SettingsRoute) -> some View {
        let _ = AppLog.shared.ui("navigationDestination called with: \(destination)", level: .debug)
        switch destination {
        case .awsBedrockSettings:
            let _ = AppLog.shared.ui("Creating AWSBedrockSettingsView", level: .debug)
            AWSBedrockSettingsView()
                .onAppear {
                    AppLog.shared.ui("Navigated to AWS Bedrock Settings")
                }
        case .openAICompatibleSettings:
            let _ = AppLog.shared.ui("Creating OpenAICompatibleSettingsView", level: .debug)
            OpenAICompatibleSettingsView(settingsManager: settingsManager)
                .onAppear {
                    AppLog.shared.ui("Navigated to OpenAI Compatible Settings")
                }
        case .onDeviceLLMSettings:
            let _ = AppLog.shared.ui("Creating OnDeviceLLMSettingsView", level: .debug)
            OnDeviceLLMSettingsView()
                .onAppear {
                    AppLog.shared.ui("Navigated to On-Device LLM Settings")
                }
        }
    }

    // MARK: - Provider Configuration Cards

    private var awsBedrockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AWS Bedrock", systemImage: "cloud.fill")
                    .font(.headline)

                Spacer()

                Button("Configure") {
                    AppLog.shared.ui("AWS Bedrock Configure button tapped")
                    selectedRoute = .awsBedrockSettings
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
                    AppLog.shared.ui("OpenAI Compatible Configure button tapped")
                    selectedRoute = .openAICompatibleSettings
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

    private var onDeviceLLMCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("On-Device LLM", systemImage: "iphone")
                    .font(.headline)

                Spacer()

                Button("Configure") {
                    AppLog.shared.ui("On-Device LLM Configure button tapped")
                    selectedRoute = .onDeviceLLMSettings
                }
                .buttonStyle(.bordered)
            }

            Text("Run AI models directly on your device. No internet required after downloading a model.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Show model status
            if MLXModelInfo.isEnabled {
                let selectedModel = MLXModelInfo.selectedModel
                HStack {
                    if MLXModelDownloadManager.shared.isModelDownloaded(selectedModel) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready: \(selectedModel.displayName)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.orange)
                        Text("Model not downloaded")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
            }
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
                case .bedrock:
                    awsBedrockCard
                case .openAICompatible:
                    openAICompatibleCard
                case .onDeviceLLM:
                    onDeviceLLMCard
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data Extraction Section

    private var dataExtractionSection: some View {
        Section("Data Extraction") {
            VStack(spacing: 16) {
                Text("Configure AI model for extracting structured data from documents (blood tests, etc.)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Extraction Provider", selection: $settingsManager.modelPreferences.extractionProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                // Show model selection based on extraction provider
                switch settingsManager.modelPreferences.extractionProvider {
                case .bedrock:
                    extractionBedrockModelPicker
                case .openAICompatible:
                    extractionOpenAIModelPicker
                case .onDeviceLLM:
                    extractionOnDeviceLLMInfo
                }

                // Cloud vision extraction (only meaningful for cloud providers)
                if settingsManager.modelPreferences.extractionProvider != .onDeviceLLM {
                    cloudVisionExtractionControls
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Cloud Vision Extraction Controls

    private var cloudVisionExtractionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Toggle("Send page images for higher accuracy", isOn: $settingsManager.modelPreferences.cloudVisionExtractionEnabled)
                .accessibilityLabel("Send document page images to the cloud AI for higher extraction accuracy")
                .accessibilityHint("When enabled, images of your documents are sent to the configured cloud provider during extraction")
                .accessibilityIdentifier("cloudVisionExtractionToggle")

            Text("Sends images of your document pages to the configured cloud AI provider so the model can read the original document directly, bypassing OCR errors. Images leave your device only during extraction and only when this is on.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if settingsManager.modelPreferences.extractionProvider == .openAICompatible {
                Toggle("Model supports image input", isOn: $settingsManager.modelPreferences.openAIVisionCapable)
                    .accessibilityLabel("The configured OpenAI-compatible model supports image input")
                    .accessibilityHint("Enable only if your server's model accepts images; capability cannot be detected automatically")
                    .accessibilityIdentifier("openAIVisionCapableToggle")

                Text("Enable only if the selected model on your server accepts images (e.g. a vision-language model). This can't be detected automatically.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Extraction Model Pickers

    private var extractionOnDeviceLLMInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("On-Device Model")
                    .foregroundColor(.secondary)
                Spacer()
            }

            let selectedModel = MLXModelInfo.selectedModel
            if MLXModelDownloadManager.shared.isModelDownloaded(selectedModel) {
                Text("Using: \(selectedModel.displayName)")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("No model downloaded. Configure On-Device LLM in AI Provider settings.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text("On-device extraction uses the same model as chat. Good for privacy-sensitive documents.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var extractionBedrockModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bedrock Model")
                    .foregroundColor(.secondary)
                Spacer()
            }

            Picker("Model", selection: $settingsManager.modelPreferences.extractionBedrockModel) {
                ForEach(AWSBedrockModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var extractionOpenAIModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OpenAI-Compatible Model")
                    .foregroundColor(.secondary)
                Spacer()
            }

            TextField("Model name (e.g., gpt-4o-mini)", text: $settingsManager.modelPreferences.extractionOpenAIModel)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Text("Enter the model name from your OpenAI-compatible server. Recommended: Fast, cheap models.")
                .font(.caption2)
                .foregroundColor(.secondary)
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

            Button {
                exportLogs()
            } label: {
                Label("Export Diagnostic Logs", systemImage: "doc.text.magnifyingglass")
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
                    
                    TextField("localhost", text: config.hostname, onEditingChanged: { isEditing in
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

        // Note: Connection status is now reset only when hostname/port actually change
        // (handled in the TextField onChange handlers in serverConfigCard)
        // This prevents the status from being reset after a successful connection test
    }
    
    private func validateConfiguration() {
        // Validation is now handled inline in the UI, so this function
        // can be simplified or used for other validation logic
        // The real-time validation happens in the UI components themselves

        // Note: Connection status is now reset only when hostname/port actually change
        // (handled in the TextField onChange handlers in serverConfigCard)
    }
    
    private func performReset() {
        guard let resetType = resetType else { return }
        
        switch resetType {
        case .servers:
            settingsManager.resetServerSettings()
            successMessage = "Server settings have been reset to defaults"
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

    private func exportLogs() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        LogExporter.exportLogs(from: rootVC)
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
