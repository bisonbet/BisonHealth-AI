//
//  AWSBedrockSettingsView.swift
//  HealthApp
//
//  Settings view for AWS Bedrock AI configuration
//

import SwiftUI

struct AWSBedrockSettingsView: View {
    @ObservedObject private var credentialsManager = AWSCredentialsManager.shared
    @AppStorage("awsBedrockModel") private var selectedModel: String = AWSBedrockModel.claudeSonnet45.rawValue
    @AppStorage("awsBedrockTemperature") private var temperature: Double = 0.1
    @AppStorage("awsBedrockMaxTokens") private var maxTokens: Int = 4096
    @AppStorage("enableAWSBedrock") private var enableAWSBedrock: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var showingCredentials = false
    @State private var testResult: String?
    @State private var isTesting = false

    // Local state for editing (sync with unified credentials)
    @State private var editingAccessKey: String = ""
    @State private var editingSecretKey: String = ""
    @State private var editingRegion: String = "us-east-1"

    private let regions = [
        "us-east-1": "US East (N. Virginia)",
        "us-east-2": "US East (Ohio)",
        "us-west-1": "US West (N. California)",
        "us-west-2": "US West (Oregon)"
    ]

    private var selectedModelEnum: AWSBedrockModel {
        return AWSBedrockModel(rawValue: selectedModel) ?? .claudeSonnet45
    }

    var body: some View {
        Form {
            headerSection

            if enableAWSBedrock {
                authenticationSection
                modelConfigurationSection
                advancedSettingsSection
                connectionTestSection
                setupInstructionsSection
                documentationSection
            }
        }
        .navigationTitle("AWS Bedrock Settings")
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
            print("🔵 AWSBedrockSettingsView.onAppear called")
            // Initialize editing states with current credentials
            editingAccessKey = credentialsManager.credentials.accessKeyId
            editingSecretKey = credentialsManager.credentials.secretAccessKey
            editingRegion = credentialsManager.credentials.region

            // Validate and fix invalid stored model selection
            if AWSBedrockModel(rawValue: selectedModel) == nil {
                print("⚠️ Invalid stored model '\(selectedModel)', resetting to default")
                selectedModel = AWSBedrockModel.claudeSonnet45.rawValue
            }
        }
    }

    private var headerSection: some View {
        Section(header: Text("AWS Bedrock AI")) {
            Toggle("Enable AWS Bedrock", isOn: $enableAWSBedrock)

            if enableAWSBedrock {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AWS Bedrock provides access to Claude Sonnet 4.5, Amazon Nova Premier, and Llama 4 Maverick models for high-quality AI analysis of health data and documents.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Context Window")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(selectedModelEnum.contextWindow/1000)K tokens")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provider")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(selectedModelEnum.provider)
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max Tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(selectedModelEnum.maxTokens)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var authenticationSection: some View {
        Section(header:
            VStack(alignment: .leading, spacing: 4) {
                Text("AWS Credentials")
                Text("These credentials are shared with other AWS services")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Access Key ID")
                    Spacer()
                    Button("Show/Hide") {
                        showingCredentials.toggle()
                    }
                    .font(.caption)
                }

                if showingCredentials {
                    TextField("Enter Access Key ID", text: $editingAccessKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: editingAccessKey) { _, newValue in
                            credentialsManager.updateAccessKey(newValue)
                        }
                } else {
                    SecureField("Enter Access Key ID", text: $editingAccessKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: editingAccessKey) { _, newValue in
                            credentialsManager.updateAccessKey(newValue)
                        }
                }

                HStack {
                    Text("Secret Access Key")
                    Spacer()
                    Button("Show/Hide") {
                        showingCredentials.toggle()
                    }
                    .font(.caption)
                }

                if showingCredentials {
                    TextField("Enter Secret Access Key", text: $editingSecretKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: editingSecretKey) { _, newValue in
                            credentialsManager.updateSecretKey(newValue)
                        }
                } else {
                    SecureField("Enter Secret Access Key", text: $editingSecretKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: editingSecretKey) { _, newValue in
                            credentialsManager.updateSecretKey(newValue)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Security Note")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                Text("Your AWS credentials are stored securely on your device. Never share these credentials or commit them to version control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var modelConfigurationSection: some View {
        Section(header: Text("Model Configuration")) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("AWS Region", selection: $editingRegion) {
                    ForEach(Array(regions.keys.sorted()), id: \.self) { key in
                        Text("\(key) - \(regions[key] ?? "")")
                            .tag(key)
                    }
                }
                .onChange(of: editingRegion) { _, newValue in
                    credentialsManager.updateRegion(newValue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.headline)

                    Picker("Model", selection: $selectedModel) {
                        ForEach(AWSBedrockModel.allCases, id: \.self) { model in
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .font(.body)
                                Text("\(model.provider) • \(model.contextWindow/1000)K context • \(model.maxTokens) max tokens")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(model.rawValue)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    // Model details
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedModelEnum.displayName)
                            .font(.body)
                            .fontWeight(.medium)

                        Text(selectedModelEnum.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Context Window")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(selectedModelEnum.contextWindow/1000)K tokens")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Max Output")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(selectedModelEnum.maxTokens) tokens")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Provider")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(selectedModelEnum.provider)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                }
            }
        }
    }

    private var advancedSettingsSection: some View {
        Section(header: Text("Advanced Settings")) {
            VStack(alignment: .leading, spacing: 16) {
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
                    ), in: 512...Double(selectedModelEnum.maxTokens), step: 256)

                    Text("Maximum number of tokens in the response. Higher values allow for longer responses but may increase costs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var connectionTestSection: some View {
        Section(header: Text("Test Connection")) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing..." : "Test AWS Bedrock Connection")
                    }
                }
                .disabled(isTesting || !isConfigurationValid)

                if let testResult = testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundColor(testResult.contains("✅") ? .green : .red)
                }
            }
        }
    }

    private var setupInstructionsSection: some View {
        Section(header: Text("Setup Instructions")) {
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    number: "1",
                    title: "Create AWS Account",
                    description: "Sign up for AWS if you don't have an account"
                )

                InstructionRow(
                    number: "2",
                    title: "Enable Bedrock Access",
                    description: "Request access to Claude Sonnet 4.5, Amazon Nova Premier, and Llama 4 Maverick models in the AWS Bedrock console"
                )

                InstructionRow(
                    number: "3",
                    title: "Create IAM User",
                    description: "Create an IAM user with bedrock:InvokeModel permissions"
                )

                InstructionRow(
                    number: "4",
                    title: "Generate Access Keys",
                    description: "Create Access Key ID and Secret Access Key for the IAM user"
                )

                InstructionRow(
                    number: "5",
                    title: "Configure App",
                    description: "Enter your credentials, region, and model preferences above"
                )
            }
        }
    }

    private var documentationSection: some View {
        Section {
            Link("AWS Bedrock Documentation", destination: URL(string: "https://docs.aws.amazon.com/bedrock/")!)
            Link("Model Access Setup Guide", destination: URL(string: "https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html")!)
            Link("IAM Permissions Guide", destination: URL(string: "https://docs.aws.amazon.com/bedrock/latest/userguide/security_iam_service-with-iam.html")!)
        }
    }

    private var isConfigurationValid: Bool {
        return credentialsManager.credentials.isValid
    }

    private func testConnection() {
        guard isConfigurationValid else { return }

        isTesting = true
        testResult = nil

        Task {
            let config = createConfig()
            let bedrockClient = BedrockClient(config: config)

            do {
                let success = try await bedrockClient.testConnection()

                await MainActor.run {
                    if success {
                        testResult = "✅ AWS Bedrock connection successful! Model \(selectedModelEnum.displayName) is ready to use."
                    } else {
                        testResult = "❌ Connection test failed. Please check your configuration."
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Connection failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private func createConfig() -> AWSBedrockConfig {
        return AWSBedrockConfig(
            region: credentialsManager.credentials.region,
            accessKeyId: credentialsManager.credentials.accessKeyId,
            secretAccessKey: credentialsManager.credentials.secretAccessKey,
            sessionToken: nil,
            model: selectedModelEnum,
            temperature: temperature,
            maxTokens: maxTokens,
            timeout: 60.0,
            useProfile: false,
            profileName: nil
        )
    }
}

// Reuse the InstructionRow from your existing code
struct InstructionRow: View {
    let number: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AWSBedrockSettingsView()
}