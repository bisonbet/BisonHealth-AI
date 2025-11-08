import Foundation
import SQLite

// MARK: - Medical Document CRUD Operations
extension DatabaseManager {

    // MARK: - Save Medical Document
    func saveMedicalDocument(_ document: MedicalDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let tagsJson = try JSONEncoder().encode(document.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"

            let extractedHealthDataJson = try JSONEncoder().encode(document.extractedHealthData)

            let extractedSectionsJson = try JSONEncoder().encode(document.extractedSections)

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
                // Medical document fields
                documentDate <- document.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- document.providerName,
                documentProviderType <- document.providerType?.rawValue,
                documentCategory <- document.documentCategory.rawValue,
                documentExtractedText <- document.extractedText,
                documentRawDoclingOutput <- document.rawDoclingOutput,
                documentExtractedSections <- extractedSectionsJson,
                documentIncludeInAIContext <- document.includeInAIContext,
                documentContextPriority <- document.contextPriority,
                documentLastEditedAt <- document.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
            )

            try db.run(insert)
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }

    // MARK: - Fetch Medical Documents
    func fetchMedicalDocuments() async throws -> [MedicalDocument] {
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

    // MARK: - Fetch Single Medical Document
    func fetchMedicalDocument(id: UUID) async throws -> MedicalDocument? {
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

    // MARK: - Fetch Documents for AI Context
    func fetchDocumentsForAIContext() async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentIncludeInAIContext == true)
                .filter(documentProcessingStatus == ProcessingStatus.completed.rawValue)
                .order(documentContextPriority.desc, documentDate.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Documents by Category
    func fetchMedicalDocuments(category: DocumentCategory) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentCategory == category.rawValue)
                .order(documentDate.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Documents by Provider
    func fetchMedicalDocuments(providerName: String) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentProviderName == providerName)
                .order(documentDate.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Documents by Date Range
    func fetchMedicalDocuments(from startDate: Date, to endDate: Date) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []
        let startTimestamp = Int64(startDate.timeIntervalSince1970)
        let endTimestamp = Int64(endDate.timeIntervalSince1970)

        do {
            let query = documentsTable
                .filter(documentDate >= startTimestamp && documentDate <= endTimestamp)
                .order(documentDate.desc)

            for row in try db.prepare(query) {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Update Medical Document
    func updateMedicalDocument(_ document: MedicalDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let tagsJson = try JSONEncoder().encode(document.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"

            let extractedHealthDataJson = try JSONEncoder().encode(document.extractedHealthData)
            let extractedSectionsJson = try JSONEncoder().encode(document.extractedSections)

            let query = documentsTable.filter(self.documentId == document.id.uuidString)

            let update = query.update(
                documentFileName <- document.fileName,
                documentFileType <- document.fileType.rawValue,
                documentFilePath <- document.filePath.absoluteString,
                documentThumbnailPath <- document.thumbnailPath?.absoluteString,
                documentProcessingStatus <- document.processingStatus.rawValue,
                documentProcessedAt <- document.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- document.fileSize,
                documentTags <- tagsString,
                documentNotes <- document.notes,
                documentExtractedData <- extractedHealthDataJson,
                // Medical document fields
                documentDate <- document.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- document.providerName,
                documentProviderType <- document.providerType?.rawValue,
                documentCategory <- document.documentCategory.rawValue,
                documentExtractedText <- document.extractedText,
                documentRawDoclingOutput <- document.rawDoclingOutput,
                documentExtractedSections <- extractedSectionsJson,
                documentIncludeInAIContext <- document.includeInAIContext,
                documentContextPriority <- document.contextPriority,
                documentLastEditedAt <- document.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
            )

            let rowsUpdated = try db.run(update)
            if rowsUpdated == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            throw DatabaseError.encryptionFailed
        }
    }

    // MARK: - Update Document AI Context Status
    func updateDocumentAIContextStatus(_ documentId: UUID, includeInContext: Bool) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = documentsTable.filter(self.documentId == documentId.uuidString)

        let update = query.update(
            documentIncludeInAIContext <- includeInContext
        )

        let rowsUpdated = try db.run(update)
        if rowsUpdated == 0 {
            throw DatabaseError.notFound
        }
    }

    // MARK: - Update Multiple Documents AI Context Status
    func updateDocumentsAIContextStatus(_ documentIds: [UUID], includeInContext: Bool) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        for documentId in documentIds {
            try await updateDocumentAIContextStatus(documentId, includeInContext: includeInContext)
        }
    }

    // MARK: - Delete Medical Document
    func deleteMedicalDocument(_ document: MedicalDocument) async throws {
        try await deleteMedicalDocument(id: document.id)
    }

    func deleteMedicalDocument(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = documentsTable.filter(documentId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())

        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }

    // MARK: - Search Medical Documents
    func searchMedicalDocuments(query: String) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []
        let searchTerm = "%\(query.lowercased())%"

        do {
            let sqlQuery = documentsTable
                .filter(
                    documentFileName.like(searchTerm) ||
                    documentProviderName.like(searchTerm) ||
                    documentExtractedText.like(searchTerm)
                )
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

    // MARK: - Statistics
    func getMedicalDocumentCount(category: DocumentCategory? = nil) async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }

        if let category = category {
            let query = documentsTable.filter(documentCategory == category.rawValue).count
            return try db.scalar(query)
        } else {
            return try db.scalar(documentsTable.count)
        }
    }

    func getAIContextDocumentCount() async throws -> Int {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = documentsTable.filter(documentIncludeInAIContext == true).count
        return try db.scalar(query)
    }

    // MARK: - Helper Methods
    private func buildMedicalDocument(from row: Row) throws -> MedicalDocument {
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

        // Decode extracted health data
        let extractedHealthData: [AnyHealthData]
        if let extractedDataBlob = row[documentExtractedData] {
            extractedHealthData = (try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob)) ?? []
        } else {
            extractedHealthData = []
        }

        // Medical document fields
        let documentDate = try? row.get(self.documentDate).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let providerName = try? row.get(self.documentProviderName)
        let providerTypeRaw = try? row.get(self.documentProviderType)
        let providerType = providerTypeRaw.flatMap { ProviderType(rawValue: $0) }
        let categoryRaw = (try? row.get(self.documentCategory)) ?? "other"
        let category = DocumentCategory(rawValue: categoryRaw) ?? .other
        let extractedText = try? row.get(self.documentExtractedText)
        let rawDoclingOutput = try? row.get(self.documentRawDoclingOutput)

        // Decode extracted sections
        let extractedSections: [DocumentSection]
        if let sectionsBlob = try? row.get(self.documentExtractedSections) {
            extractedSections = (try? JSONDecoder().decode([DocumentSection].self, from: sectionsBlob)) ?? []
        } else {
            extractedSections = []
        }

        let includeInAIContext = (try? row.get(self.documentIncludeInAIContext)) ?? false
        let contextPriority = (try? row.get(self.documentContextPriority)) ?? 3
        let lastEditedAt = try? row.get(self.documentLastEditedAt).map { Date(timeIntervalSince1970: TimeInterval($0)) }

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
            documentCategory: category,
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
