import SwiftUI

// MARK: - Offline Indicator View
/// Global offline indicator banner that appears when network is unavailable
struct OfflineIndicatorView: View {
    @ObservedObject var networkManager = NetworkManager.shared
    @ObservedObject var pendingOperationsManager = PendingOperationsManager.shared
    @State private var showDetails = false

    var body: some View {
        if !networkManager.isConnected {
            VStack(spacing: 0) {
                Button(action: {
                    withAnimation {
                        showDetails.toggle()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 16, weight: .semibold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Internet Connection")
                                .font(.system(size: 14, weight: .semibold))

                            if pendingOperationsManager.pendingOperations.count > 0 {
                                Text("\(pendingOperationsManager.pendingOperations.count) pending operations")
                                    .font(.system(size: 12))
                                    .opacity(0.8)
                            } else {
                                Text("Some features are unavailable")
                                    .font(.system(size: 12))
                                    .opacity(0.8)
                            }
                        }

                        Spacer()

                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.orange)

                if showDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("While offline, you can:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))

                        OfflineCapabilityRow(
                            icon: "eye",
                            text: "View conversations and messages",
                            available: true
                        )

                        OfflineCapabilityRow(
                            icon: "trash",
                            text: "Delete conversations",
                            available: true
                        )

                        OfflineCapabilityRow(
                            icon: "doc.viewfinder",
                            text: "Import documents",
                            available: true
                        )

                        Divider()
                            .background(Color.white.opacity(0.3))

                        Text("Not available offline:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))

                        OfflineCapabilityRow(
                            icon: "message",
                            text: "Send chat messages",
                            available: false
                        )

                        OfflineCapabilityRow(
                            icon: "doc.text.magnifyingglass",
                            text: "Process documents",
                            available: false
                        )

                        if !pendingOperationsManager.pendingOperations.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.3))

                            HStack {
                                Image(systemName: "clock")
                                Text("Operations will retry automatically when connection is restored")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.9))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Offline Capability Row
struct OfflineCapabilityRow: View {
    let icon: String
    let text: String
    let available: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(available ? .green : .red.opacity(0.8))

            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12))

            Spacer()
        }
        .foregroundColor(.white.opacity(available ? 0.9 : 0.6))
    }
}

// MARK: - Network Status Badge
/// Small badge showing network status (for use in settings, etc.)
struct NetworkStatusBadge: View {
    @ObservedObject var networkManager = NetworkManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(networkManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(networkManager.isConnected ? "Online" : "Offline")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(networkManager.isConnected ? .green : .red)

            if networkManager.isConnected {
                Text("(\(networkManager.connectionType.displayName))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(networkManager.isConnected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

// MARK: - Pending Operations Badge
/// Badge showing count of pending operations
struct PendingOperationsBadge: View {
    @ObservedObject var pendingOperationsManager = PendingOperationsManager.shared

    var body: some View {
        if pendingOperationsManager.pendingOperations.count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))

                Text("\(pendingOperationsManager.pendingOperations.count)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange)
            )
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        OfflineIndicatorView()

        Spacer()

        HStack {
            NetworkStatusBadge()
            PendingOperationsBadge()
        }
        .padding()
    }
}
