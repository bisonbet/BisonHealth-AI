import Foundation
@preconcurrency import SQLite
import CryptoKit

// MARK: - Database Manager
@MainActor
class DatabaseManager: ObservableObject {
    
    // MARK: - Shared Instance
    /// Never traps. A database that cannot be opened leaves the app running in a degraded
    /// state so `DatabaseUnavailableView` can explain what happened; trapping here turned
    /// every recoverable database fault into a launch crash whose only evidence was a
    /// crash log.
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            AppLog.shared.database("Failed to initialize DatabaseManager: \(error)", level: .critical)
            return DatabaseManager(unavailable: error)
        }
    }()
    internal var db: Connection?
    private let encryptionKey: SymmetricKey
    private let databaseURL: URL
    internal let appLog = AppLog.shared

    /// Non-nil when the database could not be opened. `db` stays nil in that case, so every
    /// query fails with `DatabaseError.connectionFailed` instead of reading placeholder state.
    private(set) var initializationError: Error?

    /// Whether `resetDatabase()` has a real path and key to rebuild with. False only when a
    /// degraded instance could recover neither, in which case erasing would target nothing.
    let canResetDatabase: Bool
    
    // Key fingerprint for detecting key changes
    private var encryptionKeyFingerprint: String {
        let keyData = encryptionKey.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: keyData)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
    
    // MARK: - Database Version
    private static let currentDatabaseVersion = 12 // Increment when making schema changes

    /// Guards the genetic URL normalization so a single migration run performs it once,
    /// even when several versions in the range ask for it. Reset per migration run.
    private var didNormalizeGeneticReferenceURLs = false

    // MARK: - Table Definitions
    internal let healthDataTable = Table("health_data")
    internal let documentsTable = Table("documents")
    internal let chatConversationsTable = Table("chat_conversations")
    internal let chatMessagesTable = Table("chat_messages")
    internal let appointmentPrepsTable = Table("appointment_preps")
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
    internal let conversationIncludedPersonalInfo = Expression<String?>("included_personal_info_categories")
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

    // Appointment Preps Table
    internal let prepId = Expression<String>("id")
    internal let prepEncryptedData = Expression<Data>("encrypted_data")
    internal let prepStatus = Expression<String>("status")
    internal let prepCreatedAt = Expression<Int64>("created_at")
    internal let prepUpdatedAt = Expression<Int64>("updated_at")

    // Database Version Table
    internal let versionNumber = Expression<Int>("version")
    internal let versionCreatedAt = Expression<Int64>("created_at")

    // MARK: - Initialization
    init(databaseURL: URL? = nil) throws {
        self.canResetDatabase = true

        // Generate or retrieve encryption key
        self.encryptionKey = try Self.getOrCreateEncryptionKey()
        
        // Set up database URL
        let resolvedDatabaseURL: URL
        let shouldRunLegacyMigration: Bool
        if let databaseURL {
            resolvedDatabaseURL = databaseURL
            shouldRunLegacyMigration = false
        } else if let runtimeDatabaseURL = AppTestRuntime.databaseURLForUITesting() {
            resolvedDatabaseURL = runtimeDatabaseURL
            shouldRunLegacyMigration = false
        } else {
            // Use Application Support directory instead of Documents for better persistence
            // This directory persists across app updates and Xcode reinstalls (unless app is deleted)
            guard let applicationSupportURL = Self.applicationSupportDatabaseURL() else {
                throw DatabaseError.connectionFailed
            }
            resolvedDatabaseURL = applicationSupportURL
            shouldRunLegacyMigration = true
        }

        try FileManager.default.createDirectory(
            at: resolvedDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        self.databaseURL = resolvedDatabaseURL

        AppLog.shared.database("Database path: \(self.databaseURL.path)")
        AppLog.shared.database("Database file exists: \(FileManager.default.fileExists(atPath: self.databaseURL.path))")
        
        // Migrate database from Documents directory if it exists (one-time migration)
        if shouldRunLegacyMigration {
            try migrateDatabaseFromDocumentsIfNeeded(newLocation: resolvedDatabaseURL)
        }
        
        // Note: Database persists across Xcode installs unless:
        // - App is manually deleted from device/simulator
        // - Simulator is reset (Device > Erase All Content and Settings)
        // - App's container is explicitly deleted

        // Initialize database connection and schema (actor init is nonisolated in Swift 6; inline to avoid isolation issues)
        db = try Connection(resolvedDatabaseURL.path)
        
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
                t.column(conversationIncludedPersonalInfo)
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

            // Create appointment_preps table
            try db.run(appointmentPrepsTable.create(ifNotExists: true) { t in
                t.column(prepId, primaryKey: true)
                t.column(prepEncryptedData)
                t.column(prepStatus, defaultValue: "draft")
                t.column(prepCreatedAt)
                t.column(prepUpdatedAt)
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
            try db.run("CREATE INDEX IF NOT EXISTS idx_appointment_preps_updated ON appointment_preps(updated_at)")

        }
    }

    /// Builds a manager that owns no connection, recording why the database could not be
    /// opened. With `db` nil every query throws before anything reads the other properties,
    /// but the real path and key are recovered where possible: `resetDatabase()` is the only
    /// way out of a database that will not open, and it needs both to rebuild one.
    private init(unavailable error: Error) {
        let recoveredEncryptionKey = try? Self.getOrCreateEncryptionKey()
        let recoveredDatabaseURL = Self.resolveDefaultDatabaseURL()

        self.encryptionKey = recoveredEncryptionKey ?? SymmetricKey(size: .bits256)
        self.databaseURL = recoveredDatabaseURL ?? URL(fileURLWithPath: "/dev/null")
        self.canResetDatabase = recoveredEncryptionKey != nil && recoveredDatabaseURL != nil
        self.db = nil
        self.initializationError = error
    }

    // MARK: - Database Location
    /// The container path the app stores its database at, or nil when the container itself
    /// cannot be located.
    private static func applicationSupportDatabaseURL() -> URL? {
        guard let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("HealthApp/Database")
            .appendingPathComponent("health_data.sqlite")
    }

    /// Mirrors the location `init(databaseURL:)` would have resolved, for the degraded
    /// instance that never got far enough to resolve one itself.
    private static func resolveDefaultDatabaseURL() -> URL? {
        AppTestRuntime.databaseURLForUITesting() ?? applicationSupportDatabaseURL()
    }

    // MARK: - Database Location Migration
    /// Migrates database from Documents directory to Application Support directory (one-time migration)
    private func migrateDatabaseFromDocumentsIfNeeded(newLocation: URL) throws {
        // Check if database already exists in new location
        if FileManager.default.fileExists(atPath: newLocation.path) {
            AppLog.shared.database("Database already in Application Support directory")
            return
        }
        
        // Check for old location in Documents directory
        guard let documentsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else {
            AppLog.shared.database("Documents directory unavailable; skipping legacy database migration", level: .warning)
            return
        }
        let oldDatabasePath = documentsPath.appendingPathComponent("HealthApp/Database/health_data.sqlite")
        
        if FileManager.default.fileExists(atPath: oldDatabasePath.path) {
            AppLog.shared.database("Found database in Documents directory, migrating to Application Support...")
            
            // Also check for WAL and SHM files (SQLite write-ahead logging files)
            let oldWALPath = oldDatabasePath.appendingPathExtension("wal")
            let oldSHMPath = oldDatabasePath.appendingPathExtension("shm")
            
            do {
                // Copy main database file
                try FileManager.default.copyItem(at: oldDatabasePath, to: newLocation)
                AppLog.shared.database("Copied database file to Application Support")
                
                // Copy WAL file if it exists
                if FileManager.default.fileExists(atPath: oldWALPath.path) {
                    let newWALPath = newLocation.appendingPathExtension("wal")
                    try FileManager.default.copyItem(at: oldWALPath, to: newWALPath)
                    AppLog.shared.database("Copied WAL file to Application Support")
                }
                
                // Copy SHM file if it exists
                if FileManager.default.fileExists(atPath: oldSHMPath.path) {
                    let newSHMPath = newLocation.appendingPathExtension("shm")
                    try FileManager.default.copyItem(at: oldSHMPath, to: newSHMPath)
                    AppLog.shared.database("Copied SHM file to Application Support")
                }
                
                // Remove old files after successful migration
                try FileManager.default.removeItem(at: oldDatabasePath)
                if FileManager.default.fileExists(atPath: oldWALPath.path) {
                    try? FileManager.default.removeItem(at: oldWALPath)
                }
                if FileManager.default.fileExists(atPath: oldSHMPath.path) {
                    try? FileManager.default.removeItem(at: oldSHMPath)
                }
                
                AppLog.shared.database("Successfully migrated database from Documents to Application Support")
            } catch {
                AppLog.shared.database("Failed to migrate database: \(error)", level: .warning)
                // Don't throw - allow app to continue with new database location
                // Old database will remain in Documents directory
            }
        } else {
            AppLog.shared.database("No existing database found in Documents directory")
        }
    }

    // MARK: - Database Migration
    private func performDatabaseMigration(db: Connection) throws {
        // Get current database version
        let currentVersion = try getCurrentDatabaseVersion(db: db)
        AppLog.shared.database("Current DB version: \(currentVersion), Target version: \(Self.currentDatabaseVersion)")

        // If this is a fresh database, set the current version
        if currentVersion == 0 {
            AppLog.shared.database("Fresh database detected, setting version to \(Self.currentDatabaseVersion)")
            try setDatabaseVersion(db: db, version: Self.currentDatabaseVersion)
            return
        }

        // Check if migration is needed
        if currentVersion < Self.currentDatabaseVersion {
            AppLog.shared.database("Migration needed from v\(currentVersion) to v\(Self.currentDatabaseVersion)", level: .warning)
            // Perform backup before migration
            try createBackupBeforeMigration()

            didNormalizeGeneticReferenceURLs = false

            // Perform migrations step by step. Each step is atomic and bumps
            // the stored version on success: a crash mid-ALTER rolls back
            // instead of leaving a half-migrated schema that bricks every
            // later launch with duplicate-column errors.
            for version in (currentVersion + 1)...Self.currentDatabaseVersion {
                try db.transaction {
                    try performMigration(db: db, toVersion: version)
                    try setDatabaseVersion(db: db, version: version)
                }
            }

            AppLog.shared.database("Database migrated from version \(currentVersion) to \(Self.currentDatabaseVersion)")

            // The pre-migration backup is a plaintext-PHI snapshot — delete it
            // once the migration has committed. (On failure it stays around for
            // recovery; resetDatabase sweeps any leftovers.)
            deleteMigrationBackups()
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
        var backupURL = databaseURL.appendingPathExtension("backup.\(Date().timeIntervalSince1970)")
        try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        // The backup is a plaintext-PHI snapshot until the v11 encryption pass
        // commits: at minimum, keep it out of iTunes/iCloud device backups.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? backupURL.setResourceValues(resourceValues)
        AppLog.shared.database("Database backup created at: \(backupURL.path)")
    }

    /// Removes every `*.backup.*` snapshot next to the database. Called after a
    /// successful migration and from resetDatabase — these backups hold
    /// pre-v11 plaintext PHI and must not outlive the migration.
    private func deleteMigrationBackups() {
        let directory = databaseURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let backupPrefix = databaseURL.lastPathComponent + ".backup."
        for url in contents where url.lastPathComponent.hasPrefix(backupPrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func performMigration(db: Connection, toVersion: Int) throws {
        AppLog.shared.database("Migrating database to version \(toVersion)...")

        switch toVersion {
        case 2:
            // Migration for version 2: Added personalMedicalHistory to PersonalHealthInfo
            // This migration is data-safe since we're only adding a field with a default value
            AppLog.shared.database("Added support for personal medical history")
            
        case 3:
            // Migration for version 3: Added app_settings table for disclaimer acceptance
            try createAppSettingsTable()
            AppLog.shared.database("Added app_settings table for disclaimer management")

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

            AppLog.shared.database("Added medical document fields and indexes")

        case 5:
            // Migration for version 5: Added supplements array to PersonalHealthInfo
            // This migration is data-safe since PersonalHealthInfo is stored as encrypted JSON
            // and the supplements property has a default value of [] in the model.
            // The Codable decoder will automatically use the default for existing records.
            AppLog.shared.database("Added support for supplements in personal health info")

        case 6:
            // Migration for version 6: Added Apple Health sync with vitals and sleep data
            // This migration is data-safe since PersonalHealthInfo is stored as encrypted JSON
            // and all new properties (bloodPressureReadings, heartRateReadings, bodyTemperatureReadings,
            // oxygenSaturationReadings, respiratoryRateReadings, weightReadings, sleepData) have
            // default values of [] in the model. The Codable decoder will automatically use the
            // defaults for existing records via decodeIfPresent.
            AppLog.shared.database("Added support for Apple Health sync (vitals and sleep data)")

        case 7:
            // Migration for version 7: HealthDocument → MedicalDocument format migration
            // Ensures all existing documents have proper default values for new fields
            AppLog.shared.database("Migrating to version 7: HealthDocument -> MedicalDocument format")

            // IMPORTANT: Use separate UPDATE statements to avoid overwriting valid data
            // If we used a single UPDATE with OR conditions, a document with valid category
            // but NULL include_in_ai_context would get its category overwritten to 'other'

            // Update only documents with missing or empty category
            try db.run("""
                UPDATE documents
                SET document_category = 'other'
                WHERE document_category IS NULL
                   OR document_category = ''
            """)

            // Update only documents with missing include_in_ai_context
            try db.run("""
                UPDATE documents
                SET include_in_ai_context = 0
                WHERE include_in_ai_context IS NULL
            """)

            AppLog.shared.database("Migrated document format: ensured default values for MedicalDocument fields")

        case 8:
            // Migration for version 8: Added appointment_preps table for "Prep for Doctor Appointment"
            // Stores encrypted AppointmentPrep records (symptoms, notes, medications + generated report).
            try db.run(appointmentPrepsTable.create(ifNotExists: true) { t in
                t.column(prepId, primaryKey: true)
                t.column(prepEncryptedData)
                t.column(prepStatus, defaultValue: "draft")
                t.column(prepCreatedAt)
                t.column(prepUpdatedAt)
            })
            try db.run("CREATE INDEX IF NOT EXISTS idx_appointment_preps_updated ON appointment_preps(updated_at)")
            AppLog.shared.database("Added appointment_preps table for appointment prep feature")

        case 9:
            // Migration for version 9: Replace stale genetic reference URLs
            // generated by the retired PharmGKB search route with canonical
            // reference pages.
            try normalizeGeneticReferenceURLs(db: db)
            AppLog.shared.database("Normalized persisted genetic reference URLs")

        case 10:
            // Migration for version 10: Re-run genetic URL normalization after
            // correcting ClinPGx links to use PA accessions and PharmDOG
            // genotype deep links. Version 9 could have persisted symbol-based
            // ClinPGx URLs that resolve to the site's client-side 404 page.
            try normalizeGeneticReferenceURLs(db: db)
            AppLog.shared.database("Re-normalized persisted genetic reference URLs")

        case 11:
            // Migration for version 11: (a) persist the per-conversation
            // personal-info category opt-outs (previously memory-only, so
            // privacy exclusions silently reverted to "include all"),
            // (b) encrypt PHI text columns at rest: documents file_name,
            // notes, provider_name, extracted_text, and chat conversation
            // titles now hold AES-GCM ciphertext instead of plaintext.
            try db.run("ALTER TABLE chat_conversations ADD COLUMN included_personal_info_categories TEXT DEFAULT NULL")
            try encryptDocumentPHIColumns(db: db)
            try encryptChatTitles(db: db)
            AppLog.shared.database("Added chat personal-info categories column; encrypted document PHI columns and chat titles")

        case 12:
            // Migration for version 12: drop legacy Docling raw_docling_output column.
            try db.run("ALTER TABLE documents DROP COLUMN raw_docling_output")
            AppLog.shared.database("Dropped legacy raw_docling_output column")

        default:
            throw DatabaseError.migrationFailed("Unknown migration version: \(toVersion)")
        }
    }

    /// v11 helper: encrypt the documents table's PHI text columns in place.
    /// Rows are read fully before any write (SELECT-while-UPDATE is undefined;
    /// same pattern as the genetic URL migration).
    private func encryptDocumentPHIColumns(db: Connection) throws {
        let legacyRawDoclingOutput = Expression<Data?>("raw_docling_output")

        struct PendingDocRow {
            let id: String
            let fileName: String?
            let notes: String?
            let providerName: String?
            let extractedText: String?
            let extractedData: Data?
            let rawDoclingOutput: Data?
            let extractedSections: Data?
        }

        var pending: [PendingDocRow] = []
        let iterator = try db.prepareRowIterator(
            documentsTable.select(
                documentId, documentFileName, documentNotes, documentProviderName, documentExtractedText,
                documentExtractedData, legacyRawDoclingOutput, documentExtractedSections
            )
        )
        while let row = try iterator.failableNext() {
            pending.append(PendingDocRow(
                id: row[documentId],
                fileName: row[documentFileName],
                notes: row[documentNotes],
                providerName: row[documentProviderName],
                extractedText: row[documentExtractedText],
                extractedData: row[documentExtractedData],
                rawDoclingOutput: row[legacyRawDoclingOutput],
                extractedSections: row[documentExtractedSections]
            ))
        }

        for doc in pending {
            try db.run(documentsTable.filter(documentId == doc.id).update(
                documentFileName <- try encryptString(doc.fileName ?? "").base64EncodedString(),
                documentNotes <- try encryptTextField(doc.notes),
                documentProviderName <- try encryptTextField(doc.providerName),
                documentExtractedText <- try encryptTextField(doc.extractedText),
                documentExtractedData <- try encryptDataField(doc.extractedData),
                legacyRawDoclingOutput <- try encryptDataField(doc.rawDoclingOutput),
                documentExtractedSections <- try encryptDataField(doc.extractedSections)
            ))
        }
        AppLog.shared.database("Encrypted PHI columns for \(pending.count) documents")
    }

    /// v11 helper: encrypt chat conversation titles in place.
    private func encryptChatTitles(db: Connection) throws {
        var pending: [(id: String, title: String)] = []
        let iterator = try db.prepareRowIterator(
            chatConversationsTable.select(conversationId, conversationTitle)
        )
        while let row = try iterator.failableNext() {
            pending.append((row[conversationId], row[conversationTitle]))
        }

        for conv in pending {
            try db.run(
                chatConversationsTable
                    .filter(conversationId == conv.id)
                    .update(conversationTitle <- try encryptString(conv.title).base64EncodedString())
            )
        }
        AppLog.shared.database("Encrypted titles for \(pending.count) conversations")
    }

    private func normalizeGeneticReferenceURLs(db: Connection) throws {
        // Versions 9 and 10 both normalize against the current reference logic, so a
        // v8 database would otherwise make two identical full-table passes on launch.
        guard !didNormalizeGeneticReferenceURLs else {
            AppLog.shared.database("Genetic reference URLs already normalized in this migration run", level: .debug)
            return
        }
        didNormalizeGeneticReferenceURLs = true

        // Read every candidate row before writing any of them. SQLite leaves it
        // undefined whether a running SELECT observes rows updated underneath it,
        // and rewriting extracted_data can move the record to another page.
        var pendingRows: [(id: String, extractedData: Data)] = []
        let query = documentsTable.select(documentId, documentExtractedData)
        let iterator = try db.prepareRowIterator(query)

        while let row = try iterator.failableNext() {
            let id: String
            do {
                id = try row.get(documentId)
            } catch {
                continue
            }

            let extractedData: Data
            do {
                guard let data = try row.get(documentExtractedData) else {
                    continue
                }
                extractedData = data
            } catch {
                continue
            }

            pendingRows.append((id: id, extractedData: extractedData))
        }

        var updatedDocumentCount = 0

        for (id, extractedData) in pendingRows {
            guard var healthData = try? JSONDecoder().decode([AnyHealthData].self, from: extractedData) else {
                continue
            }

            var documentChanged = false
            for index in healthData.indices where healthData[index].type == .geneticProfile {
                guard let originalResult = try? healthData[index].decode(as: GeneticTestResult.self) else {
                    continue
                }

                var normalizedResult = originalResult
                var resultChanged = false
                for resultIndex in normalizedResult.results.indices {
                    // Only rewrite URLs that were actually persisted. Results
                    // without a curated URL continue to use the computed,
                    // canonical fallback at display time.
                    guard normalizedResult.results[resultIndex].curatedSourceURL != nil else {
                        continue
                    }

                    let normalizedURL = normalizedResult.results[resultIndex].referenceURL?.absoluteString
                    if normalizedResult.results[resultIndex].curatedSourceURL != normalizedURL {
                        normalizedResult.results[resultIndex].curatedSourceURL = normalizedURL
                        resultChanged = true
                    }
                }

                if resultChanged {
                    healthData[index] = try AnyHealthData(normalizedResult)
                    documentChanged = true
                }
            }

            guard documentChanged else { continue }

            let encodedHealthData = try JSONEncoder().encode(healthData)
            let update = documentsTable
                .filter(self.documentId == id)
                .update(documentExtractedData <- encodedHealthData)
            try db.run(update)
            updatedDocumentCount += 1
        }

        AppLog.shared.database("Normalized genetic reference URLs in \(updatedDocumentCount) document(s)", level: .debug)
    }

    // MARK: - Database Reset
    /// Erases the local database and rebuilds an empty one. Deliberately does *not* require
    /// an open connection: a database that failed to open is exactly the case where this is
    /// the user's only way forward, and `DatabaseUnavailableView` offers it there.
    func resetDatabase() throws {
        guard canResetDatabase else { throw DatabaseError.connectionFailed }

        // Close current connection
        self.db = nil

        // Migration backups hold pre-encryption plaintext PHI — a database
        // reset must erase them too, or "permanently deleted" is a lie.
        deleteMigrationBackups()

        // Delete the database and its write-ahead log. Leaving a stale -wal or -shm behind
        // would let SQLite replay it into the fresh file and reintroduce the corruption the
        // reset was meant to clear.
        // SQLite names its sidecars "<db>-wal" / "<db>-shm" — a hyphen, not a path extension.
        let sidecarURLs = ["-wal", "-shm"].map { URL(fileURLWithPath: databaseURL.path + $0) }
        for url in [databaseURL] + sidecarURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Reinitialize database
        let connection = try Connection(databaseURL.path)
        self.db = connection
        try connection.execute("PRAGMA foreign_keys = ON")

        // Recreate all tables (this will call performDatabaseMigration)
        try self.createTables()

        // The instance is usable again, so nothing should keep showing the recovery screen.
        self.initializationError = nil

        AppLog.shared.database("Database reset completed")
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
            t.column(conversationIncludedPersonalInfo)
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

        // Create appointment_preps table
        try db.run(appointmentPrepsTable.create(ifNotExists: true) { t in
            t.column(prepId, primaryKey: true)
            t.column(prepEncryptedData)
            t.column(prepStatus, defaultValue: "draft")
            t.column(prepCreatedAt)
            t.column(prepUpdatedAt)
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
        try db.run("CREATE INDEX IF NOT EXISTS idx_appointment_preps_updated ON appointment_preps(updated_at)")
    }

    // MARK: - Encryption Key Management
    private static func getOrCreateEncryptionKey() throws -> SymmetricKey {
        let keychain = Keychain()
        let log = AppLog.shared

        if let existingKey = try keychain.getEncryptionKey() {
            // Verify key integrity
            let keyData = existingKey.withUnsafeBytes { Data($0) }
            if keyData.count != 32 { // 256 bits = 32 bytes
                log.database("Encryption key has invalid size (\(keyData.count) bytes, expected 32). This may cause data loss!", level: .error)
                throw DatabaseError.encryptionFailed
            }

            // Log key fingerprint for debugging (first 8 chars only for security)
            let hash = SHA256.hash(data: keyData)
            let fingerprint = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
            log.database("Using existing encryption key (fingerprint: \(fingerprint)...)")

            return existingKey
        } else {
            // Check if database already exists - if so, warn about potential data loss
            if let databaseURL = applicationSupportDatabaseURL(),
               FileManager.default.fileExists(atPath: databaseURL.path) {
                log.database("CRITICAL: Database exists but encryption key is missing! Creating new key will make existing data unreadable!", level: .critical)
                log.database("Attempting to scan database for recoverable data...", level: .error)
                // Don't throw - let the recovery scanner handle it
            }

            log.database("Creating new encryption key (no existing key found)", level: .warning)
            let newKey = SymmetricKey(size: .bits256)
            try keychain.storeEncryptionKey(newKey)

            // Store key fingerprint for future validation
            let keyData = newKey.withUnsafeBytes { Data($0) }
            let hash = SHA256.hash(data: keyData)
            let fingerprint = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
            log.database("New encryption key created (fingerprint: \(fingerprint)...)")

            return newKey
        }
    }
    
    // MARK: - Encryption/Decryption
    internal func encryptData<T: Codable>(_ data: T) throws -> Data {
        let jsonData = try JSONEncoder().encode(data)
        let sealedBox = try AES.GCM.seal(jsonData, using: encryptionKey)
        
        guard let combined = sealedBox.combined else {
            appLog.database("Encryption failed: sealedBox.combined is nil", level: .error)
            throw DatabaseError.encryptionFailed
        }
        
        // CRITICAL: Verify we can decrypt what we just encrypted
        // This ensures we never save data that can't be read back
        do {
            let verificationBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(verificationBox, using: encryptionKey)
            
            // Verify the decrypted data matches what we encrypted
            guard decrypted == jsonData else {
                appLog.database("Encryption verification failed: decrypted data doesn't match original", level: .error)
                throw DatabaseError.encryptionFailed
            }
        } catch {
            appLog.error("Encryption verification failed: \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.encryptionFailed
        }
        
        return combined
    }
    
    internal func decryptData<T: Codable>(_ encryptedData: Data, as type: T.Type) throws -> T {
        // Validate encrypted data is not empty
        guard !encryptedData.isEmpty else {
            throw DatabaseError.decryptionFailed
        }
        
        // Validate minimum size for AES-GCM sealed box (nonce + ciphertext + tag)
        // AES-GCM requires at least 12 bytes for nonce + 16 bytes for tag = 28 bytes minimum
        guard encryptedData.count >= 28 else {
            throw DatabaseError.decryptionFailed
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            return try JSONDecoder().decode(type, from: decryptedData)
        } catch {
            // Re-throw the error as-is to preserve the original error information
            // The calling code will log the actual error details
            throw error
        }
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

    /// Encrypts an optional string for storage in a TEXT column (Base64 of
    /// the AES-GCM combined representation). Empty strings map to nil.
    internal func encryptTextField(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        return try encryptString(value).base64EncodedString()
    }

    /// Decrypts an optional Base64 AES-GCM TEXT field. Returns nil when the
    /// stored value cannot be decrypted (corrupt data or a key change) rather
    /// than surfacing ciphertext to the model layer.
    internal func decryptTextField(_ stored: String?) -> String? {
        guard let stored, !stored.isEmpty else { return nil }
        guard let data = Data(base64Encoded: stored) else { return nil }
        return try? decryptString(data)
    }

    /// Encrypts an optional JSON/Data payload (e.g. extracted lab results,
    /// sections) for storage in a BLOB column.
    internal func encryptDataField(_ value: Data?) throws -> Data? {
        guard let value, !value.isEmpty else { return nil }
        let sealedBox = try AES.GCM.seal(value, using: encryptionKey)
        return sealedBox.combined
    }

    /// Decrypts an optional AES-GCM BLOB field. Returns nil on failure rather
    /// than surfacing ciphertext to the model layer.
    internal func decryptDataField(_ stored: Data?) -> Data? {
        guard let stored, !stored.isEmpty else { return nil }
        return try? AES.GCM.open(try AES.GCM.SealedBox(combined: stored), using: encryptionKey)
    }

    // MARK: - Storage Estimates
    func getHealthDataPayloadSizeEstimate() async throws -> Int64 {
        guard let db = db else { throw DatabaseError.connectionFailed }
        let result = try db.scalar("SELECT COALESCE(SUM(LENGTH(encrypted_data)), 0) FROM health_data")
        return result as? Int64 ?? 0
    }

    func getChatPayloadSizeEstimate() async throws -> Int64 {
        guard let db = db else { throw DatabaseError.connectionFailed }
        let result = try db.scalar("SELECT COALESCE(SUM(LENGTH(content)), 0) FROM chat_messages")
        return result as? Int64 ?? 0
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

    /// Advice for `DatabaseUnavailableView`, where this error stopped the app from starting.
    ///
    /// Deliberately *not* `LocalizedError.recoverySuggestion`: these strings assume a dead
    /// app at launch, while `ErrorHandler`'s global alert surfaces `recoverySuggestion` for
    /// ordinary runtime failures. A missing chat record must not tell the user to restart.
    var launchRecoverySuggestion: String {
        switch self {
        case .connectionFailed:
            return "Close and reopen BisonHealth AI. If it keeps happening, make sure the device has free storage space."
        case .encryptionFailed, .decryptionFailed:
            return "This device's encryption key no longer matches the stored records, so they cannot be read. Close and reopen the app first. Nothing else can decrypt this data, so share the diagnostic logs before erasing anything."
        case .invalidData, .notFound, .constraintViolation:
            return "Close and reopen BisonHealth AI. If it keeps happening, share the diagnostic logs."
        case .incompatibleVersion:
            return "This copy of BisonHealth AI is older than the data already stored on this device. Install the latest version to open it — nothing has been changed or deleted."
        case .migrationFailed:
            return "The upgrade to this version's data format did not finish. Your records are still on this device, along with a copy taken before the upgrade started. Do not delete the app — that erases your records and that copy with them. Share the diagnostic logs instead."
        }
    }

    /// Whether erasing the local database is a sensible way out of this failure.
    ///
    /// `.incompatibleVersion` is excluded on purpose: the records are intact and a newer
    /// build opens them fine, so offering to erase would destroy recoverable data.
    var isRecoverableByErasingData: Bool {
        switch self {
        case .incompatibleVersion:
            return false
        case .connectionFailed, .encryptionFailed, .decryptionFailed,
             .invalidData, .notFound, .constraintViolation, .migrationFailed:
            return true
        }
    }
}
