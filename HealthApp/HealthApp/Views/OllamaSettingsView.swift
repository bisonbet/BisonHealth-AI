import SwiftUI

// MARK: - Ollama Settings View
struct OllamaSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var hostname: String = ""
    @State private var port: String = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            serverConfigurationSection
            modelSelectionSection
            contextSizeSection
            testConnectionSection
        }
        .navigationTitle("Ollama Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.headline)
            }
        }
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Server Configuration Section

    private var serverConfigurationSection: some View {
        Section("Server Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hostname")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField(ServerConfigurationConstants.defaultOllamaHostname, text: $hostname)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: hostname) { _, newValue in
                            saveHostname(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("11434", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .onChange(of: port) { _, newValue in
                            savePort(newValue)
                        }

                    if let portNum = Int(port), (portNum < 1 || portNum > 65535) {
                        Text("Port must be between 1 and 65535")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                Text("Enter the hostname and port of your Ollama server. Default is localhost:11434")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Model Selection Section

    private var modelSelectionSection: some View {
        Section("Model Selection") {
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

                    if chatModels.isEmpty && !settingsManager.modelSelection.isLoading {
                        Text("No models available. Connect to Ollama server and refresh models.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.vertical, 8)
                    } else {
                        Picker("Chat Model", selection: $settingsManager.modelPreferences.chatModel) {
                            ForEach(chatModels, id: \.id) { model in
                                Text(model.displayName)
                                    .tag(model.name)
                            }
                            // Add currently selected model if it's not in the available list
                            if !chatModels.contains(where: { $0.name == settingsManager.modelPreferences.chatModel }) &&
                               !settingsManager.modelPreferences.chatModel.isEmpty {
                                Text("\(settingsManager.modelPreferences.chatModel) (not available)")
                                    .tag(settingsManager.modelPreferences.chatModel)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("Used for health conversations. Vision models (👁️) can also handle images and documents in chat.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Document processing model selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Document Processing Model")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if documentModels.isEmpty && !settingsManager.modelSelection.isLoading {
                        Text("No vision models available. Connect to Ollama server and refresh models.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.vertical, 8)
                    } else {
                        Picker("Document Model", selection: $settingsManager.modelPreferences.documentModel) {
                            ForEach(documentModels, id: \.id) { model in
                                Text(model.displayName)
                                    .tag(model.name)
                            }
                            // Add currently selected model if it's not in the available list
                            if !documentModels.contains(where: { $0.name == settingsManager.modelPreferences.documentModel }) &&
                               !settingsManager.modelPreferences.documentModel.isEmpty {
                                Text("\(settingsManager.modelPreferences.documentModel) (not available)")
                                    .tag(settingsManager.modelPreferences.documentModel)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("Used for processing medical documents with OCR and image analysis. Requires vision-capable models.")
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
                            // Add currently selected model if it's not in the available list
                            if !visionModels.contains(where: { $0.name == settingsManager.modelPreferences.visionModel }) &&
                               !settingsManager.modelPreferences.visionModel.isEmpty {
                                Text("\(settingsManager.modelPreferences.visionModel) (not available)")
                                    .tag(settingsManager.modelPreferences.visionModel)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Used for analyzing images, photos, and complex visual documents that require OCR")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Context Size Section
    
    private var contextSizeSection: some View {
        Section("Context Size") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Maximum context size for AI conversations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Context size options: 4k, 8k, 16k, 32k, 64k
                let contextSizes: [(value: Int, label: String)] = [
                    (4096, "4k"),
                    (8192, "8k"),
                    (16384, "16k"),
                    (32768, "32k"),
                    (65536, "64k")
                ]
                
                Picker("Context Size", selection: Binding(
                    get: { settingsManager.modelPreferences.contextSizeLimit },
                    set: { newValue in
                        settingsManager.modelPreferences.contextSizeLimit = newValue
                        settingsManager.saveSettings()
                    }
                )) {
                    ForEach(contextSizes, id: \.value) { size in
                        Text("\(size.label) (\(size.value) tokens)").tag(size.value)
                    }
                }
                .pickerStyle(.menu)
                
                Text("Larger context sizes allow the AI to see more of your health data and documents, but require more memory. Default is 16k.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Test Connection Section

    private var testConnectionSection: some View {
        Section("Connection Test") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: settingsManager.ollamaStatus.systemImage)
                        .foregroundColor(settingsManager.ollamaStatus.color)

                    Text(settingsManager.ollamaStatus.displayText)
                        .font(.caption)
                        .foregroundColor(settingsManager.ollamaStatus.color)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(settingsManager.ollamaStatus.color.opacity(0.1))
                .cornerRadius(8)

                Button(action: testConnection) {
                    HStack {
                        if settingsManager.ollamaStatus == .testing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(settingsManager.ollamaStatus == .testing ? "Testing..." : "Test Connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(settingsManager.ollamaStatus == .testing)
            }
        }
    }

    // MARK: - Helper Computed Properties

    private var chatModels: [OllamaModel] {
        let textModels = settingsManager.modelSelection.availableModels.filter { !$0.supportsVision }
        let visionModels = settingsManager.modelSelection.availableModels.filter { $0.supportsVision }
        return textModels + visionModels
    }

    private var visionModels: [OllamaModel] {
        settingsManager.modelSelection.availableModels.filter { $0.supportsVision }
    }

    private var documentModels: [OllamaModel] {
        // Document processing requires vision models for OCR and image analysis
        settingsManager.modelSelection.availableModels.filter { $0.supportsVision }
    }

    // MARK: - Helper Functions

    private func loadSettings() {
        hostname = settingsManager.ollamaConfig.hostname
        port = String(settingsManager.ollamaConfig.port)
    }

    private func saveHostname(_ newHostname: String) {
        var config = settingsManager.ollamaConfig
        config.hostname = newHostname
        settingsManager.ollamaConfig = config
        settingsManager.invalidateClients()
        settingsManager.saveSettings()
        settingsManager.ollamaStatus = .unknown
    }

    private func savePort(_ newPort: String) {
        guard let portNum = Int(newPort), portNum >= 1 && portNum <= 65535 else {
            return
        }
        var config = settingsManager.ollamaConfig
        config.port = portNum
        settingsManager.ollamaConfig = config
        settingsManager.invalidateClients()
        settingsManager.saveSettings()
        settingsManager.ollamaStatus = .unknown
    }

    private func testConnection() {
        Task {
            await settingsManager.testOllamaConnection()
        }
    }
}

#Preview {
    NavigationStack {
        OllamaSettingsView()
    }
}
