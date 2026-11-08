import Foundation
@preconcurrency import SQLite

// MARK: - Document CRUD Operations (MedicalDocument)
extension DatabaseManager {

    // MARK: - Save Document
    /// Saves a MedicalDocument to the database with safe field merging.
    ///
    /// - Parameter document: The MedicalDocument to save.
    ///
    /// - Important: This method implements safe upsert behavior:
    ///   - If document is NEW: Inserts all fields as provided
    ///   - If document EXISTS: Merges fields - only non-nil values in the input document will overwrite
    ///     existing database values. Nil values preserve existing data (no data loss).
    ///
    /// - Note: This prevents accidental data loss from partially populated MedicalDocument objects.
    ///   For explicit field updates, use dedicated methods like `updateDocumentExtractedData()`.
    ///
    /// - Throws: DatabaseError if the save operation fails.
    func saveDocument(_ document: MedicalDocument) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        // Check if document exists - if so, merge fields to prevent data loss
        let existingDoc = try await fetchDocument(id: document.id)
        let mergedDoc = existingDoc != nil ? mergeDocument(new: document, existing: existingDoc!) : document

        do {
            let extractedHealthDataJson = try JSONEncoder().encode(mergedDoc.extractedHealthData)

            // Encode extracted sections
            let sectionsJson = try JSONEncoder().encode(mergedDoc.extractedSections)

            let insert = documentsTable.insert(or: .replace,
                documentId <- mergedDoc.id.uuidString,
                documentFileName <- try encryptString(mergedDoc.fileName).base64EncodedString(),
                documentFileType <- mergedDoc.fileType.rawValue,
                // New imports are stored as "<uuid>.<ext>", so these paths no longer
                // carry the patient's own filename. Files imported before that change keep
                // their "<uuid>_<original name>" names: renaming them needs a migration
                // that rewrites every stored path, which is still deferred.
                documentFilePath <- mergedDoc.filePath.absoluteString,
                documentThumbnailPath <- mergedDoc.thumbnailPath?.absoluteString,
                documentProcessingStatus <- mergedDoc.processingStatus.rawValue,
                documentImportedAt <- Int64(mergedDoc.importedAt.timeIntervalSince1970),
                documentProcessedAt <- mergedDoc.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- mergedDoc.fileSize,
                documentTags <- try encodeTagsColumn(mergedDoc.tags),
                documentNotes <- try encryptTextField(mergedDoc.notes),
                documentExtractedData <- try encryptDataField(extractedHealthDataJson),
                documentCategory <- mergedDoc.documentCategory.rawValue,
                // MedicalDocument-specific fields (PHI text columns are
                // encrypted at the row boundary; search is in-memory)
                documentExtractedText <- try encryptTextField(mergedDoc.extractedText),
                documentExtractedSections <- try encryptDataField(sectionsJson),
                documentDate <- mergedDoc.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- try encryptTextField(mergedDoc.providerName),
                documentProviderType <- mergedDoc.providerType?.rawValue,
                documentIncludeInAIContext <- mergedDoc.includeInAIContext,
                documentContextPriority <- mergedDoc.contextPriority,
                documentLastEditedAt <- mergedDoc.lastEditedAt.map { Int64($0.timeIntervalSince1970) },
                // `insert(or: .replace)` rewrites the whole row, so omitting this would clear
                // a failed document's stored explanation on an unrelated edit.
                documentFailureReason <- try encryptTextField(mergedDoc.failureReason)
            )

            try db.run(insert)
        } catch {
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
            throw DatabaseError.encryptionFailed
        }
    }
    
    // MARK: - Fetch Documents
    func fetchDocuments() async throws -> [MedicalDocument] {
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
            // Preserve the underlying cause in the log before mapping to the generic error
            AppLog.shared.database("Database operation failed: \(error.localizedDescription)", level: .error)
            throw DatabaseError.decryptionFailed
        }
    }
    
    // MARK: - Update Document Status
    /// Set a document's processing status, and the reason when that status is `.failed`.
    ///
    /// The reason is written in the same statement as the status so the two cannot disagree,
    /// and any status other than `.failed` clears it — a stale explanation on a document
    /// that now processes cleanly is its own bug. Encrypted at rest like the table's other
    /// PHI text columns, because these messages can name the file.
    func updateDocumentStatus(
        _ documentId: UUID,
        status: ProcessingStatus,
        failureReason: String? = nil
    ) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = documentsTable.filter(self.documentId == documentId.uuidString)
        let processedAt = status == .completed ? Int64(Date().timeIntervalSince1970) : nil
        let storedReason = status == .failed ? try encryptTextField(failureReason) : nil
        
        let update = query.update(
            documentProcessingStatus <- status.rawValue,
            documentProcessedAt <- processedAt,
            documentFailureReason <- storedReason
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
    /// Updates only the extractedData, processingStatus, and processedAt fields for a document.
    ///
    /// - Important: This method uses `.update()` which performs a partial update of only the specified
    ///   fields. Unlike `.replace()`, it preserves all other MedicalDocument fields (e.g., extractedText,
    ///   extractedSections, documentCategory, etc.). No field preservation logic is needed.
    ///
    /// - Parameters:
    ///   - documentId: The UUID of the document to update
    ///   - extractedData: The array of health data extracted from the document
    ///
    /// - Throws: DatabaseError if the update fails or document is not found
    func updateDocumentExtractedData(_ documentId: UUID, extractedData: [AnyHealthData]) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let extractedDataJson = try JSONEncoder().encode(extractedData)

            let query = documentsTable.filter(self.documentId == documentId.uuidString)
            // Uses .update() for partial field update - safe, no data loss for other fields
            let update = query.update(
                documentExtractedData <- try encryptDataField(extractedDataJson),
                documentProcessingStatus <- ProcessingStatus.completed.rawValue,
                documentProcessedAt <- Int64(Date().timeIntervalSince1970)
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

    // MARK: - Delete Document
    func deleteDocument(_ document: MedicalDocument) async throws {
        try await deleteDocument(id: document.id)
    }

    // MARK: - Update Thumbnail Path
    /// Updates ONLY the thumbnail path. Thumbnail generation finishes async
    /// and must not race the processing pipeline through the full-row merge
    /// save (which would resurrect a pre-processing status snapshot).
    func updateDocumentThumbnailPath(_ documentId: UUID, thumbnailPath: URL?) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let query = documentsTable.filter(self.documentId == documentId.uuidString)
            let rows = try db.run(query.update(documentThumbnailPath <- thumbnailPath?.absoluteString))
            if rows == 0 {
                throw DatabaseError.notFound
            }
        } catch {
            if error is DatabaseError { throw error }
            AppLog.shared.database("Failed to update thumbnail path: \(error.localizedDescription)", level: .error)
            throw DatabaseError.encryptionFailed
        }
    }
    func deleteDocument(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }
        
        let query = documentsTable.filter(documentId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())
        
        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }
    
    // MARK: - Document File Paths

    /// Every document's id, file path and thumbnail path, without decrypting anything else.
    func fetchDocumentStoragePaths() async throws -> [(id: UUID, filePath: URL, thumbnailPath: URL?)] {
        guard let db = db else { throw DatabaseError.connectionFailed }
        // `prepareRowIterator`, not `prepare`: the latter's sequence traps on a step error
        // instead of throwing, and this runs from a launch task that nothing else awaits.
        var paths: [(id: UUID, filePath: URL, thumbnailPath: URL?)] = []
        let iterator = try db.prepareRowIterator(
            documentsTable.select(documentId, documentFilePath, documentThumbnailPath)
        )
        while let row = try iterator.failableNext() {
            guard let id = UUID(uuidString: try row.get(documentId)),
                  let url = URL(string: try row.get(documentFilePath)) else { continue }
            let thumbnail = try row.get(documentThumbnailPath).flatMap(URL.init(string:))
            paths.append((id, url, thumbnail))
        }
        return paths
    }

    // MARK: - Fetch Documents by Status
    func fetchDocuments(with status: ProcessingStatus) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentProcessingStatus == status.rawValue)
                .order(documentImportedAt.desc)

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

    // MARK: - Fetch Documents by Type
    func fetchDocuments(ofType type: DocumentType) async throws -> [MedicalDocument] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [MedicalDocument] = []

        do {
            let query = documentsTable
                .filter(documentFileType == type.rawValue)
                .order(documentImportedAt.desc)

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

    // MARK: - Search Documents
    func searchDocuments(query: String) async throws -> [MedicalDocument] {
        // file_name is encrypted at rest; search the decrypted in-memory list.
        // ponytail: O(all-documents) scan — fine at beta scale (no pagination
        // exists yet); revisit if document counts reach thousands.
        let documents = try await fetchDocuments()
        let searchTerm = query.lowercased()
        return documents.filter { $0.fileName.lowercased().contains(searchTerm) }
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

    /// Merges a new MedicalDocument with an existing one, preserving non-nil existing values.
    ///
    /// - Parameters:
    ///   - new: The new document with updated fields
    ///   - existing: The existing document from the database
    ///
    /// - Returns: A merged document where non-nil values from `new` overwrite `existing`,
    ///   but nil values in `new` preserve the existing values (preventing data loss)
    ///
    /// - Important: **Array Field Behavior** - Empty arrays are treated as "preserve existing" to prevent
    ///   accidental data loss. This means:
    ///   - `new.tags = []` preserves `existing.tags` (does NOT clear)
    ///   - `new.extractedSections = []` preserves `existing.extractedSections` (does NOT clear)
    ///   - `new.extractedHealthData = []` preserves `existing.extractedHealthData` (does NOT clear)
    ///
    ///   **To explicitly clear array fields**, use dedicated update methods or create a new document with
    ///   a sentinel value array (e.g., `[.empty]` marker) that calling code can interpret.
    ///
    /// - Note: This prevents accidental data loss when saving documents with nil/empty fields.
    ///   For example, if `new.extractedText` is nil but `existing.extractedText` has OCR data,
    ///   the merged document will preserve the OCR data.
    private func mergeDocument(new: MedicalDocument, existing: MedicalDocument) -> MedicalDocument {
        var merged = MedicalDocument(
            id: new.id,  // ID never changes
            fileName: new.fileName,  // Required field, always present
            fileType: new.fileType,  // Required field, always present
            filePath: new.filePath,  // Required field, always present
            thumbnailPath: new.thumbnailPath ?? existing.thumbnailPath,
            processingStatus: new.processingStatus,  // Status updates are intentional
            documentDate: new.documentDate ?? existing.documentDate,
            providerName: new.providerName ?? existing.providerName,
            providerType: new.providerType ?? existing.providerType,
            documentCategory: new.documentCategory,  // Category updates are intentional
            extractedText: new.extractedText ?? existing.extractedText,  // Preserve OCR text
            // Arrays: empty = preserve existing (safer default, prevents accidental clearing)
            extractedSections: new.extractedSections.isEmpty ? existing.extractedSections : new.extractedSections,
            includeInAIContext: new.includeInAIContext,  // Boolean, always has value
            contextPriority: new.contextPriority,  // Int, always has value
            // Arrays: empty = preserve existing (safer default, prevents accidental clearing)
            extractedHealthData: new.extractedHealthData.isEmpty ? existing.extractedHealthData : new.extractedHealthData,
            importedAt: existing.importedAt,  // Never change import date
            processedAt: new.processedAt ?? existing.processedAt,
            lastEditedAt: new.lastEditedAt ?? Date(),  // Update to now if not specified
            fileSize: new.fileSize,  // File size should match current file
            // Arrays: empty = preserve existing (safer default, prevents accidental clearing)
            tags: new.tags.isEmpty ? existing.tags : new.tags,
            notes: new.notes ?? existing.notes
        )
        // Not an init parameter, so it has to be carried across explicitly: a caller that
        // built its document without one must not clear a reason the row already holds.
        merged.failureReason = new.failureReason ?? existing.failureReason
        return merged
    }
}
