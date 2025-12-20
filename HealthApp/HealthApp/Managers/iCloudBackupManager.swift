import Foundation
import CloudKit
import CryptoKit
import Combine
import UIKit

// MARK: - Backup Models

struct BackupMetadata: Codable, Identifiable {
    let id: String
    let deviceId: String
    let deviceName: String
    let appVersion: String
    let backupDate: Date
    let dataTypes: [String]
    let encryptionKeyId: String
    let totalSize: Int64
}

struct BackupRecord {
    let id: UUID
    let metadata: BackupMetadata
    let healthData: Data?
    let chatData: Data?
    let documentsData: Data?
    let settingsData: Data?
}

// MARK: - Backup Status

enum BackupStatus: Equatable {
    case disabled
    case idle
    case backingUp(progress: Double)
    case restoring(progress: Double)
    case completed(Date)
    case failed(BackupError)

    var displayText: String {
        switch self {
        case .disabled: return "Disabled"
        case .idle: return "Ready"
        case .backingUp(let progress): return "Backing up... \(Int(progress * 100))%"
        case .restoring(let progress): return "Restoring... \(Int(progress * 100))%"
        case .completed(let date): return "Last backup: \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))"
        case .failed(let error): return "Failed: \(error.localizedDescription)"
        }
    }

    var isActive: Bool {
        switch self {
        case .backingUp, .restoring: return true
        default: return false
        }
    }
}

// MARK: - Backup Errors

enum BackupError: LocalizedError, Equatable {
    case iCloudUnavailable
    case accountNotSignedIn
    case networkUnavailable
    case insufficientStorage
    case encryptionFailed
    case cloudKitError(String)
    case dataCorrupted
    case keyDerivationFailed
    case deviceNotAuthorized

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available"
        case .accountNotSignedIn:
            return "iCloud account is not signed in"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .insufficientStorage:
            return "Insufficient iCloud storage space"
        case .encryptionFailed:
            return "Failed to encrypt backup data"
        case .cloudKitError(let message):
            return "iCloud error: \(message)"
        case .dataCorrupted:
            return "Backup data is corrupted"
        case .keyDerivationFailed:
            return "Failed to derive encryption key"
        case .deviceNotAuthorized:
            return "Device not authorized for backup"
        }
    }

    var recoveryMessage: String {
        switch self {
        case .iCloudUnavailable, .cloudKitError:
            return "Please try again later when iCloud is available."
        case .accountNotSignedIn:
            return "Please sign in to your iCloud account in Settings."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .insufficientStorage:
            return "Free up space in your iCloud account or upgrade storage."
        case .encryptionFailed, .keyDerivationFailed:
            return "Please contact support if this persists."
        case .dataCorrupted:
            return "Try creating a new backup or contact support."
        case .deviceNotAuthorized:
            return "This device needs to be authorized for backup access."
        }
    }
}

// MARK: - iCloud Backup Manager

@MainActor
class iCloudBackupManager: ObservableObject {
    static let shared = iCloudBackupManager()

    @Published var status: BackupStatus = .disabled
    @Published var lastBackupSize: Int64 = 0
    @Published var availableBackups: [BackupMetadata] = []
    @Published var storageWarningDismissed = false

    private let container: CKContainer
    private let database: CKDatabase
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager
    private weak var settingsManager: SettingsManager?
    private let keychain = Keychain()

    private var backupTimer: Timer?
    private var lastStorageWarning: Date?
    private let storageWarningCooldown: TimeInterval = 86400 // 24 hours

    // Record types for CloudKit
    private static let healthDataRecordType = "HealthData"
    private static let chatDataRecordType = "ChatData"
    private static let documentsRecordType = "Documents"
    private static let settingsRecordType = "Settings"
    private static let metadataRecordType = "BackupMetadata"

    private init() {
        self.container = CKContainer(identifier: "iCloud.com.bisonhealth.HealthApp")
        self.database = container.privateCloudDatabase
        self.databaseManager = DatabaseManager.shared
        self.fileSystemManager = FileSystemManager.shared
        // Don't initialize settingsManager here to avoid circular dependency
        // It will be set later by SettingsManager during setup

        // Defer setup to avoid circular dependency
        // setupBackupScheduler()
        // checkiCloudStatus()
    }

    // MARK: - Setup

    func configure(with settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        setupBackupScheduler()
        checkiCloudStatus()
    }

    // MARK: - Public Interface

    func enableBackup() async throws {
        try await checkiCloudAvailability()
        status = .idle
        scheduleNextBackup()
    }

    func disableBackup() {
        status = .disabled
        stopBackupScheduler()
    }

    func performManualBackup() async {
        guard settingsManager?.backupSettings.iCloudEnabled == true else { return }
        await performBackup()
    }

    func restoreFromBackup(_ metadata: BackupMetadata) async {
        status = .restoring(progress: 0.0)

        do {
            try await performRestore(metadata)
            status = .completed(Date())
        } catch {
            status = .failed(error as? BackupError ?? .cloudKitError(error.localizedDescription))
        }
    }

    func fetchAvailableBackups() async {
        do {
            // Only fetch recent backups for UI display (limit to 20 most recent)
            let backups = try await queryAvailableBackups(limit: 20)
            availableBackups = backups // Already sorted by queryAvailableBackups
        } catch {
            print("Failed to fetch available backups: \(error)")
            availableBackups = []
        }
    }

    func deleteBackupRecord(_ backup: BackupMetadata) async {
        await deleteBackupFromCloud(backup)
        
        // Remove from the list of available backups
        if let index = availableBackups.firstIndex(where: { $0.id == backup.id }) {
            availableBackups.remove(at: index)
        }
    }

    func cleanupCorruptedMetadata() async {
        print("Starting cleanup of corrupted backup metadata...")
        let query = CKQuery(recordType: Self.metadataRecordType, predicate: NSPredicate(value: true))
        
        var recordIDsToDelete: [CKRecord.ID] = []

        do {
            // We can't use a cursor-based query here as we need to check all records.
            let allRecords = try await database.records(matching: query)
            
            for (recordID, recordResult) in allRecords.matchResults {
                switch recordResult {
                case .success(let record):
                    if let metadataData = record["data"] as? Data {
                        let decoder = JSONDecoder()
                        do {
                            _ = try decoder.decode(BackupMetadata.self, from: metadataData)
                        } catch {
                            print("Found corrupted metadata, marking for deletion: \(recordID.recordName)")
                            recordIDsToDelete.append(recordID)
                        }
                    } else {
                        print("Found metadata record with no data, marking for deletion: \(recordID.recordName)")
                        recordIDsToDelete.append(recordID)
                    }
                case .failure(let error):
                    print("Error fetching record \(recordID.recordName): \(error.localizedDescription)")
                }
            }

            if recordIDsToDelete.isEmpty {
                print("No corrupted metadata found.")
            } else {
                print("Deleting \(recordIDsToDelete.count) corrupted metadata records...")
                let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDsToDelete)
                print("Deletion operation completed.")
                var successCount = 0
                for (recordID, result) in deleteResults {
                    if case .success = result {
                        successCount += 1
                    } else if case .failure(let error) = result {
                        print("Failed to delete record \(recordID.recordName): \(error.localizedDescription)")
                    }
                }
                print("\(successCount) of \(recordIDsToDelete.count) corrupted records deleted successfully.")
            }

        } catch {
            print("Failed to query or delete corrupted metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Backup Operations

    private func performBackup() async {
        guard settingsManager?.backupSettings.iCloudEnabled == true else { return }
        if case .backingUp = status { return }

        status = .backingUp(progress: 0.0)

        do {
            try await checkiCloudAvailability()

            let deviceId = await getOrCreateDeviceId()
            let backupId = UUID()

            // Prepare metadata
            let metadata = BackupMetadata(
                id: backupId.uuidString,
                deviceId: deviceId,
                deviceName: UIDevice.current.name,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                backupDate: Date(),
                dataTypes: getEnabledDataTypes(),
                encryptionKeyId: try await getEncryptionKeyId(),
                totalSize: 0 // Will be calculated during backup
            )

            status = .backingUp(progress: 0.1)

            // Backup each data type
            var totalSize: Int64 = 0
            var progress: Double = 0.1

            if settingsManager?.backupSettings.backupHealthData == true {
                let healthDataSize = try await backupHealthData(backupId: backupId)
                totalSize += healthDataSize
                progress += 0.2
                status = .backingUp(progress: progress)
            }

            if settingsManager?.backupSettings.backupChatHistory == true {
                let chatDataSize = try await backupChatData(backupId: backupId)
                totalSize += chatDataSize
                progress += 0.2
                status = .backingUp(progress: progress)
            }

            if settingsManager?.backupSettings.backupDocuments == true {
                let documentsSize = try await backupDocuments(backupId: backupId)
                totalSize += documentsSize
                progress += 0.3
                status = .backingUp(progress: progress)
            }

            if settingsManager?.backupSettings.backupAppSettings == true {
                let settingsSize = try await backupSettings(backupId: backupId)
                totalSize += settingsSize
                progress += 0.1
                status = .backingUp(progress: progress)
            }

            // Update metadata with actual size and save
            let finalMetadata = BackupMetadata(
                id: metadata.id,
                deviceId: metadata.deviceId,
                deviceName: metadata.deviceName,
                appVersion: metadata.appVersion,
                backupDate: metadata.backupDate,
                dataTypes: metadata.dataTypes,
                encryptionKeyId: metadata.encryptionKeyId,
                totalSize: totalSize
            )

            try await saveBackupMetadata(finalMetadata, backupId: backupId)

            lastBackupSize = totalSize
            status = .completed(Date())

            // Clean up old backups (keep last 10)
            await cleanupOldBackups()

        } catch let backupError as BackupError {
            await handleBackupError(backupError)
        } catch {
            await handleBackupError(.cloudKitError(error.localizedDescription))
        }
    }

    private func backupHealthData(backupId: UUID) async throws -> Int64 {
        let personalInfo = try await databaseManager.fetchPersonalHealthInfo()
        let bloodTests = try await databaseManager.fetchBloodTestResults()

        let healthData = HealthDataBackup(
            personalInfo: personalInfo,
            bloodTests: bloodTests
        )

        let encryptedData = try await encryptData(healthData)
        let record = createCloudKitRecord(
            type: Self.healthDataRecordType,
            id: backupId,
            data: encryptedData
        )

        try await database.save(record)
        return Int64(encryptedData.count)
    }

    private func backupChatData(backupId: UUID) async throws -> Int64 {
        let conversations = try await databaseManager.fetchConversations()

        let chatData = ChatDataBackup(conversations: conversations)
        let encryptedData = try await encryptData(chatData)
        let record = createCloudKitRecord(
            type: Self.chatDataRecordType,
            id: backupId,
            data: encryptedData
        )

        try await database.save(record)
        return Int64(encryptedData.count)
    }

    private func backupDocuments(backupId: UUID) async throws -> Int64 {
        let documents = try await databaseManager.fetchDocuments()
        var totalSize: Int64 = 0

        // Save each document as a separate CloudKit record with CKAsset for file data
        for (index, document) in documents.enumerated() {
            do {
                // Create temporary file for the document data (required for CKAsset)
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent("backup_\(document.id.uuidString)")
                var tempThumbnailURL: URL?

                // Guarantee cleanup of temp files even if errors occur (after CloudKit upload)
                defer {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    if let tempThumbURL = tempThumbnailURL {
                        try? FileManager.default.removeItem(at: tempThumbURL)
                    }
                }

                // 🔒 Encrypt document data before upload
                let documentData = try fileSystemManager.retrieveDocument(from: document.filePath)
                let encryptedDocData = try await encryptRawData(documentData)
                try encryptedDocData.write(to: tempFileURL)

                // Create CKAsset for the encrypted document file
                let documentAsset = CKAsset(fileURL: tempFileURL)

                // Handle thumbnail if available
                var thumbnailAsset: CKAsset?
                var encryptedThumbData: Data?
                if let thumbnailPath = document.thumbnailPath {
                    if let thumbnailData = try? Data(contentsOf: thumbnailPath) {
                        let tempThumbURL = tempDir.appendingPathComponent("thumb_\(document.id.uuidString)")
                        tempThumbnailURL = tempThumbURL

                        // 🔒 Encrypt thumbnail data before upload
                        let encryptedThumb = try await encryptRawData(thumbnailData)
                        encryptedThumbData = encryptedThumb
                        try encryptedThumb.write(to: tempThumbURL)
                        thumbnailAsset = CKAsset(fileURL: tempThumbURL)
                    }
                }

                // Create record for this individual document
                let recordName = "\(Self.documentsRecordType)_\(backupId.uuidString)_\(index)"
                let recordId = CKRecord.ID(recordName: recordName)
                let record = CKRecord(recordType: Self.documentsRecordType, recordID: recordId)

                // Store metadata as encrypted JSON
                let encryptedMetadata = try await encryptData(document)
                record["metadata"] = encryptedMetadata
                record["documentAsset"] = documentAsset
                if let thumbnailAsset = thumbnailAsset {
                    record["thumbnailAsset"] = thumbnailAsset
                }
                record["backupId"] = backupId.uuidString
                record["documentIndex"] = index

                // Save the record (CloudKit reads temp files during this call)
                try await database.save(record)

                // Track total size using in-memory encrypted data
                totalSize += Int64(encryptedDocData.count)
                if let encryptedThumb = encryptedThumbData {
                    totalSize += Int64(encryptedThumb.count)
                }

            } catch {
                print("Failed to backup document \(document.fileName): \(error)")
                // Continue with other documents even if one fails
            }
        }

        return totalSize
    }

    private func backupSettings(backupId: UUID) async throws -> Int64 {
        guard let settingsManager = settingsManager else {
            throw BackupError.cloudKitError("Settings manager not available")
        }

        let settingsData = AppSettingsBackup(
            backupSettings: settingsManager.backupSettings,
            appPreferences: settingsManager.appPreferences,
            modelPreferences: settingsManager.modelPreferences,
            ollamaConfig: settingsManager.ollamaConfig,
            doclingConfig: settingsManager.doclingConfig
        )

        let encryptedData = try await encryptData(settingsData)
        let record = createCloudKitRecord(
            type: Self.settingsRecordType,
            id: backupId,
            data: encryptedData
        )

        try await database.save(record)
        return Int64(encryptedData.count)
    }

    // MARK: - Restoration Operations

    private func performRestore(_ metadata: BackupMetadata) async throws {
        guard let backupId = UUID(uuidString: metadata.id) else {
            throw BackupError.dataCorrupted
        }

        var progress: Double = 0.0

        if metadata.dataTypes.contains("health") {
            try await restoreHealthData(backupId: backupId)
            progress += 0.3
            status = .restoring(progress: progress)
        }

        if metadata.dataTypes.contains("chat") {
            try await restoreChatData(backupId: backupId)
            progress += 0.3
            status = .restoring(progress: progress)
        }

        if metadata.dataTypes.contains("documents") {
            try await restoreDocuments(backupId: backupId)
            progress += 0.3
            status = .restoring(progress: progress)
        }

        if metadata.dataTypes.contains("settings") {
            try await restoreSettings(backupId: backupId)
            progress += 0.1
            status = .restoring(progress: progress)
        }
    }

    private func restoreHealthData(backupId: UUID) async throws {
        let recordName = "\(Self.healthDataRecordType)_\(backupId.uuidString)"
        let recordId = CKRecord.ID(recordName: recordName)
        let record = try await database.record(for: recordId)

        guard let encryptedData = record["data"] as? Data else {
            throw BackupError.dataCorrupted
        }

        let healthData: HealthDataBackup = try await decryptData(encryptedData)

        // Restore to database
        if let personalInfo = healthData.personalInfo {
            try await databaseManager.save(personalInfo)
        }

        for bloodTest in healthData.bloodTests {
            try await databaseManager.save(bloodTest)
        }
    }

    private func restoreChatData(backupId: UUID) async throws {
        let recordName = "\(Self.chatDataRecordType)_\(backupId.uuidString)"
        let recordId = CKRecord.ID(recordName: recordName)
        let record = try await database.record(for: recordId)

        guard let encryptedData = record["data"] as? Data else {
            throw BackupError.dataCorrupted
        }

        let chatData: ChatDataBackup = try await decryptData(encryptedData)

        // Restore conversations
        for conversation in chatData.conversations {
            try await databaseManager.saveConversation(conversation)
        }
    }

    private func restoreDocuments(backupId: UUID) async throws {
        // Query for all document records for this backup with pagination support
        let predicate = NSPredicate(format: "backupId == %@", backupId.uuidString)
        let query = CKQuery(recordType: Self.documentsRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "documentIndex", ascending: true)]

        var cursor: CKQueryOperation.Cursor?
        var hasMoreResults = true
        var restoredCount = 0

        // Paginate through all results to handle 100+ documents
        while hasMoreResults {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)

            if let cursor = cursor {
                // Continue from previous cursor
                results = try await database.records(continuingMatchFrom: cursor)
            } else {
                // Initial query
                results = try await database.records(matching: query)
            }

            // Restore documents in this batch
            for (_, recordResult) in results.matchResults {
                switch recordResult {
                case .success(let record):
                    do {
                        // Get encrypted metadata
                        guard let encryptedMetadata = record["metadata"] as? Data else {
                            print("Document record missing metadata")
                            continue
                        }

                        // Decrypt metadata
                        let document: MedicalDocument = try await decryptData(encryptedMetadata)

                        // Get document asset
                        guard let documentAsset = record["documentAsset"] as? CKAsset,
                              let documentURL = documentAsset.fileURL else {
                            print("Document record missing asset for \(document.fileName)")
                            continue
                        }

                        // 🔒 Read and decrypt document data from asset
                        let encryptedDocData = try Data(contentsOf: documentURL)
                        let documentData = try await decryptRawData(encryptedDocData)

                        // Save file using existing storeDocument method
                        let filePath = try fileSystemManager.storeDocument(
                            data: documentData,
                            fileName: document.fileName,
                            fileType: document.fileType
                        )

                        // Handle thumbnail if available
                        var thumbnailPath: URL?
                        if let thumbnailAsset = record["thumbnailAsset"] as? CKAsset,
                           let thumbnailURL = thumbnailAsset.fileURL {
                            do {
                                // 🔒 Read and decrypt thumbnail data
                                let encryptedThumbData = try Data(contentsOf: thumbnailURL)
                                let thumbnailData = try await decryptRawData(encryptedThumbData)

                                // Store thumbnail using FileSystemManager
                                thumbnailPath = try fileSystemManager.storeThumbnail(
                                    data: thumbnailData,
                                    forDocumentId: document.id
                                )
                            } catch {
                                print("⚠️ Failed to restore thumbnail for document \(document.fileName): \(error)")
                                // Continue without thumbnail - not a fatal error
                            }
                        }

                        // Update document with new paths
                        var restoredDoc = document
                        restoredDoc.filePath = filePath
                        restoredDoc.thumbnailPath = thumbnailPath

                        try await databaseManager.saveDocument(restoredDoc)
                        restoredCount += 1

                    } catch {
                        print("Failed to restore document: \(error)")
                        // Continue with other documents
                    }

                case .failure(let error):
                    print("Failed to fetch document record: \(error)")
                }
            }

            // Check if there are more results to fetch
            if let queryCursor = results.queryCursor {
                cursor = queryCursor
            } else {
                hasMoreResults = false
            }
        }

        print("Restored \(restoredCount) documents from backup")
    }

    private func restoreSettings(backupId: UUID) async throws {
        let recordName = "\(Self.settingsRecordType)_\(backupId.uuidString)"
        let recordId = CKRecord.ID(recordName: recordName)
        let record = try await database.record(for: recordId)

        guard let encryptedData = record["data"] as? Data else {
            throw BackupError.dataCorrupted
        }

        let settingsData: AppSettingsBackup = try await decryptData(encryptedData)

        // Restore settings
        settingsManager?.backupSettings = settingsData.backupSettings
        settingsManager?.appPreferences = settingsData.appPreferences
        settingsManager?.modelPreferences = settingsData.modelPreferences
        settingsManager?.ollamaConfig = settingsData.ollamaConfig
        settingsManager?.doclingConfig = settingsData.doclingConfig

        settingsManager?.saveSettings()
    }

    // MARK: - Encryption/Decryption

    private func encryptData<T: Codable>(_ data: T) async throws -> Data {
        let jsonData = try JSONEncoder().encode(data)
        let encryptionKey = try await getBackupEncryptionKey()
        let sealedBox = try AES.GCM.seal(jsonData, using: encryptionKey)

        guard let combinedData = sealedBox.combined else {
            throw BackupError.encryptionFailed
        }

        return combinedData
    }

    private func decryptData<T: Codable>(_ encryptedData: Data, as type: T.Type = T.self) async throws -> T {
        let encryptionKey = try await getBackupEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return try JSONDecoder().decode(T.self, from: decryptedData)
    }

    // Encrypt raw data (e.g., document files) without JSON encoding
    private func encryptRawData(_ data: Data) async throws -> Data {
        let encryptionKey = try await getBackupEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)

        guard let combinedData = sealedBox.combined else {
            throw BackupError.encryptionFailed
        }

        return combinedData
    }

    // Decrypt raw data without JSON decoding
    private func decryptRawData(_ encryptedData: Data) async throws -> Data {
        let encryptionKey = try await getBackupEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return decryptedData
    }

    private func getBackupEncryptionKey() async throws -> SymmetricKey {
        // Try to get existing key from keychain
        if let existingKey = try keychain.getBackupEncryptionKey() {
            return existingKey
        }

        // Generate new key if none exists
        let newKey = SymmetricKey(size: .bits256)
        try keychain.storeBackupEncryptionKey(newKey)
        return newKey
    }

    private func getEncryptionKeyId() async throws -> String {
        let key = try await getBackupEncryptionKey()
        let keyData = key.withUnsafeBytes { Data($0) }
        return SHA256.hash(data: keyData).compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    // MARK: - CloudKit Helpers

    private func createCloudKitRecord(type: String, id: UUID, data: Data) -> CKRecord {
        let recordName = "\(type)_\(id.uuidString)"
        let recordId = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: type, recordID: recordId)
        record["data"] = data
        return record
    }

    private func saveBackupMetadata(_ metadata: BackupMetadata, backupId: UUID) async throws {
        let recordName = "\(Self.metadataRecordType)_\(backupId.uuidString)"
        let recordId = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: Self.metadataRecordType, recordID: recordId)

        let metadataData = try JSONEncoder().encode(metadata)
        record["data"] = metadataData

        try await database.save(record)
    }

    private func queryAvailableBackups(limit: Int? = nil) async throws -> [BackupMetadata] {
        var allBackups: [BackupMetadata] = []
        var seenIds = Set<String>()
        var cursor: CKQueryOperation.Cursor? = nil
        let batchSize = 20 // Reasonable batch size for CloudKit

        let query = CKQuery(recordType: Self.metadataRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        do {
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor = cursor {
                    results = try await database.records(continuingMatchFrom: cursor, resultsLimit: limit ?? batchSize)
                } else {
                    results = try await database.records(matching: query, resultsLimit: limit ?? batchSize)
                }
                
                for (_, recordResult) in results.matchResults {
                    switch recordResult {
                    case .success(let record):
                        if let metadataData = record["data"] as? Data {
                            do {
                                let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataData)
                                if !seenIds.contains(metadata.id) {
                                    allBackups.append(metadata)
                                    seenIds.insert(metadata.id)
                                }
                            } catch {
                                print("Failed to decode backup metadata: \(error)")
                            }
                        }
                    case .failure(let error):
                        print("Failed to fetch backup record: \(error)")
                    }
                }

                cursor = results.queryCursor

                if let requestedLimit = limit, allBackups.count >= requestedLimit {
                    break
                }
            } while cursor != nil
            
            return allBackups // Already sorted by the query

        } catch let ckError as CKError {
            switch ckError.code {
            case .unknownItem:
                print("No backup metadata found - this is expected on first backup")
                return []
            default:
                print("CloudKit error querying backups: \(ckError)")
                throw ckError
            }
        }
    }

    // MARK: - Device Management

    private func getOrCreateDeviceId() async -> String {
        let key = "iCloudBackup.deviceId"

        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Helper Methods

    private func getEnabledDataTypes() -> [String] {
        var types: [String] = []
        if settingsManager?.backupSettings.backupHealthData == true { types.append("health") }
        if settingsManager?.backupSettings.backupChatHistory == true { types.append("chat") }
        if settingsManager?.backupSettings.backupDocuments == true { types.append("documents") }
        if settingsManager?.backupSettings.backupAppSettings == true { types.append("settings") }
        return types
    }

    private func checkiCloudAvailability() async throws {
        let status = try await container.accountStatus()

        switch status {
        case .available:
            return
        case .noAccount:
            throw BackupError.accountNotSignedIn
        case .restricted:
            throw BackupError.deviceNotAuthorized
        case .couldNotDetermine:
            throw BackupError.iCloudUnavailable
        case .temporarilyUnavailable:
            throw BackupError.iCloudUnavailable
        @unknown default:
            throw BackupError.iCloudUnavailable
        }
    }

    private func checkiCloudStatus() {
        Task {
            do {
                try await checkiCloudAvailability()
                if settingsManager?.backupSettings.iCloudEnabled == true {
                    status = .idle
                }
            } catch {
                if settingsManager?.backupSettings.iCloudEnabled == true {
                    status = .failed(error as? BackupError ?? .iCloudUnavailable)
                }
            }
        }
    }

    private func handleBackupError(_ error: BackupError) async {
        status = .failed(error)

        // Handle storage full error with cooldown
        if case .insufficientStorage = error {
            let now = Date()
            let shouldShowWarning = lastStorageWarning == nil ||
                now.timeIntervalSince(lastStorageWarning!) > storageWarningCooldown

            if shouldShowWarning && !storageWarningDismissed {
                lastStorageWarning = now
                // The UI will observe this status change and show the warning
            }
        }
    }

    private func cleanupOldBackups() async {
        do {
            // Get all backups to determine which ones to delete
            let allBackups = try await queryAvailableBackups()
            let sortedBackups = allBackups.sorted { $0.backupDate > $1.backupDate }

            if sortedBackups.count > 10 {
                let backupsToDelete = Array(sortedBackups.dropFirst(10))
                print("Cleaning up \(backupsToDelete.count) old backup(s), keeping most recent 10")

                for backup in backupsToDelete {
                    await deleteBackupFromCloud(backup)
                }
            } else {
                print("Only \(sortedBackups.count) backup(s) found, no cleanup needed")
            }
        } catch {
            print("Failed to cleanup old backups: \(error)")
        }
    }

    private func deleteBackupFromCloud(_ backup: BackupMetadata) async {
        do {
            // Delete metadata record
            let metadataRecordName = "\(Self.metadataRecordType)_\(backup.id)"
            let metadataRecordId = CKRecord.ID(recordName: metadataRecordName)
            try await database.deleteRecord(withID: metadataRecordId)

            // Delete associated data records
            for dataType in backup.dataTypes {
                let dataRecordType: String
                switch dataType {
                case "health": dataRecordType = Self.healthDataRecordType
                case "chat": dataRecordType = Self.chatDataRecordType
                case "documents": dataRecordType = Self.documentsRecordType
                case "settings": dataRecordType = Self.settingsRecordType
                default: continue
                }

                // Special handling for documents - query and delete all individual records with pagination
                if dataType == "documents" {
                    do {
                        let predicate = NSPredicate(format: "backupId == %@", backup.id)
                        let query = CKQuery(recordType: Self.documentsRecordType, predicate: predicate)

                        var cursor: CKQueryOperation.Cursor?
                        var hasMoreResults = true
                        var totalDeleted = 0

                        // Paginate through all results to handle 100+ documents
                        while hasMoreResults {
                            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)

                            if let cursor = cursor {
                                // Continue from previous cursor
                                results = try await database.records(continuingMatchFrom: cursor)
                            } else {
                                // Initial query
                                results = try await database.records(matching: query)
                            }

                            // Collect record IDs to delete, tracking fetch failures
                            var recordsToDelete: [CKRecord.ID] = []
                            var fetchFailures = 0
                            for (recordID, recordResult) in results.matchResults {
                                switch recordResult {
                                case .success:
                                    recordsToDelete.append(recordID)
                                case .failure(let error):
                                    fetchFailures += 1
                                    print("⚠️ Failed to fetch document record \(recordID.recordName) for deletion: \(error)")
                                }
                            }

                            if fetchFailures > 0 {
                                print("⚠️ Warning: \(fetchFailures) document records could not be fetched and may be orphaned in CloudKit")
                            }

                            // Delete this batch
                            if !recordsToDelete.isEmpty {
                                let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordsToDelete)
                                var successCount = 0
                                for (_, result) in deleteResults {
                                    if case .success = result {
                                        successCount += 1
                                    } else if case .failure(let error) = result {
                                        print("Failed to delete document record: \(error)")
                                    }
                                }
                                totalDeleted += successCount
                            }

                            // Check if there are more results to fetch
                            if let queryCursor = results.queryCursor {
                                cursor = queryCursor
                            } else {
                                hasMoreResults = false
                            }
                        }

                        if totalDeleted > 0 {
                            print("Deleted \(totalDeleted) document records")
                        }
                    } catch {
                        print("Failed to query/delete document records for backup \(backup.id): \(error)")
                    }
                } else {
                    // For other data types, delete single record (old format)
                    do {
                        let dataRecordName = "\(dataRecordType)_\(backup.id)"
                        let dataRecordId = CKRecord.ID(recordName: dataRecordName)
                        try await database.deleteRecord(withID: dataRecordId)
                    } catch {
                        // Individual data record deletion can fail if already deleted
                        print("Failed to delete \(dataRecordType) record for backup \(backup.id): \(error)")
                    }
                }
            }
            print("Successfully deleted backup from \(backup.backupDate)")
        } catch {
            print("Failed to delete backup \(backup.id): \(error)")
        }
    }

    // MARK: - Backup Scheduling

    private func setupBackupScheduler() {
        // Schedule backups based on frequency setting
        scheduleNextBackup()
    }

    private func scheduleNextBackup() {
        stopBackupScheduler()

        guard settingsManager?.backupSettings.iCloudEnabled == true && settingsManager?.backupSettings.autoBackup == true else {
            return
        }

        let interval: TimeInterval
        switch settingsManager?.backupSettings.backupFrequency {
        case .daily:
            interval = 86400 // 24 hours
        case .weekly:
            interval = 604800 // 7 days
        case .manual, .none:
            return // No automatic backup
        }

        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performBackup()
            }
        }
    }

    private func stopBackupScheduler() {
        backupTimer?.invalidate()
        backupTimer = nil
    }

    func dismissStorageWarning() {
        storageWarningDismissed = true
    }
}

// MARK: - Backup Data Models

private struct HealthDataBackup: Codable {
    let personalInfo: PersonalHealthInfo?
    let bloodTests: [BloodTestResult]
}

private struct ChatDataBackup: Codable {
    let conversations: [ChatConversation]
}

private struct DocumentBackup: Codable {
    let metadata: MedicalDocument
    let fileData: Data
    let thumbnailData: Data?
}

private struct DocumentsDataBackup: Codable {
    let documents: [DocumentBackup]
}

private struct AppSettingsBackup: Codable {
    let backupSettings: BackupSettings
    let appPreferences: AppPreferences
    let modelPreferences: ModelPreferences
    let ollamaConfig: ServerConfiguration
    let doclingConfig: ServerConfiguration
}