import Foundation
import SQLite

// MARK: - Document CRUD Operations
extension DatabaseManager {
    
    // MARK: - Save Document
    func saveDocument(_ document: HealthDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let tagsJson = try JSONEncoder().encode(document.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"
            
            let extractedDataJson = try JSONEncoder().encode(document.extractedData)
            
            let insert = documentsTable.insert(or: .replace,
                documentId <- document.id.uuidString,
                documentFileName <- document.fileName,
                documentFileType <- document.fileType.rawValue,
                documentFilePath <- document.filePath.absoluteString,
                documentThumbnailPath <- document.thumbnailPath?.absoluteString,
                documentProcessingStatus <- document.processingStatus.rawValue,
                documentImportedAt <- Int64(document.importedAt.timeIntervalSince1970),
                documentProcessedAt <- document.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- document.fileSize,
                documentTags <- tagsString,
                documentNotes <- document.notes,
                documentExtractedData <- extractedDataJson
            )
            
            try db.run(insert)
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Documents
    func fetchDocuments() async throws -> [HealthDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [HealthDocument] = []
        
        do {
            let query = documentsTable.order(documentImportedAt.desc)
            
            for row in try db.prepare(query) {
                let document = try buildHealthDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Fetch Single Document
    func fetchDocument(id: UUID) async throws -> HealthDocument? {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let query = documentsTable.filter(documentId == id.uuidString)
            
            if let row = try db.pluck(query) {
                return try buildHealthDocument(from: row)
            }
            
            return nil
        } catch {
            throw DatabaseError.decryptionFailed
        }
    }
    
    // MARK: - Update Document Status
    func updateDocumentStatus(_ documentId: UUID, status: ProcessingStatus) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = documentsTable.filter(self.documentId == documentId.uuidString)
        let processedAt = status == .completed ? Int64(Date().timeIntervalSince1970) : nil
        
        let update = query.update(
            documentProcessingStatus <- status.rawValue,
            documentProcessedAt <- processedAt
        )
        
        let rowsUpdated = try db.run(update)
        if rowsUpdated == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Update Document Extracted Data
    func updateDocumentExtractedData(_ documentId: UUID, extractedData: [AnyHealthData]) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        do {
            let extractedDataJson = try JSONEncoder().encode(extractedData)
            
            let query = documentsTable.filter(self.documentId == documentId.uuidString)
            let update = query.update(
                documentExtractedData <- extractedDataJson,
                documentProcessingStatus <- ProcessingStatus.completed.rawValue,
                documentProcessedAt <- Int64(Date().timeIntervalSince1970)
            )
            
            let rowsUpdated = try db.run(update)
            if rowsUpdated == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Delete Document
    func deleteDocument(_ document: HealthDocument) async throws {
        try await deleteDocument(id: document.id)
    }
    
    func deleteDocument(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = documentsTable.filter(documentId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())
        
        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Fetch Documents by Status
    func fetchDocuments(with status: ProcessingStatus) async throws -> [HealthDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [HealthDocument] = []
        
        do {
            let query = documentsTable
                .filter(documentProcessingStatus == status.rawValue)
                .order(documentImportedAt.desc)
            
            for row in try db.prepare(query) {
                let document = try buildHealthDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Fetch Documents by Type
    func fetchDocuments(ofType type: DocumentType) async throws -> [HealthDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [HealthDocument] = []
        
        do {
            let query = documentsTable
                .filter(documentFileType == type.rawValue)
                .order(documentImportedAt.desc)
            
            for row in try db.prepare(query) {
                let document = try buildHealthDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Search Documents
    func searchDocuments(query: String) async throws -> [HealthDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        var results: [HealthDocument] = []
        let searchTerm = "%\(query.lowercased())%"
        
        do {
            let sqlQuery = documentsTable
                .filter(documentFileName.like(searchTerm))
                .order(documentImportedAt.desc)
            
            for row in try db.prepare(sqlQuery) {
                let document = try buildHealthDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        
        return results
    }
    
    // MARK: - Document Statistics
    func getDocumentCount() async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        return try db.scalar(documentsTable.count)
    }
    
    func getDocumentCount(for status: ProcessingStatus) async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = documentsTable.filter(documentProcessingStatus == status.rawValue).count
        return try db.scalar(query)
    }
    
    func getTotalFileSize() async throws -> Int64 {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let result: Int64? = try db.scalar(documentsTable.select(documentFileSize.sum))
        return result ?? 0
    }
    
    // MARK: - Helper Methods
    private func buildHealthDocument(from row: Row) throws -> HealthDocument {
        let id = UUID(uuidString: row[documentId]) ?? UUID()
        let fileName = row[documentFileName]
        let fileType = DocumentType(rawValue: row[documentFileType]) ?? .other
        let filePath = URL(string: row[documentFilePath]) ?? URL(fileURLWithPath: "")
        let thumbnailPath = row[documentThumbnailPath].map { URL(string: $0) } ?? nil
        let processingStatus = ProcessingStatus(rawValue: row[documentProcessingStatus]) ?? .pending
        let importedAt = Date(timeIntervalSince1970: TimeInterval(row[documentImportedAt]))
        let processedAt = row[documentProcessedAt].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let fileSize = row[documentFileSize]
        let notes = row[documentNotes]
        
        // Decode tags
        let tagsString = row[documentTags]
        let tagsData = tagsString.data(using: .utf8) ?? Data()
        let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
        
        // Decode extracted data
        let extractedData: [AnyHealthData]
        if let extractedDataBlob = row[documentExtractedData] {
            extractedData = (try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob)) ?? []
        } else {
            extractedData = []
        }
        
        return HealthDocument(
            id: id,
            fileName: fileName,
            fileType: fileType,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            processingStatus: processingStatus,
            extractedData: extractedData,
            importedAt: importedAt,
            processedAt: processedAt,
            fileSize: fileSize,
            tags: tags,
            notes: notes
        )
    }
}