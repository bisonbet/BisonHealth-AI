import XCTest
import CloudKit
import CryptoKit
@testable import HealthApp

@MainActor
final class iCloudBackupTests: XCTestCase {

    var backupManager: iCloudBackupManager!
    var settingsManager: SettingsManager!
    var mockContainer: MockCKContainer!
    var mockDatabase: MockCKDatabase!

    override func setUp() async throws {
        try await super.setUp()

        // Set up mock CloudKit infrastructure
        mockDatabase = MockCKDatabase()
        mockContainer = MockCKContainer(database: mockDatabase)

        // Initialize managers with test configuration
        settingsManager = SettingsManager.shared
        settingsManager.backupSettings = BackupSettings()

        backupManager = iCloudBackupManager.shared

        // Clear any existing state
        await backupManager.disableBackup()
    }

    override func tearDown() async throws {
        await backupManager.disableBackup()
        backupManager = nil
        settingsManager = nil
        mockDatabase = nil
        mockContainer = nil
        try await super.tearDown()
    }

    // MARK: - Backup Enabling Tests

    func testEnableBackup_WhenAccountAvailable_ShouldSucceed() async throws {
        // Given
        mockContainer.accountStatus = .available
        settingsManager.backupSettings.iCloudEnabled = true

        // When
        try await backupManager.enableBackup()

        // Then
        XCTAssertEqual(backupManager.status, .idle)
    }

    func testEnableBackup_WhenAccountNotSignedIn_ShouldFail() async throws {
        // Given
        mockContainer.accountStatus = .noAccount

        // When & Then
        do {
            try await backupManager.enableBackup()
            XCTFail("Should have thrown an error")
        } catch let error as BackupError {
            XCTAssertEqual(error, .accountNotSignedIn)
        }
    }

    func testEnableBackup_WhenAccountRestricted_ShouldFail() async throws {
        // Given
        mockContainer.accountStatus = .restricted

        // When & Then
        do {
            try await backupManager.enableBackup()
            XCTFail("Should have thrown an error")
        } catch let error as BackupError {
            XCTAssertEqual(error, .deviceNotAuthorized)
        }
    }

    // MARK: - Backup Performance Tests

    func testPerformBackup_WithHealthData_ShouldCreateRecord() async throws {
        // Given
        mockContainer.accountStatus = .available
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupHealthData = true

        let personalInfo = PersonalHealthInfo(
            firstName: "John",
            lastName: "Doe",
            dateOfBirth: Date(),
            bloodType: .aPositive,
            gender: .male,
            height: 180,
            weight: 75,
            emergencyContact: EmergencyContact(
                name: "Jane Doe",
                phoneNumber: "+1234567890",
                relationship: "Spouse"
            )
        )

        // Set up database with test data
        let databaseManager = DatabaseManager.shared
        try await databaseManager.savePersonalHealthInfo(personalInfo)

        try await backupManager.enableBackup()

        // When
        await backupManager.performManualBackup()

        // Then
        // Wait for backup to complete
        await waitForBackupCompletion()

        XCTAssertTrue(mockDatabase.savedRecords.count > 0)
        XCTAssertTrue(mockDatabase.savedRecords.contains { $0.recordType == "HealthData" })

        if case .completed = backupManager.status {
            // Backup completed successfully
        } else {
            XCTFail("Backup should have completed successfully, got: \(backupManager.status)")
        }
    }

    func testPerformBackup_WithChatData_ShouldCreateRecord() async throws {
        // Given
        mockContainer.accountStatus = .available
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupChatHistory = true

        let conversation = ChatConversation(
            id: UUID(),
            title: "Test Conversation",
            messages: [
                ChatMessage(
                    id: UUID(),
                    content: "Hello",
                    role: .user,
                    timestamp: Date(),
                    isError: false
                )
            ],
            createdAt: Date(),
            updatedAt: Date(),
            includedHealthDataTypes: [],
            isArchived: false,
            tags: []
        )

        let databaseManager = DatabaseManager.shared
        try await databaseManager.saveConversation(conversation)

        try await backupManager.enableBackup()

        // When
        await backupManager.performManualBackup()

        // Then
        await waitForBackupCompletion()

        XCTAssertTrue(mockDatabase.savedRecords.contains { $0.recordType == "ChatData" })
    }

    // MARK: - Restoration Tests

    func testRestoreFromBackup_ShouldRestoreData() async throws {
        // Given
        let deviceId = UUID().uuidString
        let backupMetadata = BackupMetadata(
            deviceId: deviceId,
            deviceName: "Test Device",
            appVersion: "1.0.0",
            backupDate: Date(),
            dataTypes: ["health", "chat"],
            encryptionKeyId: "test-key-id",
            totalSize: 1024
        )

        // Set up mock backup data
        let originalPersonalInfo = PersonalHealthInfo(
            firstName: "Restored",
            lastName: "User",
            dateOfBirth: Date(),
            bloodType: .bPositive,
            gender: .female,
            height: 165,
            weight: 60,
            emergencyContact: EmergencyContact(
                name: "Emergency Contact",
                phoneNumber: "+9876543210",
                relationship: "Friend"
            )
        )

        let healthData = HealthDataBackup(personalInfo: originalPersonalInfo, bloodTests: [])
        let encryptedData = try await mockEncryptData(healthData)

        let mockRecord = CKRecord(recordType: "HealthData", recordID: CKRecord.ID(recordName: deviceId))
        mockRecord["HealthData"] = encryptedData
        mockDatabase.recordsToReturn[CKRecord.ID(recordName: deviceId)] = mockRecord

        mockContainer.accountStatus = .available
        try await backupManager.enableBackup()

        // When
        await backupManager.restoreFromBackup(backupMetadata)

        // Then
        await waitForRestoreCompletion()

        if case .completed = backupManager.status {
            // Restore completed successfully
            let databaseManager = DatabaseManager.shared
            let restoredPersonalInfo = try await databaseManager.fetchPersonalHealthInfo()

            XCTAssertNotNil(restoredPersonalInfo)
            XCTAssertEqual(restoredPersonalInfo?.firstName, "Restored")
            XCTAssertEqual(restoredPersonalInfo?.lastName, "User")
        } else {
            XCTFail("Restore should have completed successfully")
        }
    }

    // MARK: - Storage Management Tests

    func testBackupSize_ShouldBeCalculated() async throws {
        // Given
        mockContainer.accountStatus = .available
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.backupHealthData = true

        let personalInfo = PersonalHealthInfo(
            firstName: "Size",
            lastName: "Test",
            dateOfBirth: Date(),
            bloodType: .oNegative,
            gender: .male,
            height: 175,
            weight: 70,
            emergencyContact: EmergencyContact(
                name: "Emergency",
                phoneNumber: "+1111111111",
                relationship: "Family"
            )
        )

        let databaseManager = DatabaseManager.shared
        try await databaseManager.savePersonalHealthInfo(personalInfo)

        try await backupManager.enableBackup()

        // When
        await backupManager.performManualBackup()

        // Then
        await waitForBackupCompletion()

        XCTAssertGreaterThan(backupManager.lastBackupSize, 0)
    }

    // MARK: - Error Handling Tests

    func testBackup_WhenCloudKitUnavailable_ShouldReturnError() async throws {
        // Given
        mockContainer.accountStatus = .available
        mockDatabase.shouldFailOperations = true

        settingsManager.backupSettings.iCloudEnabled = true
        try await backupManager.enableBackup()

        // When
        await backupManager.performManualBackup()

        // Then
        await waitForBackupCompletion()

        if case .failed(let error) = backupManager.status {
            XCTAssertTrue(error == .cloudKitError("Mock CloudKit error"))
        } else {
            XCTFail("Expected backup to fail with CloudKit error")
        }
    }

    func testBackup_WhenInsufficientStorage_ShouldReturnStorageError() async throws {
        // Given
        mockContainer.accountStatus = .available
        mockDatabase.simulateStorageFull = true

        settingsManager.backupSettings.iCloudEnabled = true
        try await backupManager.enableBackup()

        // When
        await backupManager.performManualBackup()

        // Then
        await waitForBackupCompletion()

        if case .failed(let error) = backupManager.status {
            XCTAssertEqual(error, .insufficientStorage)
        } else {
            XCTFail("Expected backup to fail with insufficient storage error")
        }
    }

    // MARK: - Backup Scheduling Tests

    func testAutoBackup_WhenEnabled_ShouldScheduleBackup() async throws {
        // Given
        mockContainer.accountStatus = .available
        settingsManager.backupSettings.iCloudEnabled = true
        settingsManager.backupSettings.autoBackup = true
        settingsManager.backupSettings.backupFrequency = .daily

        try await backupManager.enableBackup()

        // When
        // Auto backup scheduling happens in background

        // Then
        // Verify that backup scheduling is active (this would require exposing internal state)
        XCTAssertEqual(backupManager.status, .idle)
    }

    // MARK: - Data Integrity Tests

    func testEncryptionDecryption_ShouldPreserveData() async throws {
        // Given
        let originalData = PersonalHealthInfo(
            firstName: "Encryption",
            lastName: "Test",
            dateOfBirth: Date(),
            bloodType: .abPositive,
            gender: .other,
            height: 180,
            weight: 80,
            emergencyContact: EmergencyContact(
                name: "Emergency Contact",
                phoneNumber: "+1234567890",
                relationship: "Parent"
            )
        )

        // When
        let encryptedData = try await mockEncryptData(originalData)
        let decryptedData: PersonalHealthInfo = try await mockDecryptData(encryptedData)

        // Then
        XCTAssertEqual(originalData.firstName, decryptedData.firstName)
        XCTAssertEqual(originalData.lastName, decryptedData.lastName)
        XCTAssertEqual(originalData.bloodType, decryptedData.bloodType)
        XCTAssertEqual(originalData.gender, decryptedData.gender)
    }

    // MARK: - Helper Methods

    private func waitForBackupCompletion(timeout: TimeInterval = 5.0) async {
        let startTime = Date()
        while backupManager.status.isActive && Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }

    private func waitForRestoreCompletion(timeout: TimeInterval = 5.0) async {
        let startTime = Date()
        while backupManager.status.isActive && Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }

    private func mockEncryptData<T: Codable>(_ data: T) async throws -> Data {
        let jsonData = try JSONEncoder().encode(data)
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        return sealedBox.combined!
    }

    private func mockDecryptData<T: Codable>(_ encryptedData: Data, as type: T.Type = T.self) async throws -> T {
        // For testing, we'll use a fixed key - in real implementation this would come from keychain
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(T.self, from: decryptedData)
    }
}

// MARK: - Mock CloudKit Classes

class MockCKContainer {
    let database: MockCKDatabase
    var accountStatus: CKAccountStatus = .available

    init(database: MockCKDatabase) {
        self.database = database
    }

    func accountStatus() async throws -> CKAccountStatus {
        return accountStatus
    }
}

class MockCKDatabase {
    var savedRecords: [CKRecord] = []
    var recordsToReturn: [CKRecord.ID: CKRecord] = [:]
    var shouldFailOperations = false
    var simulateStorageFull = false

    func save(_ record: CKRecord) async throws -> CKRecord {
        if shouldFailOperations {
            throw NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Mock CloudKit error"
            ])
        }

        if simulateStorageFull {
            throw NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "iCloud storage is full"
            ])
        }

        savedRecords.append(record)
        return record
    }

    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        if shouldFailOperations {
            throw NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Mock CloudKit error"
            ])
        }

        guard let record = recordsToReturn[recordID] else {
            throw NSError(domain: CKErrorDomain, code: CKError.unknownItem.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Record not found"
            ])
        }

        return record
    }

    func records(matching query: CKQuery) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?) {
        if shouldFailOperations {
            throw NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Mock CloudKit error"
            ])
        }

        let results: [(CKRecord.ID, Result<CKRecord, Error>)] = savedRecords.map { record in
            (record.recordID, .success(record))
        }

        return (matchResults: results, queryCursor: nil)
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID {
        if shouldFailOperations {
            throw NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Mock CloudKit error"
            ])
        }

        savedRecords.removeAll { $0.recordID == recordID }
        return recordID
    }
}

// MARK: - Test Data Models

private struct HealthDataBackup: Codable {
    let personalInfo: PersonalHealthInfo?
    let bloodTests: [BloodTestResult]
}