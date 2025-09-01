import SwiftUI

@main
struct HealthAppApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}

// MARK: - App State Management
@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    
    init() {
        // Initialize app state
        setupColorScheme()
    }
    
    private func setupColorScheme() {
        // Auto-detect system color scheme
        colorScheme = nil // nil means follow system setting
    }
}