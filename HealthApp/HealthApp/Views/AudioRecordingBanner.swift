import SwiftUI

struct AudioRecordingBanner: View {
    @ObservedObject var audioRecordingManager: AudioRecordingManager
    @State private var elapsedTime: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red, .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording in Progress")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(elapsedTimeString)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                audioRecordingManager.stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
        .onAppear {
            updateElapsedTime()
        }
    }

    private var elapsedTimeString: String {
        guard elapsedTime > 0 else { return "00:00" }

        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func updateElapsedTime() {
        guard let startDate = audioRecordingManager.recordingStartDate else {
            elapsedTime = 0
            return
        }

        elapsedTime = Date().timeIntervalSince(startDate)
    }
}

#Preview {
    AudioRecordingBanner(audioRecordingManager: .shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}
