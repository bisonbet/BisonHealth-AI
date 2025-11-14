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
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Initialize app state
        setupColorScheme()
        observeSettingsChanges()
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