import AppIntents

@available(iOS 17, *)
struct StartAudioRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Health Note Recording"
    static var description = IntentDescription("Launch BisonHealth AI and immediately begin recording a new audio note.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AudioRecordingManager.queueStartRecordingTrigger()
        await AudioRecordingManager.shared.processPendingShortcutTrigger()
        return .result()
    }
}

@available(iOS 17, *)
struct HealthAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .red

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAudioRecordingIntent(),
            phrases: [
                "Start a health recording in \(.applicationName)",
                "Capture a health note with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "waveform"
        )
    }
}
