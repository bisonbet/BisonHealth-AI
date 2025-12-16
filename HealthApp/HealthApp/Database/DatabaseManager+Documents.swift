import Foundation
import SQLite

// MARK: - Document CRUD Operations (MedicalDocument)
extension DatabaseManager {

    // MARK: - Save Document
    func saveDocument(_ document: MedicalDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let tagsJson = try JSONEncoder().encode(document.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"

            let extractedHealthDataJson = try JSONEncoder().encode(document.extractedHealthData)

            // Encode extracted sections
            let sectionsJson = try JSONEncoder().encode(document.extractedSections)

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
                documentExtractedData <- extractedHealthDataJson,
                documentCategory <- document.documentCategory.rawValue,
                // MedicalDocument-specific fields
                documentExtractedText <- document.extractedText,
                documentRawDoclingOutput <- document.rawDoclingOutput,
                documentExtractedSections <- sectionsJson,
                documentDate <- document.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- document.providerName,
                documentProviderType <- document.providerType?.rawValue,
                documentIncludeInAIContext <- document.includeInAIContext,
                documentContextPriority <- document.contextPriority,
                documentLastEditedAt <- document.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
            )

            try db.run(insert)
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Documents
    func fetchDocuments() async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable.order(documentImportedAt.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Single Document
    func fetchDocument(id: UUID) async throws -> MedicalDocument? {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let query = documentsTable.filter(documentId == id.uuidString)

            if let row = try db.pluck(query) {
                return try buildMedicalDocument(from: row)
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
    
    // MARK: - Update Document File Path
    func updateDocumentFilePath(_ documentId: UUID, filePath: URL) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = documentsTable.filter(self.documentId == documentId.uuidString)

        let update = query.update(
            documentFilePath <- filePath.absoluteString
        )

        let rowsUpdated = try db.run(update)
        if rowsUpdated == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Update Document Category
    func updateDocumentCategory(_ documentId: UUID, category: DocumentCategory) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = documentsTable.filter(self.documentId == documentId.uuidString)

        let update = query.update(
            documentCategory <- category.rawValue
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
    func deleteDocument(_ document: MedicalDocument) async throws {
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
    func fetchDocuments(with status: ProcessingStatus) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentProcessingStatus == status.rawValue)
                .order(documentImportedAt.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Documents by Type
    func fetchDocuments(ofType type: DocumentType) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentFileType == type.rawValue)
                .order(documentImportedAt.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Search Documents
    func searchDocuments(query: String) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []
        let searchTerm = "%\(query.lowercased())%"

        do {
            let sqlQuery = documentsTable
                .filter(documentFileName.like(searchTerm))
                .order(documentImportedAt.desc)

            for row in try db.prepare(sqlQuery) {
                let document = try buildMedicalDocument(from: row)
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
    private func buildMedicalDocument(from row: Row) throws -> MedicalDocument {
        let id = UUID(uuidString: row[documentId]) ?? UUID()
        let fileName = row[documentFileName]
        let fileType = DocumentType(rawValue: row[documentFileType]) ?? .other
        let filePath = URL(string: row[documentFilePath]) ?? URL(fileURLWithPath: "")
        let thumbnailPath = row[documentThumbnailPath].flatMap { URL(string: $0) }
        let processingStatus = ProcessingStatus(rawValue: row[documentProcessingStatus]) ?? .pending
        let importedAt = Date(timeIntervalSince1970: TimeInterval(row[documentImportedAt]))
        let processedAt = row[documentProcessedAt].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let fileSize = row[documentFileSize]
        let notes = row[documentNotes]

        // Decode tags
        let tagsString = row[documentTags]
        let tagsData = tagsString.data(using: .utf8) ?? Data()
        let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []

        // Decode extracted health data
        let extractedHealthData: [AnyHealthData]
        if let extractedDataBlob = row[documentExtractedData] {
            extractedHealthData = (try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob)) ?? []
        } else {
            extractedHealthData = []
        }

        // Decode document category
        let categoryRaw = (try? row.get(self.documentCategory)) ?? "other"
        let documentCategory = DocumentCategory(rawValue: categoryRaw) ?? .other

        // Decode MedicalDocument-specific fields
        let documentDate = (try? row.get(self.documentDate)).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let providerName = try? row.get(self.documentProviderName)
        let providerTypeRaw = try? row.get(self.documentProviderType)
        let providerType = providerTypeRaw.flatMap { ProviderType(rawValue: $0) }
        let extractedText = try? row.get(self.documentExtractedText)
        let rawDoclingOutput = try? row.get(self.documentRawDoclingOutput)
        let includeInAIContext = (try? row.get(self.documentIncludeInAIContext)) ?? false
        let contextPriority = (try? row.get(self.documentContextPriority)) ?? 3
        let lastEditedAt = (try? row.get(self.documentLastEditedAt)).map { Date(timeIntervalSince1970: TimeInterval($0)) }

        // Decode extracted sections
        let extractedSections: [DocumentSection]
        if let sectionsBlob = try? row.get(self.documentExtractedSections) {
            extractedSections = (try? JSONDecoder().decode([DocumentSection].self, from: sectionsBlob)) ?? []
        } else {
            extractedSections = []
        }

        return MedicalDocument(
            id: id,
            fileName: fileName,
            fileType: fileType,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            processingStatus: processingStatus,
            documentDate: documentDate,
            providerName: providerName,
            providerType: providerType,
            documentCategory: documentCategory,
            extractedText: extractedText,
            rawDoclingOutput: rawDoclingOutput,
            extractedSections: extractedSections,
            includeInAIContext: includeInAIContext,
            contextPriority: contextPriority,
            extractedHealthData: extractedHealthData,
            importedAt: importedAt,
            processedAt: processedAt,
            lastEditedAt: lastEditedAt,
            fileSize: fileSize,
            tags: tags,
            notes: notes
        )
    }
}