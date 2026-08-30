import Foundation
import UIKit

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
            // Gather report sections (each rendered as paginated text)
            var sections: [ReportSection] = []
            
            // Personal Health Info
            if includeTypes.contains(.personalInfo) {
                if let personalInfo = try await databaseManager.fetchPersonalHealthInfo() {
                    exportProgress = 0.2
                    sections.append(contentsOf: personalInfoSection(personalInfo))
                }
            }
            
            // Blood Test Results
            if includeTypes.contains(.bloodTest) {
                let bloodTests = try await databaseManager.fetchBloodTestResults()
                exportProgress = 0.4
                for test in bloodTests {
                    sections.append(bloodTestSection(test))
                }
            }
            
            // Documents Summary
            let documents = try await databaseManager.fetchDocuments()
            if !documents.isEmpty {
                exportProgress = 0.6
                sections.append(ReportSection(
                    title: "Documents (\(documents.count))",
                    lines: documents.map { "\($0.fileName) — imported \(Self.reportDateFormatter.string(from: $0.importedAt))" }
                ))
            }
            
            // Chat Summary
            let conversations = try await databaseManager.fetchConversations()
            if !conversations.isEmpty {
                exportProgress = 0.75
                sections.append(ReportSection(
                    title: "Chat Conversations (\(conversations.count))",
                    lines: conversations.map { "\($0.title) — \($0.messages.count) messages — \(Self.reportDateFormatter.string(from: $0.createdAt))" }
                ))
            }
            
            guard !sections.isEmpty else {
                throw DocumentExportError.noDataToExport
            }
            
            exportProgress = 0.85
            let pdfData = renderReportPDF(sections: sections)
            
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
    func exportDocumentBundle(documents: [MedicalDocument]) async throws -> URL {
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
                AppLog.shared.documents("Failed to export document '\(document.fileName)': \(error)", level: .error)
            }
        }
        
        return tempURL
    }
    
    // MARK: - PDF Rendering
    private struct ReportSection {
        let title: String
        let lines: [String]
    }
    
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 50
    private static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Renders the report as real, paginated text via UIGraphicsPDFRenderer.
    /// A block that no longer fits on the page starts a new page.
    private func renderReportPDF(sections: [ReportSection]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Health Data Report"]
        let renderer = UIGraphicsPDFRenderer(bounds: Self.pageRect, format: format)
        
        let titleFont = UIFont.boldSystemFont(ofSize: 24)
        let sectionFont = UIFont.boldSystemFont(ofSize: 14)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        // Hoist MainActor-isolated statics into locals: the renderer's
        // drawing closure is nonisolated.
        let pageRect = Self.pageRect
        let margin = Self.margin
        let generatedOn = "Generated on \(Self.reportDateFormatter.string(from: Date()))"
        
        return renderer.pdfData { ctx in
            // UIGraphicsPDFRenderer requires an explicit beginPage() before ANY
            // drawing — including the first page. Without it everything renders
            // onto a page that was never started and is silently lost.
            ctx.beginPage()
            var y: CGFloat = margin
            
            // Report header on the first page
            ("Health Data Report" as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: titleFont]
            )
            y += titleFont.lineHeight + 4
            (generatedOn as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: bodyFont, .foregroundColor: UIColor.gray]
            )
            y += bodyFont.lineHeight + 24
            
            func drawBlock(_ text: String, font: UIFont, color: UIColor, indent: CGFloat, spacing: CGFloat) {
                let width = pageRect.width - margin * 2 - indent
                let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                let bounds = attributed.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let height = ceil(bounds.height)
                if y + height > pageRect.height - margin {
                    ctx.beginPage()
                    y = margin
                }
                attributed.draw(
                    with: CGRect(x: margin + indent, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                y += height + spacing
            }
            
            for section in sections {
                drawBlock(section.title, font: sectionFont, color: UIColor.black, indent: 0, spacing: 6)
                for line in section.lines {
                    drawBlock(line, font: bodyFont, color: UIColor.darkText, indent: 14, spacing: 2)
                }
                y += 14
            }
        }
    }
    
    private func personalInfoSection(_ info: PersonalHealthInfo) -> [ReportSection] {
        var lines: [String] = []
        if let name = info.name { lines.append("Name: \(name)") }
        if let dob = info.dateOfBirth { lines.append("Date of birth: \(Self.reportDateFormatter.string(from: dob))") }
        if let gender = info.gender { lines.append("Gender: \(gender)") }
        if let height = info.height { lines.append("Height: \(height)") }
        if let weight = info.weight { lines.append("Weight: \(weight)") }
        if let bloodType = info.bloodType { lines.append("Blood type: \(bloodType)") }
        if !info.allergies.isEmpty { lines.append("Allergies: \(info.allergies.joined(separator: ", "))") }
        lines.append("Medications: \(info.medications.count) recorded")
        lines.append("Supplements: \(info.supplements.count) recorded")
        lines.append("Personal medical history: \(info.personalMedicalHistory.count) entries")
        return [ReportSection(title: "Personal Health Info", lines: lines)]
    }
    
    private func bloodTestSection(_ test: BloodTestResult) -> ReportSection {
        var lines: [String] = []
        if let lab = test.laboratoryName, !lab.isEmpty { lines.append("Laboratory: \(lab)") }
        if !test.results.isEmpty {
            lines.append(contentsOf: test.results.map { item in
                var line = "\(item.name): \(item.value)"
                if let unit = item.unit, !unit.isEmpty { line += " \(unit)" }
                if let range = item.referenceRange, !range.isEmpty { line += " (ref: \(range))" }
                if item.isAbnormal { line += "  [abnormal]" }
                return line
            })
        } else {
            lines.append("No individual results recorded")
        }
        return ReportSection(
            title: "Blood Test — \(Self.reportDateFormatter.string(from: test.testDate))",
            lines: lines
        )
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