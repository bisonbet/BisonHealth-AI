import SwiftUI

// MARK: - OpenAI Compatible Settings View
struct OpenAICompatibleSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL: String
    @State private var apiKey: String
    @State private var selectedModel: String
    @AppStorage("openAICompatibleTemperature") private var temperature: Double = 0.1
    @AppStorage("openAICompatibleMaxTokens") private var maxTokens: Int = 2048
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false

    init(settingsManager: SettingsManager) {
        print("🟢 OpenAICompatibleSettingsView.init called")
        self.settingsManager = settingsManager
        _baseURL = State(initialValue: settingsManager.openAICompatibleBaseURL)
        _apiKey = State(initialValue: settingsManager.openAICompatibleAPIKey)
        _selectedModel = State(initialValue: settingsManager.modelPreferences.openAICompatibleModel)
    }

    var body: some View {
        Form {
            // Server Configuration Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL")
                        .font(.headline)

                    TextField("http://localhost:4000", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onChange(of: baseURL) { _, newValue in
                            print("💾 Auto-saving baseURL: '\(newValue)'")
                            settingsManager.openAICompatibleBaseURL = newValue
                            settingsManager.invalidateOpenAICompatibleClient()
                            settingsManager.saveSettings()
                            settingsManager.openAICompatibleStatus = .unknown
                        }

                    Text("Enter the base URL of your OpenAI-compatible server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key (Optional)")
                        .font(.headline)

                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: apiKey) { _, newValue in
                            print("💾 Auto-saving apiKey: '\(newValue.isEmpty ? "(empty)" : "(has \(newValue.count) chars)")'")
                            settingsManager.openAICompatibleAPIKey = newValue
                            settingsManager.invalidateOpenAICompatibleClient()
                            settingsManager.saveSettings()
                            settingsManager.openAICompatibleStatus = .unknown
                        }

                    Text("Leave blank if your server doesn't require authentication")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Server Configuration")
            }

            // Connection Test Section
            Section {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "network")
                                .padding(.trailing, 8)
                        }
                        Text(isTesting ? "Testing Connection..." : "Test Connection")
                    }
                }
                .disabled(isTesting || baseURL.isEmpty)

                if let result = testResult {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                        Text(result.message)
                            .font(.caption)
                    }
                }

                // Connection Status
                HStack {
                    Text("Status")
                    Spacer()
                    ConnectionStatusBadge(status: settingsManager.openAICompatibleStatus)
                }

                HStack {
                    Text("Selected Model")
                    Spacer()
                    Text(selectedModel.isEmpty ? "Not selected" : selectedModel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Connection")
            }

            // Available Models Section
            if isLoadingModels || !availableModels.isEmpty {
                Section {
                    if isLoadingModels {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        if availableModels.isEmpty {
                            Text("Run a connection test to load available models from the server.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(availableModels, id: \.self) { model in
                                Button {
                                    selectedModel = model
                                    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                                    print("💾 Auto-saving selected model: '\(normalizedModel)'")
                                    settingsManager.updateOpenAICompatibleModel(normalizedModel)
                                    settingsManager.invalidateOpenAICompatibleClient()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedModel == model ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedModel == model ? .accentColor : .secondary)
                                        Image(systemName: "cpu")
                                            .foregroundColor(.blue)
                                        Text(model)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedModel == model {
                                            Text("Selected")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            if selectedModel.isEmpty {
                                Text("Tap a model above to select it.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            } else if !availableModels.contains(selectedModel) {
                                Text("The previously selected model is not available on this server.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.top, 4)
                            }
                        }
                    }
                } header: {
                    Text("Available Models (\(availableModels.count))")
                }
            }

            // Advanced Settings Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $temperature, in: 0.0...1.0, step: 0.1)

                    Text("Controls randomness in responses. Lower values (0.1) are more focused and deterministic, higher values (0.9) are more creative and varied.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens")
                            .font(.headline)
                        Spacer()
                        Text("\(maxTokens)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: Binding(
                        get: { Double(maxTokens) },
                        set: { maxTokens = Int($0) }
                    ), in: 512...8192, step: 256)

                    Text("Maximum number of tokens in the response. Higher values allow for longer responses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Advanced Settings")
            }

        }
        .navigationTitle("OpenAI Compatible")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func testConnection() {
        isTesting = true
        testResult = nil
        settingsManager.openAICompatibleStatus = .testing

        Task {
            do {
                let client = OpenAICompatibleClient(
                    baseURL: baseURL,
                    apiKey: apiKey.isEmpty ? nil : apiKey,
                    defaultModel: selectedModel.isEmpty ? nil : selectedModel
                )

                let connected = try await client.testConnection()

                if connected {
                    // Try to load models
                    isLoadingModels = true
                    let models = try await client.listModels().sorted()
                    availableModels = models
                    isLoadingModels = false

                    if let firstModel = models.first,
                       (selectedModel.isEmpty || !models.contains(selectedModel)) {
                        selectedModel = firstModel
                    }

                    settingsManager.openAICompatibleStatus = .connected
                    testResult = TestResult(
                        success: true,
                        message: "Connected successfully! Found \(models.count) models."
                    )
                } else {
                    availableModels = []
                    settingsManager.openAICompatibleStatus = .failed("Connection failed")
                    testResult = TestResult(
                        success: false,
                        message: "Connection failed"
                    )
                }
            } catch {
                settingsManager.openAICompatibleStatus = .failed(error.localizedDescription)
                testResult = TestResult(
                    success: false,
                    message: "Error: \(error.localizedDescription)"
                )
                isLoadingModels = false
                availableModels = []
            }

            isTesting = false
        }
    }

    // MARK: - Supporting Types

    struct TestResult {
        let success: Bool
        let message: String
    }
}

// MARK: - Example Server Row
struct ExampleServer: View {
    let name: String
    let url: String
    let description: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontDesign(.monospaced)
                }

                Spacer()

                Button("Use") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Connection Status Badge
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
    }

    var statusColor: Color {
        status.color
    }

    var statusText: String {
        status.displayText
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        OpenAICompatibleSettingsView(settingsManager: SettingsManager.shared)
    }
}
