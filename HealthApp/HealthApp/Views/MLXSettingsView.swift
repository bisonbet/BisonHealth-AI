import SwiftUI

// MARK: - MLX Settings View

struct MLXSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var modelManager = MLXModelManager.shared
    @State private var showingModelDownloadSheet = false
    @State private var selectedModelForDownload: MLXModelConfig?
    @State private var showingAdvancedSettings = false

    var body: some View {
        Form {
            // Status Section
            statusSection

            // Active Model Section
            activeModelSection

            // Available Models Section
            availableModelsSection

            // Downloaded Models Section
            if !modelManager.downloadedModels.isEmpty {
                downloadedModelsSection
            }

            // Generation Parameters Section
            generationParametersSection

            // Storage Info Section
            storageInfoSection
        }
        .navigationTitle("MLX Settings")
        .sheet(isPresented: $showingModelDownloadSheet) {
            if let model = selectedModelForDownload {
                ModelDownloadView(
                    model: model,
                    modelManager: modelManager,
                    isPresented: $showingModelDownloadSheet
                )
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                Text("MLX Status")
                Spacer()
                // GPU availability check will be determined at runtime by MLXClient
                let mlxClient = MLXClient.shared
                if mlxClient.isConnected {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityLabel("MLX is ready")
                } else {
                    Label("Not Ready", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityLabel("MLX not ready - download a model to get started")
                }
            }

            HStack {
                Text("Active Model")
                Spacer()
                if let modelId = settingsManager.modelPreferences.mlxModelId,
                   let model = modelManager.getLocalModel(modelId) {
                    Text(model.config.name)
                        .foregroundColor(.secondary)
                } else {
                    Text("None")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Active Model Section

    private var activeModelSection: some View {
        Section(header: Text("Active Model")) {
            if settingsManager.modelPreferences.mlxModelId == nil {
                Text("No model selected. Download a model to get started.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(modelManager.downloadedModels) { localModel in
                    ModelSelectionRow(
                        model: localModel,
                        isSelected: settingsManager.modelPreferences.mlxModelId == localModel.id,
                        onSelect: {
                            settingsManager.modelPreferences.mlxModelId = localModel.id
                            settingsManager.saveSettings()
                            settingsManager.invalidateMLXClient()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Available Models Section

    private var availableModelsSection: some View {
        Section(header: Text("Available for Download")) {
            ForEach(MLXModelRegistry.availableModels) { modelConfig in
                if !modelManager.isModelDownloaded(modelConfig.id) {
                    AvailableModelRow(
                        model: modelConfig,
                        onDownload: {
                            selectedModelForDownload = modelConfig
                            showingModelDownloadSheet = true
                        }
                    )
                }
            }
        }
    }

    // MARK: - Downloaded Models Section

    private var downloadedModelsSection: some View {
        Section(header: Text("Downloaded Models")) {
            ForEach(modelManager.downloadedModels) { localModel in
                DownloadedModelRow(
                    model: localModel,
                    onDelete: {
                        Task {
                            try await modelManager.deleteModel(localModel.id)
                            if settingsManager.modelPreferences.mlxModelId == localModel.id {
                                settingsManager.modelPreferences.mlxModelId = nil
                                settingsManager.saveSettings()
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Generation Parameters Section

    private var generationParametersSection: some View {
        Section(header: Text("Generation Parameters")) {
            // Temperature
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settingsManager.mlxGenerationConfig.temperature))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settingsManager.mlxGenerationConfig.temperature },
                        set: { newValue in
                            settingsManager.mlxGenerationConfig.temperature = newValue
                            settingsManager.saveSettings()
                        }
                    ),
                    in: 0.0...2.0,
                    step: 0.05
                )
                Text("Higher values make output more creative, lower values more focused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Temperature: \(String(format: "%.2f", settingsManager.mlxGenerationConfig.temperature))")
            .accessibilityHint("Adjust creativity of responses")

            // Top-P
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top-P (Nucleus Sampling)")
                    Spacer()
                    Text(String(format: "%.2f", settingsManager.mlxGenerationConfig.topP))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settingsManager.mlxGenerationConfig.topP },
                        set: { newValue in
                            settingsManager.mlxGenerationConfig.topP = newValue
                            settingsManager.saveSettings()
                        }
                    ),
                    in: 0.0...1.0,
                    step: 0.05
                )
                Text("Controls diversity by only sampling from top probability tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Max Tokens
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(settingsManager.mlxGenerationConfig.maxTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.mlxGenerationConfig.maxTokens) },
                        set: { newValue in
                            settingsManager.mlxGenerationConfig.maxTokens = Int(newValue)
                            settingsManager.saveSettings()
                        }
                    ),
                    in: 256...4096,
                    step: 256
                )
                Text("Maximum length of generated response")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Repetition Penalty
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Repetition Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settingsManager.mlxGenerationConfig.repetitionPenalty))
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settingsManager.mlxGenerationConfig.repetitionPenalty },
                        set: { newValue in
                            settingsManager.mlxGenerationConfig.repetitionPenalty = newValue
                            settingsManager.saveSettings()
                        }
                    ),
                    in: 1.0...2.0,
                    step: 0.1
                )
                Text("Penalizes repeated tokens to reduce repetition")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Preset Buttons
            HStack(spacing: 12) {
                Button("Precise") {
                    settingsManager.mlxGenerationConfig = .precise
                    settingsManager.saveSettings()
                }
                .buttonStyle(.bordered)

                Button("Default") {
                    settingsManager.mlxGenerationConfig = .default
                    settingsManager.saveSettings()
                }
                .buttonStyle(.bordered)

                Button("Creative") {
                    settingsManager.mlxGenerationConfig = .creative
                    settingsManager.saveSettings()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Storage Info Section

    private var storageInfoSection: some View {
        Section(header: Text("Storage")) {
            HStack {
                Text("Total Used")
                Spacer()
                Text(formatBytes(modelManager.getTotalStorageUsed()))
                    .foregroundColor(.secondary)
            }

            if let available = modelManager.getAvailableDiskSpace() {
                HStack {
                    Text("Available")
                    Spacer()
                    Text(formatBytes(available))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Model Selection Row

struct ModelSelectionRow: View {
    let model: MLXLocalModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.config.name)
                        .font(.headline)
                    Text(model.config.huggingFaceRepo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .accessibilityLabel("\(model.config.name), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Tap to select this model for chat")
    }
}

// MARK: - Available Model Row

struct AvailableModelRow: View {
    let model: MLXModelConfig
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name)
                            .font(.headline)
                        if model.recommended {
                            Text("Recommended")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Label(model.formattedSize, systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let specialization = model.specialization {
                            Label(specialization, systemImage: "sparkles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name), \(model.description), Size: \(model.formattedSize)")
        .accessibilityHint("Tap download button to download this model")
    }
}

// MARK: - Downloaded Model Row

struct DownloadedModelRow: View {
    let model: MLXLocalModel
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.config.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(model.config.formattedSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastUsed = model.lastUsed {
                        Label(
                            "Used \(lastUsed.formatted(.relative(presentation: .named)))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .alert("Delete Model?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove \(model.config.name) from your device. You can download it again later if needed.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.config.name), \(model.config.formattedSize)")
        .accessibilityHint("Double tap delete button to remove this model")
    }
}

// MARK: - Model Download View

struct ModelDownloadView: View {
    let model: MLXModelConfig
    @ObservedObject var modelManager: MLXModelManager
    @Binding var isPresented: Bool
    @State private var isDownloading = false
    @State private var downloadError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Model Info
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: horizontalSizeClass == .regular ? 80 : 60))
                        .foregroundColor(.blue)

                    Text(model.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(model.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Model Details
                    VStack(spacing: 8) {
                        InfoRow(label: "Size", value: model.formattedSize)
                        InfoRow(label: "Quantization", value: model.quantization)
                        InfoRow(label: "Context Window", value: "\(model.contextWindow) tokens")

                        if let specialization = model.specialization {
                            InfoRow(label: "Specialization", value: specialization)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer()

                // Download Progress
                if let (currentModelId, progress) = modelManager.currentDownload,
                   currentModelId == model.id {
                    VStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)

                        Text("Downloading: \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Cancel") {
                            modelManager.cancelDownload(model.id)
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }

                // Error Message
                if let error = downloadError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                // Download Button
                if !isDownloading {
                    Button(action: startDownload) {
                        Label("Download Model", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Download \(model.name)")
                }
            }
            .padding()
            .frame(maxWidth: horizontalSizeClass == .regular ? 600 : .infinity)  // Constrain width on iPad
            .frame(maxWidth: .infinity)  // Center the constrained content
            .navigationTitle("Download Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func startDownload() {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                try await modelManager.downloadModel(model)
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MLXSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MLXSettingsView(settingsManager: .shared)
        }
    }
}
#endif
