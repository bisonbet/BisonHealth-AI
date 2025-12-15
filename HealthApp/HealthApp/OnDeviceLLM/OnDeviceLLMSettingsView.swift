//
//  OnDeviceLLMSettingsView.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import SwiftUI

struct OnDeviceLLMSettingsView: View {
    // MARK: - Constants

    /// Minimum value for max tokens slider
    private static let minMaxTokens = 256

    /// Maximum value for max tokens slider
    private static let maxMaxTokens = 8192

    /// Step value for max tokens slider
    private static let maxTokensStep = 256

    // MARK: - State Properties

    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var llmService = OnDeviceLLMService.shared

    @State private var config = OnDeviceLLMConfig.load()
    @State private var isEnabled = OnDeviceLLMConfig.isEnabled
    @State private var selectedModel: OnDeviceLLMModel?
    @State private var selectedQuantization: OnDeviceLLMQuantization
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: (OnDeviceLLMModel, OnDeviceLLMQuantization)?
    @State private var showCellularWarning = false
    @State private var pendingDownload: (OnDeviceLLMModel, OnDeviceLLMQuantization)?
    @State private var showDeleteAllConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    init() {
        let config = OnDeviceLLMConfig.load()
        _selectedModel = State(initialValue: OnDeviceLLMModel.model(withID: config.modelID))
        _selectedQuantization = State(initialValue: config.quantization)
    }

    var body: some View {
        List {
            // Header Section
            headerSection

            // Enable Toggle
            enableSection

            if isEnabled {
                // Model Selection
                modelSelectionSection

                // Model Loading Status
                if llmService.isModelLoading {
                    modelLoadingSection
                }

                // Download Section
                if let model = selectedModel {
                    downloadSection(for: model)
                }

                // Storage Management
                storageSection

                // Advanced Settings
                advancedSettingsSection

                // Help Section
                helpSection
            }
        }
        .navigationTitle("On-Device AI")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Model", isPresented: $showDeleteConfirmation, presenting: modelToDelete) { modelInfo in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteModel(modelInfo.0, quantization: modelInfo.1)
            }
        } message: { modelInfo in
            Text("Are you sure you want to delete \(modelInfo.0.displayName) (\(modelInfo.1.rawValue))? This will free up storage space but you'll need to redownload it to use this model again.")
        }
        .alert("Use Cellular Data?", isPresented: $showCellularWarning, presenting: pendingDownload) { downloadInfo in
            Button("Cancel", role: .cancel) {
                pendingDownload = nil
            }
            Button("Download") {
                if let (model, quant) = pendingDownload {
                    Task {
                        try? await downloadManager.downloadModel(model, quantization: quant, allowCellular: true)
                    }
                }
                pendingDownload = nil
            }
        } message: { downloadInfo in
            Text("This will download approximately \(downloadInfo.1.estimatedSize) over cellular data. This may use significant data from your plan. Are you sure?")
        }
        .alert("Delete All Models", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllModels()
            }
        } message: {
            Text("Are you sure you want to delete all downloaded models? This will free up \(downloadManager.totalStorageUsedFormatted) of storage.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: config) { _, newConfig in
            newConfig.save()
        }
        .onChange(of: isEnabled) { _, newValue in
            OnDeviceLLMConfig.isEnabled = newValue
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Complete Privacy", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundColor(.blue)

                Text("Run AI models directly on your device. Your health data never leaves your iPhone or iPad. Works offline with no internet connection required.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        Section {
            Toggle("Enable On-Device AI", isOn: $isEnabled)
                .font(.headline)
                .accessibilityLabel("Enable on-device AI")
                .accessibilityHint("Toggle to enable or disable local AI processing on your device")
        } footer: {
            Text("When enabled, you can use local AI models for complete privacy. Requires downloading models to your device.")
        }
    }

    // MARK: - Model Loading Section

    private var modelLoadingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading Model...")
                        .font(.headline)
                }

                if let modelName = llmService.currentModel?.displayName {
                    Text("Loading \(modelName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let error = llmService.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityLabel("Model loading")
        .accessibilityHint("Model is currently being loaded into memory")
    }

    // MARK: - Model Selection

    private var modelSelectionSection: some View {
        Section("Available Models") {
            ForEach(OnDeviceLLMModel.availableModels) { model in
                Button {
                    selectedModel = model
                    config.modelID = model.id
                    config.contextWindow = model.contextWindow
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.displayName)
                                    .font(.headline)

                                if model.isVisionModel {
                                    Image(systemName: "eye.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }

                                Badge(text: model.specialization.displayName)
                            }

                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)

                            HStack {
                                Label("\(model.parameters) parameters", systemImage: "cpu")
                                Spacer()
                                Label("\(model.contextWindow) tokens", systemImage: "doc.text")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        if selectedModel?.id == model.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.displayName) model")
                .accessibilityHint("Select this model for on-device AI. \(model.description)")
                .accessibilityAddTraits(selectedModel?.id == model.id ? .isSelected : [])
            }
        } footer: {
            if let model = selectedModel {
                if model.isVisionModel {
                    Text("Vision models can analyze images, lab reports, and medical documents.")
                }
            }
        }
    }

    // MARK: - Download Section

    private func downloadSection(for model: OnDeviceLLMModel) -> some View {
        Section("Download Options") {
            // Quantization Selector
            Picker("Quality Level", selection: $selectedQuantization) {
                ForEach(model.quantizations, id: \.self) { quant in
                    VStack(alignment: .leading) {
                        Text(quant.displayName)
                        Text(quant.estimatedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(quant)
                }
            }
            .accessibilityLabel("Model quality level")
            .accessibilityHint("Select the quality level for the model. Higher quality requires more storage")
            .onChange(of: selectedQuantization) { _, newValue in
                config.quantization = newValue
            }

            // Download Status/Button
            let downloadKey = "\(model.id)-\(selectedQuantization.rawValue)"
            if let state = downloadManager.downloadStates[downloadKey] {
                switch state {
                case .notDownloaded:
                    downloadButton(for: model, quantization: selectedQuantization)

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading...")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: progress)

                        Button("Cancel Download") {
                            downloadManager.cancelDownload(for: model, quantization: selectedQuantization)
                        }
                        .foregroundColor(.red)
                        .accessibilityLabel("Cancel download")
                        .accessibilityHint("Cancel the current model download")
                    }

                case .downloaded(let downloadedModel):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Downloaded")
                            Spacer()
                            Text(downloadedModel.sizeFormatted)
                                .foregroundColor(.secondary)
                        }

                        Button("Delete Model") {
                            modelToDelete = (model, selectedQuantization)
                            showDeleteConfirmation = true
                        }
                        .foregroundColor(.red)
                        .accessibilityLabel("Delete model")
                        .accessibilityHint("Delete the downloaded model to free up storage space")
                    }

                case .failed(let error):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Download Failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        downloadButton(for: model, quantization: selectedQuantization)
                    }

                case .paused(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Paused")
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: progress)

                        downloadButton(for: model, quantization: selectedQuantization)
                    }
                }
            } else {
                downloadButton(for: model, quantization: selectedQuantization)
            }
        } footer: {
            Text("Higher quality levels produce better results but require more storage and memory. Q4_K_M is recommended for most devices.")
        }
    }

    private func downloadButton(for model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) -> some View {
        Button {
            Task {
                await startDownload(model: model, quantization: quantization)
            }
        } label: {
            Label("Download Model (\(quantization.estimatedSize))", systemImage: "arrow.down.circle")
        }
        .accessibilityLabel("Download \(model.displayName) model")
        .accessibilityHint("Download this model with \(quantization.displayName) quality, approximately \(quantization.estimatedSize)")
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section("Storage") {
            if downloadManager.totalStorageUsed > 0 {
                HStack {
                    Text("Total Storage Used")
                    Spacer()
                    Text(downloadManager.totalStorageUsedFormatted)
                        .foregroundColor(.secondary)
                }

                let downloadedModels = OnDeviceLLMConfig.loadDownloadedModels()
                ForEach(downloadedModels) { downloadedModel in
                    if let model = OnDeviceLLMModel.model(withID: downloadedModel.modelID) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .font(.subheadline)
                                Text(downloadedModel.quantization.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(downloadedModel.sizeFormatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if downloadedModels.count > 1 {
                    Button("Delete All Models") {
                        showDeleteAllConfirmation = true
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("Delete all models")
                    .accessibilityHint("Delete all downloaded models to free up \(downloadManager.totalStorageUsedFormatted) of storage")
                }
            } else {
                Text("No models downloaded")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Advanced Settings

    private var advancedSettingsSection: some View {
        Section("Advanced Settings") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", config.temperature))
                        .foregroundColor(.secondary)
                }

                Slider(value: $config.temperature, in: 0.0...1.0, step: 0.05)
                    .accessibilityLabel("Temperature: \(String(format: "%.2f", config.temperature))")
                    .accessibilityHint("Adjust response creativity. Lower values are more focused, higher values are more creative")

                Text("Lower = more focused, higher = more creative")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Response Length")
                    Spacer()
                    Text("\(config.maxTokens) tokens")
                        .foregroundColor(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(config.maxTokens) },
                    set: { config.maxTokens = Int($0) }
                ), in: Double(Self.minMaxTokens)...Double(Self.maxMaxTokens), step: Double(Self.maxTokensStep))
                    .accessibilityLabel("Maximum response length: \(config.maxTokens) tokens")
                    .accessibilityHint("Adjust the maximum length of AI responses")

                Text("Maximum length of generated responses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("Allow Cellular Download", isOn: $config.allowCellularDownload)
                .accessibilityLabel("Allow cellular download")
                .accessibilityHint("Toggle to allow model downloads over cellular data")
        } footer: {
            Text("Cellular downloads can use significant data. Models range from 2-4 GB depending on quality level.")
        }
    }

    // MARK: - Help Section

    private var helpSection: some View {
        Section("About On-Device AI") {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    icon: "iphone",
                    title: "Device Requirements",
                    description: "Requires iPhone 12 or newer, iPad with A14 Bionic or later, or iPad Pro with M1 or later. At least 4GB of free storage recommended."
                )

                InfoRow(
                    icon: "lock.shield.fill",
                    title: "Privacy First",
                    description: "All processing happens on your device. No data is sent to external servers. Works completely offline."
                )

                InfoRow(
                    icon: "bolt.fill",
                    title: "Performance",
                    description: "Response times vary based on device and model. Newer devices with Apple Silicon provide the best performance."
                )

                InfoRow(
                    icon: "cross.case.fill",
                    title: "Medical Use",
                    description: "These models are for informational purposes only. Always consult qualified healthcare professionals for medical advice."
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helper Methods

    private func startDownload(model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) async {
        if downloadManager.isOnCellular && !config.allowCellularDownload {
            pendingDownload = (model, quantization)
            showCellularWarning = true
        } else {
            do {
                try await downloadManager.downloadModel(model, quantization: quantization, allowCellular: config.allowCellularDownload)
            } catch {
                errorMessage = "Failed to download model: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func deleteModel(_ model: OnDeviceLLMModel, quantization: OnDeviceLLMQuantization) {
        do {
            try downloadManager.deleteModel(model, quantization: quantization)

            // Unload if currently loaded
            if llmService.currentModel?.id == model.id && llmService.currentQuantization == quantization {
                llmService.unloadModel()
            }
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteAllModels() {
        do {
            try downloadManager.deleteAllModels()
            llmService.unloadModel()
        } catch {
            errorMessage = "Failed to delete all models: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Supporting Views

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        OnDeviceLLMSettingsView()
    }
}
