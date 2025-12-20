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
    
    // MARK: - Database Version
    private static let currentDatabaseVersion = 7 // Increment when making schema changes

    // MARK: - Table Definitions
    internal let healthDataTable = Table("health_data")
    internal let documentsTable = Table("documents")
    internal let chatConversationsTable = Table("chat_conversations")
    internal let chatMessagesTable = Table("chat_messages")
    internal let databaseVersionTable = Table("database_version")
    
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
    // Medical document fields (added in v4)
    internal let documentDate = Expression<Int64?>("document_date")
    internal let documentProviderName = Expression<String?>("provider_name")
    internal let documentProviderType = Expression<String?>("provider_type")
    internal let documentCategory = Expression<String>("document_category")
    internal let documentExtractedText = Expression<String?>("extracted_text")
    internal let documentRawDoclingOutput = Expression<Data?>("raw_docling_output")
    internal let documentExtractedSections = Expression<Data?>("extracted_sections")
    internal let documentIncludeInAIContext = Expression<Bool>("include_in_ai_context")
    internal let documentContextPriority = Expression<Int>("context_priority")
    internal let documentLastEditedAt = Expression<Int64?>("last_edited_at")
    
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

    // Database Version Table
    internal let versionNumber = Expression<Int>("version")
    internal let versionCreatedAt = Expression<Int64>("created_at")

    // MARK: - Initialization
    init() throws {
        // Generate or retrieve encryption key
        self.encryptionKey = try Self.getOrCreateEncryptionKey()
        
        // Set up database URL
        // Use Application Support directory instead of Documents for better persistence
        // This directory persists across app updates and Xcode reinstalls (unless app is deleted)
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let healthAppDirectory = applicationSupport.appendingPathComponent("HealthApp/Database")
        
        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: healthAppDirectory, withIntermediateDirectories: true)
        
        self.databaseURL = healthAppDirectory.appendingPathComponent("health_data.sqlite")

        print("🗄️ DatabaseManager: Database path: \(databaseURL.path)")
        print("🗄️ DatabaseManager: Database file exists: \(FileManager.default.fileExists(atPath: databaseURL.path))")
        
        // Migrate database from Documents directory if it exists (one-time migration)
        try migrateDatabaseFromDocumentsIfNeeded(newLocation: databaseURL)
        
        // Note: Database persists across Xcode installs unless:
        // - App is manually deleted from device/simulator
        // - Simulator is reset (Device > Erase All Content and Settings)
        // - App's container is explicitly deleted

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
                // Medical document fields (v4)
                t.column(documentDate)
                t.column(documentProviderName)
                t.column(documentProviderType)
                t.column(documentCategory, defaultValue: "other")
                t.column(documentExtractedText)
                t.column(documentRawDoclingOutput)
                t.column(documentExtractedSections)
                t.column(documentIncludeInAIContext, defaultValue: false)
                t.column(documentContextPriority, defaultValue: 3)
                t.column(documentLastEditedAt)
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

            // Create database_version table
            try db.run(databaseVersionTable.create(ifNotExists: true) { t in
                t.column(versionNumber, primaryKey: true)
                t.column(versionCreatedAt)
            })
            
            // Create app_settings table
            try createAppSettingsTable()

            // Handle database migrations
            try performDatabaseMigration(db: db)

            // Create indexes
            try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_type ON health_data(type)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_created ON health_data(created_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(processing_status)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_imported ON documents(imported_at)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(file_type)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_date ON documents(document_date)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(document_category)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_ai_context ON documents(include_in_ai_context)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON chat_messages(conversation_id)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON chat_messages(timestamp)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON chat_conversations(updated_at)")
            
        }
    }

    // MARK: - Database Location Migration
    /// Migrates database from Documents directory to Application Support directory (one-time migration)
    private func migrateDatabaseFromDocumentsIfNeeded(newLocation: URL) throws {
        // Check if database already exists in new location
        if FileManager.default.fileExists(atPath: newLocation.path) {
            print("✅ DatabaseManager: Database already in Application Support directory")
            return
        }
        
        // Check for old location in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldDatabasePath = documentsPath.appendingPathComponent("HealthApp/Database/health_data.sqlite")
        
        if FileManager.default.fileExists(atPath: oldDatabasePath.path) {
            print("🔄 DatabaseManager: Found database in Documents directory, migrating to Application Support...")
            
            // Also check for WAL and SHM files (SQLite write-ahead logging files)
            let oldWALPath = oldDatabasePath.appendingPathExtension("wal")
            let oldSHMPath = oldDatabasePath.appendingPathExtension("shm")
            
            do {
                // Copy main database file
                try FileManager.default.copyItem(at: oldDatabasePath, to: newLocation)
                print("✅ DatabaseManager: Copied database file to Application Support")
                
                // Copy WAL file if it exists
                if FileManager.default.fileExists(atPath: oldWALPath.path) {
                    let newWALPath = newLocation.appendingPathExtension("wal")
                    try FileManager.default.copyItem(at: oldWALPath, to: newWALPath)
                    print("✅ DatabaseManager: Copied WAL file to Application Support")
                }
                
                // Copy SHM file if it exists
                if FileManager.default.fileExists(atPath: oldSHMPath.path) {
                    let newSHMPath = newLocation.appendingPathExtension("shm")
                    try FileManager.default.copyItem(at: oldSHMPath, to: newSHMPath)
                    print("✅ DatabaseManager: Copied SHM file to Application Support")
                }
                
                // Remove old files after successful migration
                try FileManager.default.removeItem(at: oldDatabasePath)
                if FileManager.default.fileExists(atPath: oldWALPath.path) {
                    try? FileManager.default.removeItem(at: oldWALPath)
                }
                if FileManager.default.fileExists(atPath: oldSHMPath.path) {
                    try? FileManager.default.removeItem(at: oldSHMPath)
                }
                
                print("✅ DatabaseManager: Successfully migrated database from Documents to Application Support")
            } catch {
                print("⚠️ DatabaseManager: Failed to migrate database: \(error)")
                // Don't throw - allow app to continue with new database location
                // Old database will remain in Documents directory
            }
        } else {
            print("ℹ️ DatabaseManager: No existing database found in Documents directory")
        }
    }

    // MARK: - Database Migration
    private func performDatabaseMigration(db: Connection) throws {
        // Get current database version
        let currentVersion = try getCurrentDatabaseVersion(db: db)
        print("🔧 DatabaseManager: Current DB version: \(currentVersion), Target version: \(Self.currentDatabaseVersion)")

        // If this is a fresh database, set the current version
        if currentVersion == 0 {
            print("🔧 DatabaseManager: Fresh database detected, setting version to \(Self.currentDatabaseVersion)")
            try setDatabaseVersion(db: db, version: Self.currentDatabaseVersion)
            return
        }

        // Check if migration is needed
        if currentVersion < Self.currentDatabaseVersion {
            print("⚠️ DatabaseManager: Migration needed from v\(currentVersion) to v\(Self.currentDatabaseVersion)")
            // Perform backup before migration
            try createBackupBeforeMigration()

            // Perform migrations step by step
            for version in (currentVersion + 1)...Self.currentDatabaseVersion {
                try performMigration(db: db, toVersion: version)
            }

            // Update version
            try setDatabaseVersion(db: db, version: Self.currentDatabaseVersion)

            print("✅ Database migrated from version \(currentVersion) to \(Self.currentDatabaseVersion)")
        } else if currentVersion > Self.currentDatabaseVersion {
            // This shouldn't happen unless user downgraded the app
            throw DatabaseError.incompatibleVersion("Database version \(currentVersion) is newer than app version \(Self.currentDatabaseVersion). Please update the app.")
        }
    }

    private func getCurrentDatabaseVersion(db: Connection) throws -> Int {
        do {
            let row = try db.pluck(databaseVersionTable.order(versionNumber.desc))
            return row?[versionNumber] ?? 0
        } catch {
            // Table doesn't exist or is empty, assume version 0
            return 0
        }
    }

    private func setDatabaseVersion(db: Connection, version: Int) throws {
        let timestamp = Int64(Date().timeIntervalSince1970)
        try db.run(databaseVersionTable.insert(or: .replace,
            versionNumber <- version,
            versionCreatedAt <- timestamp
        ))
    }

    private func createBackupBeforeMigration() throws {
        let backupURL = databaseURL.appendingPathExtension("backup.\(Date().timeIntervalSince1970)")
        try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        print("📦 Database backup created at: \(backupURL.path)")
    }

    private func performMigration(db: Connection, toVersion: Int) throws {
        print("🔄 Migrating database to version \(toVersion)...")

        switch toVersion {
        case 2:
            // Migration for version 2: Added personalMedicalHistory to PersonalHealthInfo
            // This migration is data-safe since we're only adding a field with a default value
            print("   ✓ Added support for personal medical history")
            
        case 3:
            // Migration for version 3: Added app_settings table for disclaimer acceptance
            try createAppSettingsTable()
            print("   ✓ Added app_settings table for disclaimer management")

        case 4:
            // Migration for version 4: Enhanced documents table with medical document fields
            try db.run("ALTER TABLE documents ADD COLUMN document_date INTEGER DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN provider_name TEXT DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN provider_type TEXT DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN document_category TEXT DEFAULT 'other'")
            try db.run("ALTER TABLE documents ADD COLUMN extracted_text TEXT DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN raw_docling_output BLOB DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN extracted_sections BLOB DEFAULT NULL")
            try db.run("ALTER TABLE documents ADD COLUMN include_in_ai_context INTEGER DEFAULT 0")
            try db.run("ALTER TABLE documents ADD COLUMN context_priority INTEGER DEFAULT 3")
            try db.run("ALTER TABLE documents ADD COLUMN last_edited_at INTEGER DEFAULT NULL")

            // Create indexes for frequently queried fields
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_date ON documents(document_date)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(document_category)")
            try db.run("CREATE INDEX IF NOT EXISTS idx_documents_ai_context ON documents(include_in_ai_context)")

            print("   ✓ Added medical document fields and indexes")

        case 5:
            // Migration for version 5: Added supplements array to PersonalHealthInfo
            // This migration is data-safe since PersonalHealthInfo is stored as encrypted JSON
            // and the supplements property has a default value of [] in the model.
            // The Codable decoder will automatically use the default for existing records.
            print("   ✓ Added support for supplements in personal health info")

        case 6:
            // Migration for version 6: Added Apple Health sync with vitals and sleep data
            // This migration is data-safe since PersonalHealthInfo is stored as encrypted JSON
            // and all new properties (bloodPressureReadings, heartRateReadings, bodyTemperatureReadings,
            // oxygenSaturationReadings, respiratoryRateReadings, weightReadings, sleepData) have
            // default values of [] in the model. The Codable decoder will automatically use the
            // defaults for existing records via decodeIfPresent.
            print("   ✓ Added support for Apple Health sync (vitals and sleep data)")

        case 7:
            // Migration for version 7: HealthDocument → MedicalDocument format migration
            // Ensures all existing documents have proper default values for new fields
            print("📦 Migrating to version 7: HealthDocument → MedicalDocument format")

            // Ensure documentCategory has default "other" for existing NULL values
            // Ensure includeInAIContext has default false for existing documents
            // Note: The schema already has these defaults (v4), but we update any NULL values
            // that may exist from pre-v4 databases that were migrated
            try db.run("""
                UPDATE documents
                SET document_category = 'other',
                    include_in_ai_context = 0
                WHERE document_category IS NULL
                   OR document_category = ''
                   OR include_in_ai_context IS NULL
            """)

            print("   ✓ Migrated document format: ensured default values for MedicalDocument fields")

        default:
            throw DatabaseError.migrationFailed("Unknown migration version: \(toVersion)")
        }
    }

    // MARK: - Database Reset
    func resetDatabase() throws {
        guard db != nil else { throw DatabaseError.connectionFailed }

        // Close current connection
        self.db = nil

        // Delete database file
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            try FileManager.default.removeItem(at: databaseURL)
        }

        // Reinitialize database
        self.db = try Connection(databaseURL.path)
        try self.db!.execute("PRAGMA foreign_keys = ON")

        // Recreate all tables (this will call performDatabaseMigration)
        try self.createTables()

        print("🗑️ Database reset completed")
    }

    private func createTables() throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

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
            // Medical document fields (v4)
            t.column(documentDate)
            t.column(documentProviderName)
            t.column(documentProviderType)
            t.column(documentCategory, defaultValue: "other")
            t.column(documentExtractedText)
            t.column(documentRawDoclingOutput)
            t.column(documentExtractedSections)
            t.column(documentIncludeInAIContext, defaultValue: false)
            t.column(documentContextPriority, defaultValue: 3)
            t.column(documentLastEditedAt)
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

        // Create database_version table
        try db.run(databaseVersionTable.create(ifNotExists: true) { t in
            t.column(versionNumber, primaryKey: true)
            t.column(versionCreatedAt)
        })
        
        // Create app_settings table
        try createAppSettingsTable()

        // Handle database migrations
        try performDatabaseMigration(db: db)

        // Create indexes
        try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_type ON health_data(type)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_health_data_created ON health_data(created_at)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(processing_status)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_documents_imported ON documents(imported_at)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(file_type)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON chat_messages(conversation_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON chat_messages(timestamp)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON chat_conversations(updated_at)")
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
    case incompatibleVersion(String)
    case migrationFailed(String)

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
        case .incompatibleVersion(let message):
            return "Database version incompatibility: \(message)"
        case .migrationFailed(let message):
            return "Database migration failed: \(message)"
        }
    }
}
