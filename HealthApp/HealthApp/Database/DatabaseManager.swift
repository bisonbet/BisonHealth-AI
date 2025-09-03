import Foundation
import SQLite
import CryptoKit

// MARK: - Database Manager
@MainActor
class DatabaseManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            fatalError("Failed to initialize DatabaseManager: \(error)")
        }
    }()
    internal var db: Connection?
    private let encryptionKey: SymmetricKey
    private let databaseURL: URL
    
    // MARK: - Table Definitions
    internal let healthDataTable = Table("health_data")
    internal let documentsTable = Table("documents")
    internal let chatConversationsTable = Table("chat_conversations")
    internal let chatMessagesTable = Table("chat_messages")
    
    // MARK: - Column Definitions
    // Health Data Table
    internal let healthDataId = Expression<String>("id")
    internal let healthDataType = Expression<String>("type")
    internal let healthDataEncryptedData = Expression<Data>("encrypted_data")
    internal let healthDataCreatedAt = Expression<Int64>("created_at")
    internal let healthDataUpdatedAt = Expression<Int64>("updated_at")
    internal let healthDataMetadata = Expression<String?>("metadata")
    
    // Documents Table
    internal let documentId = Expression<String>("id")
    internal let documentFileName = Expression<String>("file_name")
    internal let documentFileType = Expression<String>("file_type")
    internal let documentFilePath = Expression<String>("file_path")
    internal let documentThumbnailPath = Expression<String?>("thumbnail_path")
    internal let documentProcessingStatus = Expression<String>("processing_status")
    internal let documentImportedAt = Expression<Int64>("imported_at")
    internal let documentProcessedAt = Expression<Int64?>("processed_at")
    internal let documentFileSize = Expression<Int64>("file_size")
    internal let documentTags = Expression<String>("tags")
    internal let documentNotes = Expression<String?>("notes")
    internal let documentExtractedData = Expression<Data?>("extracted_data")
    
    // Chat Conversations Table
    internal let conversationId = Expression<String>("id")
    internal let conversationTitle = Expression<String>("title")
    internal let conversationCreatedAt = Expression<Int64>("created_at")
    internal let conversationUpdatedAt = Expression<Int64>("updated_at")
    internal let conversationIncludedDataTypes = Expression<String>("included_health_data_types")
    internal let conversationIsArchived = Expression<Bool>("is_archived")
    internal let conversationTags = Expression<String>("tags")
    
    // Chat Messages Table
    internal let messageId = Expression<String>("id")
    internal let messageConversationId = Expression<String>("conversation_id")
    internal let messageContent = Expression<Data>("content") // Encrypted
    internal let messageRole = Expression<String>("role")
    internal let messageTimestamp = Expression<Int64>("timestamp")
    internal let messageMetadata = Expression<String?>("metadata")
    internal let messageIsError = Expression<Bool>("is_error")
    internal let messageTokens = Expression<Int?>("tokens")
    internal let messageProcessingTime = Expression<Double?>("processing_time")
    
    // MARK: - Initialization
    init() throws {
        // Generate or retrieve encryption key
        self.encryptionKey = try Self.getOrCreateEncryptionKey()
        
        // Set up database URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let healthAppDirectory = documentsPath.appendingPathComponent("HealthApp/Database")
        
        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: healthAppDirectory, withIntermediateDirectories: true)
        
        self.databaseURL = healthAppDirectory.appendingPathComponent("health_data.sqlite")
        
        // Initialize database connection and schema (actor init is nonisolated in Swift 6; inline to avoid isolation issues)
        db = try Connection(databaseURL.path)
        
        // Enable foreign key constraints
        try db?.execute("PRAGMA foreign_keys = ON")
        
        // Create tables
        if let db = db {
            // Create health_data table
            try db.run(healthDataTable.create(ifNotExists: true) { t in
                t.column(healthDataId, primaryKey: true)
                t.column(healthDataType)
                t.column(healthDataEncryptedData)
                t.column(healthDataCreatedAt)
                t.column(healthDataUpdatedAt)
                t.column(healthDataMetadata)
            })
            
            // Create documents table
            try db.run(documentsTable.create(ifNotExists: true) { t in
                t.column(documentId, primaryKey: true)
                t.column(documentFileName)
                t.column(documentFileType)
                t.column(documentFilePath)
                t.column(documentThumbnailPath)
                t.column(documentProcessingStatus)
                t.column(documentImportedAt)
                t.column(documentProcessedAt)
                t.column(documentFileSize)
                t.column(documentTags)
                t.column(documentNotes)
                t.column(documentExtractedData)
            })
            
            // Create chat_conversations table
            try db.run(chatConversationsTable.create(ifNotExists: true) { t in
                t.column(conversationId, primaryKey: true)
                t.column(conversationTitle)
                t.column(conversationCreatedAt)
                t.column(conversationUpdatedAt)
                t.column(conversationIncludedDataTypes)
                t.column(conversationIsArchived, defaultValue: false)
                t.column(conversationTags)
            })
            
            // Create chat_messages table
            try db.run(chatMessagesTable.create(ifNotExists: true) { t in
                t.column(messageId, primaryKey: true)
                t.column(messageConversationId)
                t.column(messageContent)
                t.column(messageRole)
                t.column(messageTimestamp)
                t.column(messageMetadata)
                t.column(messageIsError, defaultValue: false)
                t.column(messageTokens)
                t.column(messageProcessingTime)
                t.foreignKey(messageConversationId, references: chatConversationsTable, conversationId, delete: .cascade)
            })
            
            // Create indexes
            try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_type ON health_data(type)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_created ON health_data(created_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(processing_status)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_imported ON documents(imported_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(file_type)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON chat_messages(conversation_id)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON chat_messages(timestamp)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON chat_conversations(updated_at)")
            
            // Run simple migration check (user_version pragma)
            let version64 = try db.scalar("PRAGMA user_version") as? Int64
            let currentVersion = Int(version64 ?? 0)
            let targetVersion = 1
            if currentVersion < targetVersion {
                // Perform migrations here as needed (none currently)
                try db.execute("PRAGMA user_version = \(targetVersion)")
            }
        }
    }
    
    // MARK: - Encryption Key Management
    private static func getOrCreateEncryptionKey() throws -> SymmetricKey {
        let keychain = Keychain()
        
        if let existingKey = try keychain.getEncryptionKey() {
            return existingKey
        } else {
            let newKey = SymmetricKey(size: .bits256)
            try keychain.storeEncryptionKey(newKey)
            return newKey
        }
    }
    
    // MARK: - Encryption/Decryption
    internal func encryptData<T: Codable>(_ data: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(data)
        let sealedBox = try AES.GCM.seal(jsonData, using: encryptionKey)
        return sealedBox.combined!
    }
    
    internal func decryptData<T: Codable>(_ encryptedData: Data, as type: T.Type) throws -> T {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return try JSONDecoder().decode(type, from: decryptedData)
    }
    
    internal func encryptString(_ string: String) throws -> Data {
        let stringData = string.data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(stringData, using: encryptionKey)
        return sealedBox.combined!
    }
    
    internal func decryptString(_ encryptedData: Data) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }
}

// MARK: - Database Errors
enum DatabaseError: LocalizedError {
    case connectionFailed
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case notFound
    case constraintViolation
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to database"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .invalidData:
            return "Invalid data format"
        case .notFound:
            return "Record not found"
        case .constraintViolation:
            return "Database constraint violation"
        }
    }
}
