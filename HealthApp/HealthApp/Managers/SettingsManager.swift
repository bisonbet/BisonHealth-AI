import SwiftUI
import Foundation

// MARK: - Settings Models

enum Theme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ServerConfiguration: Equatable {
    var hostname: String
    var port: Int

    init(hostname: String = "localhost", port: Int) {
        self.hostname = hostname
        self.port = port
    }
}

// Inert legacy state, retained until a non-iCloud backup mechanism is designed.
// These fields are still persisted but no longer drive any behavior (the
// iCloud/CloudKit backup feature was removed). A future local/self-hosted
// backup mechanism will likely redefine this struct.
struct BackupSettings: Equatable {
    var iCloudEnabled: Bool = false
    var backupHealthData: Bool = true
    var backupChatHistory: Bool = true
    var backupDocuments: Bool = false
    var backupAppSettings: Bool = true
    var autoBackup: Bool = true
    var backupFrequency: BackupFrequency = .daily
}

enum BackupFrequency: String, CaseIterable {
    case manual = "manual"
    case daily = "daily"
    case weekly = "weekly"
    
    var displayName: String {
        switch self {
        case .manual: return "Manual Only"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

struct AppPreferences: Equatable {
    var theme: Theme = .system
    var showTips: Bool = true
    var analyticsEnabled: Bool = false
}

enum AIProvider: String, CaseIterable {
    case bedrock = "bedrock"
    case openAICompatible = "openai_compatible"
    case onDeviceLLM = "on_device_llm"

    var displayName: String {
        switch self {
        case .bedrock: return "AWS Bedrock"
        case .openAICompatible: return "OpenAI Compatible"
        case .onDeviceLLM: return "On-Device AI"
        }
    }

    var description: String {
        switch self {
        case .bedrock:
            return "AWS Bedrock cloud AI service"
        case .openAICompatible:
            return "OpenAI-compatible servers (LiteLLM, LocalAI, vLLM, etc.)"
        case .onDeviceLLM:
            return "On-device AI using downloaded models (no internet required)"
        }
    }
}

struct ModelPreferences: Equatable {
    var aiProvider: AIProvider = .onDeviceLLM
    var openAICompatibleModel: String = "" // Selected model for OpenAI-compatible servers
    var bedrockModel: String = AWSBedrockModel.claudeSonnet45.rawValue // Default AWS Bedrock model

    // Extraction Settings (Independent of Chat)
    var extractionProvider: AIProvider = .onDeviceLLM
    var extractionOpenAIModel: String = ""
    var extractionBedrockModel: String = AWSBedrockModel.claudeSonnet45.rawValue

    // Cloud Vision Extraction (opt-in: sends document page IMAGES to the cloud
    // extraction provider for higher-fidelity lab extraction)
    var cloudVisionExtractionEnabled: Bool = false
    // User-declared: the configured OpenAI-compatible model accepts image input
    var openAIVisionCapable: Bool = false

    var lastUpdated: Date = Date()
}

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case unknown
    case testing
    case connected
    case failed(String)
    
    var displayText: String {
        switch self {
        case .unknown: return "Not tested"
        case .testing: return "Testing..."
        case .connected: return "Connected"
        case .failed(let error): return "Failed: \(error)"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .testing: return .blue
        case .connected: return .green
        case .failed: return .red
        }
    }
    
    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .testing: return "clock"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// MARK: - Settings Manager

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Server configurations
    @Published var openAICompatibleBaseURL = ServerConfigurationConstants.defaultOpenAICompatibleBaseURL
    @Published var openAICompatibleAPIKey = ServerConfigurationConstants.defaultOpenAICompatibleAPIKey
    @Published var openAICompatibleContextSize: Int = 32768  // Default: 32k tokens

    // Connection statuses
    @Published var openAICompatibleStatus: ConnectionStatus = .unknown
    
    // Backup settings
    @Published var backupSettings = BackupSettings()
    
    // App preferences
    @Published var appPreferences = AppPreferences()

    // Model preferences
    @Published var modelPreferences = ModelPreferences()

    // Service clients (lazy loaded)
    private var openAICompatibleClient: OpenAICompatibleClient?
    private var mlxOnDeviceClient: MLXOnDeviceClient?
    private var mlxOnDeviceExtractionClient: MLXOnDeviceClient?
    #if DEBUG
    private var aiClientOverride: (any AIProviderInterface)?
    #endif

    private let userDefaults = UserDefaults.standard
    private let keychain = Keychain()

    // Keychain keys for reinstall persistence
    private let kcModelPrefsKey = "settings.modelPreferences.v1"
    private let kcOpenAICompatibleKey = "settings.openAICompatible.apiKey.v1"
    
    init() {
        loadSettings()
    }

    // MARK: - Settings Persistence

    func loadSettings() {
        // Load OpenAI-compatible configuration
        if let storedBaseURL = userDefaults.string(forKey: "openAICompatibleBaseURL"), !storedBaseURL.isEmpty {
            openAICompatibleBaseURL = storedBaseURL
        }
        if let storedAPIKey = try? keychain.retrieveString(for: kcOpenAICompatibleKey) {
            openAICompatibleAPIKey = storedAPIKey
        } else if let legacyAPIKey = userDefaults.string(forKey: "openAICompatibleAPIKey") {
            // Legacy fallback from older builds
            openAICompatibleAPIKey = legacyAPIKey
        }
        if let storedContextSize = userDefaults.object(forKey: "openAICompatibleContextSize") as? Int {
            openAICompatibleContextSize = storedContextSize
        }

        // Load backup settings
        if let backupData = userDefaults.data(forKey: "backupSettings"),
           let decoded = try? JSONDecoder().decode(BackupSettings.self, from: backupData) {
            backupSettings = decoded
        }
        
        // Load app preferences
        if let preferencesData = userDefaults.data(forKey: "appPreferences"),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: preferencesData) {
            appPreferences = decoded
        }
        
        // Load model preferences
        if let modelData = userDefaults.data(forKey: "modelPreferences"),
           let decoded = try? JSONDecoder().decode(ModelPreferences.self, from: modelData) {
            modelPreferences = decoded
        } else if let kcData = try? keychain.retrieve(for: kcModelPrefsKey),
                  let decoded = try? JSONDecoder().decode(ModelPreferences.self, from: kcData) {
            modelPreferences = decoded
        }

    }
    
    func saveSettings() {
        // Save OpenAI-compatible configuration
        userDefaults.set(openAICompatibleBaseURL, forKey: "openAICompatibleBaseURL")
        if openAICompatibleAPIKey.isEmpty {
            _ = try? keychain.delete(for: kcOpenAICompatibleKey)
        } else {
            _ = try? keychain.store(string: openAICompatibleAPIKey, for: kcOpenAICompatibleKey)
        }
        userDefaults.set(openAICompatibleContextSize, forKey: "openAICompatibleContextSize")

        // Save backup settings
        if let encoded = try? JSONEncoder().encode(backupSettings) {
            userDefaults.set(encoded, forKey: "backupSettings")
        }
        
        // Save app preferences
        if let encoded = try? JSONEncoder().encode(appPreferences) {
            userDefaults.set(encoded, forKey: "appPreferences")
        }
        
        // Save model preferences
        if let encoded = try? JSONEncoder().encode(modelPreferences) {
            userDefaults.set(encoded, forKey: "modelPreferences")
            _ = try? keychain.store(data: encoded, for: kcModelPrefsKey)
        }

        // Sync with UserDefaults
        userDefaults.synchronize()
    }
    
    // MARK: - Service Client Management

    func getAIClient() -> any AIProviderInterface {
        #if DEBUG
        if let override = getAIClientOverrideForTesting() {
            return override
        }
        #endif

        switch modelPreferences.aiProvider {
        case .bedrock:
            return getBedrockClient()
        case .openAICompatible:
            return getOpenAICompatibleClient()
        case .onDeviceLLM:
            return getMLXOnDeviceClient()
        }
    }

    #if DEBUG
    func setAIClientOverrideForTesting(_ client: (any AIProviderInterface)?) {
        aiClientOverride = client
    }

    func getAIClientOverrideForTesting() -> (any AIProviderInterface)? {
        if let aiClientOverride {
            return aiClientOverride
        }
        if AppTestRuntime.shouldUseScriptedAIProvider {
            return ScriptedAIProvider.shared
        }
        return nil
    }
    #endif

    func getOpenAICompatibleClient() -> OpenAICompatibleClient {
        if openAICompatibleClient == nil {
            let temperature = UserDefaults.standard.double(forKey: "openAICompatibleTemperature")
            let maxTokens = UserDefaults.standard.integer(forKey: "openAICompatibleMaxTokens")

            // Use defaults if not set
            let finalTemperature = temperature == 0 ? 0.1 : temperature
            let finalMaxTokens = maxTokens == 0 ? 2048 : maxTokens

            AppLog.shared.settings("Creating new OpenAICompatibleClient:")
            AppLog.shared.settings("   baseURL: [configured]")
            AppLog.shared.settings("   apiKey: \(openAICompatibleAPIKey.isEmpty ? "(empty)" : "(configured)")")
            AppLog.shared.settings("   model: '\(modelPreferences.openAICompatibleModel)'")
            AppLog.shared.settings("   temperature: \(finalTemperature)")
            AppLog.shared.settings("   maxTokens: \(finalMaxTokens)")
            AppLog.shared.settings("   contextSize: \(openAICompatibleContextSize)")

            openAICompatibleClient = OpenAICompatibleClient(
                baseURL: openAICompatibleBaseURL,
                apiKey: openAICompatibleAPIKey.isEmpty ? nil : openAICompatibleAPIKey,
                timeout: 300.0,
                defaultModel: modelPreferences.openAICompatibleModel,
                temperature: finalTemperature,
                maxTokens: finalMaxTokens,
                contextSize: openAICompatibleContextSize
            )
        } else {
            AppLog.shared.settings("Reusing existing OpenAICompatibleClient, updating model to: '\(modelPreferences.openAICompatibleModel)'")
            openAICompatibleClient?.updateDefaultModel(modelPreferences.openAICompatibleModel)
        }
        openAICompatibleClient?.declaresVisionSupport = modelPreferences.openAIVisionCapable
        return openAICompatibleClient!
    }

    func getBedrockClient() -> BedrockClient {
        // Use shared credentials and selected model (matches working pattern)
        let sharedCredentials = AWSCredentialsManager.shared.credentials
        let config = AWSBedrockConfig(
            region: sharedCredentials.region,
            accessKeyId: sharedCredentials.accessKeyId,
            secretAccessKey: sharedCredentials.secretAccessKey,
            sessionToken: nil,
            model: AWSBedrockModel(rawValue: modelPreferences.bedrockModel) ?? .claudeSonnet45,
            temperature: 0.1,
            maxTokens: 4096,
            timeout: 300.0,
            useProfile: false,
            profileName: nil
        )
        return BedrockClient(config: config)
    }

    func getMLXOnDeviceClient() -> MLXOnDeviceClient {
        if mlxOnDeviceClient == nil {
            mlxOnDeviceClient = MLXOnDeviceClient()
        }
        return mlxOnDeviceClient!
    }

    func getMLXOnDeviceExtractionClient() throws -> MLXOnDeviceClient {
        guard let extractionModel = MLXModelDownloadManager.shared.ensureValidExtractionModelSelection() else {
            throw MLXOnDeviceError.visionModelNotDownloaded
        }

        if MLXModelInfo.selectedModel.id == extractionModel.id {
            AppLog.shared.settings("Using shared MLX client for chat and extraction model: \(extractionModel.displayName)")
            mlxOnDeviceExtractionClient = nil
            return getMLXOnDeviceClient()
        }

        if mlxOnDeviceExtractionClient == nil {
            mlxOnDeviceExtractionClient = MLXOnDeviceClient {
                MLXModelDownloadManager.shared.selectedExtractionModel ?? extractionModel
            }
        }
        return mlxOnDeviceExtractionClient!
    }

    func prepareForOnDeviceExtraction() async {
        guard modelPreferences.extractionProvider == .onDeviceLLM else { return }
        guard let extractionModel = MLXModelDownloadManager.shared.ensureValidExtractionModelSelection() else { return }
        guard let mlxOnDeviceClient, MLXModelInfo.selectedModel.id != extractionModel.id else { return }

        AppLog.shared.settings("Unloading chat MLX model before on-device extraction")
        await mlxOnDeviceClient.unloadModel()
    }

    // Force recreation of clients when configuration changes
    func invalidateClients() {
        openAICompatibleClient = nil
        mlxOnDeviceClient = nil
        mlxOnDeviceExtractionClient = nil
    }

    func invalidateOpenAICompatibleClient() {
        openAICompatibleClient = nil
    }

    func invalidateOnDeviceExtractionClient() {
        mlxOnDeviceExtractionClient = nil
    }

    @discardableResult
    func ensureValidOnDeviceExtractionModelSelection() -> MLXModelInfo? {
        MLXModelDownloadManager.shared.ensureValidExtractionModelSelection()
    }

    func canUseOnDeviceExtractionProvider() -> Bool {
        ensureValidOnDeviceExtractionModelSelection() != nil
    }

    func updateExtractionProvider(_ provider: AIProvider) -> Bool {
        if provider == .onDeviceLLM, !canUseOnDeviceExtractionProvider() {
            return false
        }

        modelPreferences.extractionProvider = provider
        modelPreferences.lastUpdated = Date()

        if provider == .bedrock, !AWSBedrockModel.visionExtractionModels.contains(where: { $0.rawValue == modelPreferences.extractionBedrockModel }) {
            modelPreferences.extractionBedrockModel = AWSBedrockModel.defaultVisionExtractionModel.rawValue
        }

        saveSettings()
        return true
    }

    // MARK: - On-Device AI Preloading

    /// Preloads the on-device AI model in the background if enabled and downloaded.
    /// Call this on app launch to have the model ready when the user opens AI chat.
    func preloadOnDeviceLLMIfNeeded() {
        // Check if on-device AI is the selected provider
        guard modelPreferences.aiProvider == .onDeviceLLM else {
            AppLog.shared.settings("On-device AI not selected, skipping preload")
            return
        }

        // Check if on-device AI is enabled and a model is downloaded
        guard MLXModelInfo.isEnabled else {
            AppLog.shared.settings("On-device AI not enabled, skipping preload")
            return
        }

        let selectedModel = MLXModelInfo.selectedModel
        guard MLXModelDownloadManager.shared.isModelDownloaded(selectedModel) else {
            AppLog.shared.settings("No model downloaded, skipping preload")
            return
        }

        AppLog.shared.settings("Preloading MLX on-device model: \(selectedModel.displayName)")

        // Start loading in background
        Task {
            do {
                let client = getMLXOnDeviceClient()
                try await client.loadModel()
                AppLog.shared.settings("MLX on-device model preloaded successfully")
            } catch {
                AppLog.shared.settings("Failed to preload MLX on-device model: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App Lifecycle

    func suspendOnDeviceLLMForBackground() async {
        guard let mlxOnDeviceClient = mlxOnDeviceClient else { return }
        await mlxOnDeviceClient.suspendForBackground()
    }

    func resumeOnDeviceLLMAfterForeground() async {
        guard let mlxOnDeviceClient = mlxOnDeviceClient else { return }
        await mlxOnDeviceClient.resumeAfterForeground()
    }

    // MARK: - Validation

    func hasValidAWSCredentials() -> Bool {
        let credentials = AWSCredentialsManager.shared.credentials
        return credentials.isValid
    }

    func hasValidOpenAICompatibleConfig() -> Bool {
        return !openAICompatibleBaseURL.isEmpty && URL(string: openAICompatibleBaseURL) != nil
    }

    func validateServerConfiguration(_ config: ServerConfiguration) -> String? {
        if config.hostname.isEmpty {
            return "Hostname cannot be empty"
        }

        if config.port < 1 || config.port > 65535 {
            return "Port must be between 1 and 65535"
        }
        
        // Validate hostname or IP address
        if !isValidHostnameOrIP(config.hostname) {
            return "Invalid hostname or IP address format"
        }
        
        return nil
    }
    
    private func isValidHostnameOrIP(_ input: String) -> Bool {
        // Check if it's a valid IPv4 address
        if isValidIPv4(input) {
            return true
        }
        
        // Check if it's a valid IPv6 address
        if isValidIPv6(input) {
            return true
        }
        
        // Check if it's a valid hostname
        if isValidHostname(input) {
            return true
        }
        
        return false
    }
    
    private func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        if parts.count != 4 {
            return false
        }
        
        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else {
                return false
            }
            // Check for leading zeros (except for "0")
            if part.count > 1 && part.first == "0" {
                return false
            }
        }
        return true
    }
    
    private func isValidIPv6(_ ip: String) -> Bool {
        // Basic IPv6 validation (simplified)
        // This supports both full and compressed formats
        let ipv6Regex = "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::$|^::1$|^([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{1,4}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", ipv6Regex)
        return predicate.evaluate(with: ip)
    }
    
    private func isValidHostname(_ hostname: String) -> Bool {
        // Hostname validation: alphanumeric, hyphens, dots
        // Must not start or end with hyphen
        // Each label must be 1-63 characters
        // Total length must be 1-253 characters
        
        if hostname.isEmpty || hostname.count > 253 {
            return false
        }
        
        let labels = hostname.split(separator: ".")
        
        for label in labels {
            let labelStr = String(label)
            
            // Check length
            if labelStr.count > 63 || labelStr.isEmpty {
                return false
            }
            
            // Check if starts or ends with hyphen
            if labelStr.first == "-" || labelStr.last == "-" {
                return false
            }
            
            // Check characters (alphanumeric and hyphens only)
            let hostnameRegex = "^[a-zA-Z0-9-]+$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
            if !predicate.evaluate(with: labelStr) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Settings Reset
    
    func resetServerSettings() {
        openAICompatibleBaseURL = ServerConfigurationConstants.defaultOpenAICompatibleBaseURL
        openAICompatibleAPIKey = ServerConfigurationConstants.defaultOpenAICompatibleAPIKey
        openAICompatibleContextSize = 32768  // Reset to 32k default
        openAICompatibleStatus = .unknown
        modelPreferences.openAICompatibleModel = ""
        _ = try? keychain.delete(for: kcOpenAICompatibleKey)
        invalidateOpenAICompatibleClient()
        saveSettings()
    }
    
    func resetBackupSettings() {
        backupSettings = BackupSettings()
        saveSettings()
    }
    
    func resetAppPreferences() {
        appPreferences = AppPreferences()
        saveSettings()
    }
    
    func resetAllSettings() {
        resetServerSettings()
        resetBackupSettings()
        resetAppPreferences()
        resetModelPreferences()
    }
    
    func resetModelPreferences() {
        modelPreferences = ModelPreferences()
        saveSettings()
    }

    func updateOpenAICompatibleModel(_ model: String) {
        modelPreferences.openAICompatibleModel = model
        modelPreferences.lastUpdated = Date()
        openAICompatibleClient?.updateDefaultModel(model)
        saveSettings()
    }
}

// MARK: - Codable Extensions

extension ServerConfiguration: Codable {}
extension BackupSettings: Codable {}
extension AppPreferences: Codable {}
extension ModelPreferences: Codable {
    enum CodingKeys: String, CodingKey {
        case aiProvider
        case openAICompatibleModel
        case bedrockModel
        case extractionProvider
        case extractionOpenAIModel
        case extractionBedrockModel
        case cloudVisionExtractionEnabled
        case openAIVisionCapable
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode with defaults for backwards compatibility
        // (legacy persisted keys like documentProcessingMode are simply ignored)
        self.aiProvider = try container.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? .onDeviceLLM
        self.openAICompatibleModel = try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel) ?? ""
        self.bedrockModel = try container.decodeIfPresent(String.self, forKey: .bedrockModel) ?? AWSBedrockModel.claudeSonnet45.rawValue

        // Extraction Settings
        self.extractionProvider = try container.decodeIfPresent(AIProvider.self, forKey: .extractionProvider) ?? .onDeviceLLM
        self.extractionOpenAIModel = try container.decodeIfPresent(String.self, forKey: .extractionOpenAIModel) ?? ""
        self.extractionBedrockModel = try container.decodeIfPresent(String.self, forKey: .extractionBedrockModel) ?? AWSBedrockModel.claudeSonnet45.rawValue

        // Cloud Vision Extraction (default off — explicit consent required)
        self.cloudVisionExtractionEnabled = try container.decodeIfPresent(Bool.self, forKey: .cloudVisionExtractionEnabled) ?? false
        self.openAIVisionCapable = try container.decodeIfPresent(Bool.self, forKey: .openAIVisionCapable) ?? false

        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(aiProvider, forKey: .aiProvider)
        try container.encode(openAICompatibleModel, forKey: .openAICompatibleModel)
        try container.encode(bedrockModel, forKey: .bedrockModel)

        // Extraction Settings
        try container.encode(extractionProvider, forKey: .extractionProvider)
        try container.encode(extractionOpenAIModel, forKey: .extractionOpenAIModel)
        try container.encode(extractionBedrockModel, forKey: .extractionBedrockModel)

        // Cloud Vision Extraction
        try container.encode(cloudVisionExtractionEnabled, forKey: .cloudVisionExtractionEnabled)
        try container.encode(openAIVisionCapable, forKey: .openAIVisionCapable)

        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}
extension AIProvider: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AIProvider(rawValue: rawValue) ?? .onDeviceLLM
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
extension Theme: Codable {}
extension BackupFrequency: Codable {}
