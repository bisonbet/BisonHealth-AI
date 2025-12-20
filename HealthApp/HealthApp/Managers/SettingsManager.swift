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
    
    init(hostname: String = ServerConfigurationConstants.defaultOllamaHostname, port: Int) {
        self.hostname = hostname
        self.port = port
    }
}

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
    var hapticFeedback: Bool = true
    var showTips: Bool = true
    var analyticsEnabled: Bool = false
}

enum AIProvider: String, CaseIterable {
    case ollama = "ollama"
    case bedrock = "bedrock"
    case openAICompatible = "openai_compatible"
    case mlx = "mlx"

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .bedrock: return "AWS Bedrock"
        case .openAICompatible: return "OpenAI Compatible"
        case .mlx: return "MLX (On-Device)"
        }
    }

    var description: String {
        switch self {
        case .ollama:
            return "Local Ollama server for privacy-focused AI"
        case .bedrock:
            return "AWS Bedrock cloud AI service"
        case .openAICompatible:
            return "OpenAI-compatible servers (LiteLLM, LocalAI, vLLM, etc.)"
        case .mlx:
            return "On-device AI using Apple's MLX framework - completely private, no network required"
        }
    }
}

struct ModelPreferences: Equatable {
    var aiProvider: AIProvider = .ollama   // Default AI provider
    var chatModel: String = "llama3.2"     // Default chat model
    var visionModel: String = "llava"      // Default vision model for image processing
    var documentModel: String = "llama3.2" // Default document processing model (text-only)
    var openAICompatibleModel: String = "" // Selected model for OpenAI-compatible servers
    var bedrockModel: String = AWSBedrockModel.claudeSonnet45.rawValue // Default AWS Bedrock model
    var mlxModelId: String? = nil          // Selected MLX model ID
    var contextSizeLimit: Int = 32768      // Default context size: 32k tokens (for Ollama)
    var lastUpdated: Date = Date()
}

struct ModelSelection: Equatable {
    var availableModels: [OllamaModel] = []
    var isLoading: Bool = false
    var lastFetchTime: Date?
    var error: String?
    
    static func == (lhs: ModelSelection, rhs: ModelSelection) -> Bool {
        lhs.availableModels == rhs.availableModels &&
        lhs.isLoading == rhs.isLoading &&
        lhs.lastFetchTime == rhs.lastFetchTime &&
        lhs.error == rhs.error
    }
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
    @Published var ollamaConfig = ServerConfigurationConstants.defaultOllamaConfig
    @Published var doclingConfig = ServerConfigurationConstants.defaultDoclingConfig
    @Published var openAICompatibleBaseURL = ServerConfigurationConstants.defaultOpenAICompatibleBaseURL
    @Published var openAICompatibleAPIKey = ServerConfigurationConstants.defaultOpenAICompatibleAPIKey
    @Published var openAICompatibleContextSize: Int = 32768  // Default: 32k tokens

    // MLX configuration
    @Published var mlxSettings = MLXSettings.default
    @Published var mlxGenerationConfig = MLXGenerationConfig.default

    // Connection statuses
    @Published var ollamaStatus: ConnectionStatus = .unknown
    @Published var doclingStatus: ConnectionStatus = .unknown
    @Published var openAICompatibleStatus: ConnectionStatus = .unknown
    @Published var mlxStatus: ConnectionStatus = .unknown
    
    // Backup settings
    @Published var backupSettings = BackupSettings()
    
    // App preferences
    @Published var appPreferences = AppPreferences()
    
    // Model preferences
    @Published var modelPreferences = ModelPreferences()
    
    // Model selection state
    @Published var modelSelection = ModelSelection()
    
    // Service clients (lazy loaded)
    private var ollamaClient: OllamaClient?
    private var doclingClient: DoclingClient?
    private var openAICompatibleClient: OpenAICompatibleClient?
    private var mlxClient: MLXClient?

    // iCloud backup manager
    @Published var backupManager: iCloudBackupManager?
    
    private let userDefaults = UserDefaults.standard
    private let keychain = Keychain()

    // Keychain keys for reinstall persistence
    private let kcOllamaKey = "settings.ollamaConfig.v1"
    private let kcDoclingKey = "settings.doclingConfig.v1"
    private let kcModelPrefsKey = "settings.modelPreferences.v1"
    private let kcOpenAICompatibleKey = "settings.openAICompatible.apiKey.v1"
    private let kcMLXSettingsKey = "settings.mlxSettings.v1"

    // Tracks whether model prefs were loaded from persisted storage
    private var loadedModelPrefsFromStorage: Bool = false
    
    init() {
        loadSettings()
        // Defer backup manager setup to avoid circular dependency
        Task { @MainActor in
            await setupBackupManager()
        }
    }
    
    // MARK: - Settings Persistence
    
    func loadSettings() {
        // Load Ollama configuration
        if let ollamaData = userDefaults.data(forKey: "ollamaConfig"),
           let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: ollamaData) {
            ollamaConfig = decoded
        } else if let kcData = try? keychain.retrieve(for: kcOllamaKey),
                  let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: kcData) {
            // Fallback to Keychain on first run after reinstall
            ollamaConfig = decoded
        }
        
        // Load Docling configuration
        if let doclingData = userDefaults.data(forKey: "doclingConfig"),
           let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: doclingData) {
            doclingConfig = decoded
        } else if let kcData = try? keychain.retrieve(for: kcDoclingKey),
                  let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: kcData) {
            doclingConfig = decoded
        }

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
            loadedModelPrefsFromStorage = true
        } else if let kcData = try? keychain.retrieve(for: kcModelPrefsKey),
                  let decoded = try? JSONDecoder().decode(ModelPreferences.self, from: kcData) {
            modelPreferences = decoded
            loadedModelPrefsFromStorage = true
        } else {
            loadedModelPrefsFromStorage = false
        }

        // Load MLX settings
        if let mlxData = userDefaults.data(forKey: "mlxSettings"),
           let decoded = try? JSONDecoder().decode(MLXSettings.self, from: mlxData) {
            mlxSettings = decoded
        } else if let kcData = try? keychain.retrieve(for: kcMLXSettingsKey),
                  let decoded = try? JSONDecoder().decode(MLXSettings.self, from: kcData) {
            mlxSettings = decoded
        }

        // Load MLX generation config
        if let mlxGenData = userDefaults.data(forKey: "mlxGenerationConfig"),
           let decoded = try? JSONDecoder().decode(MLXGenerationConfig.self, from: mlxGenData) {
            mlxGenerationConfig = decoded
        }
    }
    
    func saveSettings() {
        // Save Ollama configuration
        if let encoded = try? JSONEncoder().encode(ollamaConfig) {
            userDefaults.set(encoded, forKey: "ollamaConfig")
            // Mirror to Keychain to survive app reinstalls
            _ = try? keychain.store(data: encoded, for: kcOllamaKey)
        }
        
        // Save Docling configuration
        if let encoded = try? JSONEncoder().encode(doclingConfig) {
            userDefaults.set(encoded, forKey: "doclingConfig")
            _ = try? keychain.store(data: encoded, for: kcDoclingKey)
        }

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

        // Save MLX settings
        if let encoded = try? JSONEncoder().encode(mlxSettings) {
            userDefaults.set(encoded, forKey: "mlxSettings")
            _ = try? keychain.store(data: encoded, for: kcMLXSettingsKey)
        }

        // Save MLX generation config
        if let encoded = try? JSONEncoder().encode(mlxGenerationConfig) {
            userDefaults.set(encoded, forKey: "mlxGenerationConfig")
        }

        // Sync with UserDefaults
        userDefaults.synchronize()
    }
    
    // MARK: - Connection Testing
    
    func testOllamaConnection() async {
        ollamaStatus = .testing
        
        do {
            let client = getOllamaClient()
            let isConnected = try await client.testConnection()
            ollamaStatus = isConnected ? .connected : .failed("Service unavailable")
        } catch {
            ollamaStatus = .failed(error.localizedDescription)
        }
    }
    
    func testDoclingConnection() async {
        doclingStatus = .testing
        
        do {
            let client = getDoclingClient()
            let isConnected = try await client.testConnection()
            doclingStatus = isConnected ? .connected : .failed("Service unavailable")
        } catch {
            doclingStatus = .failed(error.localizedDescription)
        }
    }
    
    func testAllConnections() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.testOllamaConnection() }
            group.addTask { await self.testDoclingConnection() }
        }
    }
    
    // MARK: - Service Client Management
    
    func getOllamaClient() -> OllamaClient {
        // Always create new client to ensure we use the current configuration
        ollamaClient = OllamaClient(hostname: ollamaConfig.hostname, port: ollamaConfig.port)
        return ollamaClient!
    }

    func getDoclingClient() -> DoclingClient {
        // Always create new client to ensure we use the current configuration
        doclingClient = DoclingClient(hostname: doclingConfig.hostname, port: doclingConfig.port)
        return doclingClient!
    }

    func getAIClient() -> any AIProviderInterface {
        switch modelPreferences.aiProvider {
        case .ollama:
            return getOllamaClient()
        case .bedrock:
            return getBedrockClient()
        case .openAICompatible:
            return getOpenAICompatibleClient()
        case .mlx:
            return getMLXClient()
        }
    }

    func getMLXClient() -> MLXClient {
        if mlxClient == nil {
            mlxClient = MLXClient.shared

            // Set the current model if one is selected
            if let modelId = modelPreferences.mlxModelId {
                mlxClient?.currentModelId = modelId
            }

            // Set generation config
            mlxClient?.setGenerationConfig(mlxGenerationConfig)
        }
        return mlxClient!
    }

    func getOpenAICompatibleClient() -> OpenAICompatibleClient {
        if openAICompatibleClient == nil {
            let temperature = UserDefaults.standard.double(forKey: "openAICompatibleTemperature")
            let maxTokens = UserDefaults.standard.integer(forKey: "openAICompatibleMaxTokens")

            // Use defaults if not set
            let finalTemperature = temperature == 0 ? 0.1 : temperature
            let finalMaxTokens = maxTokens == 0 ? 2048 : maxTokens

            print("🔧 Creating new OpenAICompatibleClient:")
            print("   baseURL: '\(openAICompatibleBaseURL)'")
            print("   apiKey: '\(openAICompatibleAPIKey.isEmpty ? "(empty)" : "(has \(openAICompatibleAPIKey.count) chars)")'")
            print("   model: '\(modelPreferences.openAICompatibleModel)'")
            print("   temperature: \(finalTemperature)")
            print("   maxTokens: \(finalMaxTokens)")
            print("   contextSize: \(openAICompatibleContextSize)")

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
            print("🔧 Reusing existing OpenAICompatibleClient, updating model to: '\(modelPreferences.openAICompatibleModel)'")
            openAICompatibleClient?.updateDefaultModel(modelPreferences.openAICompatibleModel)
        }
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
    
    // Force recreation of clients when configuration changes
    func invalidateClients() {
        ollamaClient = nil
        doclingClient = nil
        openAICompatibleClient = nil
        mlxClient = nil
    }

    func invalidateOpenAICompatibleClient() {
        openAICompatibleClient = nil
    }

    func invalidateMLXClient() {
        mlxClient = nil
    }
    
    // MARK: - Validation

    func hasValidAWSCredentials() -> Bool {
        let credentials = AWSCredentialsManager.shared.credentials
        return credentials.isValid
    }

    func hasValidOpenAICompatibleConfig() -> Bool {
        return !openAICompatibleBaseURL.isEmpty && URL(string: openAICompatibleBaseURL) != nil
    }

    func hasValidMLXConfig() -> Bool {
        // MLX is valid if a model is selected and downloaded
        if let modelId = modelPreferences.mlxModelId {
            return MLXModelManager.shared.isModelDownloaded(modelId)
        }
        return false
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
        ollamaConfig = ServerConfigurationConstants.defaultOllamaConfig
        doclingConfig = ServerConfigurationConstants.defaultDoclingConfig
        ollamaStatus = .unknown
        doclingStatus = .unknown
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
    
    // MARK: - Model Management
    
    func fetchAvailableModels() async {
        modelSelection.isLoading = true
        modelSelection.error = nil
        
        do {
            let client = getOllamaClient()
            // Ensure we have an active connection before listing models
            if !client.isConnected {
                do {
                    _ = try await client.testConnection()
                } catch {
                    await MainActor.run {
                        self.modelSelection.error = "Unable to connect to Ollama: \(error.localizedDescription)"
                        self.modelSelection.isLoading = false
                    }
                    return
                }
            }
            let models = try await client.getAvailableModels()
            
            await MainActor.run {
                modelSelection.availableModels = models
                modelSelection.lastFetchTime = Date()
                modelSelection.isLoading = false

                // Respect persisted selections; only auto-select on first run
                if !loadedModelPrefsFromStorage {
                    autoSelectDefaultModels()
                }
            }
        } catch {
            await MainActor.run {
                modelSelection.error = error.localizedDescription
                modelSelection.isLoading = false
            }
        }
    }
    
    private func autoSelectDefaultModels() {
        let visionModels = modelSelection.availableModels.filter { $0.supportsVision }
        let allModels = modelSelection.availableModels
        
        // Auto-select chat model if current selection doesn't exist
        // Chat models can be either text-only OR vision models (for multimodal conversations)
        if !modelSelection.availableModels.contains(where: { $0.name == modelPreferences.chatModel }) {
            if let selectedChatModel = selectBestAvailableModel(from: allModels, preferences: preferredChatModels) {
                modelPreferences.chatModel = selectedChatModel.name
            }
        }
        
        // Auto-select vision model if current selection doesn't exist
        if !modelSelection.availableModels.contains(where: { $0.name == modelPreferences.visionModel }) {
            if let selectedVisionModel = selectBestAvailableModel(from: visionModels, preferences: preferredVisionModels) {
                modelPreferences.visionModel = selectedVisionModel.name
            }
        }
        
        saveSettings()
    }
    
    // MARK: - Model Selection Logic
    
    // Prioritized chat models (from legacy config + multimodal models)
    private let preferredChatModels = [
        "phi4-reasoning", // Prefix match
        "magistral",      // Prefix match  
        "qwen3:32b",
        "qwen3:30b", 
        "gemma3:27b",
        "qwen3:14b"
    ]
    
    // Prioritized vision models (from legacy config)
    private let preferredVisionModels = [
        "mistral-small3.2",     // Prefix match
        "qwen2.5vl:72b",
        "qwen2.5vl:32b", 
        "qwen2.5vl:7b",
        "gemma3:27b",
        "gemma3:12b",
        "llama3.2-vision:11b"
    ]
    
    private func selectBestAvailableModel(from availableModels: [OllamaModel], preferences: [String]) -> OllamaModel? {
        // First, try to find exact matches in preference order
        for preferredName in preferences {
            if let exactMatch = availableModels.first(where: { $0.name == preferredName }) {
                return exactMatch
            }
        }
        
        // Then try prefix matches for models that support it
        let prefixModels = ["phi4-reasoning", "magistral", "mistral-small3.2"]
        for preferredPrefix in prefixModels {
            if preferences.contains(preferredPrefix) {
                if let prefixMatch = availableModels.first(where: { $0.name.lowercased().hasPrefix(preferredPrefix.lowercased()) }) {
                    return prefixMatch
                }
            }
        }
        
        // Finally, fall back to first available model if no preferences match
        return availableModels.first
    }
    
    func refreshModelsIfNeeded() async {
        let cacheTimeout: TimeInterval = 300 // 5 minutes

        if let lastFetch = modelSelection.lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout {
            return // Cache is still valid
        }

        await fetchAvailableModels()
    }

    // MARK: - Backup Management

    private func setupBackupManager() async {
        backupManager = iCloudBackupManager.shared

        // Configure the backup manager with this settings manager to avoid circular dependency
        backupManager?.configure(with: self)

        // Enable/disable backup based on settings
        Task { @MainActor in
            if backupSettings.iCloudEnabled {
                try? await backupManager?.enableBackup()
            } else {
                backupManager?.disableBackup()
            }
        }
    }

    func enableiCloudBackup() async throws {
        guard let backupManager = backupManager else { return }

        try await backupManager.enableBackup()
        backupSettings.iCloudEnabled = true
        saveSettings()
    }

    func disableiCloudBackup() {
        guard let backupManager = backupManager else { return }

        backupManager.disableBackup()
        backupSettings.iCloudEnabled = false
        saveSettings()
    }

    func performManualBackup() async {
        await backupManager?.performManualBackup()
    }

    func fetchAvailableBackups() async {
        await backupManager?.fetchAvailableBackups()
    }

    func restoreFromBackup(_ metadata: BackupMetadata) async {
        await backupManager?.restoreFromBackup(metadata)
    }
}

// MARK: - Codable Extensions

extension ServerConfiguration: Codable {}
extension BackupSettings: Codable {}
extension AppPreferences: Codable {}
extension ModelPreferences: Codable {
    enum CodingKeys: String, CodingKey {
        case aiProvider
        case chatModel
        case visionModel
        case documentModel
        case openAICompatibleModel
        case bedrockModel
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode with defaults for backwards compatibility
        self.aiProvider = try container.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? .ollama
        self.chatModel = try container.decode(String.self, forKey: .chatModel)
        self.visionModel = try container.decode(String.self, forKey: .visionModel)
        self.documentModel = try container.decode(String.self, forKey: .documentModel)
        self.openAICompatibleModel = try container.decodeIfPresent(String.self, forKey: .openAICompatibleModel) ?? ""
        self.bedrockModel = try container.decodeIfPresent(String.self, forKey: .bedrockModel) ?? AWSBedrockModel.claudeSonnet45.rawValue
        self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(aiProvider, forKey: .aiProvider)
        try container.encode(chatModel, forKey: .chatModel)
        try container.encode(visionModel, forKey: .visionModel)
        try container.encode(documentModel, forKey: .documentModel)
        try container.encode(openAICompatibleModel, forKey: .openAICompatibleModel)
        try container.encode(bedrockModel, forKey: .bedrockModel)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}
extension AIProvider: Codable {}
extension Theme: Codable {}
extension BackupFrequency: Codable {}
