import Foundation
import SwiftUI

// MARK: - App Settings Manager
@MainActor
class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()
    
    @Published var hasAcceptedDisclaimer: Bool = false
    @Published var isFirstLaunch: Bool = true
    @Published var needsDisclaimerReacceptance: Bool = false
    
    private let databaseManager: DatabaseManager
    
    private init() {
        self.databaseManager = DatabaseManager.shared
        loadSettings()
    }
    
    // MARK: - Settings Loading
    
    private func loadSettings() {
        do {
            // Check if user has accepted disclaimer
            hasAcceptedDisclaimer = try databaseManager.hasAcceptedDisclaimer()
            
            // Check if this is first launch
            isFirstLaunch = try databaseManager.isFirstLaunch()
            
            // Check if disclaimer needs re-acceptance
            needsDisclaimerReacceptance = try databaseManager.needsDisclaimerReacceptance()
            
        } catch {
            print("❌ Failed to load app settings: \(error)")
            // Default to showing disclaimer on error
            hasAcceptedDisclaimer = false
            isFirstLaunch = true
            needsDisclaimerReacceptance = true
        }
    }
    
    // MARK: - Disclaimer Management
    
    /// Accept the disclaimer and mark first launch as completed
    func acceptDisclaimer() {
        do {
            try databaseManager.acceptDisclaimer()
            
            // Update published properties
            hasAcceptedDisclaimer = true
            isFirstLaunch = false
            needsDisclaimerReacceptance = false
            
            print("✅ Disclaimer accepted and stored in database")
            
        } catch {
            print("❌ Failed to accept disclaimer: \(error)")
        }
    }
    
    /// Reset disclaimer acceptance (for testing or if user wants to re-accept)
    func resetDisclaimerAcceptance() {
        do {
            try databaseManager.resetDisclaimerAcceptance()
            
            // Update published properties
            hasAcceptedDisclaimer = false
            isFirstLaunch = true
            needsDisclaimerReacceptance = true
            
            print("🔄 Disclaimer acceptance reset")
            
        } catch {
            print("❌ Failed to reset disclaimer acceptance: \(error)")
        }
    }
    
    /// Check if disclaimer needs to be shown
    var shouldShowDisclaimer: Bool {
        return !hasAcceptedDisclaimer || needsDisclaimerReacceptance
    }
    
    // MARK: - Generic Settings Management
    
    /// Set a generic app setting
    func setSetting(key: String, value: String) {
        do {
            try databaseManager.setAppSetting(key: key, value: value)
        } catch {
            print("❌ Failed to set app setting '\(key)': \(error)")
        }
    }
    
    /// Get a generic app setting
    func getSetting(key: String) -> String? {
        do {
            return try databaseManager.getAppSetting(key: key)
        } catch {
            print("❌ Failed to get app setting '\(key)': \(error)")
            return nil
        }
    }
    
    /// Delete a generic app setting
    func deleteSetting(key: String) {
        do {
            try databaseManager.deleteAppSetting(key: key)
        } catch {
            print("❌ Failed to delete app setting '\(key)': \(error)")
        }
    }
    
    // MARK: - App State Management
    
    /// Refresh settings from database
    func refreshSettings() {
        loadSettings()
    }
    
    /// Get app version info
    var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    /// Get build number
    var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
