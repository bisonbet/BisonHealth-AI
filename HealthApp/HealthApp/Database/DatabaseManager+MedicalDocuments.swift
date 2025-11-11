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

            print("🔍 DatabaseManager: Saving MedicalDocument '\(document.fileName)'")
            print("🔍 DatabaseManager:   - extractedText length: \(document.extractedText?.count ?? 0) chars")
            print("🔍 DatabaseManager:   - extractedText is nil: \(document.extractedText == nil)")
            print("🔍 DatabaseManager:   - extractedSections count: \(document.extractedSections.count)")
            print("🔍 DatabaseManager:   - includeInAIContext: \(document.includeInAIContext)")

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
            print("✅ DatabaseManager: MedicalDocument saved successfully to database")

            // CRITICAL: Force a WAL checkpoint to ensure data is written to disk
            try? db.execute("PRAGMA wal_checkpoint(FULL)")
            print("✅ DatabaseManager: Forced WAL checkpoint to disk")

            // Verify the save by reading it back immediately
            let verifyQuery = documentsTable.filter(self.documentId == document.id.uuidString)
            if let verifyRow = try? db.pluck(verifyQuery) {
                let savedExtractedText = try? verifyRow.get(self.documentExtractedText)
                print("🔍 DatabaseManager: Verification - extractedText in DB: \(savedExtractedText?.count ?? 0) chars, is nil: \(savedExtractedText == nil)")
            } else {
                print("⚠️ DatabaseManager: Could not verify saved document - query returned no rows")
            }
        } catch {
            print("❌ DatabaseManager: Error saving MedicalDocument: \(error)")
            print("❌ DatabaseManager: Error details: \(error.localizedDescription)")
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

        print("⚠️ DatabaseManager: updateMedicalDocument called for '\(document.fileName)'")
        print("⚠️ DatabaseManager:   - extractedText being updated: \(document.extractedText?.count ?? 0) chars, is nil: \(document.extractedText == nil)")

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
        print("🔍 DatabaseManager: Loading MedicalDocument '\(fileName)'")
        print("🔍 DatabaseManager:   - extractedText from DB length: \(extractedText?.count ?? 0) chars")
        print("🔍 DatabaseManager:   - extractedText from DB is nil: \(extractedText == nil)")

        // Debug: Check if column exists using PRAGMA
        if let db = db {
            do {
                // Check if extracted_text column exists
                let columns = try db.prepare("PRAGMA table_info(documents)")
                var extractedTextExists = false
                for column in columns {
                    if let columnName = column[1] as? String {
                        if columnName == "extracted_text" {
                            extractedTextExists = true
                            print("✅ DatabaseManager: extracted_text column EXISTS in documents table")
                            break
                        }
                    }
                }
                if !extractedTextExists {
                    print("❌ DatabaseManager: extracted_text column DOES NOT EXIST in documents table!")
                    print("❌ DatabaseManager: Migration may not have run. Current DB version should be checked.")
                }

                // If column exists, check its value
                if extractedTextExists {
                    let docId = row[documentId]
                    let lengthQuery = try db.scalar("SELECT LENGTH(extracted_text) FROM documents WHERE id = ?", docId)
                    print("🔍 DatabaseManager: Raw SQL LENGTH() result: \(lengthQuery ?? "NULL")")
                }
            } catch {
                print("❌ DatabaseManager: Error checking extracted_text: \(error)")
            }
        }

        let rawDoclingOutput = try? row.get(self.documentRawDoclingOutput)

        // Decode extracted sections
        let extractedSections: [DocumentSection]
        if let sectionsBlob = try? row.get(self.documentExtractedSections) {
            extractedSections = (try? JSONDecoder().decode([DocumentSection].self, from: sectionsBlob)) ?? []
        } else {
            extractedSections = []
        }

        // IMPORTANT FIX: If extractedText is NULL but we have rawDoclingOutput, extract markdown from it
        var finalExtractedText = extractedText
        if (extractedText == nil || extractedText?.isEmpty == true) && rawDoclingOutput != nil {
            print("🔧 DatabaseManager: extractedText is missing but rawDoclingOutput exists, extracting markdown...")
            if let rawData = rawDoclingOutput,
               let jsonObject = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
               let documentDict = jsonObject["document"] as? [String: Any],
               let mdContent = documentDict["md_content"] as? String {
                // CRITICAL: Clean the markdown to remove base64 images before storing
                let cleanedContent = cleanMarkdownForAIContext(mdContent)
                finalExtractedText = cleanedContent
                print("✅ DatabaseManager: Recovered and cleaned \(cleanedContent.count) chars from rawDoclingOutput (was \(mdContent.count) chars before cleaning)")

                // Save the CLEANED version back to avoid re-extraction next time
                if let db = db {
                    Task {
                        do {
                            let updateQuery = documentsTable.filter(self.documentId == id.uuidString)
                            try db.run(updateQuery.update(documentExtractedText <- cleanedContent))
                            print("✅ DatabaseManager: Saved cleaned recovered text back to database")
                        } catch {
                            print("⚠️ DatabaseManager: Failed to save recovered text: \(error)")
                        }
                    }
                }
            }
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
            extractedText: finalExtractedText,  // Use recovered text if needed
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

    // MARK: - Helper Functions

    /// Cleans markdown text by removing base64 image data for AI context
    private func cleanMarkdownForAIContext(_ markdown: String) -> String {
        var cleaned = markdown

        // Remove base64 image references: ![Image](data:image/...)
        // This regex matches: ![optional text](data:image/type;base64,verylongstring)
        let imagePattern = #"!\[[^\]]*\]\(data:image/[^)]+\)"#
        cleaned = cleaned.replacingOccurrences(
            of: imagePattern,
            with: "",
            options: [.regularExpression]
        )

        // Remove standalone base64 data URLs
        let dataUrlPattern = #"data:image/[^;]+;base64,[A-Za-z0-9+/=]+"#
        cleaned = cleaned.replacingOccurrences(
            of: dataUrlPattern,
            with: "[Image removed]",
            options: [.regularExpression]
        )

        // Clean up multiple consecutive newlines
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: [.regularExpression]
        )

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}
