import Foundation
import SwiftUI
import UIKit

// MARK: - Health Data Manager
@MainActor
class HealthDataManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = HealthDataManager(
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared,
        automaticallyLoad: !AppTestRuntime.isRunningXCTest
            && AppStartupHealth.shared.blockingError == nil
    )
    
    // MARK: - Published Properties
    @Published var personalInfo: PersonalHealthInfo?
    @Published var bloodTests: [BloodTestResult] = []
    @Published var geneticTestDocuments: [MedicalDocument] = []
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
    private let retryManager = NetworkRetryManager.shared
    /// Removes its observers on release; see `NotificationObserverBag`. This type is not a
    /// singleton, so every instance that is created and released would otherwise leave two
    /// live observer blocks registered for the life of the process.
    private let documentChangeObservers = NotificationObserverBag()

    // MARK: - Constants
    private let manualEntryConflictInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Thread Safety
    private let syncLock = NSLock()
    
    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager,
        fileSystemManager: FileSystemManager,
        automaticallyLoad: Bool = true
    ) {
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager

        observeMedicalDocumentChanges()

        guard automaticallyLoad else { return }

        Task {
            await loadHealthData()
        }
    }

    private func observeMedicalDocumentChanges() {
        let changeObserver = NotificationCenter.default.addObserver(
            forName: .medicalDocumentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshDocumentCollections()
            }
        }

        let deleteObserver = NotificationCenter.default.addObserver(
            forName: .medicalDocumentDidDelete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let documentID = notification.object as? UUID
            Task { @MainActor [weak self, documentID] in
                guard let self else { return }
                if let documentID {
                    self.geneticTestDocuments.removeAll { $0.id == documentID }
                    self.imagingReports.removeAll { $0.id == documentID }
                    self.healthCheckups.removeAll { $0.id == documentID }
                }
                await self.refreshGeneticTestDocuments()
            }
        }

        documentChangeObservers.insert(changeObserver)
        documentChangeObservers.insert(deleteObserver)
    }

    // MARK: - Data Loading
    func loadHealthData() async {
        isLoading = true
        errorMessage = nil

        AppLog.shared.healthData("Starting health data load")

        // Use retry manager for loading health data
        let result = await retryManager.retryNetworkOperation {
            try await self.loadHealthDataInternal()
        } onRetry: { attempt, error, delay in
            AppLog.shared.healthData("Retrying health data load, attempt \(attempt), delay \(delay)s")
        }

        switch result {
        case .success:
            AppLog.shared.healthData("Successfully loaded health data")
            errorMessage = nil

        case .failure(let error, let attempts):
            let message = "Failed to load health data after \(attempts) attempts"
            errorMessage = message
            AppLog.shared.error(message, error: error, category: .healthData)

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
            AppLog.shared.healthData("Health data load cancelled")
            errorMessage = "Load cancelled"
        }

        isLoading = false
    }

    /// Internal method for loading health data (used by retry logic)
    private func loadHealthDataInternal() async throws {
        // If we detect decryption failures, run a recovery scan
        // This helps identify if data is recoverable or if keys have changed
        do {
            // Load personal info
            personalInfo = try await databaseManager.fetchPersonalHealthInfo()

            // Load blood test results (only from lab reports or manually entered)
            // Filter out any blood tests that came from non-lab-report documents
            let allBloodTests = try await databaseManager.fetchBloodTestResults()
            bloodTests = await filterValidBloodTests(allBloodTests)
        } catch {
            // Check if this is a decryption error
            if let dbError = error as? DatabaseError,
               case .decryptionFailed = dbError {
                // Decryption failed - run recovery scan to diagnose the issue
                AppLog.shared.healthData("Decryption failures detected. Running recovery scan...", level: .warning)
                do {
                    let scanResult = try await databaseManager.scanDatabaseForRecovery()
                    
                    if scanResult.corruptedRecords.count > 0 {
                        AppLog.shared.healthData("Found \(scanResult.corruptedRecords.count) corrupted record(s) that cannot be decrypted. This may indicate the encryption key has changed or data is corrupted.", level: .error)
                        AppLog.shared.healthData("Corrupted record count: \(scanResult.corruptedRecords.count)", level: .error)
                        
                        // If we have empty records, those are definitely lost
                        if scanResult.emptyRecords.count > 0 {
                            AppLog.shared.healthData("Found \(scanResult.emptyRecords.count) record(s) with empty encrypted data - these are unrecoverable", level: .error)
                        }
                    }
                } catch {
                    // If scan fails, log but continue
                    AppLog.shared.error("Failed to run recovery scan: \(error.localizedDescription)", error: error, category: .healthData)
                }
            }
            
            // Re-throw the original error
            throw error
        }

        try await loadDocumentCollections()
    }

    /// The three collections backed by `MedicalDocument` rows rather than `health_data`.
    private func loadDocumentCollections() async throws {
        // Genetic profiles are stored with their source MedicalDocument so
        // the report, provenance, and any pending review issues stay together.
        geneticTestDocuments = try await databaseManager.fetchMedicalDocuments(category: .geneticTest)
        geneticTestDocuments.sort { doc1, doc2 in
            let date1 = doc1.documentDate ?? doc1.importedAt
            let date2 = doc2.documentDate ?? doc2.importedAt
            return date1 > date2
        }

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
            AppLog.shared.healthData("Potential duplicate blood test found: existing has \(duplicate.results.count) results, new has \(newResult.results.count) results", level: .warning)
            
            // If it's from the same document, it's definitely a duplicate
            if let newDocId = newResult.metadata?["source_document_id"],
               let existingDocId = duplicate.metadata?["source_document_id"],
               newDocId == existingDocId {
                AppLog.shared.healthData("Duplicate detected - same document ID, skipping save", level: .error)
                throw HealthDataError.validationFailed("This blood test has already been imported from this document")
            }
            
            // If same date and very similar results, likely a duplicate
            let dateDifference = abs(newResult.testDate.timeIntervalSince(duplicate.testDate))
            if dateDifference < 86400 { // Within 24 hours
                let similarity = calculateBloodTestSimilarity(newResult, duplicate)
                if similarity > 0.8 {
                    AppLog.shared.healthData("Duplicate detected - same date and \(Int(similarity * 100))% similar, skipping save", level: .error)
                    throw HealthDataError.duplicateOfExistingReport(
                        "These results were not imported: an existing record for this date has the same readings."
                    )
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
    
    /// Pure comparison, used by the duplicate guard.
    /// (internal for regression tests; @testable access)
    func calculateBloodTestSimilarity(_ test1: BloodTestResult, _ test2: BloodTestResult) -> Double {
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

        // Compare the values, not just which tests were run.
        //
        // Name-and-count comparison alone called every repeat of a standard panel a
        // duplicate: a CMP contains the same analytes whether it was drawn today or five
        // years ago. Combined with the import-date fallback — an undated report takes the
        // date it was imported — a stack of historical labs imported in one sitting all
        // landed within the 24-hour window and only the first was saved. The rest were
        // rejected as duplicates of a test they merely resembled.
        var matchingValues = 0
        let test1Values = Dictionary(
            test1.results.map { (normalizeTestNameForComparison($0.name), $0.value.trimmingCharacters(in: .whitespaces)) },
            uniquingKeysWith: { first, _ in first }
        )
        let test2Values = Dictionary(
            test2.results.map { (normalizeTestNameForComparison($0.name), $0.value.trimmingCharacters(in: .whitespaces)) },
            uniquingKeysWith: { first, _ in first }
        )
        for (name, value) in test1Values where test2Values[name] == value {
            matchingValues += 1
        }
        let valueSimilarity = matchingTests > 0
            ? Double(matchingValues) / Double(matchingTests)
            : 0.0

        // Weighted: the values dominate, because identical readings are what actually
        // make two reports the same report.
        return (countSimilarity * 0.1) + (nameSimilarity * 0.3) + (valueSimilarity * 0.6)
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
    // Note: Document management moved to DocumentManager - this class only handles imaging reports and health checkups
    
    func linkExtractedDataToDocument(_ documentId: UUID, extractedData: [AnyHealthData]) async throws {
        // Note: Document updating is handled by DocumentManager
        // This method now only processes and saves the extracted health data

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
                        AppLog.shared.healthData("Blood test has pending review - skipping save until user reviews")
                        // The blood test will be saved after user reviews in the UI.
                        // `continue` (not `return`): later items extracted from
                        // this document must still be linked.
                        continue
                    }
                    do {
                        try await addBloodTest(extractedBloodTest)
                    } catch HealthDataError.validationFailed(let reason) {
                        // Reprocessing an already-imported document must be
                        // idempotent, and a duplicate lab report must not fail
                        // the whole document — the import guard's rejection is
                        // a skip, not a document failure.
                        AppLog.shared.healthData("Blood test import skipped: \(reason)", level: .warning)
                    } catch let error as HealthDataError {
                        // A *different* report rejected as a near-duplicate is data the
                        // user expected to keep — often values they just reviewed by hand.
                        // Skipping it silently is how a whole imported report disappears
                        // with no trace outside the log.
                        //
                        // Only this case is handled here. Other HealthDataError cases keep
                        // propagating exactly as before, so this does not quietly turn a
                        // failed import into a successful one.
                        guard case .duplicateOfExistingReport = error else { throw error }
                        AppLog.shared.healthData("Blood test import rejected: \(error.localizedDescription)", level: .error)
                        ErrorHandler.shared.handle(error, context: "Lab import", severity: .error)
                    }
                }

            case .geneticProfile:
                // The structured result is stored inside the source medical
                // document; refresh the Records collection so pending and
                // completed genetic tests are both visible.
                await refreshGeneticTestDocuments()

            case .imagingReport, .healthCheckup:
                break
            }
        }
    }

    /// Reload every document-backed collection after a document row changes. A change can
    /// touch any of them — the launch-time rename rewrites the file path of imaging reports and
    /// checkups too — and a stale cached copy is written back whole when the user edits it.
    func refreshDocumentCollections() async {
        do {
            try await loadDocumentCollections()
        } catch {
            AppLog.shared.healthData("Failed to refresh document-backed records: \(error.localizedDescription)", level: .warning)
        }
    }

    /// Refreshes the Records-facing genetic test collection after a document
    /// import or review decision.
    func refreshGeneticTestDocuments() async {
        do {
            geneticTestDocuments = try await databaseManager.fetchMedicalDocuments(category: .geneticTest)
            geneticTestDocuments.sort { doc1, doc2 in
                let date1 = doc1.documentDate ?? doc1.importedAt
                let date2 = doc2.documentDate ?? doc2.importedAt
                return date1 > date2
            }
        } catch {
            AppLog.shared.healthData("Failed to refresh genetic test records: \(error.localizedDescription)", level: .warning)
        }
    }
    
    // MARK: - Data Export
    func exportHealthDataAsJSON() async throws -> URL {
        let exportData = HealthDataExport(
            personalInfo: personalInfo,
            bloodTests: bloodTests,
            geneticTestDocuments: geneticTestDocuments,
            imagingReports: imagingReports,
            healthCheckups: healthCheckups,
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
        case .geneticProfile, .imagingReport, .healthCheckup:
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
                    // Only include if document is a lab report or uncategorized (backward compatibility)
                    if document.documentCategory == .labReport || document.documentCategory == .other {
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
    
    // MARK: - HealthKit Sync

    /// Sync health data from Apple Health
    func syncFromAppleHealth() async throws {
        guard healthKitManager.isHealthKitAvailable() else {
            let error = HealthDataError.processingFailed("HealthKit is not available on this device")
            lastSyncError = error
            throw error
        }

        AppLog.shared.healthData("Starting Apple Health sync")
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

            AppLog.shared.healthData("Apple Health sync completed successfully")
        } catch {
            lastSyncError = error
            AppLog.shared.error("Apple Health sync failed", error: error, category: .healthData)
            throw error
        }
    }

    /// Merge HealthKit data with existing personal info (prioritizing manual entries)
    private func mergeHealthKitData(_ syncedData: SyncedHealthData) async throws {
        // Use async-safe scoped locking to prevent race conditions during sync
        let info = syncLock.withLock { () -> PersonalHealthInfo in
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
                info.weight = Self.weightMeasurement(of: mostRecentWeight).converted(to: .kilograms)
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

            return info
        }

        // Save merged info (outside lock to avoid holding lock during async operation)
        try await savePersonalInfo(info)
    }

    /// A weight reading as a `Measurement`, read in the unit it was stored with. Every writer
    /// stores pounds today, but `info.weight` is kilograms and a reading in kg read as pounds
    /// would silently shrink it by more than half.
    nonisolated static func weightMeasurement(of reading: VitalReading) -> Measurement<UnitMass> {
        switch reading.unit.lowercased() {
        case "kg", "kgs", "kilogram", "kilograms":
            return Measurement(value: reading.value, unit: .kilograms)
        default:
            return Measurement(value: reading.value, unit: .pounds)
        }
    }

    /// Merge stored vital readings with a fresh HealthKit batch.
    ///
    /// For each HealthKit reading, the stored reading within `conflictInterval` of it decides:
    /// - a `.manual` one wins — the user's own entry, or their correction of Apple's;
    /// - any other is replaced by the fresh reading, so a re-sync refreshes what it brought in;
    /// - with neither, the reading is added.
    ///
    /// Stored readings the batch does not touch are kept. This used to keep only `.manual`
    /// ones and rebuild the rest from the batch, which deleted readings typed in with the entry
    /// screen's "Apple Health" source, and any history the batch no longer reached.
    /// The result is sorted most recent first and cut to `limit`.
    private func mergeVitalReadings(
        manual: [VitalReading],
        healthKit: [VitalReading],
        limit: Int
    ) -> [VitalReading] {
        Self.mergeVitalReadings(stored: manual, healthKit: healthKit, limit: limit, conflictInterval: manualEntryConflictInterval)
    }

    nonisolated static func mergeVitalReadings(
        stored: [VitalReading],
        healthKit: [VitalReading],
        limit: Int,
        conflictInterval: TimeInterval
    ) -> [VitalReading] {
        let merged = mergeKeepingManual(stored: stored, healthKit: healthKit, source: \.source) { existing, fresh in
            abs(existing.timestamp.timeIntervalSince(fresh.timestamp)) < conflictInterval
        }
        return Array(merged.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// The rule both merges share: a stored `.manual` entry beats the fresh one, any other
    /// matching stored entry is replaced by it, and an unmatched fresh entry is added.
    ///
    /// Only entries that were stored before this sync can be replaced. HealthKit returns
    /// samples newest first, so within a cluster of fresh readings the first one accepted is
    /// the newest; letting a later (older) sample from the same batch replace it left only
    /// the oldest reading of every cluster.
    nonisolated private static func mergeKeepingManual<Entry>(
        stored: [Entry],
        healthKit: [Entry],
        source: KeyPath<Entry, VitalSource>,
        matches: (Entry, Entry) -> Bool
    ) -> [Entry] {
        var merged = stored
        var fromThisBatch = Array(repeating: false, count: stored.count)
        for fresh in healthKit {
            let matching = merged.indices.filter { matches(merged[$0], fresh) }
            let keepExisting = matching.contains {
                fromThisBatch[$0] || merged[$0][keyPath: source] == .manual
            }
            if keepExisting {
                continue
            }
            if let first = matching.first {
                merged[first] = fresh
                fromThisBatch[first] = true
                for index in matching.dropFirst().reversed() {
                    merged.remove(at: index)
                    fromThisBatch.remove(at: index)
                }
            } else {
                merged.append(fresh)
                fromThisBatch.append(true)
            }
        }
        return merged
    }

    /// Merge stored sleep nights with a fresh HealthKit batch, one night per calendar day.
    ///
    /// Same rule as the vitals: a `.manual` night for that day wins; a night HealthKit
    /// brought in earlier is replaced, because its totals and stages are recomputed from the
    /// current samples each sync (stages can arrive after the first one); otherwise the fresh
    /// night is added. Stored nights the batch does not cover are kept.
    private func mergeSleepData(
        manual: [SleepData],
        healthKit: [SleepData],
        limit: Int
    ) -> [SleepData] {
        Self.mergeSleepData(stored: manual, healthKit: healthKit, limit: limit)
    }

    nonisolated static func mergeSleepData(
        stored: [SleepData],
        healthKit: [SleepData],
        limit: Int,
        calendar: Calendar = .current
    ) -> [SleepData] {
        let merged = mergeKeepingManual(stored: stored, healthKit: healthKit, source: \.source) { existing, fresh in
            calendar.isDate(existing.date, inSameDayAs: fresh.date)
        }
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
    let geneticTestDocuments: [MedicalDocument]
    let imagingReports: [MedicalDocument]
    let healthCheckups: [MedicalDocument]
    let exportedAt: Date
    let version: String
}

// MARK: - Health Data Errors
enum HealthDataError: LocalizedError {
    case validationFailed(String)
    /// A report was rejected because an existing record looks like the same report, but
    /// it did NOT come from the same document. Distinct from `validationFailed` because
    /// the two want opposite handling: re-importing the same document is idempotent and
    /// should pass silently, whereas discarding what the user believes is a different
    /// report must be visible — otherwise values they just reviewed vanish without a word.
    case duplicateOfExistingReport(String)
    case invalidData(String)
    case notFound(String)
    case exportFailed(String)
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .duplicateOfExistingReport(let message):
            return message
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
