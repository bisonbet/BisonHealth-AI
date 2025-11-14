import Foundation
import SwiftUI
import UIKit

// MARK: - Health Data Manager
@MainActor
class HealthDataManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = HealthDataManager(
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared
    )
    
    // MARK: - Published Properties
    @Published var personalInfo: PersonalHealthInfo?
    @Published var bloodTests: [BloodTestResult] = []
    @Published var documents: [HealthDocument] = []
    @Published var imagingReports: [MedicalDocument] = []
    @Published var healthCheckups: [MedicalDocument] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager
    
    // MARK: - Initialization
    init(databaseManager: DatabaseManager, fileSystemManager: FileSystemManager) {
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager
        
        Task {
            await loadHealthData()
        }
    }
    
    // MARK: - Data Loading
    func loadHealthData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load personal info
            personalInfo = try await databaseManager.fetchPersonalHealthInfo()
            
            // Load blood test results (only from lab reports or manually entered)
            // Filter out any blood tests that came from non-lab-report documents
            let allBloodTests = try await databaseManager.fetchBloodTestResults()
            bloodTests = await filterValidBloodTests(allBloodTests)
            
            // Load documents
            documents = try await databaseManager.fetchDocuments()
            
            // Load imaging reports
            imagingReports = try await databaseManager.fetchMedicalDocuments(category: .imagingReport)
            imagingReports.sort { doc1, doc2 in
                let date1 = doc1.documentDate ?? doc1.importedAt
                let date2 = doc2.documentDate ?? doc2.importedAt
                return date1 > date2
            }
            
            // Load health checkups (doctors notes and consultations)
            let doctorsNotes = try await databaseManager.fetchMedicalDocuments(category: .doctorsNote)
            let consultations = try await databaseManager.fetchMedicalDocuments(category: .consultation)
            healthCheckups = doctorsNotes + consultations
            healthCheckups.sort { doc1, doc2 in
                let date1 = doc1.documentDate ?? doc1.importedAt
                let date2 = doc2.documentDate ?? doc2.importedAt
                return date1 > date2
            }
            
        } catch {
            errorMessage = "Failed to load health data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Personal Health Info Management
    func savePersonalInfo(_ info: PersonalHealthInfo) async throws {
        var updatedInfo = info
        updatedInfo.updatedAt = Date()
        
        // Note: Basic validation could be added here if needed
        
        try await databaseManager.save(updatedInfo)
        personalInfo = updatedInfo
    }
    
    func updatePersonalInfo(_ updates: (inout PersonalHealthInfo) -> Void) async throws {
        var info = personalInfo ?? PersonalHealthInfo()
        updates(&info)
        try await savePersonalInfo(info)
    }
    
    // MARK: - Blood Test Management
    func addBloodTest(_ result: BloodTestResult) async throws {
        var newResult = result
        newResult.updatedAt = Date()
        
        // Validate the blood test data
        guard newResult.isValid else {
            throw HealthDataError.validationFailed("Blood test data is incomplete or invalid")
        }
        
        // Check for potential duplicates before saving
        if let duplicate = await findDuplicateBloodTest(newResult) {
            print("⚠️ HealthDataManager: Potential duplicate blood test found:")
            print("   Existing: \(duplicate.testDate.formatted()) - \(duplicate.results.count) results")
            print("   New: \(newResult.testDate.formatted()) - \(newResult.results.count) results")
            
            // If it's from the same document, it's definitely a duplicate
            if let newDocId = newResult.metadata?["source_document_id"],
               let existingDocId = duplicate.metadata?["source_document_id"],
               newDocId == existingDocId {
                print("❌ HealthDataManager: Duplicate detected - same document ID, skipping save")
                throw HealthDataError.validationFailed("This blood test has already been imported from this document")
            }
            
            // If same date and very similar results, likely a duplicate
            let dateDifference = abs(newResult.testDate.timeIntervalSince(duplicate.testDate))
            if dateDifference < 86400 { // Within 24 hours
                let similarity = calculateBloodTestSimilarity(newResult, duplicate)
                if similarity > 0.8 {
                    print("❌ HealthDataManager: Duplicate detected - same date and \(Int(similarity * 100))% similar, skipping save")
                    throw HealthDataError.validationFailed("A very similar blood test already exists for this date")
                }
            }
        }
        
        try await databaseManager.save(newResult)
        
        // Update local array
        bloodTests.append(newResult)
        bloodTests.sort { $0.testDate > $1.testDate }
    }
    
    // MARK: - Duplicate Detection
    private func findDuplicateBloodTest(_ test: BloodTestResult) async -> BloodTestResult? {
        // Check against existing blood tests
        for existingTest in bloodTests {
            // Same document source
            if let testDocId = test.metadata?["source_document_id"],
               let existingDocId = existingTest.metadata?["source_document_id"],
               testDocId == existingDocId {
                return existingTest
            }
            
            // Same date and similar results
            let dateDifference = abs(test.testDate.timeIntervalSince(existingTest.testDate))
            if dateDifference < 86400 { // Within 24 hours
                let similarity = calculateBloodTestSimilarity(test, existingTest)
                if similarity > 0.8 {
                    return existingTest
                }
            }
        }
        
        return nil
    }
    
    private func calculateBloodTestSimilarity(_ test1: BloodTestResult, _ test2: BloodTestResult) -> Double {
        // Compare number of results
        let countDiff = abs(test1.results.count - test2.results.count)
        let maxCount = max(test1.results.count, test2.results.count)
        if maxCount == 0 { return 0.0 }
        
        let countSimilarity = 1.0 - (Double(countDiff) / Double(maxCount))
        
        // Compare test names (normalized)
        var matchingTests = 0
        let test1Names = Set(test1.results.map { normalizeTestNameForComparison($0.name) })
        let test2Names = Set(test2.results.map { normalizeTestNameForComparison($0.name) })
        
        for name1 in test1Names {
            if test2Names.contains(name1) {
                matchingTests += 1
            }
        }
        
        let nameSimilarity = maxCount > 0 ? Double(matchingTests) / Double(max(test1Names.count, test2Names.count)) : 0.0
        
        // Weighted average: 40% count similarity, 60% name similarity
        return (countSimilarity * 0.4) + (nameSimilarity * 0.6)
    }
    
    private func normalizeTestNameForComparison(_ name: String) -> String {
        return name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
    
    func updateBloodTest(_ result: BloodTestResult) async throws {
        var updatedResult = result
        updatedResult.updatedAt = Date()
        
        guard updatedResult.isValid else {
            throw HealthDataError.validationFailed("Blood test data is incomplete or invalid")
        }
        
        try await databaseManager.update(updatedResult)
        
        // Update local array
        if let index = bloodTests.firstIndex(where: { $0.id == result.id }) {
            bloodTests[index] = updatedResult
        }
    }
    
    func deleteBloodTest(_ result: BloodTestResult) async throws {
        try await databaseManager.delete(result)
        
        // Remove from local array
        bloodTests.removeAll { $0.id == result.id }
    }
    
    // MARK: - Document Management (Simplified - DocumentManager handles most operations)
    func refreshDocuments() async {
        do {
            documents = try await databaseManager.fetchDocuments()
        } catch {
            errorMessage = "Failed to refresh documents: \(error.localizedDescription)"
        }
    }
    
    func linkExtractedDataToDocument(_ documentId: UUID, extractedData: [AnyHealthData]) async throws {
        // Find document in our local array first
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            // Update document with extracted data
            documents[index].extractedData = extractedData
            documents[index].processingStatus = .completed
            documents[index].processedAt = Date()

            // Save updated document to database
            try await databaseManager.saveDocument(documents[index])
        } else {
            // Document not in our local array, try to load from database and update
            do {
                if var document = try await databaseManager.fetchDocument(id: documentId) {
                    document.extractedData = extractedData
                    document.processingStatus = ProcessingStatus.completed
                    document.processedAt = Date()
                    try await databaseManager.saveDocument(document)

                    // Add to our local array for future reference
                    documents.append(document)
                } else {
                    print("⚠️ HealthDataManager: Document \(documentId) not found in database, proceeding with health data extraction only")
                }
            } catch {
                print("⚠️ HealthDataManager: Error fetching document \(documentId) from database: \(error), proceeding with health data extraction only")
            }
        }

        // Process extracted health data and save to appropriate collections
        for anyHealthData in extractedData {
            switch anyHealthData.type {
            case .personalInfo:
                if let extractedPersonalInfo = try? anyHealthData.decode(as: PersonalHealthInfo.self) {
                    // Merge with existing personal info or create new
                    if var existingInfo = personalInfo {
                        existingInfo = mergePersonalInfo(existing: existingInfo, extracted: extractedPersonalInfo)
                        try await savePersonalInfo(existingInfo)
                    } else {
                        try await savePersonalInfo(extractedPersonalInfo)
                    }
                }
                
            case .bloodTest:
                if let extractedBloodTest = try? anyHealthData.decode(as: BloodTestResult.self) {
                    // Check if this blood test has pending duplicate review
                    // If so, don't save it yet - wait for user to review duplicates
                    if extractedBloodTest.metadata?["pending_review"] == "true" {
                        print("⏸️ HealthDataManager: Blood test has pending duplicate review - skipping save until user reviews")
                        // The blood test will be saved after user reviews duplicates in the UI
                        return
                    }
                    try await addBloodTest(extractedBloodTest)
                }
                
            case .imagingReport, .healthCheckup:
                // Placeholder for future implementation
                break
            }
        }
    }
    
    // MARK: - Data Export
    func exportHealthDataAsJSON() async throws -> URL {
        let exportData = HealthDataExport(
            personalInfo: personalInfo,
            bloodTests: bloodTests,
            documents: documents.map { DocumentExport(from: $0) },
            exportedAt: Date(),
            version: "1.0"
        )
        
        let jsonData = try JSONEncoder().encode(exportData)
        
        let fileName = "HealthData_Export_\(Date().formatted(date: .numeric, time: .omitted))"
        return try fileSystemManager.createExportFile(
            data: jsonData,
            fileName: fileName,
            fileType: .json
        )
    }
    
    func exportHealthDataAsPDF() async throws -> URL {
        // Create PDF report
        let pdfData = try await generatePDFReport()
        
        let fileName = "HealthData_Report_\(Date().formatted(date: .numeric, time: .omitted))"
        return try fileSystemManager.createExportFile(
            data: pdfData,
            fileName: fileName,
            fileType: .pdf
        )
    }
    
    // MARK: - Data Validation
    func validateHealthData<T: HealthDataProtocol>(_ data: T) -> ValidationResult {
        switch data.type {
        case .personalInfo:
            if let personalInfo = data as? PersonalHealthInfo {
                return validatePersonalInfo(personalInfo)
            }
        case .bloodTest:
            if let bloodTest = data as? BloodTestResult {
                return validateBloodTest(bloodTest)
            }
        case .imagingReport, .healthCheckup:
            // Placeholder for future validation
            return ValidationResult(isValid: true, errors: [])
        }
        
        return ValidationResult(isValid: false, errors: ["Unknown data type"])
    }
    
    private func validatePersonalInfo(_ info: PersonalHealthInfo) -> ValidationResult {
        var errors: [String] = []
        
        if info.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append("Name is required")
        }
        
        if let dateOfBirth = info.dateOfBirth, dateOfBirth > Date() {
            errors.append("Date of birth cannot be in the future")
        }
        
        if let height = info.height, height.value <= 0 {
            errors.append("Height must be greater than zero")
        }
        
        if let weight = info.weight, weight.value <= 0 {
            errors.append("Weight must be greater than zero")
        }
        
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    private func validateBloodTest(_ bloodTest: BloodTestResult) -> ValidationResult {
        var errors: [String] = []
        
        if bloodTest.testDate > Date() {
            errors.append("Test date cannot be in the future")
        }
        
        if bloodTest.results.isEmpty {
            errors.append("At least one test result is required")
        }
        
        for result in bloodTest.results {
            if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Test name is required for all results")
            }
            if result.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Test value is required for all results")
            }
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    // MARK: - Helper Methods
    private func filterValidBloodTests(_ tests: [BloodTestResult]) async -> [BloodTestResult] {
        // Filter out blood tests that came from non-lab-report documents
        var validTests: [BloodTestResult] = []
        
        for test in tests {
            // Check if this blood test came from a document
            // DocumentProcessor uses "source_document_id" key
            if let documentIdString = test.metadata?["source_document_id"] ?? test.metadata?["sourceDocumentId"],
               let documentId = UUID(uuidString: documentIdString) {
                // Check the document's category
                if let document = try? await databaseManager.fetchDocument(id: documentId) {
                    // Only include if document is a lab report or has no category (manually entered)
                    if document.documentCategory == .labReport || document.documentCategory == nil {
                        validTests.append(test)
                    }
                    // Skip if document is an imaging report or other non-lab category
                } else {
                    // Document not found, assume it's valid (might have been deleted)
                    validTests.append(test)
                }
            } else {
                // No source document ID, assume manually entered - include it
                validTests.append(test)
            }
        }
        
        return validTests
    }
    
    private func mergePersonalInfo(existing: PersonalHealthInfo, extracted: PersonalHealthInfo) -> PersonalHealthInfo {
        var merged = existing
        
        // Only update fields that are nil in existing but have values in extracted
        if merged.name == nil && extracted.name != nil {
            merged.name = extracted.name
        }
        if merged.dateOfBirth == nil && extracted.dateOfBirth != nil {
            merged.dateOfBirth = extracted.dateOfBirth
        }
        if merged.gender == nil && extracted.gender != nil {
            merged.gender = extracted.gender
        }
        if merged.height == nil && extracted.height != nil {
            merged.height = extracted.height
        }
        if merged.weight == nil && extracted.weight != nil {
            merged.weight = extracted.weight
        }
        if merged.bloodType == nil && extracted.bloodType != nil {
            merged.bloodType = extracted.bloodType
        }
        
        // Merge arrays (add new items that don't already exist)
        for allergy in extracted.allergies {
            if !merged.allergies.contains(allergy) {
                merged.allergies.append(allergy)
            }
        }
        
        for medication in extracted.medications {
            if !merged.medications.contains(where: { $0.name == medication.name }) {
                merged.medications.append(medication)
            }
        }
        
        // Note: Family history merging would need to be implemented based on FamilyMedicalHistory structure
        
        
        merged.updatedAt = Date()
        return merged
    }
    
    private func generatePDFReport() async throws -> Data {
        // This is a placeholder implementation
        // In a real app, you would use a PDF generation library
        let reportContent = """
        Health Data Report
        Generated: \(Date().formatted())
        
        Personal Information:
        \(personalInfo?.name ?? "Not provided")
        
        Blood Test Results: \(bloodTests.count) tests
        Documents: \(documents.count) documents
        """
        
        guard let data = reportContent.data(using: .utf8) else {
            throw HealthDataError.exportFailed("Failed to generate PDF report")
        }
        
        return data
    }
}

// MARK: - Supporting Types
struct ValidationResult {
    let isValid: Bool
    let errors: [String]
}

struct HealthDataExport: Codable {
    let personalInfo: PersonalHealthInfo?
    let bloodTests: [BloodTestResult]
    let documents: [DocumentExport]
    let exportedAt: Date
    let version: String
}

struct DocumentExport: Codable {
    let id: UUID
    let fileName: String
    let fileType: DocumentType
    let processingStatus: ProcessingStatus
    let importedAt: Date
    let processedAt: Date?
    let fileSize: Int64
    let tags: [String]
    let notes: String?
    let extractedDataSummary: String
    
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
        self.extractedDataSummary = document.extractedDataSummary
    }
}

// MARK: - Health Data Errors
enum HealthDataError: LocalizedError {
    case validationFailed(String)
    case invalidData(String)
    case notFound(String)
    case exportFailed(String)
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        }
    }
}