import Foundation
import SQLite

// MARK: - App Settings Database Operations
extension DatabaseManager {
    
    // MARK: - App Settings Table
    private var appSettingsTable: Table { Table("app_settings") }
    private var settingKey: SQLite.Expression<String> { SQLite.Expression<String>("key") }
    private var settingValue: SQLite.Expression<String> { SQLite.Expression<String>("value") }
    private var settingCreatedAt: SQLite.Expression<Int64> { SQLite.Expression<Int64>("created_at") }
    private var settingUpdatedAt: SQLite.Expression<Int64> { SQLite.Expression<Int64>("updated_at") }
    
    // MARK: - App Settings Keys
    private enum AppSettingKey: String, CaseIterable {
        case disclaimerAccepted = "disclaimer_accepted"
        case firstLaunchCompleted = "first_launch_completed"
        case appVersion = "app_version"
        case lastDisclaimerVersion = "last_disclaimer_version"
    }
    
    // MARK: - Create App Settings Table
    func createAppSettingsTable() throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        try db.run(appSettingsTable.create(ifNotExists: true) { t in
            t.column(settingKey, primaryKey: true)
            t.column(settingValue)
            t.column(settingCreatedAt)
            t.column(settingUpdatedAt)
        })
        
        // Create index for faster lookups
        try db.run("CREATE INDEX IF NOT EXISTS idx_app_settings_key ON app_settings(key)")
    }
    
    // MARK: - Disclaimer Acceptance Management
    
    /// Check if the user has accepted the current disclaimer
    func hasAcceptedDisclaimer() throws -> Bool {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = appSettingsTable
            .filter(settingKey == AppSettingKey.disclaimerAccepted.rawValue)
            .limit(1)
        
        if let row = try db.pluck(query) {
            return row[settingValue] == "true"
        }
        
        return false
    }
    
    /// Mark that the user has accepted the disclaimer
    func acceptDisclaimer() throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let now = Int64(Date().timeIntervalSince1970)
        
        // Insert or update the disclaimer acceptance
        try db.run(appSettingsTable.insert(
            or: .replace,
            settingKey <- AppSettingKey.disclaimerAccepted.rawValue,
            settingValue <- "true",
            settingCreatedAt <- now,
            settingUpdatedAt <- now
        ))
        
        // Also mark first launch as completed
        try db.run(appSettingsTable.insert(
            or: .replace,
            settingKey <- AppSettingKey.firstLaunchCompleted.rawValue,
            settingValue <- "true",
            settingCreatedAt <- now,
            settingUpdatedAt <- now
        ))
        
        // Store the current app version for future reference
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        try db.run(appSettingsTable.insert(
            or: .replace,
            settingKey <- AppSettingKey.appVersion.rawValue,
            settingValue <- currentVersion,
            settingCreatedAt <- now,
            settingUpdatedAt <- now
        ))
        
        // Store disclaimer version (increment this if disclaimer content changes)
        let disclaimerVersion = "1.0"
        try db.run(appSettingsTable.insert(
            or: .replace,
            settingKey <- AppSettingKey.lastDisclaimerVersion.rawValue,
            settingValue <- disclaimerVersion,
            settingCreatedAt <- now,
            settingUpdatedAt <- now
        ))
    }
    
    /// Check if this is the first launch of the app
    func isFirstLaunch() throws -> Bool {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = appSettingsTable
            .filter(settingKey == AppSettingKey.firstLaunchCompleted.rawValue)
            .limit(1)
        
        if let row = try db.pluck(query) {
            return row[settingValue] != "true"
        }
        
        return true // If no record exists, it's the first launch
    }
    
    /// Reset disclaimer acceptance (for testing or if user wants to re-accept)
    func resetDisclaimerAcceptance() throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        try db.run(appSettingsTable.filter(settingKey == AppSettingKey.disclaimerAccepted.rawValue).delete())
        try db.run(appSettingsTable.filter(settingKey == AppSettingKey.firstLaunchCompleted.rawValue).delete())
    }
    
    /// Get the last accepted disclaimer version
    func getLastDisclaimerVersion() throws -> String? {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = appSettingsTable
            .filter(settingKey == AppSettingKey.lastDisclaimerVersion.rawValue)
            .limit(1)
        
        if let row = try db.pluck(query) {
            return row[settingValue]
        }
        
        return nil
    }
    
    /// Check if disclaimer needs to be re-accepted (e.g., if content changed)
    func needsDisclaimerReacceptance() throws -> Bool {
        let currentDisclaimerVersion = "1.0"
        let lastAcceptedVersion = try getLastDisclaimerVersion()
        
        // If no version stored, needs acceptance
        guard let lastVersion = lastAcceptedVersion else { return true }
        
        // If versions don't match, needs re-acceptance
        return lastVersion != currentDisclaimerVersion
    }
    
    // MARK: - Generic App Settings Management
    
    /// Set a generic app setting
    func setAppSetting(key: String, value: String) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let now = Int64(Date().timeIntervalSince1970)
        
        try db.run(appSettingsTable.insert(
            or: .replace,
            settingKey <- key,
            settingValue <- value,
            settingCreatedAt <- now,
            settingUpdatedAt <- now
        ))
    }
    
    /// Get a generic app setting
    func getAppSetting(key: String) throws -> String? {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = appSettingsTable
            .filter(settingKey == key)
            .limit(1)
        
        if let row = try db.pluck(query) {
            return row[settingValue]
        }
        
        return nil
    }
    
    /// Delete a generic app setting
    func deleteAppSetting(key: String) throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        try db.run(appSettingsTable.filter(settingKey == key).delete())
    }
}
