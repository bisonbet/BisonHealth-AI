import SwiftUI

/// Placeholder Backup Management shell.
///
/// iCloud/CloudKit backup was removed from the app to avoid storing PHI on
/// Apple's iCloud infrastructure (no BAA available). This view remains as a
/// landing page so that a non-iCloud backup mechanism (e.g. local encrypted
/// export, self-hosted sync) can be wired in later without touching the
/// Settings navigation.
struct BackupManagementView: View {
    var body: some View {
        // Pushed onto the Settings navigation stack, so no NavigationStack of
        // its own — that would produce a nested/doubled navigation bar.
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .padding(.top, 24)

                Text("Cloud Backup Unavailable")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("iCloud/CloudKit backup has been removed from this build. Health data stays on-device only. An alternative local or self-hosted backup option may be added in a future release.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Backup Management")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    BackupManagementView()
        .environmentObject(AppState())
}
