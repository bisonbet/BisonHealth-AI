import Foundation
import AVFoundation

@MainActor
final class AudioRecordingManager: NSObject, ObservableObject {
    // MARK: - Nested Types

    enum PermissionStatus {
        case undetermined
        case granted
        case denied
    }

    // MARK: - Shared Instance

    static let shared = AudioRecordingManager()

    // MARK: - Published Properties

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var currentRecordingURL: URL?
    @Published private(set) var recordingStartDate: Date?
    @Published private(set) var permissionStatus: PermissionStatus = .undetermined
    @Published private(set) var lastSavedRecordingURL: URL?
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private let audioSession = AVAudioSession.sharedInstance()
    private let fileManager = FileManager.default
    private static let pendingShortcutKey = "com.bisonhealth.audioRecording.pendingShortcut"

    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    // MARK: - Intent Helpers

    nonisolated static func queueStartRecordingTrigger() {
        UserDefaults.standard.set(true, forKey: pendingShortcutKey)
    }

    func handleAppBecameActive() async {
        await processPendingShortcutTrigger()
    }

    func processPendingShortcutTrigger() async {
        guard consumeStartRecordingTrigger() else { return }
        let didStart = await startRecording()
        if !didStart && permissionStatus == .granted {
            Self.queueStartRecordingTrigger()
        }
    }

    private func consumeStartRecordingTrigger() -> Bool {
        let defaults = UserDefaults.standard
        let shouldStart = defaults.bool(forKey: Self.pendingShortcutKey)
        if shouldStart {
            defaults.set(false, forKey: Self.pendingShortcutKey)
        }
        return shouldStart
    }

    // MARK: - Recording Controls

    @discardableResult
    func startRecording() async -> Bool {
        guard !isRecording else { return true }

        do {
            let permissionGranted = await requestMicrophonePermission()
            guard permissionGranted else {
                errorMessage = "Microphone access is required to record audio. You can enable access in Settings > Privacy > Microphone."
                return false
            }

            let recordingURL = try prepareRecordingURL()
            try configureAudioSession()

            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                throw AudioRecordingError.unableToStart
            }

            currentRecordingURL = recordingURL
            recordingStartDate = Date()
            lastSavedRecordingURL = nil
            isRecording = true
            errorMessage = nil
            return true
        } catch {
            handleRecordingFailure(error: error)
            return false
        }
    }

    func stopRecording(saveRecording: Bool = true) {
        guard isRecording else { return }

        audioRecorder?.stop()
        if !saveRecording, let url = currentRecordingURL {
            try? fileManager.removeItem(at: url)
        } else {
            lastSavedRecordingURL = currentRecordingURL
        }

        cleanupRecordingState()
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private Helpers

    private func requestMicrophonePermission() async -> Bool {
        switch audioSession.recordPermission {
        case .granted:
            permissionStatus = .granted
            return true
        case .denied:
            permissionStatus = .denied
            return false
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            permissionStatus = granted ? .granted : .denied
            return granted
        @unknown default:
            permissionStatus = .denied
            return false
        }
    }

    private func configureAudioSession() throws {
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func prepareRecordingURL() throws -> URL {
        let documentsDirectory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let recordingsDirectory = documentsDirectory.appendingPathComponent("AudioRecordings", isDirectory: true)

        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Recording-\(formatter.string(from: Date())).m4a"

        return recordingsDirectory.appendingPathComponent(filename)
    }

    private func handleRecordingFailure(error: Error) {
        errorMessage = "Recording failed: \(error.localizedDescription)"
        if let url = currentRecordingURL {
            try? fileManager.removeItem(at: url)
        }
        lastSavedRecordingURL = nil
        cleanupRecordingState()
    }

    private func cleanupRecordingState() {
        audioRecorder = nil
        isRecording = false
        currentRecordingURL = nil
        recordingStartDate = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            handleRecordingFailure(error: AudioRecordingError.unableToStart)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        handleRecordingFailure(error: error ?? AudioRecordingError.encodingFailed)
    }
}

// MARK: - Errors

enum AudioRecordingError: LocalizedError {
    case unableToStart
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unableToStart:
            return "The audio recorder was unable to start. Please try again."
        case .encodingFailed:
            return "An encoding error occurred while saving the recording."
        }
    }
}
