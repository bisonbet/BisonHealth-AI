import SwiftUI

// MARK: - MLX Settings View

struct MLXSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @StateObject private var mlxClient = MLXClient.shared
    @State private var showingAdvancedSettings = false
    @State private var isLoadingModel = false
    @State private var loadError: String?
    @State private var generationConfig: MLXGenerationConfig = .default

    var body: some View {
        Form {
            // Status Section
            statusSection

            // Chat Model Selection Section
            chatModelSelectionSection

            // Document Processing Section
            documentProcessingSection

            // Generation Parameters Section
            generationParametersSection
        }
        .navigationTitle("MLX Settings")
        .alert("Model Load Error", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .onAppear {
            loadCurrentConfiguration()
            mlxClient.scanDownloadedModels()
        }
    }

    // MARK: - Computed Properties
    
    private var chatModels: [MLXModelConfig] {
        MLXModelRegistry.availableModels.filter { $0.modelType == .textOnly }
    }
    
    private var documentModels: [MLXModelConfig] {
        MLXModelRegistry.availableModels.filter { $0.modelType == .vision }
    }
    
    private var isDeviceCapableOfLocalDocling: Bool {
        // Require at least 4GB RAM for VLM + App overhead
        DeviceMemory.getTotalMemoryGB() >= 4.0
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section(header: Text("Status")) {
            MLXStatusRow()

            HStack {
                Text("Active Chat Model")
                Spacer()
                if let modelId = settingsManager.modelPreferences.mlxModelId,
                   let model = MLXModelRegistry.model(withId: modelId) {
                    Text(model.name)
                        .foregroundColor(.secondary)
                } else {
                    Text("None")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Chat Model Selection Section

    private var chatModelSelectionSection: some View {
        Section(header: HStack {
            Text("Chat Models")
            Spacer()
            Button(action: {
                mlxClient.scanDownloadedModels()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.caption)
            }
        }) {
            if isLoadingModel {
                HStack {
                    ProgressView()
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(chatModels) { model in
                let isDownloaded = mlxClient.downloadedModelIds.contains(model.id)

                ModelRow(
                    model: model,
                    isSelected: settingsManager.modelPreferences.mlxModelId == model.id,
                    isDownloaded: isDownloaded,
                    isLoading: isLoadingModel,
                    onSelect: {
                        selectAndLoadModel(model)
                    },
                    onDelete: isDownloaded ? {
                        deleteModel(model)
                    } : nil
                )
            }
        }
    }
    
    // MARK: - Document Processing Section
    
    private var documentProcessingSection: some View {
        Section(header: Text("Document Processing")) {
            // Mode Selection
            Picker("Processing Mode", selection: Binding(
                get: { settingsManager.modelPreferences.useLocalDocling },
                set: { newValue in
                    settingsManager.modelPreferences.useLocalDocling = newValue
                    settingsManager.saveSettings()
                }
            )) {
                Text("Remote Server").tag(false)
                if isDeviceCapableOfLocalDocling {
                    Text("Local On-Device (MLX)").tag(true)
                }
            }
            .onChange(of: settingsManager.modelPreferences.useLocalDocling) { oldValue, newValue in
                 if newValue && !isDeviceCapableOfLocalDocling {
                     // Force back to false if hacked/state mismatch
                     settingsManager.modelPreferences.useLocalDocling = false
                     settingsManager.saveSettings()
                 }
            }
            
            // Capability Warning
            if !isDeviceCapableOfLocalDocling {
                 Text("⚠️ Local processing requires at least 4GB RAM.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Local Model Management (Only show if Local is selected or for management)
            // We show it if Local is selected so user can download it.
            if settingsManager.modelPreferences.useLocalDocling {
                ForEach(documentModels) { model in
                    let isDownloaded = mlxClient.downloadedModelIds.contains(model.id)
                    
                    ModelRow(
                        model: model,
                        isSelected: isDownloaded, // Mark as selected if downloaded since it's the only option
                        isDownloaded: isDownloaded,
                        isLoading: isLoadingModel,
                        onSelect: {
                            // Just load/download, don't set as chat model
                            selectAndLoadModel(model)
                        },
                        onDelete: isDownloaded ? {
                            deleteModel(model)
                        } : nil
                    )
                }
                
                Text("Uses 'Granite Docling' vision model for local OCR and table extraction.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Generation Parameters Section

    private var generationParametersSection: some View {
        Section(header: Text("Generation Parameters")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", generationConfig.temperature))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $generationConfig.temperature,
                    in: 0.0...2.0,
                    step: 0.1,
                    onEditingChanged: { _ in updateMLXConfig() }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", generationConfig.topP))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $generationConfig.topP,
                    in: 0.0...1.0,
                    step: 0.05,
                    onEditingChanged: { _ in updateMLXConfig() }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(generationConfig.maxTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(generationConfig.maxTokens) },
                        set: { generationConfig.maxTokens = Int($0) }
                    ),
                    in: 512...4096,
                    step: 128,
                    onEditingChanged: { _ in updateMLXConfig() }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Context Window")
                    Spacer()
                    Text("\(generationConfig.contextWindow / 1024)K")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(generationConfig.contextWindow) },
                        set: { generationConfig.contextWindow = Int($0) }
                    ),
                    in: 2048...32768,
                    step: 1024,
                    onEditingChanged: { _ in updateMLXConfig() }
                )
                Text("Maximum context length for the model")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Repetition Penalty")
                    Spacer()
                    Text(String(format: "%.1f", generationConfig.repetitionPenalty))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $generationConfig.repetitionPenalty,
                    in: 1.0...2.0,
                    step: 0.1,
                    onEditingChanged: { _ in updateMLXConfig() }
                )
                Text("Higher values reduce repetition")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Private Methods

    private func selectAndLoadModel(_ model: MLXModelConfig) {
        guard !isLoadingModel else { return }

        // Only update chat model preference if it's a text model
        // Docling models are managed separately via useLocalDocling flag
        if model.modelType == .textOnly {
            settingsManager.modelPreferences.mlxModelId = model.id
            settingsManager.saveSettings()
        }

        // Load model (MLX will download if needed)
        isLoadingModel = true
        loadError = nil

        Task {
            do {
                try await mlxClient.loadModel(modelId: model.id)
                await MainActor.run {
                    isLoadingModel = false
                }
            } catch {
                await MainActor.run {
                    isLoadingModel = false
                    loadError = "Failed to load model: \(error.localizedDescription)"
                }
            }
        }
    }

    private func updateMLXConfig() {
        mlxClient.setGenerationConfig(generationConfig)

        // Persist to SettingsManager
        settingsManager.mlxGenerationConfig = generationConfig
        settingsManager.saveSettings()
    }

    private func loadCurrentConfiguration() {
        // Load from SettingsManager
        generationConfig = settingsManager.mlxGenerationConfig

        // Also update the MLX client
        mlxClient.setGenerationConfig(generationConfig)
    }

    private func deleteModel(_ model: MLXModelConfig) {
        Task {
            do {
                try await mlxClient.deleteModel(modelId: model.id)

                // If this was the selected model, clear the selection
                if settingsManager.modelPreferences.mlxModelId == model.id {
                    settingsManager.modelPreferences.mlxModelId = nil
                    settingsManager.saveSettings()
                }
            } catch {
                loadError = "Failed to delete model: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: MLXModelConfig
    let isSelected: Bool
    let isDownloaded: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.name)
                                .font(.headline)
                                .foregroundColor(.primary)

                            if isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        Text(model.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if model.recommended {
                                Text("Recommended")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }

                            Text(model.formattedSize)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if let specialization = model.specialization {
                                Text(specialization)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .disabled(isLoading)
            .opacity(isLoading && !isSelected ? 0.5 : 1.0)

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .padding(.leading, 12)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - MLX Status Row

struct MLXStatusRow: View {
    var body: some View {
        HStack {
            Text("MLX Status")
            Spacer()
            Text("Ready")
                .foregroundColor(.green)
        }
    }
}

#if DEBUG
struct MLXSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MLXSettingsView(settingsManager: .shared)
        }
    }
}
#endif

// MARK: - Docling Local Settings View

struct DoclingLocalSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @StateObject private var mlxClient = MLXClient.shared
    @State private var isLoadingModel = false
    @State private var loadError: String?
    
    var body: some View {
        Form {
            Section(header: Text("Document Analysis Model (OCR)")) {
                
                if !isDeviceCapableOfLocalDocling {
                     Text("⚠️ Device memory insufficient for local processing. At least 4GB RAM required.")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                ForEach(documentModels) { model in
                    let isDownloaded = mlxClient.downloadedModelIds.contains(model.id)
                    
                    ModelRow(
                        model: model,
                        isSelected: isDownloaded, // Mark as selected if downloaded
                        isDownloaded: isDownloaded,
                        isLoading: isLoadingModel,
                        onSelect: {
                            selectAndLoadModel(model)
                        },
                        onDelete: isDownloaded ? {
                            deleteModel(model)
                        } : nil
                    )
                }
                
                Text("Uses 'Granite Docling' vision model for local OCR and table extraction.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Data Extraction Model (Reasoning)")) {
                Text("Select a model to interpret the extracted text and convert it to structured data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(extractionModels) { model in
                    let isDownloaded = mlxClient.downloadedModelIds.contains(model.id)
                    let isSelected = settingsManager.modelPreferences.extractionModelId == model.id
                    
                    ModelRow(
                        model: model,
                        isSelected: isSelected,
                        isDownloaded: isDownloaded,
                        isLoading: isLoadingModel,
                        onSelect: {
                            selectAndLoadModel(model)
                        },
                        onDelete: isDownloaded ? {
                            deleteModel(model)
                        } : nil
                    )
                }
            }
        }
        .navigationTitle("Local Docling Settings")
        .alert("Model Load Error", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .onAppear {
            mlxClient.scanDownloadedModels()
            // Set default extraction model if not set
            if settingsManager.modelPreferences.extractionModelId == nil {
                // Default to Granite 1B if available, else first text model
                if let defaultModel = extractionModels.first(where: { $0.id.contains("granite") }) ?? extractionModels.first {
                    settingsManager.modelPreferences.extractionModelId = defaultModel.id
                    settingsManager.saveSettings()
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var documentModels: [MLXModelConfig] {
        MLXModelRegistry.availableModels.filter { $0.modelType == .vision }
    }
    
    private var extractionModels: [MLXModelConfig] {
        MLXModelRegistry.availableModels.filter { $0.modelType == .textOnly }
    }
    
    private var isDeviceCapableOfLocalDocling: Bool {
        DeviceMemory.getTotalMemoryGB() >= 4.0
    }
    
    private func selectAndLoadModel(_ model: MLXModelConfig) {
        guard !isLoadingModel else { return }
        
        // Update preference based on type
        if model.modelType == .textOnly {
             settingsManager.modelPreferences.extractionModelId = model.id
             settingsManager.saveSettings()
        }
        
        isLoadingModel = true
        loadError = nil
        
        Task {
            do {
                try await mlxClient.loadModel(modelId: model.id)
                await MainActor.run {
                    isLoadingModel = false
                }
            } catch {
                await MainActor.run {
                    isLoadingModel = false
                    loadError = "Failed to load model: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteModel(_ model: MLXModelConfig) {
        Task {
            do {
                try await mlxClient.deleteModel(modelId: model.id)
            } catch {
                loadError = "Failed to delete model: \(error.localizedDescription)"
            }
        }
    }
}
