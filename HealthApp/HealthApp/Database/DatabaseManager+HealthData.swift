import Foundation
import SQLite

// MARK: - Health Data CRUD Operations
extension DatabaseManager {
    
    // MARK: - Save Health Data
    func save<T: HealthDataProtocol>(_ data: T) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let encryptedData = try encryptData(data)
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
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Health Data
    func fetch<T: HealthDataProtocol>(_ type: T.Type, healthDataType: HealthDataType) async throws -> [T] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [T] = []
        
        do {
            let query = healthDataTable.filter(self.healthDataType == healthDataType.rawValue)
                .order(healthDataUpdatedAt.desc)
            
            for row in try db.prepare(query) {
                let encryptedData = row[healthDataEncryptedData]
                let decryptedData = try decryptData(encryptedData, as: type)
                results.append(decryptedData)
            }
        } catch {
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
                return try decryptData(encryptedData, as: type)
            }
            
            return nil
        } catch {
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