import SwiftUI

struct StorageUsageView: View {
    @State private var storageInfo = StorageInfo()
    @State private var isLoading = true
    
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
        
        // Simulate loading storage information
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Mock storage data
        storageInfo = StorageInfo(
            healthDataSize: 1_024_000,      // 1 MB
            documentsSize: 15_728_640,      // 15 MB
            thumbnailsSize: 2_097_152,      // 2 MB
            chatHistorySize: 512_000,       // 512 KB
            cacheSize: 1_048_576,           // 1 MB
            documentCount: 25,
            conversationCount: 8
        )
        
        isLoading = false
    }
    
    private func clearCache() {
        // Implement cache clearing
        Task {
            storageInfo.cacheSize = 0
        }
    }
    
    private func optimizeStorage() {
        // Implement storage optimization
        Task {
            // Simulate optimization
            storageInfo.thumbnailsSize = Int64(Double(storageInfo.thumbnailsSize) * 0.8)
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