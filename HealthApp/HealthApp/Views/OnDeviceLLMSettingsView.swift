//
//  OnDeviceLLMSettingsView.swift
//  HealthApp
//
//  Settings view for MLX on-device LLM configuration
//

import SwiftUI

// MARK: - On-Device LLM Settings View

struct OnDeviceLLMSettingsView: View {

    // MARK: - Properties

    @ObservedObject var downloadManager = MLXModelDownloadManager.shared
    @State private var isEnabled = MLXModelInfo.isEnabled
    @State private var selectedModelId = MLXModelInfo.selectedModel.id
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: MLXModelInfo?
    @State private var showAdvancedSettings = false

    // Sampling parameters
    @State private var temperature = MLXModelInfo.configuredTemperature
    @State private var topP = MLXModelInfo.configuredTopP
    @State private var maxTokens = MLXModelInfo.configuredMaxTokens
    @State private var contextSize = MLXModelInfo.configuredContextSize

    // MARK: - Body

    var body: some View {
        List {
            enableSection
            simulatorWarningSection
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
                Text("Delete \(model.displayName)? This will free up storage.")
            }
        }
        .accessibilityIdentifier("onDeviceLLMSettingsView")
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            Toggle("Enable On-Device LLM", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: MLXModelInfo.SettingsKeys.enableOnDeviceLLM)
                    SettingsManager.shared.invalidateClients()
                }
                .accessibilityIdentifier("enableOnDeviceLLMToggle")
        } header: {
            Text("On-Device AI (MLX)")
        } footer: {
            Text("Run AI models directly on your device using Apple MLX. No internet required after downloading a model. Fully private - your data never leaves your device.")
        }
    }

    @ViewBuilder
    private var simulatorWarningSection: some View {
        #if targetEnvironment(simulator)
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("On-device LLM requires a physical device. MLX is not available in the iOS Simulator.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        #endif
    }

    private var modelSelectionSection: some View {
        Section {
            ForEach(MLXModelInfo.allModels) { model in
                MLXModelRowView(
                    model: model,
                    isSelected: model.id == selectedModelId && downloadManager.isModelDownloaded(model),
                    isDownloaded: downloadManager.isModelDownloaded(model),
                    onSelect: {
                        if downloadManager.isModelDownloaded(model) {
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
            Text("AI Models")
        } footer: {
            Text("MediPhi is optimized for medical Q&A and clinical reasoning. Qwen 3.5 Vision supports both text and image understanding.")
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

                        Text("\(Int(downloadManager.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    // Context Size
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
                        ), in: Double(MLXModelInfo.minContextSize)...Double(MLXModelInfo.maxContextSize), step: 1024)
                            .onChange(of: contextSize) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: MLXModelInfo.SettingsKeys.contextSize)
                            }
                        Text("Default: 16K. Larger context allows more conversation history but uses more memory.")
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
                                UserDefaults.standard.set(newValue, forKey: MLXModelInfo.SettingsKeys.temperature)
                            }
                        Text("Medical models use low temperature (0.0-0.4) for accurate, consistent responses.")
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
                                UserDefaults.standard.set(newValue, forKey: MLXModelInfo.SettingsKeys.topP)
                            }
                        Text("Nucleus sampling threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Max Tokens
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Max Response Tokens")
                            Spacer()
                            Text("\(maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(maxTokens) },
                            set: { maxTokens = Int($0) }
                        ), in: 100...4096, step: 100)
                            .onChange(of: maxTokens) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: MLXModelInfo.SettingsKeys.maxTokens)
                            }
                        Text("Maximum number of tokens in each response.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Reset to Defaults
                    Button("Reset to Model Defaults") {
                        if let model = MLXModelInfo.model(withId: selectedModelId) {
                            MLXModelInfo.applyDefaultSettings(for: model)
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
                    Text(downloadManager.formatSize(downloadManager.totalStorageUsed))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No models downloaded")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Storage")
        }
    }

    // MARK: - Helper Methods

    private func refreshState() {
        isEnabled = MLXModelInfo.isEnabled
        selectedModelId = MLXModelInfo.selectedModel.id
        temperature = MLXModelInfo.configuredTemperature
        topP = MLXModelInfo.configuredTopP
        maxTokens = MLXModelInfo.configuredMaxTokens
        contextSize = MLXModelInfo.configuredContextSize
        downloadManager.refreshModelStatus()
    }

    private func selectModel(_ model: MLXModelInfo) {
        selectedModelId = model.id
        UserDefaults.standard.set(model.id, forKey: MLXModelInfo.SettingsKeys.selectedModelId)
        downloadManager.selectModel(model)
        SettingsManager.shared.invalidateClients()
    }
}

// MARK: - Model Row View

private struct MLXModelRowView: View {
    let model: MLXModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)

                        // Model type badge
                        Text(model.modelType.badge)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(model.modelType == .vlm ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(model.modelType == .vlm ? .purple : .blue)
                            .clipShape(Capsule())

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

                if isDownloaded {
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
                            Text(model.estimatedSize)
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

                if isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded {
                onSelect()
            }
        }
        .accessibilityLabel("\(model.displayName), \(model.modelType.displayName) model, \(isDownloaded ? "downloaded" : "not downloaded")")
        .accessibilityHint(isDownloaded ? "Tap to select this model" : "Tap download button to get this model")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OnDeviceLLMSettingsView()
    }
}
