import Foundation
import UIKit
import PDFKit

// MARK: - Document Exporter
@MainActor
class DocumentExporter: ObservableObject {
    
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var lastError: Error?
    
    private let fileSystemManager: FileSystemManager
    private let databaseManager: DatabaseManager
    
    // MARK: - Initialization
    init(fileSystemManager: FileSystemManager, databaseManager: DatabaseManager) {
        self.fileSystemManager = fileSystemManager
        self.databaseManager = databaseManager
    }
    
    // MARK: - JSON Export
    func exportHealthDataAsJSON(includeTypes: Set<HealthDataType> = Set(HealthDataType.allCases)) async throws -> URL {
        isExporting = true
        exportProgress = 0.0
        
        defer {
            isExporting = false
            exportProgress = 0.0
        }
        
        do {
            var exportData: [String: Any] = [:]
            exportData["exportDate"] = ISO8601DateFormatter().string(from: Date())
            exportData["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            
            exportProgress = 0.1
            
            // Export Personal Health Info
            if includeTypes.contains(.personalInfo) {
                if let personalInfo = try await databaseManager.fetchPersonalHealthInfo() {
                    exportData["personalHealthInfo"] = try encodeToJSON(personalInfo)
                }
            }
            exportProgress = 0.3
            
            // Export Blood Test Results
            if includeTypes.contains(.bloodTest) {
                let bloodTests = try await databaseManager.fetchBloodTestResults()
                exportData["bloodTestResults"] = try bloodTests.map { try encodeToJSON($0) }
            }
            exportProgress = 0.5
            
            // Export Documents metadata
            let documents = try await databaseManager.fetchDocuments()
            let documentsMetadata = documents.map { document in
                return [
                    "id": document.id.uuidString,
                    "fileName": document.fileName,
                    "fileType": document.fileType.rawValue,
                    "importedAt": ISO8601DateFormatter().string(from: document.importedAt),
                    "fileSize": document.fileSize,
                    "tags": document.tags,
                    "notes": document.notes ?? ""
                ]
            }
            exportData["documents"] = documentsMetadata
            exportProgress = 0.7
            
            // Export Chat Conversations
            let conversations = try await databaseManager.fetchConversations()
            let conversationsData = conversations.map { conversation in
                return [
                    "id": conversation.id.uuidString,
                    "title": conversation.title,
                    "createdAt": ISO8601DateFormatter().string(from: conversation.createdAt),
                    "messageCount": conversation.messages.count,
                    "tags": conversation.tags
                ]
            }
            exportData["chatConversations"] = conversationsData
            exportProgress = 0.9
            
            // Create JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            
            // Generate filename
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let fileName = "HealthData_Export_\(timestamp)"
            
            // Save to exports directory
            let exportURL = try fileSystemManager.createExportFile(
                data: jsonData,
                fileName: fileName,
                fileType: .json
            )
            
            exportProgress = 1.0
            return exportURL
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - PDF Report Export
    func exportHealthReportAsPDF(includeTypes: Set<HealthDataType> = Set(HealthDataType.allCases)) async throws -> URL {
        isExporting = true
        exportProgress = 0.0
        
        defer {
            isExporting = false
            exportProgress = 0.0
        }
        
        do {
            // Create PDF document
            let pdfDocument = PDFDocument()
            var pageIndex = 0
            
            exportProgress = 0.1
            
            // Title Page
            let titlePage = createTitlePage()
            pdfDocument.insert(titlePage, at: pageIndex)
            pageIndex += 1
            
            exportProgress = 0.2
            
            // Personal Health Info
            if includeTypes.contains(.personalInfo) {
                if let personalInfo = try await databaseManager.fetchPersonalHealthInfo() {
                    let personalInfoPage = createPersonalInfoPage(personalInfo)
                    pdfDocument.insert(personalInfoPage, at: pageIndex)
                    pageIndex += 1
                }
            }
            
            exportProgress = 0.4
            
            // Blood Test Results
            if includeTypes.contains(.bloodTest) {
                let bloodTests = try await databaseManager.fetchBloodTestResults()
                if !bloodTests.isEmpty {
                    let bloodTestPages = createBloodTestPages(bloodTests)
                    for page in bloodTestPages {
                        pdfDocument.insert(page, at: pageIndex)
                        pageIndex += 1
                    }
                }
            }
            
            exportProgress = 0.6
            
            // Documents Summary
            let documents = try await databaseManager.fetchDocuments()
            if !documents.isEmpty {
                let documentsPage = createDocumentsSummaryPage(documents)
                pdfDocument.insert(documentsPage, at: pageIndex)
                pageIndex += 1
            }
            
            exportProgress = 0.8
            
            // Chat Summary
            let conversations = try await databaseManager.fetchConversations()
            if !conversations.isEmpty {
                let chatPage = createChatSummaryPage(conversations)
                pdfDocument.insert(chatPage, at: pageIndex)
                pageIndex += 1
            }
            
            exportProgress = 0.9
            
            // Save PDF
            guard let pdfData = pdfDocument.dataRepresentation() else {
                throw DocumentExportError.pdfGenerationFailed
            }
            
            // Generate filename
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let fileName = "Health_Report_\(timestamp)"
            
            // Save to exports directory
            let exportURL = try fileSystemManager.createExportFile(
                data: pdfData,
                fileName: fileName,
                fileType: .pdf
            )
            
            exportProgress = 1.0
            return exportURL
            
        } catch {
            lastError = error
            throw error
        }
    }
    
    // MARK: - Document Bundle Export
    func exportDocumentBundle(documents: [HealthDocument]) async throws -> URL {
        isExporting = true
        exportProgress = 0.0
        
        defer {
            isExporting = false
            exportProgress = 0.0
        }
        
        // This would create a ZIP file containing all selected documents
        // For now, we'll create a simple folder structure
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let bundleName = "Document_Bundle_\(timestamp)"
        
        // Create temporary directory for bundle
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(bundleName)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        let totalDocuments = documents.count
        
        for (index, document) in documents.enumerated() {
            do {
                // Copy document to bundle
                let documentData = try fileSystemManager.retrieveDocument(from: document.filePath)
                let destinationURL = tempURL.appendingPathComponent(document.fileName)
                try documentData.write(to: destinationURL)
                
                exportProgress = Double(index + 1) / Double(totalDocuments)
            } catch {
                print("Failed to export document \(document.fileName): \(error)")
            }
        }
        
        return tempURL
    }
    
    // MARK: - PDF Page Creation
    private func createTitlePage() -> PDFPage {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let page = PDFPage()
        
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            
            // Background
            cgContext.setFillColor(UIColor.systemBackground.cgColor)
            cgContext.fill(pageRect)
            
            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.label
            ]
            let title = "Health Data Report"
            let titleSize = title.size(withAttributes: titleAttributes)
            let titleRect = CGRect(
                x: (pageRect.width - titleSize.width) / 2,
                y: pageRect.height - 200,
                width: titleSize.width,
                height: titleSize.height
            )
            title.draw(in: titleRect, withAttributes: titleAttributes)
            
            // Date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            let dateString = "Generated on \(dateFormatter.string(from: Date()))"
            
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let dateSize = dateString.size(withAttributes: dateAttributes)
            let dateRect = CGRect(
                x: (pageRect.width - dateSize.width) / 2,
                y: titleRect.minY - 50,
                width: dateSize.width,
                height: dateSize.height
            )
            dateString.draw(in: dateRect, withAttributes: dateAttributes)
        }
        
        page.setBounds(pageRect, for: .mediaBox)
        // Note: In a real implementation, you'd need to properly set the page content
        // This is a simplified version for demonstration
        
        return page
    }
    
    private func createPersonalInfoPage(_ personalInfo: PersonalHealthInfo) -> PDFPage {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        
        // Create page content (simplified)
        page.setBounds(pageRect, for: .mediaBox)
        
        return page
    }
    
    private func createBloodTestPages(_ bloodTests: [BloodTestResult]) -> [PDFPage] {
        // Create pages for blood test results (simplified)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        page.setBounds(pageRect, for: .mediaBox)
        
        return [page]
    }
    
    private func createDocumentsSummaryPage(_ documents: [HealthDocument]) -> PDFPage {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        page.setBounds(pageRect, for: .mediaBox)
        
        return page
    }
    
    private func createChatSummaryPage(_ conversations: [ChatConversation]) -> PDFPage {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let page = PDFPage()
        page.setBounds(pageRect, for: .mediaBox)
        
        return page
    }
    
    // MARK: - Utility Methods
    private func encodeToJSON<T: Codable>(_ object: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(object)
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [String: Any] ?? [:]
    }
}

// MARK: - Document Export Errors
enum DocumentExportError: LocalizedError {
    case noDataToExport
    case pdfGenerationFailed
    case jsonSerializationFailed
    case fileCreationFailed
    case insufficientStorage
    
    var errorDescription: String? {
        switch self {
        case .noDataToExport:
            return "No data available to export"
        case .pdfGenerationFailed:
            return "Failed to generate PDF report"
        case .jsonSerializationFailed:
            return "Failed to serialize data to JSON"
        case .fileCreationFailed:
            return "Failed to create export file"
        case .insufficientStorage:
            return "Insufficient storage space for export"
        }
    }
}