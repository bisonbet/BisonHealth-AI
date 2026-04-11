import Foundation
import SQLite
import CryptoKit

// MARK: - Data Recovery Operations
extension DatabaseManager {
    
    // MARK: - Recovery Scan Results
    struct RecoveryScanResult {
        let totalRecords: Int
        let recoverableRecords: [RecoverableRecord]
        let corruptedRecords: [CorruptedRecord]
        let emptyRecords: [String] // Record IDs with empty data
    }
    
    struct RecoverableRecord {
        let recordId: String
        let type: HealthDataType
        let encryptedData: Data
        let dataSize: Int
        let isValidFormat: Bool
    }
    
    struct CorruptedRecord {
        let recordId: String
        let type: HealthDataType
        let encryptedData: Data
        let dataSize: Int
        let error: String
    }
    
    // MARK: - Scan Database for Recoverable Data
    /// Scans the database to identify recoverable and corrupted records
    func scanDatabaseForRecovery() async throws -> RecoveryScanResult {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        AppLog.shared.database("Starting database recovery scan...")
        
        var totalRecords = 0
        var recoverableRecords: [RecoverableRecord] = []
        var corruptedRecords: [CorruptedRecord] = []
        var emptyRecords: [String] = []
        
        do {
            let query = healthDataTable.select(
                healthDataId,
                healthDataType,
                healthDataEncryptedData
            )
            
            for row in try db.prepare(query) {
                totalRecords += 1
                let recordId = row[healthDataId]
                let typeString = row[healthDataType]
                let encryptedData = row[healthDataEncryptedData]
                
                guard let healthDataType = HealthDataType(rawValue: typeString) else {
                    AppLog.shared.database("Unknown health data type: \(typeString) for record \(recordId)", level: .warning)
                    continue
                }
                
                // Check if data is empty
                if encryptedData.isEmpty {
                    AppLog.shared.database("Record \(recordId) has empty encrypted data", level: .warning)
                    emptyRecords.append(recordId)
                    continue
                }
                
                // Check minimum size
                if encryptedData.count < 28 {
                    AppLog.shared.database("Record \(recordId) has invalid size (\(encryptedData.count) bytes, minimum 28)", level: .warning)
                    corruptedRecords.append(CorruptedRecord(
                        recordId: recordId,
                        type: healthDataType,
                        encryptedData: encryptedData,
                        dataSize: encryptedData.count,
                        error: "Data too small (\(encryptedData.count) bytes)"
                    ))
                    continue
                }
                
                // Try to create a sealed box (validates format)
                do {
                    _ = try AES.GCM.SealedBox(combined: encryptedData)
                    
                    // Format is valid - check if we can decrypt with current key
                    let canDecrypt = await tryDecryptWithCurrentKey(encryptedData, type: healthDataType)
                    
                    if canDecrypt {
                        recoverableRecords.append(RecoverableRecord(
                            recordId: recordId,
                            type: healthDataType,
                            encryptedData: encryptedData,
                            dataSize: encryptedData.count,
                            isValidFormat: true
                        ))
                    } else {
                        corruptedRecords.append(CorruptedRecord(
                            recordId: recordId,
                            type: healthDataType,
                            encryptedData: encryptedData,
                            dataSize: encryptedData.count,
                            error: "Cannot decrypt with current key (key may have changed)"
                        ))
                    }
                } catch {
                    corruptedRecords.append(CorruptedRecord(
                        recordId: recordId,
                        type: healthDataType,
                        encryptedData: encryptedData,
                        dataSize: encryptedData.count,
                        error: "Invalid encrypted data format: \(error.localizedDescription)"
                    ))
                }
            }
            
            AppLog.shared.database("Recovery scan complete: Total=\(totalRecords), Recoverable=\(recoverableRecords.count), Corrupted=\(corruptedRecords.count), Empty=\(emptyRecords.count)")

        } catch {
            AppLog.shared.error("Failed to scan database for recovery: \(error.localizedDescription)", error: error, category: .database)
            throw error
        }
        
        return RecoveryScanResult(
            totalRecords: totalRecords,
            recoverableRecords: recoverableRecords,
            corruptedRecords: corruptedRecords,
            emptyRecords: emptyRecords
        )
    }
    
    // MARK: - Try Decrypt with Current Key
    private func tryDecryptWithCurrentKey(_ encryptedData: Data, type: HealthDataType) async -> Bool {
        do {
            // Try to decrypt based on type
            switch type {
            case .personalInfo:
                _ = try decryptData(encryptedData, as: PersonalHealthInfo.self)
                return true
            case .bloodTest:
                _ = try decryptData(encryptedData, as: BloodTestResult.self)
                return true
            case .imagingReport, .healthCheckup:
                // These are stored in documents table, not health_data table
                return false
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Attempt Recovery of Corrupted Records
    /// Attempts to recover data from corrupted records by trying different decryption methods
    func attemptDataRecovery(for recordIds: [String]? = nil) async throws -> RecoveryAttemptResult {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        AppLog.shared.database("Attempting data recovery...")
        
        var recovered: [String] = []
        var failed: [String] = []
        
        // First, scan to identify records
        let scanResult = try await scanDatabaseForRecovery()
        
        // Focus on corrupted records that have valid format but can't be decrypted
        let recordsToRecover = recordIds ?? scanResult.corruptedRecords
            .filter { $0.dataSize >= 28 } // Only try records with valid size
            .map { $0.recordId }
        
        AppLog.shared.database("Attempting to recover \(recordsToRecover.count) record(s)...")
        
        for recordId in recordsToRecover {
            do {
                // Get the record
                let query = healthDataTable.filter(healthDataId == recordId)
                guard let row = try db.pluck(query) else {
                    AppLog.shared.database("Record \(recordId) not found", level: .warning)
                    failed.append(recordId)
                    continue
                }
                
                let typeString = row[healthDataType]
                let encryptedData = row[healthDataEncryptedData]
                
                guard let healthDataType = HealthDataType(rawValue: typeString) else {
                    AppLog.shared.database("Unknown type for record \(recordId): \(typeString)", level: .warning)
                    failed.append(recordId)
                    continue
                }
                
                // Try to decrypt with current key
                var decrypted = false
                switch healthDataType {
                case .personalInfo:
                    if let _ = try? decryptData(encryptedData, as: PersonalHealthInfo.self) {
                        decrypted = true
                    }
                case .bloodTest:
                    if let _ = try? decryptData(encryptedData, as: BloodTestResult.self) {
                        decrypted = true
                    }
                case .imagingReport, .healthCheckup:
                    // Not in health_data table
                    break
                }
                
                if decrypted {
                    AppLog.shared.database("Successfully recovered record \(recordId)")
                    recovered.append(recordId)
                } else {
                    AppLog.shared.database("Could not recover record \(recordId) - data may be encrypted with different key", level: .warning)
                    failed.append(recordId)
                }
                
            } catch {
                AppLog.shared.error("Error recovering record \(recordId): \(error.localizedDescription)", error: error, category: .database)
                failed.append(recordId)
            }
        }
        
        AppLog.shared.database("Recovery attempt complete: \(recovered.count) recovered, \(failed.count) failed")
        
        return RecoveryAttemptResult(
            recoveredRecordIds: recovered,
            failedRecordIds: failed,
            scanResult: scanResult
        )
    }
    
    // MARK: - Export Corrupted Records for Analysis
    /// Exports corrupted record data for external analysis (without decryption)
    func exportCorruptedRecordsForAnalysis() async throws -> URL {
        let scanResult = try await scanDatabaseForRecovery()
        
        struct CorruptedRecordExport: Codable {
            let recordId: String
            let type: String
            let dataSize: Int
            let error: String
            let dataHex: String // Hex representation for analysis
        }
        
        var exports: [CorruptedRecordExport] = []
        
        for corrupted in scanResult.corruptedRecords {
            let hexString = corrupted.encryptedData.map { String(format: "%02x", $0) }.joined()
            exports.append(CorruptedRecordExport(
                recordId: corrupted.recordId,
                type: corrupted.type.rawValue,
                dataSize: corrupted.dataSize,
                error: corrupted.error,
                dataHex: hexString
            ))
        }
        
        let jsonData = try JSONEncoder().encode(exports)
        let fileName = "corrupted_records_\(Date().timeIntervalSince1970).json"
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try jsonData.write(to: fileURL)
        
        appLog.database("Exported \(exports.count) corrupted records to \(fileURL.path)")
        
        return fileURL
    }
}

// MARK: - Recovery Result Types
struct RecoveryAttemptResult {
    let recoveredRecordIds: [String]
    let failedRecordIds: [String]
    let scanResult: DatabaseManager.RecoveryScanResult
}

