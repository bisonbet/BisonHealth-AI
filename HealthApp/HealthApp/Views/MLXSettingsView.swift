import SwiftUI

// MARK: - MLX Settings View

struct MLXSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var showingAdvancedSettings = false
    @State private var isLoadingModel = false
    @State private var loadError: String?
    @State private var generationConfig: MLXGenerationConfig = .default

    var body: some View {
        Form {
            // Status Section
            statusSection

            // Model Selection Section
            modelSelectionSection

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
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section(header: Text("Status")) {
            MLXStatusRow()

            HStack {
                Text("Active Model")
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

    // MARK: - Model Selection Section

    private var modelSelectionSection: some View {
        Section(header: Text("Select Model")) {
            if isLoadingModel {
                HStack {
                    ProgressView()
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(MLXModelRegistry.availableModels) { model in
                let mlxClient = settingsManager.getMLXClient()
                let isDownloaded = mlxClient.isModelDownloaded(modelId: model.id)

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

        // Update selection
        settingsManager.modelPreferences.mlxModelId = model.id
        settingsManager.saveSettings()

        // Load model (MLX will download if needed)
        // Get client BEFORE invalidating to keep the same instance
        let client = settingsManager.getMLXClient()

        isLoadingModel = true
        loadError = nil

        Task {
            do {
                try await client.loadModel(modelId: model.id)
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
        let client = settingsManager.getMLXClient()
        client.setGenerationConfig(generationConfig)

        // Persist to SettingsManager
        settingsManager.mlxGenerationConfig = generationConfig
        settingsManager.saveSettings()
    }

    private func loadCurrentConfiguration() {
        // Load from SettingsManager
        generationConfig = settingsManager.mlxGenerationConfig

        // Also update the MLX client
        let client = settingsManager.getMLXClient()
        client.setGenerationConfig(generationConfig)
    }

    private func deleteModel(_ model: MLXModelConfig) {
        Task {
            do {
                let client = settingsManager.getMLXClient()
                try await client.deleteModel(modelId: model.id)

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
