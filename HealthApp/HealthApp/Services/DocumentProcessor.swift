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
        print("📥 DocumentProcessor: Adding document '\(document.fileName)' to queue with priority \(priority.displayName)")
        
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
        print("📥 DocumentProcessor: Document added to queue at position \(insertIndex), total queue size: \(processingQueue.count)")
        
        // Update document status to queued
        do {
            try await databaseManager.updateDocumentStatus(document.id, status: .queued)
            print("✅ DocumentProcessor: Document status updated to queued")
        } catch {
            print("❌ DocumentProcessor: Failed to update document status to queued: \(error)")
        }
        
        // Start processing if not already running
        if !isProcessing {
            print("🚀 DocumentProcessor: Starting processing queue")
            await startProcessing()
        } else {
            print("⏳ DocumentProcessor: Processing already running, document will be processed when current tasks complete")
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
        
        print("🔄 DocumentProcessor: Starting processing for document '\(currentItem.document.fileName)' (attempt \(currentItem.retryCount + 1)/\(maxRetryAttempts))")
        
        do {
            // Update status to processing
            print("📝 DocumentProcessor: Updating status to processing for document \(currentItem.document.id)")
            try await databaseManager.updateDocumentStatus(currentItem.document.id, status: .processing)
            print("✅ DocumentProcessor: Successfully updated status to processing")
            
            // Process the document
            print("🔧 DocumentProcessor: Starting document processing via Docling")
            let result = try await processDocument(currentItem.document)
            print("✅ DocumentProcessor: Document processing completed successfully")
            
            // Extract and save health data
            print("📊 DocumentProcessor: Extracting health data from processed result")
            let extractedHealthData = try await extractHealthData(from: result, document: currentItem.document)
            print("✅ DocumentProcessor: Health data extraction completed, found \(extractedHealthData.count) items")
            
            // Update document with extracted data
            print("💾 DocumentProcessor: Saving extracted data to database")
            try await databaseManager.updateDocumentExtractedData(
                currentItem.document.id,
                extractedData: extractedHealthData
            )
            print("✅ DocumentProcessor: Extracted data saved to database")
            
            // Link extracted data to health data manager
            print("🔗 DocumentProcessor: Linking extracted data to health data manager")
            try await healthDataManager.linkExtractedDataToDocument(
                currentItem.document.id,
                extractedData: extractedHealthData
            )
            print("✅ DocumentProcessor: Data linking completed")
            
            currentItem.completedAt = Date()
            currentItem.status = .completed
            lastProcessedDocument = currentItem.document
            
            print("🎉 DocumentProcessor: Document '\(currentItem.document.fileName)' processed successfully!")
            
            // Send success notification
            await sendProcessingSuccessNotification(for: currentItem.document)
            
        } catch {
            print("❌ DocumentProcessor: Processing failed for '\(currentItem.document.fileName)' with error: \(error)")
            print("❌ DocumentProcessor: Error details - \(error.localizedDescription)")
            
            // Log specific error types and check for known iOS permission issues
            if let urlError = error as? URLError {
                print("❌ DocumentProcessor: Network error - Code: \(urlError.code), Description: \(urlError.localizedDescription)")
            } else if error.localizedDescription.contains("database") || 
                      error.localizedDescription.contains("process may not map database") ||
                      error.localizedDescription.contains("permission was denied") {
                print("❌ DocumentProcessor: Database permission error detected!")
                print("❌ DocumentProcessor: This is likely the iOS LaunchServices database permission issue")
            } else if error.localizedDescription.contains("LaunchServices") ||
                      error.localizedDescription.contains("usermanagerd") ||
                      error.localizedDescription.contains("NSCocoaErrorDomain Code=4099") {
                print("❌ DocumentProcessor: LaunchServices system error detected!")
                print("❌ DocumentProcessor: iOS system service connection invalidated")
            } else if error.localizedDescription.contains("OSStatusErrorDomain Code=-54") {
                print("❌ DocumentProcessor: iOS database mapping error (Code -54) detected!")
                print("❌ DocumentProcessor: This is a known iOS system issue requiring device restart")
            } else {
                print("❌ DocumentProcessor: Unknown error type: \(type(of: error))")
            }
            
            currentItem.error = error
            currentItem.retryCount += 1
            
            if currentItem.retryCount < maxRetryAttempts {
                // Retry processing
                currentItem.status = .retrying
                let delaySeconds = pow(2.0, Double(currentItem.retryCount))
                print("🔄 DocumentProcessor: Retrying in \(delaySeconds) seconds (attempt \(currentItem.retryCount + 1)/\(maxRetryAttempts))")
                
                // Add back to queue with delay
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    await addToQueue(currentItem.document, priority: currentItem.priority)
                }
            } else {
                // Mark as failed
                print("💀 DocumentProcessor: Maximum retry attempts reached, marking as failed")
                currentItem.status = .failed
                
                do {
                    try await databaseManager.updateDocumentStatus(currentItem.document.id, status: .failed)
                    print("✅ DocumentProcessor: Status updated to failed")
                } catch {
                    print("❌ DocumentProcessor: Failed to update status to failed: \(error)")
                }
                
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
        print("📄 DocumentProcessor: Reading document data from \(document.filePath)")
        
        // Debug: Check file accessibility
        let fileExists = FileManager.default.fileExists(atPath: document.filePath.path)
        print("🔍 DocumentProcessor: File exists at path? \(fileExists)")
        
        if fileExists {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: document.filePath.path)
                let fileSize = attributes[.size] as? Int64 ?? -1
                print("🔍 DocumentProcessor: File system reports size: \(fileSize) bytes")
            } catch {
                print("❌ DocumentProcessor: Cannot get file attributes: \(error)")
            }
        }
        
        // Read document data using proper decryption
        let documentData = try fileSystemManager.retrieveDocument(from: document.filePath)
        print("✅ DocumentProcessor: Document data read successfully, size: \(documentData.count) bytes")
        
        // Debug: Check what's actually in the data
        let firstBytes = documentData.prefix(20)
        let hexString = firstBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("🔍 DocumentProcessor: First 20 bytes (hex): \(hexString)")
        
        let asciiString = String(data: firstBytes, encoding: .ascii) ?? "not ascii"
        print("🔍 DocumentProcessor: First 20 bytes (ascii): '\(asciiString)'")
        
        // Check if data is all zeros
        let isAllZeros = documentData.allSatisfy { $0 == 0 }
        print("🔍 DocumentProcessor: Is data all zeros? \(isAllZeros)")
        
        // Configure processing options based on document type
        let options = ProcessingOptions(
            extractText: true,
            extractStructuredData: true,
            extractImages: document.fileType.isImage,
            ocrEnabled: true,
            language: "en"
        )
        print("⚙️ DocumentProcessor: Processing options configured for \(document.fileType.displayName)")
        
        // Check Docling client connection
        print("🔌 DocumentProcessor: Checking Docling client connection...")
        print("🔌 DocumentProcessor: Docling client URL: \(doclingClient.baseURL)")
        print("🔌 DocumentProcessor: Settings Docling config: \(settingsManager.doclingConfig.hostname):\(settingsManager.doclingConfig.port)")
        
        if !doclingClient.isConnected {
            print("❌ DocumentProcessor: Docling client not connected!")
            print("❌ DocumentProcessor: Attempting to test connection...")
            
            do {
                let isConnected = try await doclingClient.testConnection()
                print("🔌 DocumentProcessor: Connection test result: \(isConnected)")
                if !isConnected {
                    print("❌ DocumentProcessor: Connection test failed")
                    throw DocumentProcessingError.doclingNotConnected
                }
            } catch {
                print("❌ DocumentProcessor: Connection test threw error: \(error)")
                throw DocumentProcessingError.doclingNotConnected
            }
        }
        print("✅ DocumentProcessor: Docling client is connected")
        
        // Process with Docling
        print("🔧 DocumentProcessor: Sending document to Docling for processing...")
        print("🔧 DocumentProcessor: About to send data - size: \(documentData.count) bytes")
        
        // Verify data integrity before sending
        if documentData.isEmpty {
            print("❌ DocumentProcessor: Document data is empty before sending to Docling!")
            throw DocumentProcessingError.fileReadError
        }
        
        // Check if it's a PDF and validate header
        if document.fileType == .pdf {
            let header = documentData.prefix(4)
            let headerString = String(data: header, encoding: .ascii) ?? ""
            print("🔧 DocumentProcessor: PDF header before sending: '\(headerString)'")
        }
        
        let result = try await doclingClient.processDocument(
            documentData,
            type: document.fileType,
            options: options
        )
        print("✅ DocumentProcessor: Docling processing completed successfully")
        
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

// MARK: - Document Processing Errors
enum DocumentProcessingError: LocalizedError {
    case doclingNotConnected
    case fileReadError
    case databasePermissionError
    case launchServicesError
    case processingTimeout
    case unsupportedFileType
    
    var errorDescription: String? {
        switch self {
        case .doclingNotConnected:
            return "Docling service is not connected. Please check your server connection."
        case .fileReadError:
            return "Failed to read document file. The file may be corrupted or inaccessible."
        case .databasePermissionError:
            return "Database permission error. Please restart the app or device."
        case .launchServicesError:
            return "iOS LaunchServices database error. Please restart the device."
        case .processingTimeout:
            return "Document processing timed out."
        case .unsupportedFileType:
            return "Unsupported file type for processing."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .doclingNotConnected:
            return "Check if the Docling server is running on localhost:5001"
        case .fileReadError:
            return "Try re-importing the document"
        case .databasePermissionError:
            return "Restart the app. If the issue persists, restart your device."
        case .launchServicesError:
            return "This is an iOS system issue. Restart your device to resolve."
        case .processingTimeout:
            return "Try processing a smaller document or check server performance"
        case .unsupportedFileType:
            return "Convert to PDF, DOCX, or supported image format"
        }
    }
}