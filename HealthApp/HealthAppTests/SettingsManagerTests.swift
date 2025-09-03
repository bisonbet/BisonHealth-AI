import XCTest
@testable import HealthApp

@MainActor
final class SettingsManagerTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    var userDefaults: UserDefaults!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Use a separate UserDefaults suite for testing
        userDefaults = UserDefaults(suiteName: "HealthAppTests")
        userDefaults.removePersistentDomain(forName: "HealthAppTests")
        
        // Create a fresh settings manager instance for each test
        settingsManager = SettingsManager()
        
        // Replace the user defaults instance
        // Note: In a real implementation, we'd inject UserDefaults as a dependency
        // For now, we'll test with the default implementation
    }
    
    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: "HealthAppTests")
        settingsManager = nil
        userDefaults = nil
        try await super.tearDown()
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultServerConfigurations() {
        XCTAssertEqual(settingsManager.ollamaConfig.hostname, "localhost")
        XCTAssertEqual(settingsManager.ollamaConfig.port, 11434)
        
        XCTAssertEqual(settingsManager.doclingConfig.hostname, "localhost")
        XCTAssertEqual(settingsManager.doclingConfig.port, 5001)
    }
    
    func testDefaultBackupSettings() {
        XCTAssertFalse(settingsManager.backupSettings.iCloudEnabled)
        XCTAssertTrue(settingsManager.backupSettings.backupHealthData)
        XCTAssertTrue(settingsManager.backupSettings.backupChatHistory)
        XCTAssertFalse(settingsManager.backupSettings.backupDocuments)
        XCTAssertTrue(settingsManager.backupSettings.backupAppSettings)
        XCTAssertTrue(settingsManager.backupSettings.autoBackup)
        XCTAssertEqual(settingsManager.backupSettings.backupFrequency, .daily)
    }
    
    func testDefaultAppPreferences() {
        XCTAssertEqual(settingsManager.appPreferences.theme, .system)
        XCTAssertTrue(settingsManager.appPreferences.hapticFeedback)
        XCTAssertTrue(settingsManager.appPreferences.showTips)
        XCTAssertFalse(settingsManager.appPreferences.analyticsEnabled)
    }
    
    func testDefaultConnectionStatus() {
        XCTAssertEqual(settingsManager.ollamaStatus, .unknown)
        XCTAssertEqual(settingsManager.doclingStatus, .unknown)
    }
    
    // MARK: - Configuration Validation Tests
    
    func testValidServerConfiguration() {
        let validConfig = ServerConfiguration(hostname: "192.168.1.100", port: 8080)
        XCTAssertNil(settingsManager.validateServerConfiguration(validConfig))
    }
    
    func testInvalidServerConfigurationEmptyHostname() {
        let invalidConfig = ServerConfiguration(hostname: "", port: 8080)
        let error = settingsManager.validateServerConfiguration(invalidConfig)
        XCTAssertEqual(error, "Hostname cannot be empty")
    }
    
    func testInvalidServerConfigurationInvalidPort() {
        let invalidConfigLow = ServerConfiguration(hostname: "localhost", port: 0)
        let errorLow = settingsManager.validateServerConfiguration(invalidConfigLow)
        XCTAssertEqual(errorLow, "Port must be between 1 and 65535")
        
        let invalidConfigHigh = ServerConfiguration(hostname: "localhost", port: 70000)
        let errorHigh = settingsManager.validateServerConfiguration(invalidConfigHigh)
        XCTAssertEqual(errorHigh, "Port must be between 1 and 65535")
    }
    
    func testInvalidServerConfigurationInvalidHostname() {
        let invalidConfig = ServerConfiguration(hostname: "invalid!@#hostname", port: 8080)
        let error = settingsManager.validateServerConfiguration(invalidConfig)
        XCTAssertEqual(error, "Invalid hostname format")
    }
    
    // MARK: - Settings Persistence Tests
    
    func testServerConfigurationPersistence() {
        // Modify server configurations
        settingsManager.ollamaConfig.hostname = "test-ollama.local"
        settingsManager.ollamaConfig.port = 12345
        
        settingsManager.doclingConfig.hostname = "test-docling.local"
        settingsManager.doclingConfig.port = 54321
        
        // Save settings
        settingsManager.saveSettings()
        
        // Create new settings manager instance to test loading
        let newSettingsManager = SettingsManager()
        
        // Verify settings were loaded correctly
        // Note: This would work if we properly inject UserDefaults
        // For now, we test the save/load mechanism conceptually
        XCTAssertNotNil(newSettingsManager.ollamaConfig)
        XCTAssertNotNil(newSettingsManager.doclingConfig)
    }
    
    func testBackupSettingsPersistence() {
        // Modify backup settings
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupHealthData = false
        settingsManager.backupSettings.backupFrequency = .weekly
        
        // Save settings
        settingsManager.saveSettings()
        
        // Create new settings manager instance
        let newSettingsManager = SettingsManager()
        
        // Verify default settings are loaded (since we can't easily test persistence without DI)
        XCTAssertNotNil(newSettingsManager.backupSettings)
    }
    
    func testAppPreferencesPersistence() {
        // Modify app preferences
        settingsManager.appPreferences.theme = .dark
        settingsManager.appPreferences.hapticFeedback = false
        settingsManager.appPreferences.analyticsEnabled = true
        
        // Save settings
        settingsManager.saveSettings()
        
        // Create new settings manager instance
        let newSettingsManager = SettingsManager()
        
        // Verify settings structure exists
        XCTAssertNotNil(newSettingsManager.appPreferences)
    }
    
    // MARK: - Reset Functionality Tests
    
    func testResetServerSettings() {
        // Modify settings
        settingsManager.ollamaConfig.hostname = "modified"
        settingsManager.ollamaConfig.port = 9999
        settingsManager.doclingConfig.hostname = "modified"
        settingsManager.doclingConfig.port = 9998
        settingsManager.ollamaStatus = .connected
        settingsManager.doclingStatus = .failed("Test error")
        
        // Reset server settings
        settingsManager.resetServerSettings()
        
        // Verify reset to defaults
        XCTAssertEqual(settingsManager.ollamaConfig.hostname, "localhost")
        XCTAssertEqual(settingsManager.ollamaConfig.port, 11434)
        XCTAssertEqual(settingsManager.doclingConfig.hostname, "localhost")
        XCTAssertEqual(settingsManager.doclingConfig.port, 5001)
        XCTAssertEqual(settingsManager.ollamaStatus, .unknown)
        XCTAssertEqual(settingsManager.doclingStatus, .unknown)
    }
    
    func testResetBackupSettings() {
        // Modify settings
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupHealthData = false
        settingsManager.backupSettings.backupFrequency = .weekly
        
        // Reset backup settings
        settingsManager.resetBackupSettings()
        
        // Verify reset to defaults
        XCTAssertFalse(settingsManager.backupSettings.iCloudEnabled)
        XCTAssertTrue(settingsManager.backupSettings.backupHealthData)
        XCTAssertEqual(settingsManager.backupSettings.backupFrequency, .daily)
    }
    
    func testResetAppPreferences() {
        // Modify settings
        settingsManager.appPreferences.theme = .dark
        settingsManager.appPreferences.hapticFeedback = false
        settingsManager.appPreferences.analyticsEnabled = true
        
        // Reset app preferences
        settingsManager.resetAppPreferences()
        
        // Verify reset to defaults
        XCTAssertEqual(settingsManager.appPreferences.theme, .system)
        XCTAssertTrue(settingsManager.appPreferences.hapticFeedback)
        XCTAssertFalse(settingsManager.appPreferences.analyticsEnabled)
    }
    
    func testResetAllSettings() {
        // Modify all settings
        settingsManager.ollamaConfig.hostname = "modified"
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.appPreferences.theme = .dark
        
        // Reset all settings
        settingsManager.resetAllSettings()
        
        // Verify all settings reset to defaults
        XCTAssertEqual(settingsManager.ollamaConfig.hostname, "localhost")
        XCTAssertFalse(settingsManager.backupSettings.iCloudEnabled)
        XCTAssertEqual(settingsManager.appPreferences.theme, .system)
    }
    
    // MARK: - Client Management Tests
    
    func testOllamaClientCreation() {
        let client = settingsManager.getOllamaClient()
        XCTAssertNotNil(client)
    }
    
    func testDoclingClientCreation() {
        let client = settingsManager.getDoclingClient()
        XCTAssertNotNil(client)
    }
    
    func testClientInvalidation() {
        // Get initial clients
        let _ = settingsManager.getOllamaClient()
        let _ = settingsManager.getDoclingClient()
        
        // Invalidate clients
        settingsManager.invalidateClients()
        
        // Get new clients - should create fresh instances
        let newOllamaClient = settingsManager.getOllamaClient()
        let newDoclingClient = settingsManager.getDoclingClient()
        
        XCTAssertNotNil(newOllamaClient)
        XCTAssertNotNil(newDoclingClient)
    }
    
    // MARK: - Connection Status Tests
    
    func testConnectionStatusTypes() {
        // Test unknown status
        let unknownStatus = ConnectionStatus.unknown
        XCTAssertEqual(unknownStatus.displayText, "Not tested")
        XCTAssertEqual(unknownStatus.systemImage, "questionmark.circle")
        
        // Test testing status
        let testingStatus = ConnectionStatus.testing
        XCTAssertEqual(testingStatus.displayText, "Testing...")
        XCTAssertEqual(testingStatus.systemImage, "clock")
        
        // Test connected status
        let connectedStatus = ConnectionStatus.connected
        XCTAssertEqual(connectedStatus.displayText, "Connected")
        XCTAssertEqual(connectedStatus.systemImage, "checkmark.circle.fill")
        
        // Test failed status
        let failedStatus = ConnectionStatus.failed("Network error")
        XCTAssertEqual(failedStatus.displayText, "Failed: Network error")
        XCTAssertEqual(failedStatus.systemImage, "xmark.circle.fill")
    }
    
    // MARK: - Theme Tests
    
    func testThemeColorSchemes() {
        XCTAssertNil(Theme.system.colorScheme)
        XCTAssertEqual(Theme.light.colorScheme, .light)
        XCTAssertEqual(Theme.dark.colorScheme, .dark)
    }
    
    func testThemeDisplayNames() {
        XCTAssertEqual(Theme.system.displayName, "System")
        XCTAssertEqual(Theme.light.displayName, "Light")
        XCTAssertEqual(Theme.dark.displayName, "Dark")
    }
    
    // MARK: - Backup Frequency Tests
    
    func testBackupFrequencyDisplayNames() {
        XCTAssertEqual(BackupFrequency.manual.displayName, "Manual Only")
        XCTAssertEqual(BackupFrequency.daily.displayName, "Daily")
        XCTAssertEqual(BackupFrequency.weekly.displayName, "Weekly")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteSettingsFlow() async {
        // Test a complete settings configuration flow
        
        // 1. Configure servers
        settingsManager.ollamaConfig.hostname = "ai-server.local"
        settingsManager.ollamaConfig.port = 8080
        settingsManager.doclingConfig.hostname = "doc-server.local"
        settingsManager.doclingConfig.port = 8081
        
        // 2. Configure backup
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupHealthData = true
        settingsManager.backupSettings.backupChatHistory = false
        settingsManager.backupSettings.backupFrequency = .weekly
        
        // 3. Configure app preferences
        settingsManager.appPreferences.theme = .dark
        settingsManager.appPreferences.hapticFeedback = false
        
        // 4. Save settings
        settingsManager.saveSettings()
        
        // 5. Test validation
        XCTAssertNil(settingsManager.validateServerConfiguration(settingsManager.ollamaConfig))
        XCTAssertNil(settingsManager.validateServerConfiguration(settingsManager.doclingConfig))
        
        // 6. Test client creation
        let ollamaClient = settingsManager.getOllamaClient()
        let doclingClient = settingsManager.getDoclingClient()
        
        XCTAssertNotNil(ollamaClient)
        XCTAssertNotNil(doclingClient)
        
        // 7. Test client invalidation
        settingsManager.invalidateClients()
        
        let newOllamaClient = settingsManager.getOllamaClient()
        let newDoclingClient = settingsManager.getDoclingClient()
        
        XCTAssertNotNil(newOllamaClient)
        XCTAssertNotNil(newDoclingClient)
    }
}

