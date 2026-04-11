import Foundation
import SQLite
import CryptoKit

// MARK: - Health Data CRUD Operations
extension DatabaseManager {
    
    // MARK: - Save Health Data
    func save<T: HealthDataProtocol>(_ data: T) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            // CRITICAL: Encrypt and verify before saving
            let encryptedData = try encryptData(data)

            // Double-check: Verify encrypted data is not empty
            guard !encryptedData.isEmpty else {
                AppLog.shared.database("CRITICAL: Encrypted data is empty after encryption! Not saving to prevent data loss.", level: .error)
                throw DatabaseError.encryptionFailed
            }

            // Double-check: Verify minimum size
            guard encryptedData.count >= 28 else {
                AppLog.shared.database("CRITICAL: Encrypted data is too small (\(encryptedData.count) bytes)! Not saving to prevent data loss.", level: .error)
                throw DatabaseError.encryptionFailed
            }

            // Triple-check: Verify we can decrypt what we're about to save
            do {
                switch data.type {
                case .personalInfo:
                    if data is PersonalHealthInfo {
                        _ = try decryptData(encryptedData, as: PersonalHealthInfo.self)
                    }
                case .bloodTest:
                    if data is BloodTestResult {
                        _ = try decryptData(encryptedData, as: BloodTestResult.self)
                    }
                case .imagingReport, .healthCheckup:
                    // These are stored in documents table
                    break
                }
            } catch {
                AppLog.shared.error("CRITICAL: Cannot decrypt data we just encrypted! Not saving to prevent data loss. Error: \(error.localizedDescription)", error: error, category: .database)
                throw DatabaseError.encryptionFailed
            }
            
            let metadataJson = try data.metadata.map { try JSONSerialization.data(withJSONObject: $0) }
            let metadataString = metadataJson.map { String(data: $0, encoding: .utf8) } ?? nil
            
            let insert = healthDataTable.insert(or: .replace,
                healthDataId <- data.id.uuidString,
                healthDataType <- data.type.rawValue,
                healthDataEncryptedData <- encryptedData,
                healthDataCreatedAt <- Int64(data.createdAt.timeIntervalSince1970),
                healthDataUpdatedAt <- Int64(data.updatedAt.timeIntervalSince1970),
                healthDataMetadata <- metadataString
            )
            
            try db.run(insert)
            
            AppLog.shared.database("Successfully saved \(data.type.rawValue) record \(data.id.uuidString) (encrypted size: \(encryptedData.count) bytes)")
        } catch let error as DatabaseError {
            throw error
        } catch {
            AppLog.shared.error("Failed to save health data: \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Health Data
    func fetch<T: HealthDataProtocol>(_ type: T.Type, healthDataType: HealthDataType) async throws -> [T] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [T] = []
        var corruptedRecords: Int = 0
        var corruptedRecordIds: [String] = []

        do {
            let query = healthDataTable.filter(self.healthDataType == healthDataType.rawValue)
                .order(healthDataUpdatedAt.desc)
            
            for row in try db.prepare(query) {
                let recordId = row[healthDataId]
                let encryptedData = row[healthDataEncryptedData]
                
                // Check if encrypted data is empty or invalid before attempting decryption
                if encryptedData.isEmpty {
                    AppLog.shared.database("Health data record \(recordId) of type \(healthDataType.rawValue) has empty encrypted data - skipping", level: .warning)
                    corruptedRecords += 1
                    corruptedRecordIds.append(recordId)
                    continue
                }
                
                do {
                    let decryptedData = try decryptData(encryptedData, as: type)
                    results.append(decryptedData)
                } catch {
                    // Log the actual error for debugging
                    AppLog.shared.error("Failed to decrypt health data record \(recordId) of type \(healthDataType.rawValue): \(error.localizedDescription)", error: error, category: .database)
                    corruptedRecords += 1
                    corruptedRecordIds.append(recordId)
                    
                    // Continue processing other records instead of failing entirely
                    // This allows the app to load valid data even if some records are corrupted
                }
            }
            
            // If all records failed to decrypt, log a warning but return empty array instead of throwing
            // This allows the app to continue functioning even with corrupted data
            if corruptedRecords > 0 && results.isEmpty {
                AppLog.shared.database("All \(corruptedRecords) health data records of type \(healthDataType.rawValue) failed to decrypt. Returning empty array. Corrupted record IDs: \(corruptedRecordIds.joined(separator: ", "))", level: .warning)
                // Don't throw - return empty array to allow app to continue
                return []
            }
            
            // Log warning if some records were corrupted but we have valid data
            if corruptedRecords > 0 {
                AppLog.shared.database("Skipped \(corruptedRecords) corrupted health data record(s) of type \(healthDataType.rawValue), loaded \(results.count) valid record(s). Corrupted IDs: \(corruptedRecordIds.joined(separator: ", "))", level: .warning)
            }
        } catch let error as DatabaseError {
            // Re-throw database errors as-is (connection errors, etc.)
            throw error
        } catch {
            // For other errors, log and throw decryption error
            AppLog.shared.error("Unexpected error while fetching health data of type \(healthDataType.rawValue): \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Fetch Single Health Data Item
    func fetchHealthData<T: HealthDataProtocol>(id: UUID, as type: T.Type) async throws -> T? {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let query = healthDataTable.filter(healthDataId == id.uuidString)
            
            if let row = try db.pluck(query) {
                let encryptedData = row[healthDataEncryptedData]
                
                do {
                    return try decryptData(encryptedData, as: type)
                } catch {
                    // Log the actual error for debugging
                    AppLog.shared.error("Failed to decrypt health data record \(id.uuidString): \(error.localizedDescription)", error: error, category: .database)
                    throw DatabaseError.decryptionFailed
                }
            }
            
            return nil
        } catch let error as DatabaseError {
            // Re-throw database errors as-is
            throw error
        } catch {
            // For other errors, log and throw decryption error
            AppLog.shared.error("Unexpected error while fetching health data record \(id.uuidString): \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.decryptionFailed
        }
    }
    
    // MARK: - Update Health Data
    func update<T: HealthDataProtocol>(_ data: T) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let encryptedData = try encryptData(data)
            let metadataJson = try data.metadata.map { try JSONSerialization.data(withJSONObject: $0) }
            let metadataString = metadataJson.map { String(data: $0, encoding: .utf8) } ?? nil
            
            let query = healthDataTable.filter(healthDataId == data.id.uuidString)
            let update = query.update(
                healthDataEncryptedData <- encryptedData,
                healthDataUpdatedAt <- Int64(data.updatedAt.timeIntervalSince1970),
                healthDataMetadata <- metadataString
            )
            
            let rowsUpdated = try db.run(update)
            if rowsUpdated == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            if error is DatabaseError {
                throw error
            } else {
                throw DatabaseError.encryptionFailed
            }
        }
    }
    
    // MARK: - Delete Health Data
    func delete<T: HealthDataProtocol>(_ data: T) async throws {
        try await deleteHealthData(id: data.id)
    }
    
    func deleteHealthData(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = healthDataTable.filter(healthDataId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())
        
        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Fetch All Health Data Types
    func fetchAllHealthDataTypes() async throws -> [HealthDataType] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var types: Set<HealthDataType> = []
        
        let query = healthDataTable.select(distinct: healthDataType)
        
        for row in try db.prepare(query) {
            if let type = HealthDataType(rawValue: row[healthDataType]) {
                types.insert(type)
            }
        }
        
        return Array(types).sorted { $0.displayName < $1.displayName }
    }
    
    // MARK: - Health Data Statistics
    func getHealthDataCount(for type: HealthDataType) async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = healthDataTable.filter(healthDataType == type.rawValue).count
        return try db.scalar(query)
    }
    
    func getTotalHealthDataCount() async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        return try db.scalar(healthDataTable.count)
    }
    
    // MARK: - Fetch Personal Health Info (Convenience)
    func fetchPersonalHealthInfo() async throws -> PersonalHealthInfo? {
        let results: [PersonalHealthInfo] = try await fetch(PersonalHealthInfo.self, healthDataType: .personalInfo)
        return results.first
    }
    
    // MARK: - Fetch Blood Test Results (Convenience)
    func fetchBloodTestResults() async throws -> [BloodTestResult] {
        return try await fetch(BloodTestResult.self, healthDataType: .bloodTest)
    }
    
    // MARK: - Fetch Recent Health Data
    func fetchRecentHealthData(limit: Int = 10) async throws -> [AnyHealthDataItem] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [AnyHealthDataItem] = []
        
        let query = healthDataTable
            .order(healthDataUpdatedAt.desc)
            .limit(limit)
        
        for row in try db.prepare(query) {
            let typeString = row[healthDataType]
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(row[healthDataUpdatedAt]))
            let id = UUID(uuidString: row[healthDataId]) ?? UUID()
            
            if let healthDataType = HealthDataType(rawValue: typeString) {
                let item = AnyHealthDataItem(
                    id: id,
                    type: healthDataType,
                    updatedAt: updatedAt
                )
                results.append(item)
            }
        }
        
        return results
    }
    
    // MARK: - Cleanup Corrupted Records
    /// Deletes health data records that have empty or invalid encrypted data
    /// Returns the number of records deleted
    func cleanupCorruptedRecords(for healthDataType: HealthDataType? = nil) async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var deletedCount = 0
        
        do {
            var query = healthDataTable
            
            // Filter by type if specified
            if let type = healthDataType {
                query = query.filter(self.healthDataType == type.rawValue)
            }
            
            // Find records with empty encrypted data
            for row in try db.prepare(query) {
                let recordId = row[healthDataId]
                let encryptedData = row[healthDataEncryptedData]
                let typeString = row[self.healthDataType]
                
                // Check if encrypted data is empty or too small to be valid
                if encryptedData.isEmpty || encryptedData.count < 28 {
                    AppLog.shared.database("Deleting corrupted health data record \(recordId) of type \(typeString) (empty or invalid encrypted data)", level: .warning)
                    
                    // Delete the corrupted record
                    let deleteQuery = healthDataTable.filter(healthDataId == recordId)
                    try db.run(deleteQuery.delete())
                    deletedCount += 1
                } else {
                    // Try to decrypt to verify it's valid
                    do {
                        // We don't know the exact type, so we'll just try to create a sealed box
                        // If this fails, the data is corrupted
                        _ = try AES.GCM.SealedBox(combined: encryptedData)
                    } catch {
                        AppLog.shared.database("Deleting corrupted health data record \(recordId) of type \(typeString) (decryption validation failed)", level: .warning)
                        
                        // Delete the corrupted record
                        let deleteQuery = healthDataTable.filter(healthDataId == recordId)
                        try db.run(deleteQuery.delete())
                        deletedCount += 1
                    }
                }
            }
            
            if deletedCount > 0 {
                AppLog.shared.database("Cleaned up \(deletedCount) corrupted health data record(s)")
            }
        } catch {
            AppLog.shared.error("Failed to cleanup corrupted records: \(error.localizedDescription)", error: error, category: .database)
            throw error
        }
        
        return deletedCount
    }
}

// MARK: - Helper Types
struct AnyHealthDataItem {
    let id: UUID
    let type: HealthDataType
    let updatedAt: Date
    
    var displayName: String {
        return type.displayName
    }
    
    var icon: String {
        return type.icon
    }
}