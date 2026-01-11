//
//  OnDeviceLLMSettingsView.swift
//  HealthApp
//
//  Settings view for on-device LLM configuration
//

import SwiftUI

// MARK: - On-Device LLM Settings View

struct OnDeviceLLMSettingsView: View {

    // MARK: - Properties

    @ObservedObject var downloadManager = OnDeviceLLMDownloadManager.shared
    @State private var isEnabled = OnDeviceLLMModelInfo.isEnabled
    @State private var selectedModelId = OnDeviceLLMModelInfo.selectedModel.id
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: OnDeviceLLMModelInfo?
    @State private var showAdvancedSettings = false

    // Sampling parameters
    @State private var temperature = OnDeviceLLMModelInfo.configuredTemperature
    @State private var topK = Int(OnDeviceLLMModelInfo.configuredTopK)
    @State private var topP = OnDeviceLLMModelInfo.configuredTopP
    @State private var repeatPenalty = OnDeviceLLMModelInfo.configuredRepeatPenalty
    @State private var contextSize = OnDeviceLLMModelInfo.configuredContextSize

    // MARK: - Body

    var body: some View {
        List {
            enableSection
            modelSelectionSection
            downloadSection
            advancedSettingsSection
            storageSection
        }
        .navigationTitle("On-Device LLM")
        .onAppear {
            refreshState()
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    downloadManager.deleteModel(model)
                    refreshState()
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Delete \(model.displayName)? This will free up \(model.downloadSize) of storage.")
            }
        }
        .accessibilityIdentifier("onDeviceLLMSettingsView")
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle("Enable On-Device LLM", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.enableOnDeviceLLM)
                    SettingsManager.shared.invalidateClients()
                }
                .accessibilityIdentifier("enableOnDeviceLLMToggle")
        } header: {
            Text("On-Device AI")
        } footer: {
            Text("Run AI models directly on your device. No internet required after downloading a model. Fully private - your data never leaves your device.")
        }
    }

    private var modelSelectionSection: some View {
        Section {
            ForEach(OnDeviceLLMModelInfo.allModels) { model in
                ModelRowView(
                    model: model,
                    isSelected: model.id == selectedModelId && model.isDownloaded,
                    onSelect: {
                        if model.isDownloaded {
                            selectModel(model)
                        }
                    },
                    onDownload: {
                        downloadManager.startDownload(for: model)
                    },
                    onDelete: {
                        modelToDelete = model
                        showDeleteConfirmation = true
                    }
                )
            }
        } header: {
            Text("Medical AI Models")
        } footer: {
            Text("These models are specifically trained for medical and clinical applications. MedGemma excels at clinical reasoning and radiology, while MediPhi is optimized for medical coding and documentation.")
        }
    }

    private var downloadSection: some View {
        Group {
            if downloadManager.isDownloading {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Downloading \(downloadManager.currentlyDownloadingModel?.displayName ?? "model")...")
                                .font(.headline)
                            Spacer()
                            Button("Cancel") {
                                downloadManager.cancelDownload()
                            }
                            .foregroundColor(.red)
                        }

                        ProgressView(value: downloadManager.downloadProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("\(formatSize(downloadManager.downloadedSize)) / \(formatSize(downloadManager.totalSize))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(downloadManager.formattedDownloadSpeed)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let timeRemaining = downloadManager.estimatedTimeRemaining {
                            Text(timeRemaining)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Download Progress")
                }
            }

            if let error = downloadManager.downloadError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Download Error")
                }
            }
        }
    }

    private var advancedSettingsSection: some View {
        Section {
            DisclosureGroup("Advanced Settings", isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 16) {
                    // Context Size (Primary setting for medical use)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Context Size")
                            Spacer()
                            Text("\(contextSize / 1024)K tokens")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(contextSize) },
                            set: { contextSize = Int($0) }
                        ), in: Double(OnDeviceLLMModelInfo.minContextSize)...Double(OnDeviceLLMModelInfo.maxContextSize), step: 1024)
                            .onChange(of: contextSize) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.contextSize)
                            }
                        Text("Default: 16K. Range: 4K-64K. Larger context allows more conversation history but uses more memory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Temperature
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $temperature, in: 0.0...1.0, step: 0.05)
                            .onChange(of: temperature) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.temperature)
                            }
                        Text("Medical models use low temperature (0.0-0.2) for accurate, consistent responses. Higher values increase creativity but may reduce accuracy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Top K
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Top K")
                            Spacer()
                            Text("\(topK)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(topK) },
                            set: { topK = Int($0) }
                        ), in: 1...100, step: 1)
                            .onChange(of: topK) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.topK)
                            }
                        Text("Number of top tokens to consider for sampling.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Top P
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Top P")
                            Spacer()
                            Text(String(format: "%.2f", topP))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $topP, in: 0.0...1.0, step: 0.05)
                            .onChange(of: topP) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.topP)
                            }
                        Text("Nucleus sampling threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Repeat Penalty
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Repeat Penalty")
                            Spacer()
                            Text(String(format: "%.2f", repeatPenalty))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $repeatPenalty, in: 1.0...2.0, step: 0.05)
                            .onChange(of: repeatPenalty) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: OnDeviceLLMModelInfo.SettingsKeys.repeatPenalty)
                            }
                        Text("Penalizes repetition in generated text.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Reset to Defaults
                    Button("Reset to Model Defaults") {
                        if let model = OnDeviceLLMModelInfo.model(withId: selectedModelId) {
                            OnDeviceLLMModelInfo.applyDefaultSettings(for: model)
                            refreshState()
                        }
                    }
                    .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var storageSection: some View {
        Section {
            HStack {
                Text("Models Directory")
                Spacer()
                Text(URL.onDeviceLLMModelsDirectory.lastPathComponent)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            let downloadedModels = downloadManager.downloadedModels
            if !downloadedModels.isEmpty {
                HStack {
                    Text("Downloaded Models")
                    Spacer()
                    Text("\(downloadedModels.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Total Storage Used")
                    Spacer()
                    Text(formatTotalStorage(downloadedModels))
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Storage")
        }
    }

    // MARK: - Helper Methods

    private func refreshState() {
        isEnabled = OnDeviceLLMModelInfo.isEnabled
        selectedModelId = OnDeviceLLMModelInfo.selectedModel.id
        temperature = OnDeviceLLMModelInfo.configuredTemperature
        topK = Int(OnDeviceLLMModelInfo.configuredTopK)
        topP = OnDeviceLLMModelInfo.configuredTopP
        repeatPenalty = OnDeviceLLMModelInfo.configuredRepeatPenalty
        contextSize = OnDeviceLLMModelInfo.configuredContextSize
        downloadManager.refreshModelStatus()
    }

    private func selectModel(_ model: OnDeviceLLMModelInfo) {
        selectedModelId = model.id
        UserDefaults.standard.set(model.id, forKey: OnDeviceLLMModelInfo.SettingsKeys.selectedModelId)
        downloadManager.selectModel(model)
        SettingsManager.shared.invalidateClients()
    }

    private func formatSize(_ bytes: Int64) -> String {
        let sizeInGB = Double(bytes) / 1_000_000_000.0
        if sizeInGB >= 1.0 {
            return String(format: "%.2f GB", sizeInGB)
        } else {
            let sizeInMB = Double(bytes) / 1_000_000.0
            return String(format: "%.0f MB", sizeInMB)
        }
    }

    private func formatTotalStorage(_ models: [OnDeviceLLMModelInfo]) -> String {
        let totalBytes = models.compactMap { $0.downloadedFileSize }.reduce(0, +)
        return formatSize(totalBytes)
    }
}

// MARK: - Model Row View

private struct ModelRowView: View {
    let model: OnDeviceLLMModelInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .font(.headline)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if model.isDownloaded {
                    Menu {
                        if !isSelected {
                            Button("Select") {
                                onSelect()
                            }
                        }
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        onDownload()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text(model.downloadSize)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Label("\(model.contextWindow / 1024)K context", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if model.isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                onSelect()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OnDeviceLLMSettingsView()
    }
}
