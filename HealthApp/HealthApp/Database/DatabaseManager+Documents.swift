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
            let tagsJson = try JSONEncoder().encode(mergedDoc.tags)
            let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"

            let extractedHealthDataJson = try JSONEncoder().encode(mergedDoc.extractedHealthData)

            // Encode extracted sections
            let sectionsJson = try JSONEncoder().encode(mergedDoc.extractedSections)

            let insert = documentsTable.insert(or: .replace,
                documentId <- mergedDoc.id.uuidString,
                documentFileName <- try encryptString(mergedDoc.fileName).base64EncodedString(),
                documentFileType <- mergedDoc.fileType.rawValue,
                // ponytail: file_path/thumbnail_path still carry the original
                // (patient-identifying) filename, and the on-disk ciphertext
                // blobs keep UUID_<name> names. Encrypting these needs a file-rename
                // migration to UUID-only storage; deferred for beta.
                documentFilePath <- mergedDoc.filePath.absoluteString,
                documentThumbnailPath <- mergedDoc.thumbnailPath?.absoluteString,
                documentProcessingStatus <- mergedDoc.processingStatus.rawValue,
                documentImportedAt <- Int64(mergedDoc.importedAt.timeIntervalSince1970),
                documentProcessedAt <- mergedDoc.processedAt.map { Int64($0.timeIntervalSince1970) },
                documentFileSize <- mergedDoc.fileSize,
                documentTags <- tagsString,
                documentNotes <- try encryptTextField(mergedDoc.notes),
                documentExtractedData <- try encryptDataField(extractedHealthDataJson),
                documentCategory <- mergedDoc.documentCategory.rawValue,
                // MedicalDocument-specific fields (PHI text columns are
                // encrypted at the row boundary; search is in-memory)
                documentExtractedText <- try encryptTextField(mergedDoc.extractedText),
                documentRawDoclingOutput <- try encryptDataField(mergedDoc.rawDoclingOutput),
                documentExtractedSections <- try encryptDataField(sectionsJson),
                documentDate <- mergedDoc.documentDate.map { Int64($0.timeIntervalSince1970) },
                documentProviderName <- try encryptTextField(mergedDoc.providerName),
                documentProviderType <- mergedDoc.providerType?.rawValue,
                documentIncludeInAIContext <- mergedDoc.includeInAIContext,
                documentContextPriority <- mergedDoc.contextPriority,
                documentLastEditedAt <- mergedDoc.lastEditedAt.map { Int64($0.timeIntervalSince1970) }
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
        let table = documentsTable
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try db.scalar(table.count))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
        return MedicalDocument(
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
            rawDoclingOutput: new.rawDoclingOutput ?? existing.rawDoclingOutput,  // Preserve raw OCR
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
    }

    private func buildMedicalDocument(from row: Row) throws -> MedicalDocument {
        let id = UUID(uuidString: row[documentId]) ?? UUID()
        // PHI text columns are encrypted at rest; fall back to the raw value
        // only for fileName (non-optional) so corruption is visible, not hidden.
        let fileName = decryptTextField(row[documentFileName]) ?? row[documentFileName]
        let fileType = DocumentType(rawValue: row[documentFileType]) ?? .other
        let filePath = URL(string: row[documentFilePath]) ?? URL(fileURLWithPath: "")
        let thumbnailPath = row[documentThumbnailPath].flatMap { URL(string: $0) }
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

        // Decode document category
        let categoryRaw = (try? row.get(self.documentCategory)) ?? "other"
        let documentCategory = DocumentCategory(rawValue: categoryRaw) ?? .other

        // Decode MedicalDocument-specific fields
        let documentDate = (try? row.get(self.documentDate)).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let providerName = decryptTextField((try? row.get(self.documentProviderName)) ?? nil)
        let providerTypeRaw = try? row.get(self.documentProviderType)
        let providerType = providerTypeRaw.flatMap { ProviderType(rawValue: $0) }
        let extractedText = decryptTextField((try? row.get(self.documentExtractedText)) ?? nil)
        let rawDoclingOutput = decryptDataField((try? row.get(self.documentRawDoclingOutput)) ?? nil)
        let includeInAIContext = (try? row.get(self.documentIncludeInAIContext)) ?? false
        let contextPriority = (try? row.get(self.documentContextPriority)) ?? 3
        let lastEditedAt = (try? row.get(self.documentLastEditedAt)).map { Date(timeIntervalSince1970: TimeInterval($0)) }

        // Decode extracted sections (BLOB is encrypted at rest)
        let extractedSections: [DocumentSection]
        if let sectionsBlob = decryptDataField((try? row.get(self.documentExtractedSections)) ?? nil) {
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
