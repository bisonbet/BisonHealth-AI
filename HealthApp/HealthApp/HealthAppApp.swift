import SwiftUI
import Combine

@main
struct HealthAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettingsManager = AppSettingsManager.shared
    
    var body: some Scene {
        WindowGroup {
            if appSettingsManager.shouldShowDisclaimer {
                FirstLaunchDisclaimerView {
                    appSettingsManager.acceptDisclaimer()
                }
            } else {
                ContentView()
                    .environmentObject(appState)
                    .preferredColorScheme(appState.colorScheme)
            }
        }
    }
}

// MARK: - App State Management
@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil

    private let settingsManager = SettingsManager.shared
    private let healthDataManager = HealthDataManager.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize app state
        setupColorScheme()
        observeSettingsChanges()
        syncHealthKitOnLaunch()
    }

    private func syncHealthKitOnLaunch() {
        // Sync from Apple Health on app launch with throttling
        Task {
            do {
                // Check if we should sync (throttle to once every 4 hours)
                if let lastSync = UserDefaults.standard.object(forKey: "lastHealthKitSyncDate") as? Date {
                    let hoursSinceLastSync = Date().timeIntervalSince(lastSync) / 3600
                    if hoursSinceLastSync < 4 {
                        logger.info("App launch: Skipping HealthKit sync (last sync was \(String(format: "%.1f", hoursSinceLastSync)) hours ago)")
                        return
                    }
                }

                logger.info("App launch: Attempting HealthKit sync")
                try await healthDataManager.syncFromAppleHealth()

                // Save sync timestamp
                UserDefaults.standard.set(Date(), forKey: "lastHealthKitSyncDate")

                logger.info("App launch: HealthKit sync completed successfully")
            } catch {
                // Silently fail if HealthKit is not available or authorized
                // The user can manually trigger sync from settings if needed
                logger.warning("App launch: HealthKit sync failed (this is normal if not authorized): \(error.localizedDescription)")
            }
        }
    }
    
    private func setupColorScheme() {
        // Get initial theme from settings
        colorScheme = settingsManager.appPreferences.theme.colorScheme
    }
    
    private func observeSettingsChanges() {
        // Observe settings changes to update app state using Combine
        settingsManager.$appPreferences
            .map { $0.theme.colorScheme }
            .removeDuplicates()
            .assign(to: &$colorScheme)
    }
}