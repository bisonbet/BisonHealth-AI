import Foundation
import UIKit
import UniformTypeIdentifiers
import VisionKit
import PhotosUI

// MARK: - Document Importer
@MainActor
class DocumentImporter: NSObject, ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DocumentImporter(
        fileSystemManager: FileSystemManager.shared,
        databaseManager: DatabaseManager.shared
    )
    
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var lastError: Error?
    
    private let fileSystemManager: FileSystemManager
    private let databaseManager: DatabaseManager
    
    // MARK: - Initialization
    init(fileSystemManager: FileSystemManager, databaseManager: DatabaseManager) {
        self.fileSystemManager = fileSystemManager
        self.databaseManager = databaseManager
        super.init()
    }
    
    // MARK: - Document Import from Files
    func importDocument(from url: URL) async throws -> HealthDocument {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            importProgress = 0.2
            
            // Get file information
            let fileName = url.lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            let fileType = DocumentType.from(fileExtension: fileExtension)
            
            // Validate file type
            guard isValidDocumentType(fileType) else {
                throw DocumentImportError.unsupportedFileType
            }
            
            importProgress = 0.4
            
            // Get file size and validate
            let fileSize = try getFileSize(url)
            try validateFileSize(fileSize)
            
            importProgress = 0.6
            
            // Copy file to secure storage
            let storedURL = try fileSystemManager.copyFile(
                from: url,
                fileName: fileName,
                fileType: fileType
            )
            
            importProgress = 0.8
            
            // Create document record
            let document = HealthDocument(
                fileName: fileName,
                fileType: fileType,
                filePath: storedURL,
                fileSize: fileSize
            )
            
            // Save to database
            try await databaseManager.saveDocument(document)
            
            importProgress = 1.0
            
            // Generate thumbnail asynchronously
            Task {
                do {
                    if let thumbnailURL = try await fileSystemManager.generateThumbnail(
                        for: storedURL,
                        documentType: fileType
                    ) {
                        var updatedDocument = document
                        updatedDocument.thumbnailPath = thumbnailURL
                        try await databaseManager.saveDocument(updatedDocument)
                    }
                } catch {
                    // Thumbnail generation failure is not critical
                    print("Failed to generate thumbnail: \(error)")
                }
            }
            
            return document
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Document Scanner Integration
    func presentDocumentScanner() -> VNDocumentCameraViewController? {
        guard VNDocumentCameraViewController.isSupported else {
            return nil
        }
        
        let scannerViewController = VNDocumentCameraViewController()
        return scannerViewController
    }
    
    // MARK: - Document Import from Camera/Scanner
    func importScannedDocument(_ scannedDocument: VNDocumentCameraScan) async throws -> HealthDocument {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            importProgress = 0.2
            
            // Convert scanned pages to PDF
            let pdfData = try createPDFFromScannedPages(scannedDocument)
            
            importProgress = 0.6
            
            // Generate filename
            let fileName = generateScannedDocumentFileName()
            
            // Store document
            let storedURL = try fileSystemManager.storeDocument(
                data: pdfData,
                fileName: fileName,
                fileType: .pdf
            )
            
            importProgress = 0.8
            
            // Create document record
            let document = HealthDocument(
                fileName: fileName,
                fileType: .pdf,
                filePath: storedURL,
                fileSize: Int64(pdfData.count),
                tags: ["scanned"]
            )
            
            // Save to database
            try await databaseManager.saveDocument(document)
            
            importProgress = 1.0
            
            // Generate thumbnail asynchronously
            Task {
                do {
                    if let thumbnailURL = try await fileSystemManager.generateThumbnail(
                        for: storedURL,
                        documentType: .pdf
                    ) {
                        var updatedDocument = document
                        updatedDocument.thumbnailPath = thumbnailURL
                        try await databaseManager.saveDocument(updatedDocument)
                    }
                } catch {
                    print("Failed to generate thumbnail: \(error)")
                }
            }
            
            return document
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Image Import
    func importImage(_ image: UIImage, fileName: String? = nil) async throws -> HealthDocument {
        isImporting = true
        importProgress = 0.0
        
        defer {
            isImporting = false
            importProgress = 0.0
        }
        
        do {
            importProgress = 0.3
            
            // Convert image to JPEG data
            guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                throw DocumentImportError.imageProcessingFailed
            }
            
            importProgress = 0.6
            
            // Generate filename if not provided
            let finalFileName = fileName ?? generateImageFileName()
            
            // Store image
            let storedURL = try fileSystemManager.storeDocument(
                data: imageData,
                fileName: finalFileName,
                fileType: .jpeg
            )
            
            importProgress = 0.8
            
            // Create document record
            let document = HealthDocument(
                fileName: finalFileName,
                fileType: .jpeg,
                filePath: storedURL,
                fileSize: Int64(imageData.count),
                tags: ["photo"]
            )
            
            // Save to database
            try await databaseManager.saveDocument(document)
            
            importProgress = 1.0
            
            // Generate thumbnail asynchronously
            Task {
                do {
                    if let thumbnailURL = try await fileSystemManager.generateThumbnail(
                        for: storedURL,
                        documentType: .jpeg
                    ) {
                        var updatedDocument = document
                        updatedDocument.thumbnailPath = thumbnailURL
                        try await databaseManager.saveDocument(updatedDocument)
                    }
                } catch {
                    print("Failed to generate thumbnail: \(error)")
                }
            }
            
            return document
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Batch Import
    func importMultipleDocuments(from urls: [URL]) async throws -> [HealthDocument] {
        var importedDocuments: [HealthDocument] = []
        let totalFiles = urls.count
        
        for (index, url) in urls.enumerated() {
            do {
                let document = try await importDocument(from: url)
                importedDocuments.append(document)
                
                // Update overall progress
                importProgress = Double(index + 1) / Double(totalFiles)
            } catch {
                // Continue with other files even if one fails
                print("Failed to import \(url.lastPathComponent): \(error)")
                lastError = error
            }
        }
        
        return importedDocuments
    }
    
    // MARK: - Validation Methods
    private func isValidDocumentType(_ type: DocumentType) -> Bool {
        switch type {
        case .pdf, .doc, .docx, .jpeg, .jpg, .png, .heic:
            return true
        case .other:
            return false
        }
    }
    
    private func validateFileSize(_ size: Int64) throws {
        let maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB
        
        if size > maxFileSize {
            throw DocumentImportError.fileTooLarge
        }
        
        if size == 0 {
            throw DocumentImportError.emptyFile
        }
    }
    
    private func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    // MARK: - PDF Creation from Scanned Pages
    private func createPDFFromScannedPages(_ scan: VNDocumentCameraScan) throws -> Data {
        let pdfDocument = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfDocument, .zero, nil)
        
        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            let pageRect = CGRect(origin: .zero, size: image.size)
            
            UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
            
            image.draw(in: pageRect)
        }
        
        UIGraphicsEndPDFContext()
        
        return pdfDocument as Data
    }
    
    // MARK: - Photo Picker Integration
    func importFromPhotoLibrary(_ results: [PHPickerResult]) async throws -> [HealthDocument] {
        var importedDocuments: [HealthDocument] = []
        
        for result in results {
            do {
                let document = try await importFromPhotoPickerResult(result)
                importedDocuments.append(document)
            } catch {
                print("Failed to import photo: \(error)")
                lastError = error
            }
        }
        
        return importedDocuments
    }
    
    private func importFromPhotoPickerResult(_ result: PHPickerResult) async throws -> HealthDocument {
        return try await withCheckedThrowingContinuation { continuation in
            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    Task { @MainActor in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        guard let image = object as? UIImage else {
                            continuation.resume(throwing: DocumentImportError.imageProcessingFailed)
                            return
                        }
                        
                        do {
                            let document = try await self?.importImage(image)
                            if let document = document {
                                continuation.resume(returning: document)
                            } else {
                                continuation.resume(throwing: DocumentImportError.imageProcessingFailed)
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } else {
                continuation.resume(throwing: DocumentImportError.unsupportedFileType)
            }
        }
    }
    
    // MARK: - Document Type Detection
    func detectDocumentType(from image: UIImage) async -> DocumentTypeDetectionResult {
        // Use Vision framework to detect document type
        // This is a simplified implementation - could be enhanced with ML models
        
        let aspectRatio = image.size.width / image.size.height
        let imageSize = image.size.width * image.size.height
        
        var confidence: Double = 0.5
        var detectedType: DetectedDocumentType = .unknown
        
        // Simple heuristics for document type detection
        if aspectRatio > 1.2 && aspectRatio < 1.6 {
            // Likely a document page
            detectedType = .medicalReport
            confidence = 0.7
        } else if aspectRatio > 0.6 && aspectRatio < 0.8 {
            // Likely a lab report or form
            detectedType = .labReport
            confidence = 0.6
        } else if imageSize > 1000000 {
            // High resolution image, likely a photo of document
            detectedType = .medicalReport
            confidence = 0.5
        }
        
        return DocumentTypeDetectionResult(
            type: detectedType,
            confidence: confidence,
            suggestedTags: getSuggestedTags(for: detectedType)
        )
    }
    
    private func getSuggestedTags(for type: DetectedDocumentType) -> [String] {
        switch type {
        case .labReport:
            return ["lab", "blood test", "results"]
        case .medicalReport:
            return ["medical", "report", "doctor"]
        case .prescription:
            return ["prescription", "medication", "pharmacy"]
        case .insurance:
            return ["insurance", "coverage", "benefits"]
        case .unknown:
            return ["document"]
        }
    }
    
    // MARK: - File Name Generation
    private func generateScannedDocumentFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Scanned_Document_\(timestamp)"
    }
    
    private func generateImageFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Health_Image_\(timestamp)"
    }
}

// MARK: - Document Type Detection
struct DocumentTypeDetectionResult {
    let type: DetectedDocumentType
    let confidence: Double
    let suggestedTags: [String]
}

enum DetectedDocumentType {
    case labReport
    case medicalReport
    case prescription
    case insurance
    case unknown
    
    var displayName: String {
        switch self {
        case .labReport:
            return "Lab Report"
        case .medicalReport:
            return "Medical Report"
        case .prescription:
            return "Prescription"
        case .insurance:
            return "Insurance Document"
        case .unknown:
            return "Unknown Document"
        }
    }
}

// MARK: - Document Import Errors
enum DocumentImportError: LocalizedError {
    case unsupportedFileType
    case fileTooLarge
    case emptyFile
    case imageProcessingFailed
    case scanningFailed
    case accessDenied
    case networkError
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Please select a PDF, Word document, or image file."
        case .fileTooLarge:
            return "File is too large. Maximum file size is 50MB."
        case .emptyFile:
            return "The selected file is empty."
        case .imageProcessingFailed:
            return "Failed to process the image."
        case .scanningFailed:
            return "Document scanning failed."
        case .accessDenied:
            return "Access to the file was denied."
        case .networkError:
            return "Network error occurred during import."
        case .storageError:
            return "Storage error occurred while saving the document."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .unsupportedFileType:
            return "Try converting your file to PDF or select a supported image format."
        case .fileTooLarge:
            return "Try compressing the file or splitting it into smaller parts."
        case .emptyFile:
            return "Please select a different file that contains data."
        case .imageProcessingFailed:
            return "Try selecting a different image or check if the image is corrupted."
        case .scanningFailed:
            return "Try scanning the document again with better lighting."
        case .accessDenied:
            return "Check file permissions or try selecting the file again."
        case .networkError:
            return "Check your internet connection and try again."
        case .storageError:
            return "Check available storage space and try again."
        }
    }
}