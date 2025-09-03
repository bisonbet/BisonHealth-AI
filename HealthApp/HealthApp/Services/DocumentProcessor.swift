import Foundation
import Combine
import UserNotifications

// MARK: - Document Processor
@MainActor
class DocumentProcessor: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = DocumentProcessor(
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared,
        healthDataManager: HealthDataManager.shared
    )
    
    // MARK: - Published Properties
    @Published var processingQueue: [ProcessingQueueItem] = []
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var lastProcessedDocument: HealthDocument?
    @Published var processingErrors: [ProcessingError] = []
    
    // MARK: - Dependencies
    private let settingsManager = SettingsManager.shared
    
    // Get the current DoclingClient from SettingsManager (always uses latest config)
    private var doclingClient: DoclingClient {
        return settingsManager.getDoclingClient()
    }
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager
    private let healthDataManager: HealthDataManager
    
    // MARK: - Processing Configuration
    private let maxConcurrentProcessing = 3
    private let maxRetryAttempts = 3
    private let processingTimeout: TimeInterval = 300 // 5 minutes
    
    // MARK: - Private Properties
    private var processingTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        databaseManager: DatabaseManager,
        fileSystemManager: FileSystemManager,
        healthDataManager: HealthDataManager
    ) {
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager
        self.healthDataManager = healthDataManager
        
        setupNotifications()
        loadPendingDocuments()
    }
    
    // MARK: - Queue Management
    func addToQueue(_ document: HealthDocument, priority: ProcessingPriority = .normal) async {
        let queueItem = ProcessingQueueItem(
            document: document,
            priority: priority,
            addedAt: Date()
        )
        
        // Insert based on priority
        let insertIndex = processingQueue.firstIndex { item in
            item.priority.rawValue < priority.rawValue
        } ?? processingQueue.count
        
        processingQueue.insert(queueItem, at: insertIndex)
        
        // Update document status to queued
        try? await databaseManager.updateDocumentStatus(document.id, status: .queued)
        
        // Start processing if not already running
        if !isProcessing {
            await startProcessing()
        }
    }
    
    func removeFromQueue(_ documentId: UUID) async {
        // Cancel processing task if running
        if let task = processingTasks[documentId] {
            task.cancel()
            processingTasks.removeValue(forKey: documentId)
        }
        
        // Remove from queue
        processingQueue.removeAll { $0.document.id == documentId }
        
        // Update document status back to pending
        try? await databaseManager.updateDocumentStatus(documentId, status: .pending)
    }
    
    func processDocumentImmediately(_ document: HealthDocument) async throws -> ProcessedDocumentResult {
        // Process document synchronously without adding to queue
        return try await processDocument(document)
    }
    
    func processBatch(_ documents: [HealthDocument], priority: ProcessingPriority = .normal) async {
        for document in documents {
            await addToQueue(document, priority: priority)
        }
    }
    
    // MARK: - Processing Control
    func startProcessing() async {
        guard !isProcessing else { return }
        
        isProcessing = true
        processingProgress = 0.0
        
        while !processingQueue.isEmpty && processingTasks.count < maxConcurrentProcessing {
            guard let queueItem = processingQueue.first else { break }
            
            // Remove from queue
            processingQueue.removeFirst()
            
            // Start processing task
            let task = Task {
                await processQueueItem(queueItem)
            }
            
            processingTasks[queueItem.document.id] = task
        }
        
        // Wait for all tasks to complete
        await withTaskGroup(of: Void.self) { group in
            for (_, task) in processingTasks {
                group.addTask {
                    await task.value
                }
            }
        }
        
        processingTasks.removeAll()
        isProcessing = false
        processingProgress = 1.0
        
        // Send completion notification
        await sendProcessingCompletionNotification()
    }
    
    func pauseProcessing() {
        // Cancel all running tasks
        for (_, task) in processingTasks {
            task.cancel()
        }
        processingTasks.removeAll()
        isProcessing = false
    }
    
    func clearQueue() async {
        // Cancel all processing
        pauseProcessing()
        
        // Reset all queued documents to pending
        for queueItem in processingQueue {
            try? await databaseManager.updateDocumentStatus(queueItem.document.id, status: .pending)
        }
        
        processingQueue.removeAll()
    }
    
    // MARK: - Processing Implementation
    private func processQueueItem(_ queueItem: ProcessingQueueItem) async {
        var currentItem = queueItem
        currentItem.startedAt = Date()
        
        do {
            // Update status to processing
            try await databaseManager.updateDocumentStatus(currentItem.document.id, status: .processing)
            
            // Process the document
            let result = try await processDocument(currentItem.document)
            
            // Extract and save health data
            let extractedHealthData = try await extractHealthData(from: result, document: currentItem.document)
            
            // Update document with extracted data
            try await databaseManager.updateDocumentExtractedData(
                currentItem.document.id,
                extractedData: extractedHealthData
            )
            
            // Link extracted data to health data manager
            try await healthDataManager.linkExtractedDataToDocument(
                currentItem.document.id,
                extractedData: extractedHealthData
            )
            
            currentItem.completedAt = Date()
            currentItem.status = .completed
            lastProcessedDocument = currentItem.document
            
            // Send success notification
            await sendProcessingSuccessNotification(for: currentItem.document)
            
        } catch {
            currentItem.error = error
            currentItem.retryCount += 1
            
            if currentItem.retryCount < maxRetryAttempts {
                // Retry processing
                currentItem.status = .retrying
                
                // Add back to queue with delay
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(currentItem.retryCount)) * 1_000_000_000))
                    await addToQueue(currentItem.document, priority: currentItem.priority)
                }
            } else {
                // Mark as failed
                currentItem.status = .failed
                try? await databaseManager.updateDocumentStatus(currentItem.document.id, status: .failed)
                
                let processingError = ProcessingError(
                    documentId: currentItem.document.id,
                    documentName: currentItem.document.fileName,
                    error: error,
                    timestamp: Date()
                )
                processingErrors.append(processingError)
                
                // Send failure notification
                await sendProcessingFailureNotification(for: currentItem.document, error: error)
            }
        }
        
        // Remove from processing tasks
        processingTasks.removeValue(forKey: currentItem.document.id)
        
        // Update progress
        updateProcessingProgress()
    }
    
    private func processDocument(_ document: HealthDocument) async throws -> ProcessedDocumentResult {
        // Read document data
        let documentData = try Data(contentsOf: document.filePath)
        
        // Configure processing options based on document type
        let options = ProcessingOptions(
            extractText: true,
            extractStructuredData: true,
            extractImages: document.fileType.isImage,
            ocrEnabled: true,
            language: "en"
        )
        
        // Process with Docling
        let result = try await doclingClient.processDocument(
            documentData,
            type: document.fileType,
            options: options
        )
        
        return result
    }
    
    private func extractHealthData(from result: ProcessedDocumentResult, document: HealthDocument) async throws -> [AnyHealthData] {
        var extractedData: [AnyHealthData] = []
        
        // Parse structured data for health information
        let healthDataItems = result.healthDataItems
        
        // Group health data items by type and create appropriate health data objects
        let groupedItems = Dictionary(grouping: healthDataItems) { $0.type }
        
        // Extract personal information
        if let personalInfoItems = groupedItems["Personal Information"] ?? groupedItems["Demographics"] {
            if let personalInfo = try? createPersonalHealthInfo(from: personalInfoItems, document: document) {
                extractedData.append(try AnyHealthData(personalInfo))
            }
        }
        
        // Extract blood test results
        if let bloodTestItems = groupedItems["Blood Test"] ?? groupedItems["Lab Results"] {
            if let bloodTest = try? createBloodTestResult(from: bloodTestItems, document: document) {
                extractedData.append(try AnyHealthData(bloodTest))
            }
        }
        
        // Extract vital signs and create health checkup
        if let vitalSignsItems = groupedItems["Vital Signs"] {
            if let healthCheckup = try? createHealthCheckup(from: vitalSignsItems, document: document) {
                extractedData.append(try AnyHealthData(healthCheckup))
            }
        }
        
        // Extract imaging information
        if let imagingItems = groupedItems["Imaging"] ?? groupedItems["Radiology"] {
            if let imagingReport = try? createImagingReport(from: imagingItems, document: document) {
                extractedData.append(try AnyHealthData(imagingReport))
            }
        }
        
        return extractedData
    }
    
    // MARK: - Health Data Creation
    private func createPersonalHealthInfo(from items: [HealthDataItem], document: HealthDocument) throws -> PersonalHealthInfo {
        var personalInfo = PersonalHealthInfo()
        
        for item in items {
            switch item.type.lowercased() {
            case "name", "patient name", "full name":
                personalInfo.name = item.value
            case "date of birth", "dob", "birth date":
                personalInfo.dateOfBirth = parseDate(from: item.value)
            case "gender", "sex":
                personalInfo.gender = Gender.from(string: item.value)
            case "height":
                personalInfo.height = parseHeight(from: item.value)
            case "weight":
                personalInfo.weight = parseWeight(from: item.value)
            case "blood type":
                personalInfo.bloodType = BloodType.from(string: item.value)
            case "allergies", "allergy":
                personalInfo.allergies.append(item.value)
            case "medications", "medication":
                if let medication = parseMedication(from: item.value) {
                    personalInfo.medications.append(medication)
                }
            default:
                break
            }
        }
        
        // Add document reference to metadata
        personalInfo.metadata = ["source_document_id": document.id.uuidString]
        
        return personalInfo
    }
    
    private func createBloodTestResult(from items: [HealthDataItem], document: HealthDocument) throws -> BloodTestResult {
        var bloodTest = BloodTestResult(testDate: document.importedAt, results: [])
        
        // Try to extract test date from document name or content
        if let testDate = extractTestDate(from: document.fileName) {
            bloodTest.testDate = testDate
        }
        
        // Convert health data items to blood test items
        for item in items {
            let bloodTestItem = BloodTestItem(
                name: item.type,
                value: item.value,
                unit: extractUnit(from: item.value),
                referenceRange: nil, // Could be extracted if available
                isAbnormal: false // Could be determined based on reference ranges
            )
            bloodTest.results.append(bloodTestItem)
        }
        
        // Add document reference to metadata
        bloodTest.metadata = ["source_document_id": document.id.uuidString]
        
        return bloodTest
    }
    
    private func createHealthCheckup(from items: [HealthDataItem], document: HealthDocument) throws -> HealthCheckup {
        var checkup = HealthCheckup()
        checkup.checkupDate = document.importedAt
        
        var vitalSigns = VitalSigns()
        
        for item in items {
            switch item.type.lowercased() {
            case "blood pressure", "bp":
                if let (systolic, diastolic) = parseBloodPressure(from: item.value) {
                    vitalSigns.bloodPressureSystolic = systolic
                    vitalSigns.bloodPressureDiastolic = diastolic
                }
            case "heart rate", "pulse":
                vitalSigns.heartRate = Int(item.value)
            case "temperature":
                vitalSigns.temperature = parseTemperature(from: item.value)
            case "respiratory rate":
                vitalSigns.respiratoryRate = Int(item.value)
            case "oxygen saturation", "spo2":
                vitalSigns.oxygenSaturation = Double(item.value)
            default:
                break
            }
        }
        
        checkup.vitalSigns = vitalSigns
        checkup.metadata = ["source_document_id": document.id.uuidString]
        
        return checkup
    }
    
    private func createImagingReport(from items: [HealthDataItem], document: HealthDocument) throws -> ImagingReport {
        var report = ImagingReport()
        report.studyDate = document.importedAt
        
        for item in items {
            switch item.type.lowercased() {
            case "study type", "modality":
                report.studyType = ImagingStudyType.from(string: item.value)
            case "body part", "anatomy":
                report.bodyPart = item.value
            case "findings":
                report.findings = item.value
            case "impression", "conclusion":
                report.impression = item.value
            case "radiologist":
                report.radiologist = item.value
            case "facility", "hospital":
                report.facility = item.value
            default:
                break
            }
        }
        
        report.metadata = ["source_document_id": document.id.uuidString]
        
        return report
    }
    
    // MARK: - Parsing Helpers
    private func parseDate(from string: String) -> Date? {
        let formatters = [
            DateFormatter.iso8601,
            DateFormatter.shortDate,
            DateFormatter.mediumDate,
            DateFormatter.longDate
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return nil
    }
    
    private func parseHeight(from string: String) -> Measurement<UnitLength>? {
        // Parse height in various formats (cm, inches, feet/inches)
        let cleanString = string.replacingOccurrences(of: " ", with: "").lowercased()
        
        if cleanString.contains("cm") {
            let value = Double(cleanString.replacingOccurrences(of: "cm", with: ""))
            return value.map { Measurement(value: $0, unit: UnitLength.centimeters) }
        } else if cleanString.contains("in") || cleanString.contains("\"") {
            let value = Double(cleanString.replacingOccurrences(of: "in", with: "").replacingOccurrences(of: "\"", with: ""))
            return value.map { Measurement(value: $0, unit: UnitLength.inches) }
        }
        
        return nil
    }
    
    private func parseWeight(from string: String) -> Measurement<UnitMass>? {
        let cleanString = string.replacingOccurrences(of: " ", with: "").lowercased()
        
        if cleanString.contains("kg") {
            let value = Double(cleanString.replacingOccurrences(of: "kg", with: ""))
            return value.map { Measurement(value: $0, unit: UnitMass.kilograms) }
        } else if cleanString.contains("lb") || cleanString.contains("lbs") {
            let value = Double(cleanString.replacingOccurrences(of: "lb", with: "").replacingOccurrences(of: "lbs", with: ""))
            return value.map { Measurement(value: $0, unit: UnitMass.pounds) }
        }
        
        return nil
    }
    
    private func parseMedication(from string: String) -> Medication? {
        // Simple medication parsing - could be enhanced with dosage extraction
        return Medication(name: string, dosage: nil, frequency: nil)
    }
    
    private func parseBloodPressure(from string: String) -> (Int, Int)? {
        let components = string.components(separatedBy: "/")
        guard components.count == 2,
              let systolic = Int(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let diastolic = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return (systolic, diastolic)
    }
    
    private func parseTemperature(from string: String) -> Measurement<UnitTemperature>? {
        let cleanString = string.replacingOccurrences(of: " ", with: "").lowercased()
        
        if cleanString.contains("°f") || cleanString.contains("f") {
            let value = Double(cleanString.replacingOccurrences(of: "°f", with: "").replacingOccurrences(of: "f", with: ""))
            return value.map { Measurement(value: $0, unit: UnitTemperature.fahrenheit) }
        } else if cleanString.contains("°c") || cleanString.contains("c") {
            let value = Double(cleanString.replacingOccurrences(of: "°c", with: "").replacingOccurrences(of: "c", with: ""))
            return value.map { Measurement(value: $0, unit: UnitTemperature.celsius) }
        }
        
        return nil
    }
    
    private func extractUnit(from value: String) -> String? {
        let units = ["mg/dL", "mmol/L", "g/dL", "IU/L", "ng/mL", "pg/mL", "μg/dL", "mEq/L", "%"]
        
        for unit in units {
            if value.contains(unit) {
                return unit
            }
        }
        
        return nil
    }
    
    private func extractTestDate(from fileName: String) -> Date? {
        // Try to extract date from filename patterns
        let dateRegex = try? NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4}|\d{2}-\d{2}-\d{4}"#)
        let range = NSRange(location: 0, length: fileName.count)
        
        if let match = dateRegex?.firstMatch(in: fileName, range: range) {
            let dateString = String(fileName[Range(match.range, in: fileName)!])
            return parseDate(from: dateString)
        }
        
        return nil
    }
    
    // MARK: - Progress Tracking
    private func updateProcessingProgress() {
        let totalItems = processingQueue.count + processingTasks.count
        let completedItems = max(0, processingTasks.count)
        
        if totalItems > 0 {
            processingProgress = Double(completedItems) / Double(totalItems)
        } else {
            processingProgress = 1.0
        }
    }
    
    // MARK: - Notifications
    private func setupNotifications() {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func sendProcessingSuccessNotification(for document: HealthDocument) async {
        let content = UNMutableNotificationContent()
        content.title = "Document Processed"
        content.body = "Successfully processed \(document.fileName)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "processing_success_\(document.id)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    private func sendProcessingFailureNotification(for document: HealthDocument, error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = "Document Processing Failed"
        content.body = "Failed to process \(document.fileName): \(error.localizedDescription)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "processing_failure_\(document.id)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    private func sendProcessingCompletionNotification() async {
        guard !processingQueue.isEmpty else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Processing Complete"
        content.body = "All documents have been processed"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "processing_complete_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Persistence
    private func loadPendingDocuments() {
        Task {
            do {
                let pendingDocuments = try await databaseManager.fetchDocuments(with: .queued)
                for document in pendingDocuments {
                    await addToQueue(document)
                }
            } catch {
                print("Failed to load pending documents: \(error)")
            }
        }
    }
}

// MARK: - Supporting Types
struct ProcessingQueueItem: Identifiable {
    let id = UUID()
    let document: HealthDocument
    let priority: ProcessingPriority
    let addedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var status: ProcessingItemStatus = .queued
    var retryCount = 0
    var error: Error?
}

enum ProcessingPriority: Int, CaseIterable {
    case low = 1
    case normal = 2
    case high = 3
    case urgent = 4
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

enum ProcessingItemStatus {
    case queued
    case processing
    case completed
    case failed
    case retrying
}

struct ProcessingError: Identifiable {
    let id = UUID()
    let documentId: UUID
    let documentName: String
    let error: Error
    let timestamp: Date
}

// MARK: - Extensions for Parsing
extension Gender {
    static func from(string: String) -> Gender? {
        switch string.lowercased() {
        case "male", "m":
            return .male
        case "female", "f":
            return .female
        case "other", "o":
            return .other
        default:
            return nil
        }
    }
}

extension BloodType {
    static func from(string: String) -> BloodType? {
        switch string.uppercased().replacingOccurrences(of: " ", with: "") {
        case "A+", "APOSITIVE":
            return .aPositive
        case "A-", "ANEGATIVE":
            return .aNegative
        case "B+", "BPOSITIVE":
            return .bPositive
        case "B-", "BNEGATIVE":
            return .bNegative
        case "AB+", "ABPOSITIVE":
            return .abPositive
        case "AB-", "ABNEGATIVE":
            return .abNegative
        case "O+", "OPOSITIVE":
            return .oPositive
        case "O-", "ONEGATIVE":
            return .oNegative
        default:
            return nil
        }
    }
}

extension ImagingStudyType {
    static func from(string: String) -> ImagingStudyType? {
        switch string.lowercased() {
        case "x-ray", "xray", "radiograph":
            return .xray
        case "ct", "ct scan", "computed tomography":
            return .ct
        case "mri", "magnetic resonance imaging":
            return .mri
        case "ultrasound", "us", "sonogram":
            return .ultrasound
        case "mammography", "mammogram":
            return .mammography
        case "dexa", "bone density":
            return .dexa
        case "nuclear medicine", "nuclear":
            return .nuclear
        case "pet", "pet scan":
            return .pet
        default:
            return .other
        }
    }
}

// MARK: - Date Formatter Extensions
extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()
}