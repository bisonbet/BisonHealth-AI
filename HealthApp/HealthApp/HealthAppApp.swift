import SwiftUI

@main
struct HealthAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audioRecordingManager = AudioRecordingManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
                .overlay(alignment: .top) {
                    if audioRecordingManager.isRecording {
                        AudioRecordingBanner(audioRecordingManager: audioRecordingManager)
                            .padding()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: audioRecordingManager.isRecording)
                .alert(
                    "Recording Unavailable",
                    isPresented: Binding(
                        get: { audioRecordingManager.errorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                audioRecordingManager.clearError()
                            }
                        }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        audioRecordingManager.clearError()
                    }
                } message: {
                    Text(audioRecordingManager.errorMessage ?? "")
                }
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await audioRecordingManager.handleAppBecameActive()
            }
        }
    }
}

// MARK: - App State Management
@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    
    private let settingsManager = SettingsManager.shared
    
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
        // Observe settings changes to update app state
        // This would typically use Combine in a more complex app
        colorScheme = settingsManager.appPreferences.theme.colorScheme
    }
}