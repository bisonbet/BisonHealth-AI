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

            AppLog.shared.database("Saving MedicalDocument '\(document.fileName)' - extractedText: \(document.extractedText?.count ?? 0) chars, sections: \(document.extractedSections.count), includeInAIContext: \(document.includeInAIContext)", level: .debug)

            let insert = documentsTable.insert(or: .replace,
                documentId <- document.id.uuidString,
                documentFileName <- try encryptString(document.fileName).base64EncodedString(),
                documentFileType <- document.fileType.rawValue,
                documentFilePath <- document.filePath.absoluteString,
                documentThumbnailPath <- document.thumbnailPath?.absoluteString,
                documentProcessingStatus <- document.processingStatus.rawValue,
                documentImportedAt <- Int64(document.importedAt.timeIntervalSince1970),
                documentProcessedAt <- document.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- document.fileSize,
                documentTags <- tagsString,
                documentNotes <- try encryptTextField(document.notes),
                documentExtractedData <- try encryptDataField(extractedHealthDataJson),
                // Medical document fields (PHI text columns encrypted at rest)
                documentDate <- document.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- try encryptTextField(document.providerName),
                documentProviderType <- document.providerType?.rawValue,
                documentCategory <- document.documentCategory.rawValue,
                documentExtractedText <- try encryptTextField(document.extractedText),
                documentExtractedSections <- try encryptDataField(extractedSectionsJson),
                documentIncludeInAIContext <- document.includeInAIContext,
                documentContextPriority <- document.contextPriority,
                documentLastEditedAt <- document.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
            )

            try db.run(insert)
            AppLog.shared.database("MedicalDocument saved successfully to database")

            // CRITICAL: Force a WAL checkpoint to ensure data is written to disk
            try? db.execute("PRAGMA wal_checkpoint(FULL)")
            AppLog.shared.database("Forced WAL checkpoint to disk")

            // Verify the save by reading it back immediately
            let verifyQuery = documentsTable.filter(self.documentId == document.id.uuidString)
            if let verifyRow = try? db.pluck(verifyQuery) {
                let savedExtractedText = decryptTextField((try? verifyRow.get(self.documentExtractedText)) ?? nil)
                AppLog.shared.database("Verification - extractedText in DB: \(savedExtractedText?.count ?? 0) chars, is nil: \(savedExtractedText == nil)", level: .debug)
            } else {
                AppLog.shared.database("Could not verify saved document - query returned no rows", level: .warning)
            }
        } catch {
            AppLog.shared.error("Error saving MedicalDocument: \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.encryptionFailed
        }
    }

    // MARK: - Fetch Medical Documents
    func fetchMedicalDocuments() async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable.order(documentImportedAt.desc)

            let iterator = try db.prepareRowIterator(query)
            while let row = try iterator.failableNext() {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
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
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
            throw DatabaseError.decryptionFailed
        }
    }

    // MARK: - Fetch Documents for AI Context
    func fetchDocumentsForAIContext(categories: [DocumentCategory]? = nil) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        var query = documentsTable
            .filter(documentIncludeInAIContext == true)
            .filter(documentProcessingStatus == ProcessingStatus.completed.rawValue)
        
        // Filter by categories if provided
        if let categories = categories, !categories.isEmpty {
            // Build OR condition for multiple categories
            let categoryValues = categories.map { $0.rawValue }
            // Since we've already checked !categories.isEmpty, first! is safe
            var categoryFilter: SQLite.Expression<Bool> = documentCategory == categoryValues.first!
            for categoryValue in categoryValues.dropFirst() {
                categoryFilter = categoryFilter || documentCategory == categoryValue
            }
            query = query.filter(categoryFilter)
        } else if categories != nil && categories!.isEmpty {
            // Empty array means explicitly filter to no results (user selected types that don't map to documents)
            query = query.filter(documentCategory == "")
        }
        
        query = query.order(documentContextPriority.desc, documentDate.desc)

        do {
            let iterator = try db.prepareRowIterator(query)
            while let row = try iterator.failableNext() {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
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

            let iterator = try db.prepareRowIterator(query)
            while let row = try iterator.failableNext() {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Fetch Documents by Provider
    func fetchMedicalDocuments(providerName: String) async throws -> [MedicalDocument] {
        // provider_name is encrypted at rest; filter the decrypted in-memory
        // list. Match the previous SQL semantics: document_date DESC with
        // undated documents last (importedAt as a stable tiebreak).
        let documents = try await fetchMedicalDocuments()
        return documents
            .filter { $0.providerName == providerName }
            .sorted { lhs, rhs in
                let l = lhs.documentDate ?? .distantPast
                let r = rhs.documentDate ?? .distantPast
                return l == r ? lhs.importedAt > rhs.importedAt : l > r
            }
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

            let iterator = try db.prepareRowIterator(query)
            while let row = try iterator.failableNext() {
                let document = try buildMedicalDocument(from: row)
                results.append(document)
            }
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
            throw DatabaseError.decryptionFailed
        }

        return results
    }

    // MARK: - Update Medical Document
    func updateMedicalDocument(_ document: MedicalDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        AppLog.shared.database("updateMedicalDocument called for '\(document.fileName)' - extractedText: \(document.extractedText?.count ?? 0) chars, is nil: \(document.extractedText == nil)", level: .debug)

        do {
            let tagsJson = try JSONEncoder().encode(document.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"

            let extractedHealthDataJson = try JSONEncoder().encode(document.extractedHealthData)
            let extractedSectionsJson = try JSONEncoder().encode(document.extractedSections)

            let query = documentsTable.filter(self.documentId == document.id.uuidString)

            let update = query.update(
                documentFileName <- try encryptString(document.fileName).base64EncodedString(),
                documentFileType <- document.fileType.rawValue,
                documentFilePath <- document.filePath.absoluteString,
                documentThumbnailPath <- document.thumbnailPath?.absoluteString,
                documentProcessingStatus <- document.processingStatus.rawValue,
                documentProcessedAt <- document.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- document.fileSize,
                documentTags <- tagsString,
                documentNotes <- try encryptTextField(document.notes),
                documentExtractedData <- try encryptDataField(extractedHealthDataJson),
                // Medical document fields
                documentDate <- document.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- try encryptTextField(document.providerName),
                documentProviderType <- document.providerType?.rawValue,
                documentCategory <- document.documentCategory.rawValue,
                documentExtractedText <- try encryptTextField(document.extractedText),
                documentExtractedSections <- try encryptDataField(extractedSectionsJson),
                documentIncludeInAIContext <- document.includeInAIContext,
                documentContextPriority <- document.contextPriority,
                documentLastEditedAt <- document.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
            )

            let rowsUpdated = try db.run(update)
            if rowsUpdated == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
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
        guard db != nil else { throw DatabaseError.connectionFailed }

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
        // PHI text columns are encrypted at rest; search the decrypted list.
        // ponytail: O(all-documents × text) scan — fine at beta scale; revisit
        // with an index or FTS if search becomes slow.
        let documents = try await fetchMedicalDocuments()
        let searchTerm = query.lowercased()
        return documents.filter {
            $0.fileName.lowercased().contains(searchTerm)
            || $0.providerName?.lowercased().contains(searchTerm) == true
            || $0.extractedText?.lowercased().contains(searchTerm) == true
        }
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
        // PHI text columns are encrypted at rest; fall back to the raw value
        // only for fileName (non-optional) so corruption is visible, not hidden.
        let fileName = decryptTextField(row[documentFileName]) ?? row[documentFileName]
        let fileType = DocumentType(rawValue: row[documentFileType]) ?? .other
        let filePath = URL(string: row[documentFilePath]) ?? URL(fileURLWithPath: "")
        let thumbnailPath = row[documentThumbnailPath].map { URL(string: $0) } ?? nil
        let processingStatus = ProcessingStatus(rawValue: row[documentProcessingStatus]) ?? .pending
        let importedAt = Date(timeIntervalSince1970: TimeInterval(row[documentImportedAt]))
        let processedAt = row[documentProcessedAt].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let fileSize = row[documentFileSize]
        let notes = decryptTextField(row[documentNotes])

        // Decode tags
        let tagsString = row[documentTags]
        let tagsData = tagsString.data(using: .utf8) ?? Data()
        let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []

        // Decode extracted health data (BLOB is encrypted at rest)
        let extractedHealthData: [AnyHealthData]
        if let extractedDataBlob = decryptDataField(row[documentExtractedData]) {
            extractedHealthData = (try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob)) ?? []
        } else {
            extractedHealthData = []
        }

        // Medical document fields
        let documentDate = try? row.get(self.documentDate).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let providerName = decryptTextField((try? row.get(self.documentProviderName)) ?? nil)
        let providerTypeRaw = try? row.get(self.documentProviderType)
        let providerType = providerTypeRaw.flatMap { ProviderType(rawValue: $0) }
        let categoryRaw = (try? row.get(self.documentCategory)) ?? "other"
        let category = DocumentCategory(rawValue: categoryRaw) ?? .other
        let extractedText = decryptTextField((try? row.get(self.documentExtractedText)) ?? nil)
        AppLog.shared.database("Loading MedicalDocument '\(fileName)' - extractedText: \(extractedText?.count ?? 0) chars, is nil: \(extractedText == nil)", level: .debug)

        // Decode extracted sections (BLOB is encrypted at rest)
        let extractedSections: [DocumentSection]
        if let sectionsBlob = decryptDataField((try? row.get(self.documentExtractedSections)) ?? nil) {
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
