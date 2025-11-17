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
    @Published var lastSyncError: Error?
    @Published var lastSyncStats: SyncStatistics?
    
    // MARK: - Dependencies
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager
    private let healthKitManager = HealthKitManager.shared
    private let errorHandler = ErrorHandler.shared
    private let logger = Logger.shared
    private let retryManager = NetworkRetryManager.shared

    // MARK: - Constants
    private let manualEntryConflictInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Thread Safety
    private let syncLock = NSLock()
    
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

        logger.info("Starting health data load")

        // Use retry manager for loading health data
        let result = await retryManager.retryNetworkOperation {
            try await self.loadHealthDataInternal()
        } onRetry: { attempt, error, delay in
            self.logger.info("Retrying health data load, attempt \(attempt), delay \(delay)s")
        }

        switch result {
        case .success:
            logger.info("Successfully loaded health data")
            errorMessage = nil

        case .failure(let error, let attempts):
            let message = "Failed to load health data after \(attempts) attempts"
            errorMessage = message
            logger.error(message, error: error)

            // Handle error with global error handler
            errorHandler.handle(
                error,
                context: "Load Health Data",
                retryAction: {
                    Task {
                        await self.loadHealthData()
                    }
                }
            )

        case .cancelled:
            logger.info("Health data load cancelled")
            errorMessage = "Load cancelled"
        }

        isLoading = false
    }

    /// Internal method for loading health data (used by retry logic)
    private func loadHealthDataInternal() async throws {
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

    // MARK: - HealthKit Sync

    /// Sync health data from Apple Health
    func syncFromAppleHealth() async throws {
        guard healthKitManager.isHealthKitAvailable() else {
            let error = HealthDataError.processingFailed("HealthKit is not available on this device")
            lastSyncError = error
            throw error
        }

        logger.info("Starting Apple Health sync")
        lastSyncError = nil

        do {
            // Request authorization if needed
            if !healthKitManager.isAuthorized {
                try await healthKitManager.requestAuthorization()
            }

            // Sync data from HealthKit
            let syncedData = try await healthKitManager.syncAllHealthData()

            // Merge with existing personal info
            try await mergeHealthKitData(syncedData)

            // Copy sync statistics from HealthKitManager
            lastSyncStats = healthKitManager.lastSyncStats

            logger.info("Apple Health sync completed successfully")
        } catch {
            lastSyncError = error
            logger.error("Apple Health sync failed", error: error)
            throw error
        }
    }

    /// Merge HealthKit data with existing personal info (prioritizing manual entries)
    private func mergeHealthKitData(_ syncedData: SyncedHealthData) async throws {
        // Use lock to prevent race conditions during sync
        syncLock.lock()
        defer { syncLock.unlock() }

        var info = personalInfo ?? PersonalHealthInfo()

        // Update characteristics only if not manually set
        if info.dateOfBirth == nil, let dob = syncedData.dateOfBirth {
            info.dateOfBirth = dob
        }

        if info.gender == nil, let gender = syncedData.biologicalSex {
            info.gender = gender
        }

        if info.bloodType == nil, let bloodType = syncedData.bloodType {
            info.bloodType = bloodType
        }

        if info.height == nil, let height = syncedData.height {
            info.height = height
        }

        // For weight, prefer the most recent manual entry, but merge HealthKit readings
        // Keep manual entries and add HealthKit entries, limiting to 7 most recent
        info.weightReadings = mergeVitalReadings(
            manual: info.weightReadings,
            healthKit: syncedData.weightReadings,
            limit: 7
        )

        // Update weight property with the most recent reading using Measurement API
        if let mostRecentWeight = info.weightReadings.first {
            // Use Foundation's Measurement API for accurate unit conversion
            let weightInPounds = Measurement(value: mostRecentWeight.value, unit: UnitMass.pounds)
            info.weight = weightInPounds.converted(to: .kilograms)
        }

        // Merge vitals (prioritize manual, then fill with HealthKit data)
        info.bloodPressureReadings = mergeVitalReadings(
            manual: info.bloodPressureReadings,
            healthKit: syncedData.bloodPressureReadings,
            limit: 7
        )

        info.heartRateReadings = mergeVitalReadings(
            manual: info.heartRateReadings,
            healthKit: syncedData.heartRateReadings,
            limit: 7
        )

        info.bodyTemperatureReadings = mergeVitalReadings(
            manual: info.bodyTemperatureReadings,
            healthKit: syncedData.bodyTemperatureReadings,
            limit: 7
        )

        info.oxygenSaturationReadings = mergeVitalReadings(
            manual: info.oxygenSaturationReadings,
            healthKit: syncedData.oxygenSaturationReadings,
            limit: 7
        )

        info.respiratoryRateReadings = mergeVitalReadings(
            manual: info.respiratoryRateReadings,
            healthKit: syncedData.respiratoryRateReadings,
            limit: 7
        )

        // Merge sleep data (prioritize manual, then fill with HealthKit data)
        info.sleepData = mergeSleepData(
            manual: info.sleepData,
            healthKit: syncedData.sleepData,
            limit: 7
        )

        // Save merged info
        try await savePersonalInfo(info)
    }

    /// Merge vital readings, prioritizing manual entries over HealthKit data
    ///
    /// This method implements a smart merging strategy to prevent data loss while avoiding duplicates:
    /// 1. Manual entries are always preserved (user's explicit input takes precedence)
    /// 2. HealthKit entries are added only if they don't conflict with manual entries
    /// 3. Conflict detection uses a 5-minute time window (manualEntryConflictInterval)
    /// 4. Results are sorted by timestamp (most recent first) and limited to the specified count
    ///
    /// Example:
    /// - Manual entry at 10:00 AM prevents HealthKit entries from 9:57:30 AM to 10:02:30 AM
    /// - This ensures user-corrected readings override automatic Apple Health data
    ///
    /// - Parameters:
    ///   - manual: Array of manually entered vital readings
    ///   - healthKit: Array of vital readings from Apple Health sync
    ///   - limit: Maximum number of readings to return (typically 7)
    /// - Returns: Merged array with most recent readings, prioritizing manual entries
    private func mergeVitalReadings(
        manual: [VitalReading],
        healthKit: [VitalReading],
        limit: Int
    ) -> [VitalReading] {
        // Start with manual entries (these are sacrosanct - never discard user input)
        var merged = manual.filter { $0.source == .manual }

        // Add HealthKit entries that don't conflict with manual entries (by date)
        for hkReading in healthKit {
            // Check if there's a manual entry within the conflict window (5 minutes)
            // This prevents duplicate entries when user manually entered what HealthKit also has
            let hasManualConflict = merged.contains { manualReading in
                abs(manualReading.timestamp.timeIntervalSince(hkReading.timestamp)) < manualEntryConflictInterval
            }

            if !hasManualConflict {
                merged.append(hkReading)
            }
        }

        // Sort by timestamp (most recent first) and limit to 'limit' readings
        // This ensures we keep the most relevant recent data while honoring the storage limit
        return Array(merged.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// Merge sleep data, prioritizing manual entries over HealthKit data
    ///
    /// Sleep data merging uses same-day conflict detection instead of time windows:
    /// 1. Manual sleep entries are preserved (user-entered sleep logs take precedence)
    /// 2. HealthKit sleep data is added only if no manual entry exists for that calendar day
    /// 3. Conflict detection checks if dates fall on the same calendar day
    /// 4. Results are sorted by date (most recent first) and limited to the specified count
    ///
    /// Rationale for same-day detection:
    /// - Sleep sessions typically span a single night (even if crossing midnight)
    /// - Users won't manually enter multiple sleep sessions for the same night
    /// - Time-window detection (like vitals) isn't appropriate for multi-hour events
    ///
    /// Example:
    /// - Manual entry for March 15, 2024 prevents HealthKit entries for same date
    /// - This ensures user corrections (e.g., adjusted wake time) override Apple Watch data
    ///
    /// - Parameters:
    ///   - manual: Array of manually entered sleep data
    ///   - healthKit: Array of sleep data from Apple Health sync
    ///   - limit: Maximum number of nights to return (typically 7)
    /// - Returns: Merged array with most recent sleep nights, prioritizing manual entries
    private func mergeSleepData(
        manual: [SleepData],
        healthKit: [SleepData],
        limit: Int
    ) -> [SleepData] {
        // Start with manual entries (preserve user's explicit sleep logs)
        var merged = manual.filter { $0.source == .manual }

        // Add HealthKit entries that don't conflict with manual entries (by calendar date)
        for hkSleep in healthKit {
            // Check if there's a manual entry for the same calendar day
            // Uses same-day check since sleep sessions represent a single night
            let hasManualConflict = merged.contains { manualSleep in
                Calendar.current.isDate(manualSleep.date, inSameDayAs: hkSleep.date)
            }

            if !hasManualConflict {
                merged.append(hkSleep)
            }
        }

        // Sort by date (most recent first) and limit to 'limit' nights
        return Array(merged.sorted { $0.date > $1.date }.prefix(limit))
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