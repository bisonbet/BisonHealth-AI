import XCTest
@testable import HealthApp

@MainActor
final class iCloudBackupTests: XCTestCase {

    func testBackupMetadataUsesStableIdentifier() {
        let metadata = BackupMetadata(
            id: "backup-1",
            deviceId: "device-1",
            deviceName: "Test Device",
            appVersion: "1.0.0",
            backupDate: Date(),
            dataTypes: ["health", "chat"],
            encryptionKeyId: "key-1",
            totalSize: 1024
        )

        XCTAssertEqual(metadata.id, "backup-1")
        XCTAssertEqual(metadata.deviceId, "device-1")
        XCTAssertEqual(metadata.dataTypes, ["health", "chat"])
        XCTAssertEqual(metadata.totalSize, 1024)
    }

    func testBackupStatusDisplayTextForTerminalStates() {
        XCTAssertEqual(BackupStatus.disabled.displayText, "Disabled")
        XCTAssertEqual(BackupStatus.idle.displayText, "Ready")
        XCTAssertFalse(BackupStatus.disabled.isActive)
        XCTAssertFalse(BackupStatus.idle.isActive)

        XCTAssertTrue(BackupStatus.backingUp(progress: 0.25).isActive)
        XCTAssertTrue(BackupStatus.restoring(progress: 0.75).isActive)
    }

    func testBackupErrorRecoveryMessagesAreActionable() {
        XCTAssertEqual(
            BackupError.accountNotSignedIn.recoveryMessage,
            "Please sign in to your iCloud account in Settings."
        )
        XCTAssertEqual(
            BackupError.insufficientStorage.recoveryMessage,
            "Free up space in your iCloud account or upgrade storage."
        )
        XCTAssertEqual(
            BackupError.deviceNotAuthorized.recoveryMessage,
            "This device needs to be authorized for backup access."
        )
    }

    func testBackupSettingsDefaultsIncludeCoreDataTypes() {
        let settings = BackupSettings()

        XCTAssertFalse(settings.iCloudEnabled)
        XCTAssertTrue(settings.backupHealthData)
        XCTAssertTrue(settings.backupChatHistory)
        XCTAssertFalse(settings.backupDocuments)
        XCTAssertTrue(settings.backupAppSettings)
    }
}
