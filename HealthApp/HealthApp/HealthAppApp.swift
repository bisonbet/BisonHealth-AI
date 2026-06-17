import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@main
struct HealthAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettingsManager = AppSettingsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppChrome.configure()
    }
    
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
        .onChange(of: scenePhase) { _, newPhase in
            appState.handleScenePhaseChange(newPhase)
        }
    }
}

// MARK: - App Chrome

private enum AppChrome {
    static func configure() {
        #if os(iOS)
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor.bisonAppBackground
        navigationAppearance.shadowColor = UIColor.bisonSeparator
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.bisonPrimaryText
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.bisonPrimaryText
        ]
        navigationAppearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.bisonGold
        ]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = UIColor.bisonGold

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.bisonSidebarBackground
        tabAppearance.shadowColor = UIColor.bisonSeparator

        let selectedTabAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.bisonGold
        ]
        let normalTabAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.bisonSecondaryText
        ]

        [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ].forEach { itemAppearance in
            itemAppearance.selected.iconColor = UIColor.bisonGold
            itemAppearance.selected.titleTextAttributes = selectedTabAttributes
            itemAppearance.normal.iconColor = UIColor.bisonSecondaryText
            itemAppearance.normal.titleTextAttributes = normalTabAttributes
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor.bisonGold
        UITabBar.appearance().unselectedItemTintColor = UIColor.bisonSecondaryText

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor.bisonGold
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor.bisonInkOnGold],
            for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor.bisonPrimaryText],
            for: .normal
        )

        UISwitch.appearance().onTintColor = UIColor.bisonSage
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.bisonGold
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.bisonSecondaryText.withAlphaComponent(0.35)
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    static var bisonPrimaryText: UIColor {
        dynamicColor(
            light: UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1.0),
            dark: UIColor(red: 0.91, green: 0.88, blue: 0.82, alpha: 1.0)
        )
    }

    static var bisonSecondaryText: UIColor {
        dynamicColor(
            light: UIColor(red: 0.30, green: 0.38, blue: 0.43, alpha: 1.0),
            dark: UIColor(red: 0.61, green: 0.70, blue: 0.74, alpha: 1.0)
        )
    }

    static var bisonGold: UIColor {
        dynamicColor(
            light: UIColor(red: 0.78, green: 0.55, blue: 0.16, alpha: 1.0),
            dark: UIColor(red: 0.93, green: 0.70, blue: 0.28, alpha: 1.0)
        )
    }

    static var bisonInkOnGold: UIColor {
        UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1.0)
    }

    static var bisonSage: UIColor {
        dynamicColor(
            light: UIColor(red: 0.23, green: 0.47, blue: 0.39, alpha: 1.0),
            dark: UIColor(red: 0.45, green: 0.69, blue: 0.58, alpha: 1.0)
        )
    }

    static var bisonAppBackground: UIColor {
        dynamicColor(
            light: UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0),
            dark: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1.0)
        )
    }

    static var bisonSidebarBackground: UIColor {
        dynamicColor(
            light: UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0),
            dark: UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1.0)
        )
    }

    static var bisonSeparator: UIColor {
        dynamicColor(
            light: UIColor(red: 0.48, green: 0.29, blue: 0.16, alpha: 0.18),
            dark: UIColor(red: 0.93, green: 0.70, blue: 0.28, alpha: 0.18)
        )
    }

    static func dynamicColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }
}
#endif

// MARK: - App State Management
@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil

    private let settingsManager = SettingsManager.shared
    private let healthDataManager = HealthDataManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize crash detection
        AppLog.shared.markLaunch()

        // Initialize app state
        setupColorScheme()
        observeSettingsChanges()
        syncHealthKitOnLaunch()
        preloadOnDeviceLLMIfNeeded()
    }

    private func preloadOnDeviceLLMIfNeeded() {
        // Preload on-device LLM in background so it's ready when user opens AI chat
        // This is done after a short delay to not compete with app launch tasks
        Task {
            // Small delay to let the app finish launching
            try? await Task.sleep(for: .seconds(2))
            settingsManager.preloadOnDeviceLLMIfNeeded()
        }
    }

    private func syncHealthKitOnLaunch() {
        // Sync from Apple Health on app launch with throttling
        Task {
            do {
                // Check if we should sync (throttle to once every 4 hours)
                // Use the same key as HealthKitManager for consistency
                if let lastSync = UserDefaults.standard.object(forKey: "healthKitLastSyncDate") as? Date {
                    let hoursSinceLastSync = Date().timeIntervalSince(lastSync) / 3600
                    if hoursSinceLastSync < 4 {
                        AppLog.shared.general("App launch: Skipping HealthKit sync (last sync was \(String(format: "%.1f", hoursSinceLastSync)) hours ago)")
                        return
                    }
                }

                AppLog.shared.general("App launch: Attempting HealthKit sync")
                try await healthDataManager.syncFromAppleHealth()

                // HealthKitManager will automatically save the sync timestamp
                AppLog.shared.general("App launch: HealthKit sync completed successfully")
            } catch {
                // Silently fail if HealthKit is not available or authorized
                // The user can manually trigger sync from settings if needed
                AppLog.shared.general("App launch: HealthKit sync failed (this is normal if not authorized): \(error.localizedDescription)", level: .warning)
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

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await settingsManager.resumeOnDeviceLLMAfterForeground()
            }
        case .inactive, .background:
            AppLog.shared.markCleanShutdown()
            Task {
                await settingsManager.suspendOnDeviceLLMForBackground()
            }
        @unknown default:
            break
        }
    }
}
