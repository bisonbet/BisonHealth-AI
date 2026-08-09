import SwiftUI
import Combine
import Foundation
#if os(iOS)
import UIKit
#endif

@main
struct HealthAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettingsManager = AppSettingsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    static let legacyPendingOperationsKey = "com.bisonhealth.pendingoperations"

    init() {
        Self.removeLegacyPendingOperations()
        AppChrome.configure()
        AppTestRuntimeBootstrap.bootstrapIfNeeded()
    }

    static func removeLegacyPendingOperations(from userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: legacyPendingOperationsKey)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appSettingsManager.shouldShowDisclaimer && !AppTestRuntime.shouldSkipDisclaimer {
                    FirstLaunchDisclaimerView {
                        appSettingsManager.acceptDisclaimer()
                    }
                } else {
                    ContentView()
                        .environmentObject(appState)
                        .preferredColorScheme(appState.colorScheme)
                }
            }
            .alert("Unexpected Shutdown Detected", isPresented: $appState.showCrashReportAlert) {
                Button("Share Logs") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let rootVC = windowScene.windows.first?.rootViewController else { return }
                        LogExporter.exportLogs(from: rootVC, context: .crashReport)
                    }
                }
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text("The app didn't close properly last time. You can share diagnostic logs to help investigate — no data leaves your device without your action.")
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
    @Published var showCrashReportAlert = false

    private let settingsManager = SettingsManager.shared
    private let healthDataManager = HealthDataManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        AppLog.shared.markLaunch()
        if !AppTestRuntime.isUITesting && AppLog.shared.previousSessionCrashed {
            showCrashReportAlert = true
        }

        setupColorScheme()
        observeSettingsChanges()
        syncHealthKitOnLaunch()
        preloadOnDeviceLLMIfNeeded()
    }

    private func preloadOnDeviceLLMIfNeeded() {
        guard !AppTestRuntime.shouldDisableMLXPreload else { return }

        // Preload on-device LLM in background so it's ready when user opens AI chat
        // This is done after a short delay to not compete with app launch tasks
        Task {
            // Small delay to let the app finish launching
            try? await Task.sleep(for: .seconds(2))
            settingsManager.preloadOnDeviceLLMIfNeeded()
        }
    }

    private func syncHealthKitOnLaunch() {
        guard !AppTestRuntime.shouldDisableHealthKitSync else { return }

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
            AppLog.shared.markSessionActive()
            Task {
                await settingsManager.resumeOnDeviceLLMAfterForeground()
            }
        case .inactive:
            break
        case .background:
            AppLog.shared.markCleanShutdown()
            Task {
                await settingsManager.suspendOnDeviceLLMForBackground()
            }
        @unknown default:
            break
        }
    }
}

// MARK: - UI Test Runtime

enum AppTestRuntime {
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    static var isRunningXCTest: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment.keys.contains("XCTestConfigurationFilePath")
            || environment["XCTestSessionIdentifier"] != nil
        #else
        return false
        #endif
    }

    static var shouldResetTestData: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--reset-test-data")
        #else
        false
        #endif
    }

    static var shouldSkipDisclaimer: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--skip-disclaimer")
        #else
        false
        #endif
    }

    static var shouldSeedLabReport: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--seed-lab-report")
        #else
        false
        #endif
    }

    static var shouldUseScriptedAIProvider: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--scripted-ai-provider")
        #else
        false
        #endif
    }

    static var shouldDisableHealthKitSync: Bool {
        #if DEBUG
        isRunningXCTest || (isUITesting && ProcessInfo.processInfo.arguments.contains("--disable-healthkit-sync"))
        #else
        false
        #endif
    }

    static var shouldDisableMLXPreload: Bool {
        #if DEBUG
        isRunningXCTest || (isUITesting && ProcessInfo.processInfo.arguments.contains("--disable-mlx-preload"))
        #else
        false
        #endif
    }

    static func databaseURLForUITesting() -> URL? {
        #if DEBUG
        guard isUITesting else { return nil }
        prepareTestStorageIfNeeded()
        let directory = testRootDirectory.appendingPathComponent("Database", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("health_data.sqlite")
        #else
        return nil
        #endif
    }

    static func fileSystemBaseDirectoryForUITesting() -> URL? {
        #if DEBUG
        guard isUITesting else { return nil }
        prepareTestStorageIfNeeded()
        let directory = testRootDirectory.appendingPathComponent("Files/HealthApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static var testRootDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("BisonHealthAIRegressionUITests", isDirectory: true)
    }

    private static func prepareTestStorageIfNeeded() {
        guard shouldResetTestData else { return }

        let marker = testRootDirectory.appendingPathComponent(".reset-\(ProcessInfo.processInfo.processIdentifier)")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        try? FileManager.default.removeItem(at: testRootDirectory)
        try? FileManager.default.createDirectory(at: testRootDirectory, withIntermediateDirectories: true)
        try? Data().write(to: marker)
    }
    #endif
}

#if DEBUG
@MainActor
private enum AppTestRuntimeBootstrap {
    private static var didStart = false

    static func bootstrapIfNeeded() {
        guard AppTestRuntime.isUITesting, !didStart else { return }
        didStart = true

        Task { @MainActor in
            if AppTestRuntime.shouldSeedLabReport {
                try? await seedLabReport()
            }
        }
    }

    private static func seedLabReport() async throws {
        let fileSystemManager = FileSystemManager.shared
        let databaseManager = DatabaseManager.shared
        let healthDataManager = HealthDataManager.shared

        let labText = """
        Bison Diagnostics
        Collection Date: 2026-01-15
        Patient: Test Patient
        Ordering Physician: Dr. Ada Test

        CHEMISTRY
        Glucose\t98\tmg/dL\t70-100
        BUN\t15\tmg/dL\t7-20
        Creatinine\t0.9\tmg/dL\t0.6-1.2
        Total Cholesterol\t220\tmg/dL\t<200\tH

        CBC
        Hemoglobin\t13.5\tg/dL\t12.0-16.0
        WBC\t6.1\tK/uL\t4.0-11.0
        """

        let pdfData = makePDFData(text: labText)
        let storedURL = try fileSystemManager.storeDocument(
            data: pdfData,
            fileName: "ui-test-lab-report.pdf",
            fileType: .pdf
        )

        let document = MedicalDocument(
            fileName: "ui-test-lab-report.pdf",
            fileType: .pdf,
            filePath: storedURL,
            processingStatus: .completed,
            documentDate: ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"),
            providerName: "Bison Diagnostics",
            providerType: .laboratory,
            documentCategory: .labReport,
            extractedText: labText,
            includeInAIContext: true,
            contextPriority: 5,
            fileSize: Int64(pdfData.count),
            tags: ["ui-test"]
        )
        try await databaseManager.saveMedicalDocument(document)

        let personalInfo = PersonalHealthInfo(
            name: "Test Patient",
            dateOfBirth: ISO8601DateFormatter().date(from: "1980-01-01T12:00:00Z"),
            gender: .other,
            allergies: ["Penicillin"],
            medications: [
                Medication(
                    name: "Atorvastatin",
                    dosage: Dosage(value: 20, unit: .mg),
                    frequency: .daily,
                    prescribedBy: "Dr. Ada Test"
                )
            ]
        )
        try await healthDataManager.savePersonalInfo(personalInfo)

        let bloodTest = BloodTestResult(
            testDate: ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z") ?? Date(),
            laboratoryName: "Bison Diagnostics",
            orderingPhysician: "Dr. Ada Test",
            results: [
                BloodTestItem(name: "Glucose", value: "98", unit: "mg/dL", referenceRange: "70-100"),
                BloodTestItem(name: "Total Cholesterol", value: "220", unit: "mg/dL", referenceRange: "<200", isAbnormal: true),
                BloodTestItem(name: "Hemoglobin", value: "13.5", unit: "g/dL", referenceRange: "12.0-16.0")
            ],
            includeInAIContext: true,
            metadata: ["source_document_id": document.id.uuidString]
        )

        do {
            try await healthDataManager.addBloodTest(bloodTest)
        } catch {
            try await databaseManager.save(bloodTest)
        }
        await healthDataManager.loadHealthData()
    }

    private static func makePDFData(text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            text.draw(
                in: pageRect.insetBy(dx: 48, dy: 48),
                withAttributes: attributes
            )
        }
    }
}
#else
private enum AppTestRuntimeBootstrap {
    static func bootstrapIfNeeded() {}
}
#endif
