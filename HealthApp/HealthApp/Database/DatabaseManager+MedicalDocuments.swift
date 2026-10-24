import Foundation
import SQLite

// MARK: - Medical Document CRUD Operations
extension DatabaseManager {

    // MARK: - Save Medical Document
    func saveMedicalDocument(_ document: MedicalDocument) async throws {
        try await saveMedicalDocument(document, requireExistingRow: false)
    }

    /// Save a document, optionally refusing to recreate a row that has been deleted.
    ///
    /// The write is `INSERT OR REPLACE`, which is what reprocessing needs — but it means a
    /// save that races a delete does not fail, it *resurrects* the row, pointing at a file
    /// that is already gone. The library is then left with a document stuck on "Pending"
    /// that cannot be opened or reprocessed.
    ///
    /// With `requireExistingRow` the existence check and the write happen in one
    /// transaction, so there is no window between them. Extraction commits pass true; the
    /// first save of a newly imported document passes false, because there is no row yet.
    ///
    /// - Returns: false when the row was gone and nothing was written.
    @discardableResult
    func saveMedicalDocument(_ document: MedicalDocument, requireExistingRow: Bool) async throws -> Bool {
        guard let db = db else { throw DatabaseError.connectionFailed }
        var wasWritten = true

        // A record whose columns could not be read must never be written back whole: the
        // in-memory value for those fields is empty, and this write would put that emptiness
        // over ciphertext a decoder fix could still recover. Partial updaters exist for
        // changing one field without touching the rest.
        guard document.unreadableFields.isEmpty else {
            AppLog.shared.database(
                "Refusing a full-row write of '\(document.fileName)': \(document.unreadableFields.map(\.rawValue).sorted()) could not be read back",
                level: .error
            )
            throw DatabaseError.lossyWriteRefused(document.unreadableFields.map(\.rawValue).sorted())
        }


        do {
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
                documentTags <- try encodeTagsColumn(document.tags),
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

            if requireExistingRow {
                try db.transaction {
                    let stillPresent = try db.scalar(
                        documentsTable.filter(self.documentId == document.id.uuidString).count
                    ) > 0
                    guard stillPresent else {
                        wasWritten = false
                        return
                    }
                    try db.run(insert)
                }
            } else {
                try db.run(insert)
            }

            guard wasWritten else {
                AppLog.shared.database(
                    "Refused to recreate deleted document row for '\(document.fileName)'",
                    level: .warning
                )
                return false
            }
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

        return wasWritten
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
        // A record whose columns could not be read must never be written back whole: the
        // in-memory value for those fields is empty, and this write would put that emptiness
        // over ciphertext a decoder fix could still recover. Partial updaters exist for
        // changing one field without touching the rest.
        guard document.unreadableFields.isEmpty else {
            AppLog.shared.database(
                "Refusing a full-row write of '\(document.fileName)': \(document.unreadableFields.map(\.rawValue).sorted()) could not be read back",
                level: .error
            )
            throw DatabaseError.lossyWriteRefused(document.unreadableFields.map(\.rawValue).sorted())
        }


        guard let db = db else { throw DatabaseError.connectionFailed }

        AppLog.shared.database("updateMedicalDocument called for '\(document.fileName)' - extractedText: \(document.extractedText?.count ?? 0) chars, is nil: \(document.extractedText == nil)", level: .debug)

        do {
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
                documentTags <- try encodeTagsColumn(document.tags),
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
        let storedNotes = row[documentNotes]

        // Every decode below falls back to an empty value, and the full-row writers would
        // then persist that emptiness over readable ciphertext. Record each failure so the
        // writers can refuse instead.
        var unreadableFields: Set<MedicalDocument.UnreadableField> = []

        let notes = decryptTextField(storedNotes)
        if notes == nil, storedNotes != nil {
            unreadableFields.insert(.notes)
        }

        // Decode tags (encrypted as of v14; plaintext JSON still readable)
        let decodedTags = decodeTagsColumn(row[documentTags])
        let tags = decodedTags.tags
        if decodedTags.wasUnreadable {
            unreadableFields.insert(.tags)
        }

        // Decode extracted health data (BLOB is encrypted at rest)
        let extractedHealthData: [AnyHealthData]
        let storedExtractedData = row[documentExtractedData]
        if let extractedDataBlob = decryptDataField(storedExtractedData) {
            if let decoded = try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob) {
                extractedHealthData = decoded
            } else {
                // One unknown `type` discards the whole array, which is exactly the case a
                // later decoder fix could recover — if the ciphertext is still there.
                extractedHealthData = []
                unreadableFields.insert(.extractedHealthData)
            }
        } else {
            extractedHealthData = []
            if storedExtractedData != nil {
                unreadableFields.insert(.extractedHealthData)
            }
        }

        // Medical document fields
        let documentDate = try? row.get(self.documentDate).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let storedProviderName = (try? row.get(self.documentProviderName)) ?? nil
        let providerName = decryptTextField(storedProviderName)
        if providerName == nil, storedProviderName != nil {
            unreadableFields.insert(.providerName)
        }
        let providerTypeRaw = try? row.get(self.documentProviderType)
        let providerType = providerTypeRaw.flatMap { ProviderType(rawValue: $0) }
        let categoryRaw = (try? row.get(self.documentCategory)) ?? "other"
        let category = DocumentCategory(rawValue: categoryRaw) ?? .other
        let storedExtractedText = (try? row.get(self.documentExtractedText)) ?? nil
        let extractedText = decryptTextField(storedExtractedText)
        if extractedText == nil, storedExtractedText != nil {
            unreadableFields.insert(.extractedText)
        }
        AppLog.shared.database("Loading MedicalDocument '\(fileName)' - extractedText: \(extractedText?.count ?? 0) chars, is nil: \(extractedText == nil)", level: .debug)

        // Decode extracted sections (BLOB is encrypted at rest)
        let extractedSections: [DocumentSection]
        let storedSections = (try? row.get(self.documentExtractedSections)) ?? nil
        if let sectionsBlob = decryptDataField(storedSections) {
            if let decoded = try? JSONDecoder().decode([DocumentSection].self, from: sectionsBlob) {
                extractedSections = decoded
            } else {
                extractedSections = []
                unreadableFields.insert(.extractedSections)
            }
        } else {
            extractedSections = []
            if storedSections != nil {
                unreadableFields.insert(.extractedSections)
            }
        }

        let includeInAIContext = (try? row.get(self.documentIncludeInAIContext)) ?? false
        let contextPriority = (try? row.get(self.documentContextPriority)) ?? 3
        let lastEditedAt = try? row.get(self.documentLastEditedAt).map { Date(timeIntervalSince1970: TimeInterval($0)) }

        if !unreadableFields.isEmpty {
            AppLog.shared.database(
                "MedicalDocument '\(fileName)' has unreadable columns \(unreadableFields.map(\.rawValue).sorted()) — full-row writes will be refused so the stored bytes survive",
                level: .warning
            )
        }

        var document = MedicalDocument(
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
        document.unreadableFields = unreadableFields
        return document
    }
}

// MARK: - Pending Import Reviews (v13)
//
// Extracted lab values the user has not decided on yet. Before this they lived only in
// `DocumentProcessor`'s memory, so cancelling the sheet or relaunching the app discarded
// every group — including the ones the reconciler had auto-accepted — with nothing in the
// UI offering to bring them back. Only re-processing the document recovered them.
//
// The payload is encrypted like every other PHI column: it holds the patient's actual
// results.
extension DatabaseManager {

    func savePendingImportReview(_ review: PendingImportReview) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let payload = try encryptData(review).base64EncodedString()
        try db.run(pendingReviewsTable.insert(or: .replace,
            pendingReviewDocumentId <- review.documentId.uuidString,
            pendingReviewPayload <- payload,
            pendingReviewCreatedAt <- Int64(review.timestamp.timeIntervalSince1970)
        ))
    }

    func deletePendingImportReview(documentId: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let row = pendingReviewsTable.filter(pendingReviewDocumentId == documentId.uuidString)
        try db.run(row.delete())
    }

    /// Every un-reviewed import, oldest first, for resurfacing on launch.
    ///
    /// A row that cannot be decoded is dropped rather than thrown: one unreadable payload
    /// must not stop the others being offered back to the user, and the document itself
    /// is still there to re-process.
    func fetchPendingImportReviews() async throws -> [PendingImportReview] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var reviews: [PendingImportReview] = []
        for row in try db.prepare(pendingReviewsTable.order(pendingReviewCreatedAt.asc)) {
            guard let data = Data(base64Encoded: row[pendingReviewPayload]) else {
                AppLog.shared.database("Pending review payload is not valid base64 — skipping", level: .warning)
                continue
            }
            do {
                reviews.append(try decryptData(data, as: PendingImportReview.self))
            } catch {
                AppLog.shared.database("Could not decode a pending import review — skipping", level: .warning)
            }
        }
        return reviews
    }
}
