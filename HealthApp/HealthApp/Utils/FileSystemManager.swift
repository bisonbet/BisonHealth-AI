import Foundation
import UIKit
import CryptoKit
import UniformTypeIdentifiers

// MARK: - File System Manager
@MainActor
class FileSystemManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared: FileSystemManager = {
        do {
            return try FileSystemManager()
        } catch {
            fatalError("Failed to initialize FileSystemManager: \(error)")
        }
    }()
    
    // MARK: - Directory Structure
    private let baseDirectory: URL
    private let documentsDirectory: URL
    private let thumbnailsDirectory: URL
    private let exportsDirectory: URL
    private let logsDirectory: URL
    
    private let encryptionKey: SymmetricKey
    
    // MARK: - Initialization
    init() throws {
        // Get app's documents directory
        let appDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseDirectory = appDocuments.appendingPathComponent("HealthApp")
        
        // Set up directory structure
        self.documentsDirectory = baseDirectory.appendingPathComponent("Documents/Imported")
        self.thumbnailsDirectory = baseDirectory.appendingPathComponent("Documents/Thumbnails")
        self.exportsDirectory = baseDirectory.appendingPathComponent("Exports")
        self.logsDirectory = baseDirectory.appendingPathComponent("Logs")
        
        // Get encryption key from keychain
        let keychain = Keychain()
        self.encryptionKey = try keychain.getEncryptionKey() ?? {
            let newKey = SymmetricKey(size: .bits256)
            try keychain.storeEncryptionKey(newKey)
            return newKey
        }()
        
        // Create directory structure
        try createDirectoryStructure()
    }
    
    // MARK: - Directory Management
    private func createDirectoryStructure() throws {
        let directories = [
            baseDirectory,
            documentsDirectory,
            thumbnailsDirectory,
            exportsDirectory,
            logsDirectory
        ]
        
        for directory in directories {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
    }
    
    // MARK: - Document Storage
    func storeDocument(data: Data, fileName: String, fileType: DocumentType) throws -> URL {
        let sanitizedFileName = sanitizeFileName(fileName)
        let fileExtension = getFileExtension(for: fileType)
        let finalFileName = "\(UUID().uuidString)_\(sanitizedFileName).\(fileExtension)"
        let destinationURL = documentsDirectory.appendingPathComponent(finalFileName)
        
        // Encrypt the document data
        let encryptedData = try encryptData(data)
        
        // Write encrypted data to file
        try encryptedData.write(to: destinationURL)
        
        // Set file protection
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destinationURL.path
        )
        
        return destinationURL
    }
    
    func retrieveDocument(from url: URL) throws -> Data {
        // Read encrypted data
        let encryptedData = try Data(contentsOf: url)
        
        // Decrypt and return
        return try decryptData(encryptedData)
    }
    
    func deleteDocument(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        
        // Also delete associated thumbnail if it exists
        let thumbnailURL = getThumbnailURL(for: url)
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            try FileManager.default.removeItem(at: thumbnailURL)
        }
    }
    
    // MARK: - Thumbnail Management
    func generateThumbnail(for documentURL: URL, documentType: DocumentType) async throws -> URL? {
        let thumbnailURL = getThumbnailURL(for: documentURL)
        
        switch documentType {
        case .jpeg, .jpg, .png, .heic:
            return try await generateImageThumbnail(documentURL: documentURL, thumbnailURL: thumbnailURL)
        case .pdf:
            return try await generatePDFThumbnail(documentURL: documentURL, thumbnailURL: thumbnailURL)
        default:
            return try generateGenericThumbnail(documentType: documentType, thumbnailURL: thumbnailURL)
        }
    }
    
    private func generateImageThumbnail(documentURL: URL, thumbnailURL: URL) async throws -> URL {
        let imageData = try retrieveDocument(from: documentURL)
        
        guard let image = UIImage(data: imageData) else {
            throw FileSystemError.thumbnailGenerationFailed
        }
        
        let thumbnailSize = CGSize(width: 200, height: 200)
        let thumbnail = image.preparingThumbnail(of: thumbnailSize) ?? image
        
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw FileSystemError.thumbnailGenerationFailed
        }
        
        try thumbnailData.write(to: thumbnailURL)
        return thumbnailURL
    }
    
    private func generatePDFThumbnail(documentURL: URL, thumbnailURL: URL) async throws -> URL {
        let pdfData = try retrieveDocument(from: documentURL)
        
        guard let pdfDocument = CGPDFDocument(CGDataProvider(data: pdfData as CFData)!),
              let firstPage = pdfDocument.page(at: 1) else {
            throw FileSystemError.thumbnailGenerationFailed
        }
        
        let pageRect = firstPage.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        
        let thumbnail = renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 200, height: 200)))
            
            context.cgContext.scaleBy(x: 200 / pageRect.width, y: 200 / pageRect.height)
            context.cgContext.drawPDFPage(firstPage)
        }
        
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw FileSystemError.thumbnailGenerationFailed
        }
        
        try thumbnailData.write(to: thumbnailURL)
        return thumbnailURL
    }
    
    private func generateGenericThumbnail(documentType: DocumentType, thumbnailURL: URL) throws -> URL {
        let iconName = documentType.icon
        let systemImage = UIImage(systemName: iconName) ?? UIImage(systemName: "doc")!
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let thumbnail = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemBackground.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 200, height: 200)))
            
            systemImage.draw(in: CGRect(x: 50, y: 50, width: 100, height: 100))
        }
        
        guard let thumbnailData = thumbnail.pngData() else {
            throw FileSystemError.thumbnailGenerationFailed
        }
        
        try thumbnailData.write(to: thumbnailURL)
        return thumbnailURL
    }
    
    private func getThumbnailURL(for documentURL: URL) -> URL {
        let documentName = documentURL.deletingPathExtension().lastPathComponent
        return thumbnailsDirectory.appendingPathComponent("\(documentName)_thumb.jpg")
    }
    
    // MARK: - File Operations
    func copyFile(from sourceURL: URL, fileName: String, fileType: DocumentType) throws -> URL {
        let fileData = try Data(contentsOf: sourceURL)
        return try storeDocument(data: fileData, fileName: fileName, fileType: fileType)
    }
    
    func moveFile(from sourceURL: URL, fileName: String, fileType: DocumentType) throws -> URL {
        let destinationURL = try copyFile(from: sourceURL, fileName: fileName, fileType: fileType)
        
        // Remove original file if it's not in our managed directory
        if !sourceURL.path.hasPrefix(baseDirectory.path) {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        
        return destinationURL
    }
    
    func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    // MARK: - Storage Management
    func getTotalStorageUsed() throws -> Int64 {
        let documentsSize = try getDirectorySize(documentsDirectory)
        let thumbnailsSize = try getDirectorySize(thumbnailsDirectory)
        let exportsSize = try getDirectorySize(exportsDirectory)
        return documentsSize + thumbnailsSize + exportsSize
    }
    
    func getDocumentStorageUsed() throws -> Int64 {
        return try getDirectorySize(documentsDirectory)
    }
    
    func getThumbnailStorageUsed() throws -> Int64 {
        return try getDirectorySize(thumbnailsDirectory)
    }
    
    func getDirectorySize(_ directoryType: DirectoryType) async throws -> Int64 {
        let directory: URL
        switch directoryType {
        case .documents:
            directory = documentsDirectory
        case .thumbnails:
            directory = thumbnailsDirectory
        case .exports:
            directory = exportsDirectory
        case .logs:
            directory = logsDirectory
        }
        
        return try getDirectorySize(directory)
    }
    
    func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    private func getDirectorySize(_ directory: URL) throws -> Int64 {
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        
        var totalSize: Int64 = 0
        
        if let enumerator = enumerator {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isDirectory != true {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        }
        
        return totalSize
    }
    
    // MARK: - Cleanup Operations
    func cleanupOrphanedFiles(keepingDocuments: Set<String>, keepingThumbnails: Set<String>) async throws {
        // Clean up orphaned document files
        let documentContents = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
        for fileURL in documentContents {
            let fileName = fileURL.lastPathComponent
            if !keepingDocuments.contains(fileName) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // Clean up orphaned thumbnail files
        let thumbnailContents = try FileManager.default.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: nil)
        for fileURL in thumbnailContents {
            let fileName = fileURL.lastPathComponent
            if !keepingThumbnails.contains(fileName) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    func cleanupOldThumbnails(olderThan days: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        
        if let enumerator = enumerator {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                if let modificationDate = resourceValues.contentModificationDate,
                   modificationDate < cutoffDate {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
    
    // MARK: - Export Management
    func createExportFile(data: Data, fileName: String, fileType: ExportFileType) throws -> URL {
        let sanitizedFileName = sanitizeFileName(fileName)
        let fileExtension = fileType.fileExtension
        let finalFileName = "\(sanitizedFileName).\(fileExtension)"
        let exportURL = exportsDirectory.appendingPathComponent(finalFileName)
        
        try data.write(to: exportURL)
        return exportURL
    }
    
    func getExportURL(for fileName: String, fileType: ExportFileType) -> URL {
        let sanitizedFileName = sanitizeFileName(fileName)
        let fileExtension = fileType.fileExtension
        let finalFileName = "\(sanitizedFileName).\(fileExtension)"
        return exportsDirectory.appendingPathComponent(finalFileName)
    }
    
    // MARK: - Utility Methods
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func getFileExtension(for documentType: DocumentType) -> String {
        switch documentType {
        case .pdf: return "pdf"
        case .doc: return "doc"
        case .docx: return "docx"
        case .jpeg: return "jpg"
        case .jpg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .other: return "dat"
        }
    }
    
    // MARK: - Encryption/Decryption
    private func encryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        guard let encryptedData = sealedBox.combined else {
            throw FileSystemError.encryptionFailed
        }
        return encryptedData
    }
    
    private func decryptData(_ encryptedData: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
}

// MARK: - Directory Types
enum DirectoryType {
    case documents
    case thumbnails
    case exports
    case logs
}

// MARK: - Export File Types
enum ExportFileType {
    case json
    case pdf
    case csv
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .pdf: return "pdf"
        case .csv: return "csv"
        }
    }
    
    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .pdf: return "application/pdf"
        case .csv: return "text/csv"
        }
    }
}

// MARK: - File System Errors
enum FileSystemError: LocalizedError {
    case directoryCreationFailed
    case fileNotFound
    case encryptionFailed
    case decryptionFailed
    case thumbnailGenerationFailed
    case insufficientStorage
    case invalidFileName
    case fileOperationFailed
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Failed to create directory structure"
        case .fileNotFound:
            return "File not found"
        case .encryptionFailed:
            return "Failed to encrypt file"
        case .decryptionFailed:
            return "Failed to decrypt file"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .invalidFileName:
            return "Invalid file name"
        case .fileOperationFailed:
            return "File operation failed"
        }
    }
}