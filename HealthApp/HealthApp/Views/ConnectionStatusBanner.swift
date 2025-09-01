import SwiftUI

struct ConnectionStatusBanner: View {
    let isOffline: Bool
    let onRetry: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isOffline ? "Offline" : "Connection Issue")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(isOffline ? "AI assistant unavailable" : "Reconnecting to AI server...")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Button("Retry") {
                onRetry()
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2))
            .foregroundColor(.white)
            .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isOffline ? Color.red : Color.orange)
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

#Preview {
    VStack {
        ConnectionStatusBanner(isOffline: true, onRetry: {})
        ConnectionStatusBanner(isOffline: false, onRetry: {})
    }
}