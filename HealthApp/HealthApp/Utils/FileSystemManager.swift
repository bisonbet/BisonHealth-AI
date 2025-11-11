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
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
                // Reduced logging - only log in debug builds
                #if DEBUG
                print("📁 FileSystemManager: Ensured directory exists: \(directory.lastPathComponent)")
                #endif
            } catch {
                print("❌ FileSystemManager: Failed to create directory \(directory.path): \(error)")
                throw error
            }
        }
    }

    // Public method to ensure directories exist (for debugging/recovery)
    func ensureDirectoriesExist() throws {
        try createDirectoryStructure()
    }
    
    // MARK: - Document Storage
    func storeDocument(data: Data, fileName: String, fileType: DocumentType) throws -> URL {
        let sanitizedFileName = sanitizeFileName(fileName)
        let fileExtension = fileType.rawValue
        
        // Check if fileName already has the correct extension, if so don't add it again
        let finalFileName: String
        if sanitizedFileName.lowercased().hasSuffix(".\(fileExtension)") {
            finalFileName = "\(UUID().uuidString)_\(sanitizedFileName)"
        } else {
            finalFileName = "\(UUID().uuidString)_\(sanitizedFileName).\(fileExtension)"
        }
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
        
        // Try to decrypt, but handle authentication failures gracefully
        do {
            return try decryptData(encryptedData)
        } catch let error as CryptoKitError {
            // Check if this is an authentication failure (wrong key or corrupted data)
            if case .authenticationFailure = error {
                print("⚠️ FileSystemManager: Decryption authentication failure for file: \(url.lastPathComponent)")
                print("⚠️ FileSystemManager: This may indicate the file was encrypted with a different key or is corrupted")
                
                // Check if the file might be unencrypted by checking common file signatures
                let firstBytes = encryptedData.prefix(8)
                
                // PDF files start with "%PDF"
                if let pdfHeader = String(data: encryptedData.prefix(4), encoding: .utf8),
                   pdfHeader == "%PDF" {
                    print("ℹ️ FileSystemManager: File appears to be unencrypted PDF, returning as-is")
                    return encryptedData
                }
                
                // JPEG files start with FF D8 FF
                if firstBytes.count >= 3 && firstBytes[0] == 0xFF && firstBytes[1] == 0xD8 && firstBytes[2] == 0xFF {
                    print("ℹ️ FileSystemManager: File appears to be unencrypted JPEG, returning as-is")
                    return encryptedData
                }
                
                // PNG files start with 89 50 4E 47
                if firstBytes.count >= 4 && firstBytes[0] == 0x89 && firstBytes[1] == 0x50 && 
                   firstBytes[2] == 0x4E && firstBytes[3] == 0x47 {
                    print("ℹ️ FileSystemManager: File appears to be unencrypted PNG, returning as-is")
                    return encryptedData
                }
                
                // If it's not a recognizable unencrypted format, throw the error
                print("❌ FileSystemManager: Cannot decrypt file and it doesn't appear to be unencrypted")
                throw FileSystemError.decryptionFailed
            } else {
                // Other CryptoKit errors
                throw FileSystemError.decryptionFailed
            }
        } catch {
            // Re-throw other errors
            throw error
        }
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

    func findDocumentByFileName(_ displayName: String) -> URL? {
        let fileManager = FileManager.default

        do {
            let documentContents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)

            for fileURL in documentContents {
                let fileName = fileURL.lastPathComponent

                if fileName.contains(displayName.replacingOccurrences(of: " ", with: "%20")) ||
                   fileName.contains(displayName.replacingOccurrences(of: " ", with: "_")) ||
                   fileName.contains(displayName) {
                    return fileURL
                }
            }

            return nil
        } catch {
            print("❌ FileSystemManager: Error searching for document '\(displayName)': \(error)")
            return nil
        }
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
    
    // MARK: - Cache Management
    func clearCache() async throws {
        let fileManager = FileManager.default
        
        // Clear thumbnail cache
        let thumbnailContents = try fileManager.contentsOfDirectory(at: thumbnailsDirectory, 
                                                                     includingPropertiesForKeys: nil)
        for thumbnailURL in thumbnailContents {
            try fileManager.removeItem(at: thumbnailURL)
        }
        
        // Clear temporary exports older than 24 hours
        let exportContents = try fileManager.contentsOfDirectory(at: exportsDirectory, 
                                                                 includingPropertiesForKeys: [.creationDateKey])
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        
        for exportURL in exportContents {
            let resourceValues = try exportURL.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = resourceValues.creationDate, creationDate < dayAgo {
                try fileManager.removeItem(at: exportURL)
            }
        }
        
        // Clear any log files older than 7 days
        let logContents = try fileManager.contentsOfDirectory(at: logsDirectory, 
                                                              includingPropertiesForKeys: [.creationDateKey])
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        
        for logURL in logContents {
            let resourceValues = try logURL.resourceValues(forKeys: [.creationDateKey])
            if let creationDate = resourceValues.creationDate, creationDate < weekAgo {
                try fileManager.removeItem(at: logURL)
            }
        }
    }
    
    // MARK: - Storage Usage
    func getStorageUsage() async throws -> FileSystemStorageUsage {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var documentSize: Int64 = 0
        var thumbnailSize: Int64 = 0
        var exportSize: Int64 = 0
        var logSize: Int64 = 0
        
        // Calculate documents size
        let documentContents = try fileManager.contentsOfDirectory(at: documentsDirectory, 
                                                                   includingPropertiesForKeys: [.fileSizeKey])
        for documentURL in documentContents {
            let resourceValues = try documentURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(resourceValues.fileSize ?? 0)
            documentSize += size
            totalSize += size
        }
        
        // Calculate thumbnails size
        let thumbnailContents = try fileManager.contentsOfDirectory(at: thumbnailsDirectory, 
                                                                    includingPropertiesForKeys: [.fileSizeKey])
        for thumbnailURL in thumbnailContents {
            let resourceValues = try thumbnailURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(resourceValues.fileSize ?? 0)
            thumbnailSize += size
            totalSize += size
        }
        
        // Calculate exports size
        let exportContents = try fileManager.contentsOfDirectory(at: exportsDirectory, 
                                                                 includingPropertiesForKeys: [.fileSizeKey])
        for exportURL in exportContents {
            let resourceValues = try exportURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(resourceValues.fileSize ?? 0)
            exportSize += size
            totalSize += size
        }
        
        // Calculate logs size
        let logContents = try fileManager.contentsOfDirectory(at: logsDirectory, 
                                                              includingPropertiesForKeys: [.fileSizeKey])
        for logURL in logContents {
            let resourceValues = try logURL.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(resourceValues.fileSize ?? 0)
            logSize += size
            totalSize += size
        }
        
        return FileSystemStorageUsage(
            totalSize: totalSize,
            documentsSize: documentSize,
            thumbnailsSize: thumbnailSize,
            exportsSize: exportSize,
            logsSize: logSize
        )
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

// MARK: - Storage Usage Model
struct FileSystemStorageUsage {
    let totalSize: Int64
    let documentsSize: Int64
    let thumbnailsSize: Int64
    let exportsSize: Int64
    let logsSize: Int64
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedDocumentsSize: String {
        ByteCountFormatter.string(fromByteCount: documentsSize, countStyle: .file)
    }
    
    var formattedThumbnailsSize: String {
        ByteCountFormatter.string(fromByteCount: thumbnailsSize, countStyle: .file)
    }
    
    var formattedExportsSize: String {
        ByteCountFormatter.string(fromByteCount: exportsSize, countStyle: .file)
    }
    
    var formattedLogsSize: String {
        ByteCountFormatter.string(fromByteCount: logsSize, countStyle: .file)
    }
}