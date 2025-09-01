import Foundation
import SwiftUI
import VisionKit
import PhotosUI
import UserNotifications
import Combine

// MARK: - Document Manager
@MainActor
class DocumentManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DocumentManager(
        documentImporter: DocumentImporter.shared,
        documentProcessor: DocumentProcessor.shared,
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared
    )
    
    // MARK: - Published Properties
    @Published var documents: [HealthDocument] = []
    @Published var isImporting = false
    @Published var isProcessing = false
    @Published var importProgress: Double = 0.0
    @Published var processingProgress: Double = 0.0
    @Published var selectedDocuments: Set<UUID> = []
    @Published var searchText = ""
    @Published var filterStatus: ProcessingStatus?
    @Published var filterType: DocumentType?
    @Published var sortOrder: DocumentSortOrder = .dateDescending
    @Published var lastError: Error?
    
    // MARK: - Dependencies
    private let documentImporter: DocumentImporter
    private let documentProcessor: DocumentProcessor
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager
    
    // MARK: - Computed Properties
    var filteredDocuments: [HealthDocument] {
        var filtered = documents
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { document in
                document.fileName.localizedCaseInsensitiveContains(searchText) ||
                document.tags.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
                document.notes?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply status filter
        if let status = filterStatus {
            filtered = filtered.filter { $0.processingStatus == status }
        }
        
        // Apply type filter
        if let type = filterType {
            filtered = filtered.filter { $0.fileType == type }
        }
        
        // Apply sorting
        switch sortOrder {
        case .dateAscending:
            filtered.sort { $0.importedAt < $1.importedAt }
        case .dateDescending:
            filtered.sort { $0.importedAt > $1.importedAt }
        case .nameAscending:
            filtered.sort { $0.fileName < $1.fileName }
        case .nameDescending:
            filtered.sort { $0.fileName > $1.fileName }
        case .sizeAscending:
            filtered.sort { $0.fileSize < $1.fileSize }
        case .sizeDescending:
            filtered.sort { $0.fileSize > $1.fileSize }
        case .statusAscending:
            filtered.sort { $0.processingStatus.rawValue < $1.processingStatus.rawValue }
        case .statusDescending:
            filtered.sort { $0.processingStatus.rawValue > $1.processingStatus.rawValue }
        }
        
        return filtered
    }
    
    var documentStatistics: DocumentStatistics {
        let total = documents.count
        let processed = documents.filter { $0.processingStatus == .completed }.count
        let pending = documents.filter { $0.processingStatus == .pending }.count
        let processing = documents.filter { $0.processingStatus == .processing }.count
        let failed = documents.filter { $0.processingStatus == .failed }.count
        let totalSize = documents.reduce(0) { $0 + $1.fileSize }
        
        return DocumentStatistics(
            total: total,
            processed: processed,
            pending: pending,
            processing: processing,
            failed: failed,
            totalSize: totalSize
        )
    }
    
    // MARK: - Initialization
    init(
        documentImporter: DocumentImporter,
        documentProcessor: DocumentProcessor,
        databaseManager: DatabaseManager,
        fileSystemManager: FileSystemManager
    ) {
        self.documentImporter = documentImporter
        self.documentProcessor = documentProcessor
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager
        
        Task {
            await loadDocuments()
            await setupProcessorObservation()
        }
    }
    
    // MARK: - Document Loading
    func loadDocuments() async {
        do {
            documents = try await databaseManager.fetchDocuments()
        } catch {
            lastError = error
            print("Failed to load documents: \(error)")
        }
    }
    
    func refreshDocuments() async {
        await loadDocuments()
    }
    
    // MARK: - Document Import
    func importDocuments(from urls: [URL]) async {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            let importedDocuments = try await documentImporter.importMultipleDocuments(from: urls)
            
            // Add to local array
            documents.append(contentsOf: importedDocuments)
            documents.sort { $0.importedAt > $1.importedAt }
            
            // Add to processing queue
            for document in importedDocuments {
                await documentProcessor.addToQueue(document)
            }
            
        } catch {
            lastError = error
        }
    }
    
    func importDocument(from url: URL) async {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            let document = try await documentImporter.importDocument(from: url)
            
            // Add to local array
            documents.append(document)
            documents.sort { $0.importedAt > $1.importedAt }
            
            // Add to processing queue
            await documentProcessor.addToQueue(document)
            
        } catch {
            lastError = error
        }
    }
    
    func importScannedDocument(_ scan: VNDocumentCameraScan) async {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            let document = try await documentImporter.importScannedDocument(scan)
            
            // Add to local array
            documents.append(document)
            documents.sort { $0.importedAt > $1.importedAt }
            
            // Add to processing queue with high priority for scanned documents
            await documentProcessor.addToQueue(document, priority: .high)
            
        } catch {
            lastError = error
        }
    }
    
    func importFromPhotoLibrary(_ results: [PHPickerResult]) async {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            let importedDocuments = try await documentImporter.importFromPhotoLibrary(results)
            
            // Add to local array
            documents.append(contentsOf: importedDocuments)
            documents.sort { $0.importedAt > $1.importedAt }
            
            // Add to processing queue
            for document in importedDocuments {
                await documentProcessor.addToQueue(document)
            }
            
        } catch {
            lastError = error
        }
    }
    
    // MARK: - Document Processing
    func processDocument(_ document: HealthDocument, immediately: Bool = false) async {
        if immediately {
            do {
                _ = try await documentProcessor.processDocumentImmediately(document)
                await refreshDocuments()
            } catch {
                lastError = error
            }
        } else {
            await documentProcessor.addToQueue(document, priority: .normal)
        }
    }
    
    func processSelectedDocuments(immediately: Bool = false) async {
        let documentsToProcess = documents.filter { selectedDocuments.contains($0.id) }
        
        if immediately {
            for document in documentsToProcess {
                await processDocument(document, immediately: true)
            }
        } else {
            await documentProcessor.processBatch(documentsToProcess)
        }
        
        selectedDocuments.removeAll()
    }
    
    func processAllPendingDocuments() async {
        let pendingDocuments = documents.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }
        await documentProcessor.processBatch(pendingDocuments)
    }
    
    func retryFailedDocuments() async {
        let failedDocuments = documents.filter { $0.processingStatus == .failed }
        await documentProcessor.processBatch(failedDocuments, priority: .high)
    }
    
    // MARK: - Document Management
    func updateDocument(_ document: HealthDocument) async {
        do {
            try await databaseManager.saveDocument(document)
            
            // Update local array
            if let index = documents.firstIndex(where: { $0.id == document.id }) {
                documents[index] = document
            }
        } catch {
            lastError = error
        }
    }
    
    func addTagToDocument(_ documentId: UUID, tag: String) async {
        guard let index = documents.firstIndex(where: { $0.id == documentId }) else { return }
        
        var document = documents[index]
        document.addTag(tag)
        
        await updateDocument(document)
    }
    
    func removeTagFromDocument(_ documentId: UUID, tag: String) async {
        guard let index = documents.firstIndex(where: { $0.id == documentId }) else { return }
        
        var document = documents[index]
        document.removeTag(tag)
        
        await updateDocument(document)
    }
    
    func updateDocumentNotes(_ documentId: UUID, notes: String?) async {
        guard let index = documents.firstIndex(where: { $0.id == documentId }) else { return }
        
        var document = documents[index]
        document.notes = notes
        
        await updateDocument(document)
    }
    
    func deleteDocument(_ document: HealthDocument) async {
        do {
            // Remove from processing queue if queued
            await documentProcessor.removeFromQueue(document.id)
            
            // Delete from database and file system
            try await databaseManager.deleteDocument(id: document.id)
            try fileSystemManager.deleteDocument(at: document.filePath)
            
            if let thumbnailPath = document.thumbnailPath {
                try? fileSystemManager.deleteFile(at: thumbnailPath)
            }
            
            // Remove from local array
            documents.removeAll { $0.id == document.id }
            selectedDocuments.remove(document.id)
            
        } catch {
            lastError = error
        }
    }
    
    func deleteSelectedDocuments() async {
        let documentsToDelete = documents.filter { selectedDocuments.contains($0.id) }
        
        for document in documentsToDelete {
            await deleteDocument(document)
        }
        
        selectedDocuments.removeAll()
    }
    
    // MARK: - Selection Management
    func selectDocument(_ documentId: UUID) {
        selectedDocuments.insert(documentId)
    }
    
    func deselectDocument(_ documentId: UUID) {
        selectedDocuments.remove(documentId)
    }
    
    func toggleDocumentSelection(_ documentId: UUID) {
        if selectedDocuments.contains(documentId) {
            selectedDocuments.remove(documentId)
        } else {
            selectedDocuments.insert(documentId)
        }
    }
    
    func selectAllDocuments() {
        selectedDocuments = Set(filteredDocuments.map { $0.id })
    }
    
    func deselectAllDocuments() {
        selectedDocuments.removeAll()
    }
    
    func selectDocuments(with status: ProcessingStatus) {
        let documentsWithStatus = filteredDocuments.filter { $0.processingStatus == status }
        selectedDocuments.formUnion(documentsWithStatus.map { $0.id })
    }
    
    // MARK: - Search and Filter
    func searchDocuments(_ query: String) async {
        searchText = query
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func setStatusFilter(_ status: ProcessingStatus?) {
        filterStatus = status
    }
    
    func setTypeFilter(_ type: DocumentType?) {
        filterType = type
    }
    
    func setSortOrder(_ order: DocumentSortOrder) {
        sortOrder = order
    }
    
    func clearAllFilters() {
        searchText = ""
        filterStatus = nil
        filterType = nil
        sortOrder = .dateDescending
    }
    
    // MARK: - Document Sharing and Export
    func shareDocument(_ document: HealthDocument) -> URL? {
        return document.filePath
    }
    
    func shareSelectedDocuments() -> [URL] {
        let documentsToShare = documents.filter { selectedDocuments.contains($0.id) }
        return documentsToShare.map { $0.filePath }
    }
    
    func exportDocumentMetadata() async throws -> URL {
        let metadata = documents.map { DocumentMetadataExport(from: $0) }
        let jsonData = try JSONEncoder().encode(metadata)
        
        let fileName = "Document_Metadata_Export_\(Date().formatted(date: .numeric, time: .omitted))"
        return try fileSystemManager.createExportFile(
            data: jsonData,
            fileName: fileName,
            fileType: .json
        )
    }
    
    // MARK: - Thumbnail Management
    func regenerateThumbnail(for document: HealthDocument) async {
        do {
            if let thumbnailURL = try await fileSystemManager.generateThumbnail(
                for: document.filePath,
                documentType: document.fileType
            ) {
                var updatedDocument = document
                updatedDocument.thumbnailPath = thumbnailURL
                await updateDocument(updatedDocument)
            }
        } catch {
            lastError = error
        }
    }
    
    func regenerateAllThumbnails() async {
        for document in documents where document.thumbnailPath == nil {
            await regenerateThumbnail(for: document)
        }
    }
    
    // MARK: - Storage Management
    func cleanupOrphanedFiles() async {
        do {
            let documentPaths = Set(documents.map { $0.filePath.lastPathComponent })
            let thumbnailPaths = Set(documents.compactMap { $0.thumbnailPath?.lastPathComponent })
            
            try await fileSystemManager.cleanupOrphanedFiles(
                keepingDocuments: documentPaths,
                keepingThumbnails: thumbnailPaths
            )
        } catch {
            lastError = error
        }
    }
    
    func getStorageUsage() async -> StorageUsage {
        do {
            let documentsSize = try await fileSystemManager.getDirectorySize(.documents)
            let thumbnailsSize = try await fileSystemManager.getDirectorySize(.thumbnails)
            let totalSize = documentsSize + thumbnailsSize
            
            return StorageUsage(
                documentsSize: documentsSize,
                thumbnailsSize: thumbnailsSize,
                totalSize: totalSize,
                documentCount: documents.count
            )
        } catch {
            return StorageUsage(documentsSize: 0, thumbnailsSize: 0, totalSize: 0, documentCount: 0)
        }
    }
    
    // MARK: - Private Methods
    private func setupProcessorObservation() async {
        // Observe processor progress and update local state
        documentProcessor.$processingProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$processingProgress)
        
        documentProcessor.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isProcessing)
        
        // Refresh documents when processing completes
        documentProcessor.$lastProcessedDocument
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.refreshDocuments()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Supporting Types
enum DocumentSortOrder: String, CaseIterable {
    case dateAscending = "date_asc"
    case dateDescending = "date_desc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case sizeAscending = "size_asc"
    case sizeDescending = "size_desc"
    case statusAscending = "status_asc"
    case statusDescending = "status_desc"
    
    var displayName: String {
        switch self {
        case .dateAscending:
            return "Date (Oldest First)"
        case .dateDescending:
            return "Date (Newest First)"
        case .nameAscending:
            return "Name (A-Z)"
        case .nameDescending:
            return "Name (Z-A)"
        case .sizeAscending:
            return "Size (Smallest First)"
        case .sizeDescending:
            return "Size (Largest First)"
        case .statusAscending:
            return "Status (A-Z)"
        case .statusDescending:
            return "Status (Z-A)"
        }
    }
}

struct DocumentStatistics {
    let total: Int
    let processed: Int
    let pending: Int
    let processing: Int
    let failed: Int
    let totalSize: Int64
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var processingRate: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}

struct DocumentMetadataExport: Codable {
    let id: UUID
    let fileName: String
    let fileType: DocumentType
    let processingStatus: ProcessingStatus
    let importedAt: Date
    let processedAt: Date?
    let fileSize: Int64
    let tags: [String]
    let notes: String?
    let extractedDataCount: Int
    
    init(from document: HealthDocument) {
        self.id = document.id
        self.fileName = document.fileName
        self.fileType = document.fileType
        self.processingStatus = document.processingStatus
        self.importedAt = document.importedAt
        self.processedAt = document.processedAt
        self.fileSize = document.fileSize
        self.tags = document.tags
        self.notes = document.notes
        self.extractedDataCount = document.extractedData.count
    }
}

struct StorageUsage {
    let documentsSize: Int64
    let thumbnailsSize: Int64
    let totalSize: Int64
    let documentCount: Int
    
    var formattedDocumentsSize: String {
        ByteCountFormatter.string(fromByteCount: documentsSize, countStyle: .file)
    }
    
    var formattedThumbnailsSize: String {
        ByteCountFormatter.string(fromByteCount: thumbnailsSize, countStyle: .file)
    }
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var averageDocumentSize: Int64 {
        guard documentCount > 0 else { return 0 }
        return documentsSize / Int64(documentCount)
    }
}