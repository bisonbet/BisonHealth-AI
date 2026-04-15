import SwiftUI

struct StorageUsageView: View {
    @State private var storageInfo = StorageInfo()
    @State private var isLoading = true
    @State private var lastErrorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Calculating storage usage...")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if let lastErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lastErrorMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .accessibilityLabel(lastErrorMessage)
                        Button("Retry") {
                            Task { await loadStorageInfo() }
                        }
                        .accessibilityLabel("Retry loading storage information")
                        .accessibilityHint("Attempts to reload storage usage data")
                        .accessibilityIdentifier("retryStorageLoadButton")
                    }
                }
            } else {
                Section("Storage Overview") {
                    StorageRowView(
                        title: "Total Used",
                        size: storageInfo.totalSize,
                        color: .blue,
                        isTotal: true
                    )
                }
                
                Section("Breakdown") {
                    StorageRowView(
                        title: "Health Data",
                        size: storageInfo.healthDataSize,
                        color: .red
                    )
                    
                    StorageRowView(
                        title: "Documents",
                        size: storageInfo.documentsSize,
                        color: .green
                    )
                    
                    StorageRowView(
                        title: "Thumbnails",
                        size: storageInfo.thumbnailsSize,
                        color: .orange
                    )
                    
                    StorageRowView(
                        title: "Chat History",
                        size: storageInfo.chatHistorySize,
                        color: .purple
                    )
                    
                    StorageRowView(
                        title: "App Cache",
                        size: storageInfo.cacheSize,
                        color: .gray
                    )
                }
                
                Section("Statistics") {
                    HStack {
                        Text("Documents")
                        Spacer()
                        Text("\(storageInfo.documentCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Conversations")
                        Spacer()
                        Text("\(storageInfo.conversationCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Average Document Size")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: storageInfo.averageDocumentSize, countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Storage Management") {
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .foregroundColor(.orange)
                    
                    Button("Optimize Storage") {
                        optimizeStorage()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Storage Usage")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadStorageInfo()
        }
        .task {
            await loadStorageInfo()
        }
    }
    
    private func loadStorageInfo() async {
        isLoading = true
        lastErrorMessage = nil

        do {
            async let fileSystemUsage = FileSystemManager.shared.getStorageUsage()
            async let documentCount = DatabaseManager.shared.getDocumentCount()
            async let chatStats = DatabaseManager.shared.getChatStatistics()
            async let healthDataPayloadSize = DatabaseManager.shared.getHealthDataPayloadSizeEstimate()
            async let chatPayloadSize = DatabaseManager.shared.getChatPayloadSizeEstimate()

            let usage = try await fileSystemUsage
            let docs = try await documentCount
            let chats = try await chatStats
            let healthSize = try await healthDataPayloadSize
            let chatSize = try await chatPayloadSize

            storageInfo = StorageInfo(
                healthDataSize: healthSize,
                documentsSize: usage.documentsSize,
                thumbnailsSize: usage.thumbnailsSize,
                chatHistorySize: chatSize,
                cacheSize: usage.exportsSize + usage.logsSize,
                documentCount: docs,
                conversationCount: chats.totalConversations
            )
        } catch {
            storageInfo = StorageInfo()
            lastErrorMessage = "Unable to load storage details right now."
            AppLog.shared.ui("Failed to load storage usage: \(error)", level: .error)
        }

        isLoading = false
    }
    
    private func clearCache() {
        Task {
            do {
                try await FileSystemManager.shared.clearCache()
                await loadStorageInfo()
            } catch {
                lastErrorMessage = "Failed to clear cache."
                AppLog.shared.ui("Failed to clear cache: \(error)", level: .error)
            }
        }
    }

    private func optimizeStorage() {
        Task {
            do {
                // Only remove thumbnails older than 14 days — intentionally less aggressive
                // than clearCache() which deletes all thumbnails. Keeping these separate
                // preserves the semantic distinction between the two actions.
                try FileSystemManager.shared.cleanupOldThumbnails(olderThan: 14)
                await loadStorageInfo()
            } catch {
                lastErrorMessage = "Failed to optimize storage."
                AppLog.shared.ui("Failed to optimize storage: \(error)", level: .error)
            }
        }
    }
}

struct StorageRowView: View {
    let title: String
    let size: Int64
    let color: Color
    var isTotal: Bool = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                Text(title)
                    .fontWeight(isTotal ? .semibold : .regular)
            }
            
            Spacer()
            
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .foregroundColor(isTotal ? .primary : .secondary)
                .fontWeight(isTotal ? .semibold : .regular)
        }
    }
}

struct StorageInfo {
    var healthDataSize: Int64 = 0
    var documentsSize: Int64 = 0
    var thumbnailsSize: Int64 = 0
    var chatHistorySize: Int64 = 0
    var cacheSize: Int64 = 0
    var documentCount: Int = 0
    var conversationCount: Int = 0
    
    var totalSize: Int64 {
        healthDataSize + documentsSize + thumbnailsSize + chatHistorySize + cacheSize
    }
    
    var averageDocumentSize: Int64 {
        guard documentCount > 0 else { return 0 }
        return documentsSize / Int64(documentCount)
    }
}

#Preview {
    NavigationStack {
        StorageUsageView()
    }
}
