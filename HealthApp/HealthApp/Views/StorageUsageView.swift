import SwiftUI
import SQLite

struct StorageUsageView: View {
    @State private var storageInfo = StorageInfo()
    @State private var isLoading = true

    private let databaseManager = DatabaseManager.shared
    private let fileSystemManager = FileSystemManager.shared

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
        defer { isLoading = false }

        do {
            let fileStorage = try await fileSystemManager.getStorageUsage()
            let databaseStorage = try await getDatabaseStorageSnapshot()

            storageInfo = StorageInfo(
                healthDataSize: databaseStorage.healthDataSize,
                documentsSize: fileStorage.documentsSize,
                thumbnailsSize: fileStorage.thumbnailsSize,
                chatHistorySize: databaseStorage.chatHistorySize,
                cacheSize: fileStorage.exportsSize + fileStorage.logsSize,
                documentCount: databaseStorage.documentCount,
                conversationCount: databaseStorage.conversationCount
            )
        } catch {
            AppLog.shared.error("Failed to load storage info", error: error, category: .ui)
            storageInfo = StorageInfo()
        }
    }

    private func clearCache() {
        Task {
            do {
                try await fileSystemManager.clearCache()
                await loadStorageInfo()
            } catch {
                AppLog.shared.error("Failed to clear cache", error: error, category: .fileManagement)
            }
        }
    }

    private func optimizeStorage() {
        Task {
            do {
                try fileSystemManager.cleanupOldThumbnails(olderThan: 14)
                try await fileSystemManager.clearCache()
                await loadStorageInfo()
            } catch {
                AppLog.shared.error("Failed to optimize storage", error: error, category: .fileManagement)
            }
        }
    }

    private func getDatabaseStorageSnapshot() async throws -> DatabaseStorageSnapshot {
        guard let db = databaseManager.db else {
            throw DatabaseError.connectionFailed
        }

        let healthDataSize = try sizeForQuery(
            "SELECT COALESCE(SUM(LENGTH(encrypted_data) + COALESCE(LENGTH(metadata), 0)), 0) FROM health_data",
            db: db
        )
        let chatHistorySize = try sizeForQuery(
            "SELECT COALESCE(SUM(LENGTH(content) + COALESCE(LENGTH(metadata), 0)), 0) FROM chat_messages",
            db: db
        )

        let documentCount = try db.scalar(databaseManager.documentsTable.count)
        let conversationCount = try db.scalar(databaseManager.chatConversationsTable.count)

        return DatabaseStorageSnapshot(
            healthDataSize: healthDataSize,
            chatHistorySize: chatHistorySize,
            documentCount: documentCount,
            conversationCount: conversationCount
        )
    }

    private func sizeForQuery(_ query: String, db: Connection) throws -> Int64 {
        for row in try db.prepare(query) {
            if let int64Value = row[0] as? Int64 {
                return int64Value
            }

            if let intValue = row[0] as? Int {
                return Int64(intValue)
            }
        }

        return 0
    }
}

private struct DatabaseStorageSnapshot {
    let healthDataSize: Int64
    let chatHistorySize: Int64
    let documentCount: Int
    let conversationCount: Int
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
