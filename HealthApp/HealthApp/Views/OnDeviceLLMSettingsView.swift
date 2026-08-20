//
//  OnDeviceLLMSettingsView.swift
//  HealthApp
//
//  Settings view for MLX on-device AI configuration
//

import SwiftUI

// MARK: - On-Device AI Settings View

struct OnDeviceLLMSettingsView: View {

    // MARK: - Properties

    @ObservedObject var downloadManager = MLXModelDownloadManager.shared
    @State private var isEnabled = MLXModelInfo.isEnabled
    @State private var selectedModelId = MLXModelDownloadManager.shared.selectedModelId
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
            macModelAvailabilitySection
            modelSelectionSection
            extractionModelSelectionSection
            downloadSection
            advancedSettingsSection
            storageSection
        }
        .navigationTitle("On-Device AI")
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
            Toggle("Enable On-Device AI", isOn: $isEnabled)
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
                Text("On-device AI requires a physical device. MLX is not available in the iOS Simulator.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        #endif
    }

    @ViewBuilder
    private var macModelAvailabilitySection: some View {
        if PlatformCapabilities.isRunningOnMac {
            Section {
                Label(
                    "MedGemma 27B Chat is available on Macs with at least 24 GB of installed physical memory. It downloads about 16.02 GB across three weight shards and uses additional memory while generating.",
                    systemImage: "memorychip"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("High-Memory Mac Model")
            }
        }
    }

    private var modelSelectionSection: some View {
        Section {
            ForEach(MLXModelInfo.allModels) { model in
                MLXModelRowView(
                    model: model,
                    isSelected: model.id == selectedModelId && downloadManager.isModelDownloaded(model),
                    isDownloaded: downloadManager.isModelDownloaded(model),
                    isDownloading: downloadManager.isDownloading
                        && downloadManager.currentlyDownloadingModel?.id == model.id,
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
            Text("MediPhi is optimized for medical Q&A. MedGemma 27B is a text-only medical model for Mac chat. Qwen 3.5 Vision supports text and image understanding.")
        }
    }

    private var extractionModelSelectionBinding: Binding<String> {
        Binding(
            get: {
                downloadManager.selectedExtractionModelId
                    ?? downloadManager.downloadedVisionModels.first?.id
                    ?? ""
            },
            set: { modelId in
                guard let model = MLXModelInfo.model(withId: modelId),
                      downloadManager.isModelDownloaded(model) else {
                    return
                }
                downloadManager.selectExtractionModel(model)
                SettingsManager.shared.invalidateOnDeviceExtractionClient()
            }
        )
    }

    private var extractionModelSelectionSection: some View {
        Section {
            let visionModels = downloadManager.downloadedVisionModels
            if visionModels.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No downloaded Vision model is available for document extraction.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Extraction Model", selection: extractionModelSelectionBinding) {
                    ForEach(visionModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                HStack {
                    Text("Downloaded Vision Models")
                    Spacer()
                    Text("\(visionModels.count)")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Document Extraction")
        } footer: {
            Text("On-device document extraction uses a downloaded Vision model. Text models remain available for chat.")
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

                        Text(downloadStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("modelDownloadStatusText")

                        HStack(spacing: 6) {
                            Image(systemName: downloadManager.downloadPhase.systemImage)
                            Text(downloadManager.downloadPhase.title)
                        }
                        .font(.caption)
                        .foregroundColor(downloadPhaseColor)
                        .accessibilityIdentifier("modelDownloadPhase")

                        Text("Progress follows actual bytes reported by the active shard. Cache size may jump when a large shard finishes.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if downloadManager.isDownloadStalled {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("No data received for a while. Retrying the transfer automatically; check your network connection if this continues.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                    .foregroundColor(BisonTheme.gold)
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

    /// Progress is based on byte-weighted Hub progress; cache size can still jump when a whole
    /// shard is materialized.
    private var downloadStatusText: String {
        let percent = Int(downloadManager.downloadProgress * 100)
        guard let model = downloadManager.currentlyDownloadingModel else {
            return "\(percent)%"
        }

        let transferred = downloadManager.formatSize(downloadManager.downloadedBytes)
        let total = downloadManager.formatSize(model.estimatedSizeBytes)
        let progressText = "\(percent)% · \(transferred) of ~\(total)"

        switch downloadManager.downloadPhase {
        case .connecting:
            return "\(progressText) · Connecting"
        case .downloading:
            if let speed = downloadManager.downloadSpeedBytesPerSecond {
                return "\(progressText) · \(formatSpeed(speed))"
            }
            return "\(progressText) · Receiving data"
        case .waitingForData:
            return "\(progressText) · Waiting for data"
        case .retrying:
            return "\(progressText) · Retrying connection"
        }
    }

    private var downloadPhaseColor: Color {
        switch downloadManager.downloadPhase {
        case .waitingForData, .retrying:
            return .orange
        case .connecting, .downloading:
            return .secondary
        }
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", max(bytesPerSecond, 0))
    }

    private func refreshState() {
        isEnabled = MLXModelInfo.isEnabled
        selectedModelId = downloadManager.selectedModelId
        temperature = MLXModelInfo.configuredTemperature
        topP = MLXModelInfo.configuredTopP
        maxTokens = MLXModelInfo.configuredMaxTokens
        contextSize = MLXModelInfo.configuredContextSize
        downloadManager.refreshModelStatus()
    }

    private func selectModel(_ model: MLXModelInfo) {
        selectedModelId = model.id
        downloadManager.selectModel(model)
        SettingsManager.shared.invalidateClients()
    }
}

// MARK: - Model Row View

private struct MLXModelRowView: View {
    let model: MLXModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
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
                            .background(model.modelType == .vlm ? Color.purple.opacity(0.15) : BisonTheme.gold.opacity(0.15))
                            .foregroundColor(model.modelType == .vlm ? .purple : BisonTheme.gold)
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
                } else if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading…")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("modelDownloadInProgress")
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
        .accessibilityLabel("\(model.displayName), \(model.modelType.displayName) model, \(isDownloaded ? "downloaded" : isDownloading ? "downloading" : "not downloaded")")
        .accessibilityHint(isDownloaded ? "Tap to select this model" : isDownloading ? "Download in progress" : "Tap download button to get this model")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OnDeviceLLMSettingsView()
    }
}
