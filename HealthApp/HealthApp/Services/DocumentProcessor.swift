import Foundation
import Combine
import UserNotifications
import CryptoKit

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
    @Published var lastProcessedDocument: MedicalDocument?
    @Published var processingErrors: [ProcessingError] = []
    @Published var pendingImportReview: PendingImportReview?
    /// Set when an import completed silently (all values auto-accepted) — drives the confirmation banner
    @Published var lastAutoImportSummary: AutoImportSummary?

    /// Documents the user explicitly asked to re-extract with cloud vision,
    /// overriding the global toggle for one run
    var forceCloudVisionDocumentIds: Set<UUID> = []
    
    // MARK: - Dependencies
    private let settingsManager = SettingsManager.shared
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
    func addToQueue(_ document: MedicalDocument, priority: ProcessingPriority = .normal) async {
        AppLog.shared.documents("Adding document '\(document.fileName)' to queue with priority \(priority.displayName)")
        
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
        AppLog.shared.documents("Document added to queue at position \(insertIndex), total queue size: \(processingQueue.count)")
        
        // Update document status to queued
        do {
            try await databaseManager.updateDocumentStatus(document.id, status: .queued)
            AppLog.shared.documents("Document status updated to queued")
        } catch {
            AppLog.shared.error("Failed to update document status to queued", error: error, category: .documents)
        }
        
        // Start processing if not already running
        if !isProcessing {
            AppLog.shared.documents("Starting processing queue")
            await startProcessing()
        } else {
            AppLog.shared.documents("Processing already running, document will be processed when current tasks complete")
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
    
    func processDocumentImmediately(_ document: MedicalDocument) async throws -> ProcessedDocumentResult {
        // Process document synchronously without adding to queue
        return try await processDocument(document)
    }
    
    func processBatch(_ documents: [MedicalDocument], priority: ProcessingPriority = .normal) async {
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
        
        AppLog.shared.documents("Processing document '\(currentItem.document.fileName)' (attempt \(currentItem.retryCount + 1)/\(maxRetryAttempts))")

        do {
            // Update status to processing
            AppLog.shared.documents("Updating status to processing for document \(currentItem.document.id)", level: .debug)
            try await databaseManager.updateDocumentStatus(currentItem.document.id, status: .processing)
            AppLog.shared.documents("Status updated to processing", level: .debug)

            // Process the document
            AppLog.shared.documents("Starting document processing pipeline for '\(currentItem.document.fileName)'")
            let result = try await processDocument(currentItem.document)
            AppLog.shared.documents("Document text extraction completed -- \(result.extractedText.count) chars, confidence: \(String(format: "%.0f", result.confidence * 100))%")

            // Extract and save health data
            AppLog.shared.documents("Extracting health data from processed result")
            let extractedHealthData = try await extractHealthData(from: result, document: currentItem.document)
            AppLog.shared.documents("Health data extraction completed -- found \(extractedHealthData.count) items")

            // Extract medical document information (sections, metadata, etc.)
            AppLog.shared.documents("Starting medical document extraction (sections, metadata)")
            var medicalDocument: MedicalDocument?

            do {
                let extractor = MedicalDocumentExtractor()
                let aiClient = await getAIClientForDocument(currentItem.document)

                AppLog.shared.documents("Medical extraction: on-device plain text (\(result.extractedText.count) chars, confidence: \(String(format: "%.0f", result.confidence * 100))%)")
                let extractionResult = try await extractor.extractFromText(
                    text: result.extractedText,
                    fileName: currentItem.document.fileName,
                    aiClient: aiClient,
                    extractionConfidence: result.confidence
                )

                // Use document category from existing document if set, otherwise use extracted category
                let finalCategory = currentItem.document.documentCategory != .other
                    ? currentItem.document.documentCategory
                    : extractionResult.documentCategory

                // Clean text for AI context (removes base64 images, etc.)
                let rawExtractedText = extractionResult.extractedText.isEmpty ? result.extractedText : extractionResult.extractedText
                let extractedText = cleanMarkdownForAIContext(rawExtractedText)
                AppLog.shared.documents("Text lengths -- extraction: \(extractionResult.extractedText.count), raw: \(result.extractedText.count), cleaned: \(extractedText.count)", level: .debug)

                medicalDocument = MedicalDocument(
                    id: currentItem.document.id,
                    fileName: currentItem.document.fileName,
                    fileType: currentItem.document.fileType,
                    filePath: currentItem.document.filePath,
                    thumbnailPath: currentItem.document.thumbnailPath,
                    processingStatus: .completed,
                    documentDate: extractionResult.documentDate,
                    providerName: extractionResult.providerName,
                    providerType: extractionResult.providerType,
                    documentCategory: finalCategory,
                    extractedText: extractedText.isEmpty ? nil : extractedText,
                    rawDoclingOutput: nil,
                    extractedSections: extractionResult.extractedSections,
                    includeInAIContext: false, // User must explicitly enable
                    contextPriority: 3,
                    extractedHealthData: extractedHealthData,
                    importedAt: currentItem.document.importedAt,
                    processedAt: Date(),
                    lastEditedAt: nil,
                    fileSize: currentItem.document.fileSize,
                    tags: currentItem.document.tags,
                    notes: currentItem.document.notes
                )

                // Save as MedicalDocument
                try await databaseManager.saveMedicalDocument(medicalDocument!)
                AppLog.shared.documents("Medical document saved -- text: \(extractedText.count) chars, sections: \(extractionResult.extractedSections.count), category: \(finalCategory.rawValue)")

                // CRITICAL: Verify the document is still in DB correctly AFTER potential UI interactions
                try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds
                if let verifiedDoc = try? await databaseManager.fetchMedicalDocument(id: medicalDocument!.id) {
                    AppLog.shared.documents("Post-save verification: extractedText \(verifiedDoc.extractedText?.count ?? 0) chars, isNil: \(verifiedDoc.extractedText == nil)", level: .debug)
                    if verifiedDoc.extractedText == nil || verifiedDoc.extractedText?.isEmpty == true {
                        AppLog.shared.documents("DATA LOST: extractedText was overwritten between save and verification", level: .critical)
                    }
                }
            } catch {
                AppLog.shared.documents("Medical document extraction failed: \(error.localizedDescription)", level: .warning)

                // Fallback: Still create a MedicalDocument with at least the extracted text
                do {
                    let finalCategory = currentItem.document.documentCategory
                    let cleanedText = cleanMarkdownForAIContext(result.extractedText)
                    let fallbackDocument = MedicalDocument(
                        id: currentItem.document.id,
                        fileName: currentItem.document.fileName,
                        fileType: currentItem.document.fileType,
                        filePath: currentItem.document.filePath,
                        thumbnailPath: currentItem.document.thumbnailPath,
                        processingStatus: .completed,
                        documentDate: nil,
                        providerName: nil,
                        providerType: nil,
                        documentCategory: finalCategory,
                        extractedText: cleanedText.isEmpty ? nil : cleanedText,
                        rawDoclingOutput: nil,
                        extractedSections: [],
                        includeInAIContext: false,
                        contextPriority: 3,
                        extractedHealthData: extractedHealthData,
                        importedAt: currentItem.document.importedAt,
                        processedAt: Date(),
                        lastEditedAt: nil,
                        fileSize: currentItem.document.fileSize,
                        tags: currentItem.document.tags,
                        notes: currentItem.document.notes
                    )
                    try await databaseManager.saveMedicalDocument(fallbackDocument)
                    medicalDocument = fallbackDocument
                    AppLog.shared.documents("Saved MedicalDocument with fallback text (\(cleanedText.count) chars)")
                } catch {
                    AppLog.shared.error("Failed to save fallback MedicalDocument", error: error, category: .documents)
                }
            }
            
            // Update document with extracted data (fallback if medical extraction failed)
            if medicalDocument == nil {
                AppLog.shared.documents("Saving extracted data to database (fallback)")
                try await databaseManager.updateDocumentExtractedData(
                    currentItem.document.id,
                    extractedData: extractedHealthData
                )
                AppLog.shared.documents("Extracted data saved to database")
            }
            
            // Link extracted data to health data manager
            AppLog.shared.documents("Linking extracted data to health data manager")
            try await healthDataManager.linkExtractedDataToDocument(
                currentItem.document.id,
                extractedData: extractedHealthData
            )
            AppLog.shared.documents("Data linking completed")
            
            currentItem.completedAt = Date()
            currentItem.status = .completed
            lastProcessedDocument = currentItem.document
            
            AppLog.shared.documents("Document '\(currentItem.document.fileName)' processed successfully")
            
            // Send success notification
            await sendProcessingSuccessNotification(for: currentItem.document)
            
        } catch {
            AppLog.shared.error("Processing failed for '\(currentItem.document.fileName)': \(error.localizedDescription)", error: error, category: .documents)
            
            // Log specific error types and check for known iOS permission issues
            if let urlError = error as? URLError {
                AppLog.shared.documents("Network error - Code: \(urlError.code), Description: \(urlError.localizedDescription)", level: .error)
            } else if let cryptoError = error as? CryptoKitError {
                AppLog.shared.documents("CryptoKit error detected", level: .error)
                if case .authenticationFailure = cryptoError {
                    AppLog.shared.documents("Decryption authentication failure - file may be encrypted with different key or corrupted", level: .error)
                    AppLog.shared.documents("This can happen if the encryption key changed or the file was moved between devices", level: .error)
                }
            } else if error.localizedDescription.contains("database") ||
                      error.localizedDescription.contains("process may not map database") ||
                      error.localizedDescription.contains("permission was denied") {
                AppLog.shared.documents("Database permission error detected", level: .error)
                AppLog.shared.documents("This is likely the iOS LaunchServices database permission issue", level: .error)
            } else if error.localizedDescription.contains("LaunchServices") ||
                      error.localizedDescription.contains("usermanagerd") ||
                      error.localizedDescription.contains("NSCocoaErrorDomain Code=4099") {
                AppLog.shared.documents("LaunchServices system error detected", level: .error)
                AppLog.shared.documents("iOS system service connection invalidated", level: .error)
            } else if error.localizedDescription.contains("OSStatusErrorDomain Code=-54") {
                AppLog.shared.documents("iOS database mapping error (Code -54) detected", level: .error)
                AppLog.shared.documents("This is a known iOS system issue requiring device restart", level: .error)
            } else {
                AppLog.shared.documents("Unknown error type: \(type(of: error))", level: .error)
            }
            
            currentItem.error = error
            currentItem.retryCount += 1
            
            if currentItem.retryCount < maxRetryAttempts {
                // Retry processing
                currentItem.status = .retrying
                let delaySeconds = pow(2.0, Double(currentItem.retryCount))
                AppLog.shared.documents("Retrying in \(delaySeconds) seconds (attempt \(currentItem.retryCount + 1)/\(maxRetryAttempts))", level: .warning)
                
                // Add back to queue with delay
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    await addToQueue(currentItem.document, priority: currentItem.priority)
                }
            } else {
                // Mark as failed
                AppLog.shared.documents("Maximum retry attempts reached, marking as failed", level: .error)
                currentItem.status = .failed
                
                do {
                    try await databaseManager.updateDocumentStatus(currentItem.document.id, status: .failed)
                    AppLog.shared.documents("Status updated to failed")
                } catch {
                    AppLog.shared.error("Failed to update status to failed", error: error, category: .documents)
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
    
    private func processDocument(_ document: MedicalDocument) async throws -> ProcessedDocumentResult {
        // Resolve file path
        let finalFilePath = try await resolveDocumentFilePath(document)

        // Read document data using proper decryption
        let documentData = try fileSystemManager.retrieveDocument(from: finalFilePath)
        AppLog.shared.documents("Document data read: \(documentData.count) bytes from \(finalFilePath.lastPathComponent)")

        guard !documentData.isEmpty else {
            AppLog.shared.documents("Document data is empty for '\(document.fileName)'", level: .error)
            throw DocumentProcessingError.fileReadError
        }

        return try await processDocumentOnDevice(document: document, data: documentData, filePath: finalFilePath)
    }

    // MARK: - File Path Resolution
    private func resolveDocumentFilePath(_ document: MedicalDocument) async throws -> URL {
        var finalFilePath = document.filePath
        let fileExists = FileManager.default.fileExists(atPath: document.filePath.path)
        AppLog.shared.documents("File exists at path? \(fileExists)", level: .debug)

        if !fileExists {
            AppLog.shared.documents("File not found at expected path, searching for file by name...", level: .debug)
            if let correctedPath = fileSystemManager.findDocumentByFileName(document.fileName) {
                AppLog.shared.documents("Found file at corrected path: \(correctedPath)")
                finalFilePath = correctedPath
                try await databaseManager.updateDocumentFilePath(document.id, filePath: correctedPath)
                AppLog.shared.documents("Updated database with corrected file path")
            } else {
                AppLog.shared.documents("Could not locate file '\(document.fileName)' in documents directory", level: .error)
                throw DocumentProcessingError.documentNotFound(document.fileName)
            }
        }

        if FileManager.default.fileExists(atPath: finalFilePath.path) {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: finalFilePath.path),
               let fileSize = attributes[.size] as? Int64 {
                AppLog.shared.documents("File system reports size: \(fileSize) bytes", level: .debug)
            }
        }

        return finalFilePath
    }

    // MARK: - On-Device Processing (PDFKit + Vision OCR)
    /// Fully on-device document processing pipeline:
    /// 1. PDFKit direct text extraction (for digital PDFs with embedded text)
    /// 2. Vision framework OCR fallback (for scanned docs, images)
    /// 3. Spatial text reconstruction preserving table layout
    private func processDocumentOnDevice(document: MedicalDocument, data: Data, filePath: URL) async throws -> ProcessedDocumentResult {
        AppLog.shared.documents("ON-DEVICE processing started for '\(document.fileName)' (\(document.fileType.rawValue), \(data.count) bytes)")
        let startTime = Date()

        let nativeExtractor = NativeDocumentExtractor()

        // Extract text using best available on-device method
        let extractionResult: NativeDocumentExtractor.ExtractionResult
        do {
            extractionResult = try await nativeExtractor.extractText(from: data, fileType: document.fileType, fileName: document.fileName)
        } catch let error as NativeDocumentExtractor.NativeExtractionError {
            AppLog.shared.error("Native extraction failed for '\(document.fileName)'", error: error, category: .documents)
            throw DocumentProcessingError.nativeExtractionFailed(error.localizedDescription)
        }

        let processingTime = Date().timeIntervalSince(startTime)
        AppLog.shared.documents("On-device extraction complete in \(String(format: "%.2f", processingTime))s -- method: \(extractionResult.method.rawValue), pages: \(extractionResult.pageCount), confidence: \(String(format: "%.0f", extractionResult.confidence * 100))%, text: \(extractionResult.text.count) chars")

        guard extractionResult.isUsable else {
            AppLog.shared.documents("Extracted text too short (\(extractionResult.text.count) chars) for '\(document.fileName)' -- document may be image-only", level: .warning)
            throw DocumentProcessingError.nativeExtractionFailed("Extracted text too short — document may be image-only or corrupted")
        }

        // Build metadata about the extraction
        var metadata: [String: Any] = [
            "processing_mode": "on_device",
            "extraction_method": extractionResult.method.rawValue,
            "page_count": extractionResult.pageCount,
            "extraction_confidence": extractionResult.confidence,
            "text_length": extractionResult.text.count
        ]

        // Add per-page confidence if OCR was used
        if extractionResult.method != .pdfKit {
            let pageConfidences = extractionResult.perPageText.compactMap { page -> Double? in
                guard let observations = page.observations, !observations.isEmpty else { return nil }
                let avgConf = observations.reduce(0.0) { $0 + Double($1.confidence) } / Double(observations.count)
                return avgConf
            }
            if !pageConfidences.isEmpty {
                metadata["per_page_confidences"] = pageConfidences
            }
        }

        return ProcessedDocumentResult(
            extractedText: extractionResult.text,
            structuredData: [:],
            confidence: extractionResult.confidence,
            processingTime: processingTime,
            metadata: metadata,
            pages: extractionResult.perPageText
        )
    }


    private func extractHealthData(from result: ProcessedDocumentResult, document: MedicalDocument) async throws -> [AnyHealthData] {
        var extractedData: [AnyHealthData] = []

        AppLog.shared.documents("Starting health data extraction -- text: \(result.extractedText.count) chars, category: \(document.documentCategory.displayName)")

        // Parse structured data once so we can use it as fallback context for blood test extraction
        let healthDataItems = result.healthDataItems
        AppLog.shared.documents("Found \(healthDataItems.count) structured health data items")

        // Filter to lab-relevant items only to avoid importing non-lab data (vitals, demographics, etc.)
        // as blood test results if the AI mapping fails during fallback
        let nonLabTypes: Set<String> = ["Personal Information", "Demographics", "Vital Signs", "Imaging", "Radiology"]
        let labOnlyItems = healthDataItems.filter { !nonLabTypes.contains($0.type) }
        AppLog.shared.documents("Filtered to \(labOnlyItems.count) lab-specific items for blood test extraction")

        // Only extract blood tests for lab reports (or uncategorized documents for backward compatibility)
        let isLabReport = document.documentCategory == .labReport || document.documentCategory == .other

        // Primary approach: multi-pass extraction (deterministic parser + AI) for lab reports
        if isLabReport && !result.extractedText.isEmpty {
            AppLog.shared.documents("Attempting blood test extraction from full document text (lab report)")
            do {
                let bloodTest = try await createBloodTestResultFromText(
                    documentText: result.extractedText,
                    pages: result.pages,
                    extractedItems: labOnlyItems, // Lab-only items as safe fallback if AI text mapping fails
                    document: document
                )
                extractedData.append(try AnyHealthData(bloodTest))
                AppLog.shared.documents("Successfully extracted blood test data from document text")
            } catch {
                AppLog.shared.error("Failed to create blood test from text", error: error, category: .documents)
                // Continue with fallback approaches
            }
        } else if !isLabReport {
            AppLog.shared.documents("Skipping blood test extraction for \(document.documentCategory.displayName) document")
        }

        // Fallback approach: Parse structured data if available (for other data types)

        if !healthDataItems.isEmpty {
            // Group health data items by type and create appropriate health data objects
            let groupedItems = Dictionary(grouping: healthDataItems) { $0.type }

            // Extract personal information
            if let personalInfoItems = groupedItems["Personal Information"] ?? groupedItems["Demographics"] {
                if let personalInfo = try? createPersonalHealthInfo(from: personalInfoItems, document: document) {
                    extractedData.append(try AnyHealthData(personalInfo))
                    AppLog.shared.documents("Extracted personal information")
                }
            }

            // Extract vital signs and create health checkup
            if let vitalSignsItems = groupedItems["Vital Signs"] {
                if let healthCheckup = try? createHealthCheckup(from: vitalSignsItems, document: document) {
                    extractedData.append(try AnyHealthData(healthCheckup))
                    AppLog.shared.documents("Extracted vital signs")
                }
            }

            // Extract imaging information
            if let imagingItems = groupedItems["Imaging"] ?? groupedItems["Radiology"] {
                if let imagingReport = try? createImagingReport(from: imagingItems, document: document) {
                    extractedData.append(try AnyHealthData(imagingReport))
                    AppLog.shared.documents("Extracted imaging report")
                }
            }
        }

        // Only create basic blood test fallback for lab reports (or uncategorized for backward compatibility)
        if isLabReport && extractedData.isEmpty && !result.extractedText.isEmpty {
            AppLog.shared.documents("No specific data extracted, creating basic blood test placeholder", level: .warning)
            let basicBloodTest = createBasicBloodTestResult(document: document)
            extractedData.append(try AnyHealthData(basicBloodTest))
        } else if !isLabReport && extractedData.isEmpty {
            AppLog.shared.documents("No health data extracted for \(document.documentCategory.displayName) document - this is expected")
        }

        AppLog.shared.documents("Health data extraction complete -- found \(extractedData.count) items")
        return extractedData
    }
    
    // MARK: - Health Data Creation
    private func createPersonalHealthInfo(from items: [HealthDataItem], document: MedicalDocument) throws -> PersonalHealthInfo {
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
    
    // MARK: - Multi-Pass Blood Test Extraction (deterministic parser + LLM + reconciler)
    /// Orchestrates lab value extraction:
    /// 1. Deterministic registry-anchored parse of OCR geometry/tables/plain text
    /// 2. LLM extraction pass (best-effort — deterministic results survive AI failures)
    /// 3. Reconciliation: cross-pass agreement merges; the auto-accept rule partitions
    ///    results into silently-imported values and user-review items.
    private func createBloodTestResultFromText(
        documentText: String,
        pages: [NativeDocumentExtractor.PageText]?,
        extractedItems: [HealthDataItem],
        document: MedicalDocument
    ) async throws -> BloodTestResult {
        AppLog.shared.documents("Multi-pass blood test extraction — text: \(documentText.count) chars, pages: \(pages?.count ?? 0)")

        // Pass 1: Deterministic parser (registry-anchored, no LLM)
        let parser = LabReportParser()
        var candidates: [LabValueCandidate]
        if let pages, !pages.isEmpty {
            candidates = parser.parse(pages: pages)
        } else {
            candidates = parser.parse(plainText: documentText)
        }
        let deterministicCount = candidates.count
        AppLog.shared.documents("Deterministic pass found \(deterministicCount) candidates")

        // Pass 2: LLM extraction (best-effort)
        let aiClient = await getAIClientForDocument(document)
        var basicInfo: BasicTestInfo?
        var llmCount = 0
        do {
            let mappingService = BloodTestMappingService(aiClient: aiClient)
            let source: CandidateSource = aiClient is MLXOnDeviceClient ? .onDeviceLLM : .cloudText
            let llmResult = try await mappingService.extractCandidates(from: documentText, source: source)
            candidates.append(contentsOf: llmResult.candidates)
            basicInfo = llmResult.basicInfo
            llmCount = llmResult.candidates.count
            AppLog.shared.documents("LLM pass found \(llmCount) candidates")
        } catch {
            AppLog.shared.error("LLM extraction pass failed — continuing with deterministic results only", error: error, category: .documents)
        }

        // Pass 2b: Vision extraction (never fails the document).
        // On-device VLM runs automatically — nothing leaves the device.
        // Cloud vision requires the explicit opt-in toggle or a per-document override.
        let isOnDeviceVision = aiClient is MLXOnDeviceClient
        let visionAllowed = isOnDeviceVision
            || settingsManager.modelPreferences.cloudVisionExtractionEnabled
            || forceCloudVisionDocumentIds.contains(document.id)
        let cloudVisionExplicitlyRequested = !isOnDeviceVision && visionAllowed

        if visionAllowed,
           let visionClient = aiClient as? VisionDocumentExtractor,
           visionClient.supportsVisionExtraction {
            let source: CandidateSource = isOnDeviceVision ? .onDeviceVision : .cloudVision
            let visionResult = await runVisionPass(for: document, using: visionClient, source: source)
            candidates.append(contentsOf: visionResult.candidates)
            if basicInfo?.testDate == nil, let visionDate = visionResult.documentDate {
                basicInfo = BasicTestInfo(
                    testDate: visionDate,
                    laboratoryName: basicInfo?.laboratoryName ?? visionResult.laboratoryName,
                    orderingPhysician: basicInfo?.orderingPhysician ?? visionResult.orderingPhysician,
                    patientName: nil
                )
            }
        } else if cloudVisionExplicitlyRequested {
            AppLog.shared.documents("Cloud vision requested but the extraction provider/model does not support image input", level: .warning)
        }
        forceCloudVisionDocumentIds.remove(document.id)

        guard !candidates.isEmpty else {
            AppLog.shared.documents("No candidates from any pass, falling back to item-based mapping", level: .warning)
            return try await createBloodTestResultFromItems(from: extractedItems, document: document)
        }

        // Pass 3: Reconcile — merge cross-pass agreement, apply the auto-accept rule
        let reconciled = LabCandidateReconciler.reconcile(candidates)

        let testDate = basicInfo?.testDate
            ?? extractTestDate(from: document.fileName)
            ?? document.importedAt

        var metadata: [String: String] = [
            "source_document_id": document.id.uuidString,
            "document_filename": document.fileName,
            "processing_method": "multi_pass_reconciliation",
            "document_text_length": String(documentText.count),
            "deterministic_candidates": String(deterministicCount),
            "llm_candidates": String(llmCount),
            "auto_accepted_keys": reconciled.autoAccepted.map { $0.standardKey }.joined(separator: ",")
        ]

        var bloodTest = BloodTestResult(
            testDate: testDate,
            laboratoryName: basicInfo?.laboratoryName ?? extractLaboratoryName(from: document.fileName),
            orderingPhysician: basicInfo?.orderingPhysician,
            results: bloodTestItems(from: reconciled.autoAccepted),
            metadata: metadata
        )

        if reconciled.needsReview.isEmpty {
            // Everything auto-accepted — no pending_review flag, so
            // linkExtractedDataToDocument saves it directly. Publish the summary
            // so the UI can show an "Imported N values — View | Undo" banner.
            AppLog.shared.documents("All \(reconciled.autoAccepted.count) values auto-accepted — importing silently")
            lastAutoImportSummary = AutoImportSummary(
                documentId: document.id,
                documentName: document.fileName,
                bloodTestId: bloodTest.id,
                importedCount: bloodTest.results.count
            )
        } else {
            AppLog.shared.documents("\(reconciled.needsReview.count) groups need review (\(reconciled.autoAccepted.count) auto-accepted) — showing review sheet", level: .warning)

            metadata["pending_review"] = "true"
            metadata["needs_review"] = "true"
            metadata["import_groups_count"] = String(reconciled.needsReview.count)
            bloodTest.metadata = metadata

            pendingImportReview = PendingImportReview(
                documentId: document.id,
                documentName: document.fileName,
                importGroups: reconciled.needsReview,
                autoAcceptedGroups: reconciled.autoAccepted,
                bloodTestResult: bloodTest
            )
        }

        return bloodTest
    }

    // MARK: - Vision Pass
    /// Rasterize the document and run the vision-model extraction in batches —
    /// up to 8 pages per call for cloud models, one page at a time for the
    /// on-device VLM (memory-bounded). Any failure degrades to the other passes.
    private func runVisionPass(
        for document: MedicalDocument,
        using visionClient: VisionDocumentExtractor,
        source: CandidateSource
    ) async -> CloudVisionLabExtraction.Result {
        var merged = CloudVisionLabExtraction.Result(candidates: [], documentDate: nil, laboratoryName: nil, orderingPhysician: nil)

        do {
            let filePath = try await resolveDocumentFilePath(document)
            let data = try fileSystemManager.retrieveDocument(from: filePath)
            let extractor = NativeDocumentExtractor()
            var pageImages = try extractor.renderPageImages(from: data, fileType: document.fileType)
            guard !pageImages.isEmpty else {
                AppLog.shared.documents("Vision pass: no page images rendered", level: .warning)
                return merged
            }

            // The on-device VLM is slow per page — cap total pages
            let maxOnDevicePages = 6
            if source == .onDeviceVision && pageImages.count > maxOnDevicePages {
                AppLog.shared.documents("Vision pass: limiting on-device VLM to first \(maxOnDevicePages) of \(pageImages.count) pages", level: .warning)
                pageImages = Array(pageImages.prefix(maxOnDevicePages))
            }

            AppLog.shared.documents("Vision pass (\(source.rawValue)): sending \(pageImages.count) page(s) to vision model")

            let batchSize = source == .onDeviceVision ? 1 : 8
            for batchStart in stride(from: 0, to: pageImages.count, by: batchSize) {
                let batch = Array(pageImages[batchStart..<min(batchStart + batchSize, pageImages.count)])
                let batchPrompt = pageImages.count > batchSize
                    ? CloudVisionLabExtraction.schemaPrompt + "\n\nThese images are pages \(batch.first?.pageNumber ?? 0)–\(batch.last?.pageNumber ?? 0) of the document."
                    : CloudVisionLabExtraction.schemaPrompt

                do {
                    let response = try await visionClient.extractFromDocument(
                        pages: batch,
                        ocrText: "",
                        schemaPrompt: batchPrompt
                    )
                    let batchResult = CloudVisionLabExtraction.parse(response, source: source)
                    merged.candidates.append(contentsOf: batchResult.candidates)
                    if merged.documentDate == nil { merged.documentDate = batchResult.documentDate }
                    if merged.laboratoryName == nil { merged.laboratoryName = batchResult.laboratoryName }
                    if merged.orderingPhysician == nil { merged.orderingPhysician = batchResult.orderingPhysician }
                } catch {
                    AppLog.shared.error("Vision batch failed (pages \(batch.first?.pageNumber ?? 0)+) — continuing", error: error, category: .documents)
                }
            }

            AppLog.shared.documents("Vision pass found \(merged.candidates.count) candidates")
        } catch {
            AppLog.shared.error("Vision pass failed — degrading to remaining passes", error: error, category: .documents)
        }

        return merged
    }

    /// Build BloodTestItems from groups whose selected candidate is decided.
    private func bloodTestItems(from groups: [BloodTestImportGroup]) -> [BloodTestItem] {
        groups.compactMap { group in
            guard let selectedId = group.selectedCandidateId,
                  let candidate = group.candidates.first(where: { $0.id == selectedId }),
                  let parameter = BloodTestResult.standardizedLabParameters[group.standardKey] else {
                return nil
            }
            return BloodTestItem(
                name: parameter.name,
                value: candidate.value,
                unit: candidate.unit ?? parameter.unit,
                referenceRange: candidate.referenceRange ?? parameter.referenceRange,
                isAbnormal: candidate.isAbnormal,
                category: parameter.category,
                notes: candidate.originalTestName != parameter.name ? "Original name: \(candidate.originalTestName)" : nil,
                confidence: candidate.confidence
            )
        }
    }

    // MARK: - Blood Test Creation from Extracted Items (Fallback)
    private func createBloodTestResultFromItems(from items: [HealthDataItem], document: MedicalDocument) async throws -> BloodTestResult {
        AppLog.shared.documents("Creating blood test result using AI-powered mapping...")

        // Check if we have enough data to use AI mapping
        guard !items.isEmpty else {
            AppLog.shared.documents("No health data items found, falling back to basic blood test result", level: .warning)
            return createBasicBloodTestResult(document: document)
        }

        // Try to get the processed document text for AI analysis
        // Note: We should have access to the processed document content from earlier processing
        // For now, we'll reconstruct text from items, but ideally we'd pass the full document text
        let reconstructedText = items.map { "\($0.type): \($0.value)" }.joined(separator: "\n")

        AppLog.shared.documents("Using AI mapping service with \(items.count) data items")
        AppLog.shared.documents("Reconstructed text length: \(reconstructedText.count) characters")

        do {
            // Use the AI-powered mapping service
            let aiClient = await getAIClientForDocument(document)
            let mappingService = BloodTestMappingService(aiClient: aiClient)

            // Extract suggested test date from document
            let suggestedTestDate = extractTestDate(from: document.fileName) ?? document.importedAt

            AppLog.shared.documents("Using test date: \(suggestedTestDate.formatted())")

            // Perform AI mapping
            let mappingResult = try await mappingService.mapDocumentToBloodTest(
                reconstructedText,
                suggestedTestDate: suggestedTestDate,
                patientName: nil as String? // Could be extracted from document metadata if available
            )

            AppLog.shared.documents("AI mapping completed with \(mappingResult.confidence)% confidence")
            AppLog.shared.documents("Mapped \(mappingResult.bloodTestResult.results.count) lab values")

            // Force review for all imports (same behavior as full-text path)
            var finalBloodTest = mappingResult.bloodTestResult
            if mappingResult.needsReview {
                AppLog.shared.documents("Found \(mappingResult.importGroups.count) groups requiring review", level: .warning)

                let pendingReview = PendingImportReview(
                    documentId: document.id,
                    documentName: document.fileName,
                    importGroups: mappingResult.importGroups,
                    bloodTestResult: finalBloodTest
                )

                await MainActor.run {
                    self.pendingImportReview = pendingReview
                }

                AppLog.shared.documents("Set pending import review from item-based mapping - UI should show review sheet")

                var reviewMetadata = finalBloodTest.metadata ?? [:]
                reviewMetadata["needs_review"] = "true"
                reviewMetadata["import_groups_count"] = String(mappingResult.importGroups.count)
                reviewMetadata["pending_review"] = "true"
                finalBloodTest.metadata = reviewMetadata
            }

            // Add additional metadata
            var enhancedMetadata = finalBloodTest.metadata ?? [:]
            enhancedMetadata["source_document_id"] = document.id.uuidString
            enhancedMetadata["document_filename"] = document.fileName
            enhancedMetadata["processing_method"] = "ai_powered_mapping"
            enhancedMetadata["raw_items_count"] = String(items.count)

            // Create enhanced blood test result
            var enhancedBloodTest = finalBloodTest
            enhancedBloodTest.metadata = enhancedMetadata

            return enhancedBloodTest

        } catch {
            AppLog.shared.error("AI mapping failed, falling back to legacy method", error: error, category: .documents)

            // Fallback to legacy method if AI mapping fails
            return createLegacyBloodTestResult(from: items, document: document)
        }
    }

    // MARK: - Legacy Blood Test Creation (Fallback)
    private func createLegacyBloodTestResult(from items: [HealthDataItem], document: MedicalDocument) -> BloodTestResult {
        AppLog.shared.documents("Using legacy blood test creation method")

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
        var metadata = bloodTest.metadata ?? [:]
        metadata["source_document_id"] = document.id.uuidString
        metadata["processing_method"] = "legacy_extraction"
        bloodTest.metadata = metadata

        return bloodTest
    }

    // MARK: - Basic Blood Test Creation (No Data)
    private func createBasicBloodTestResult(document: MedicalDocument) -> BloodTestResult {
        AppLog.shared.documents("Creating basic blood test result placeholder")

        let testDate = extractTestDate(from: document.fileName) ?? document.importedAt

        // Create a placeholder result with at least one item to pass validation
        // This ensures isValid returns true (results not empty + all items have non-empty names)
        let placeholderResult = BloodTestItem(
            name: "Lab Report Processed",
            value: "Document imported successfully",
            unit: nil,
            referenceRange: nil,
            isAbnormal: false,
            category: .other,
            notes: "Full lab values require AI processing"
        )

        return BloodTestResult(
            testDate: testDate,
            laboratoryName: extractLaboratoryName(from: document.fileName),
            orderingPhysician: nil,
            results: [placeholderResult],
            metadata: [
                "source_document_id": document.id.uuidString,
                "processing_method": "basic_placeholder",
                "note": "Placeholder result - full lab values require AI processing",
                "document_filename": document.fileName
            ]
        )
    }

    private func extractLaboratoryName(from filename: String) -> String? {
        // Try to extract lab name from common filename patterns
        let lowercased = filename.lowercased()
        if lowercased.contains("labcorp") {
            return "LabCorp"
        } else if lowercased.contains("quest") {
            return "Quest Diagnostics"
        } else if lowercased.contains("mayo") {
            return "Mayo Clinic Laboratories"
        }
        return nil
    }

    private func createHealthCheckup(from items: [HealthDataItem], document: MedicalDocument) throws -> HealthCheckup {
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
    
    private func createImagingReport(from items: [HealthDataItem], document: MedicalDocument) throws -> ImagingReport {
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
    
    // MARK: - Markdown Cleaning Helper
    /// Removes base64-encoded images and other non-text content from markdown for AI context
    /// IMPORTANT: This ensures only text is used - no image data is included
    private func cleanMarkdownForAIContext(_ markdown: String) -> String {
        var cleaned = markdown
        
        // Remove base64 image references: ![Image](data:image/...)
        // This regex matches: ![optional text](data:image/type;base64,verylongstring)
        let imagePattern = #"!\[[^\]]*\]\(data:image/[^)]+\)"#
        cleaned = cleaned.replacingOccurrences(
            of: imagePattern,
            with: "",
            options: [.regularExpression]
        )
        
        // Remove standalone base64 data URLs (more comprehensive pattern)
        let dataUrlPattern = #"data:image/[^;]+;base64,[A-Za-z0-9+/=\s]+"#
        cleaned = cleaned.replacingOccurrences(
            of: dataUrlPattern,
            with: "[Image removed - OCR text only]",
            options: [.regularExpression]
        )
        
        // Remove any image file references or image tags
        let imageFilePattern = #"!\[[^\]]*\]\([^)]*\.(jpg|jpeg|png|gif|bmp|webp|heic)[^)]*\)"#
        cleaned = cleaned.replacingOccurrences(
            of: imageFilePattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove any HTML img tags that might have slipped through
        let htmlImagePattern = #"<img[^>]*>"#
        cleaned = cleaned.replacingOccurrences(
            of: htmlImagePattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Clean up multiple consecutive newlines
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: [.regularExpression]
        )
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
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
        return Medication(name: string)
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
    
    // MARK: - AI Provider Selection Logic
    private func getAIClientForDocument(_ document: MedicalDocument) async -> any AIProviderInterface {
        // Use the extraction provider settings (independent from chat)
        let extractionProvider = settingsManager.modelPreferences.extractionProvider

        AppLog.shared.documents("Using extraction provider: \(extractionProvider)")

        // Get the appropriate client based on extraction provider
        let aiClient: any AIProviderInterface

        switch extractionProvider {
        case .openAICompatible:
            let openAIClient = settingsManager.getOpenAICompatibleClient()
            let extractionModel = settingsManager.modelPreferences.extractionOpenAIModel
            openAIClient.currentModel = extractionModel.isEmpty ? nil : extractionModel
            AppLog.shared.documents("Using OpenAI-compatible extraction model: \(extractionModel.isEmpty ? "(default)" : extractionModel)")
            aiClient = openAIClient

        case .bedrock:
            let bedrockClient = settingsManager.getBedrockClient()
            if let extractionModel = AWSBedrockModel(rawValue: settingsManager.modelPreferences.extractionBedrockModel) {
                bedrockClient.currentModel = extractionModel
                AppLog.shared.documents("Using Bedrock extraction model: \(extractionModel.displayName)")
            } else {
                AppLog.shared.documents("Invalid Bedrock extraction model, using config default", level: .warning)
            }
            aiClient = bedrockClient

        case .onDeviceLLM:
            let mlxClient = settingsManager.getMLXOnDeviceClient()
            let selectedModel = MLXModelInfo.selectedModel
            AppLog.shared.documents("Using MLX on-device extraction model: \(selectedModel.displayName)")
            aiClient = mlxClient
        }

        // Log file type info
        if document.fileType.isImage {
            AppLog.shared.documents("Processing image file: \(document.fileType.displayName)")
            AppLog.shared.documents("Note: Current BloodTestMappingService is optimized for text, not images", level: .warning)
        } else {
            AppLog.shared.documents("Processing text file: \(document.fileType.displayName)")
        }

        return aiClient
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
                AppLog.shared.error("Notification permission error", error: error, category: .documents)
            }
        }
    }
    
    private func sendProcessingSuccessNotification(for document: MedicalDocument) async {
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
    
    private func sendProcessingFailureNotification(for document: MedicalDocument, error: Error) async {
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
                AppLog.shared.error("Failed to load pending documents", error: error, category: .documents)
            }
        }
    }
}

// MARK: - Supporting Types
struct ProcessingQueueItem: Identifiable {
    let id = UUID()
    let document: MedicalDocument
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

// MARK: - Pending Import Review
struct PendingImportReview: Identifiable, Equatable {
    let id = UUID()
    let documentId: UUID
    let documentName: String
    /// Groups the user must decide on (multiple distinct values or failed validation)
    let importGroups: [BloodTestImportGroup]
    /// Groups the reconciler auto-accepted — shown as an audit trail; the user can
    /// demote one back into review
    let autoAcceptedGroups: [BloodTestImportGroup]
    let bloodTestResult: BloodTestResult
    let timestamp: Date

    init(
        documentId: UUID,
        documentName: String,
        importGroups: [BloodTestImportGroup],
        autoAcceptedGroups: [BloodTestImportGroup] = [],
        bloodTestResult: BloodTestResult
    ) {
        self.documentId = documentId
        self.documentName = documentName
        self.importGroups = importGroups
        self.autoAcceptedGroups = autoAcceptedGroups
        self.bloodTestResult = bloodTestResult
        self.timestamp = Date()
    }

    static func == (lhs: PendingImportReview, rhs: PendingImportReview) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Auto Import Summary
/// Published after a fully silent import (every extracted value auto-accepted),
/// so the UI can confirm what happened and offer undo.
struct AutoImportSummary: Identifiable, Equatable {
    let id = UUID()
    let documentId: UUID
    let documentName: String
    let bloodTestId: UUID
    let importedCount: Int
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
    case fileReadError
    case databasePermissionError
    case launchServicesError
    case processingTimeout
    case unsupportedFileType
    case documentNotFound(String)
    case nativeExtractionFailed(String)

    var errorDescription: String? {
        switch self {
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
        case .documentNotFound(let fileName):
            return "Document file '\(fileName)' could not be found."
        case .nativeExtractionFailed(let detail):
            return "On-device document extraction failed: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
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
        case .documentNotFound:
            return "The file may have been moved or deleted. Try re-importing the document."
        case .nativeExtractionFailed:
            return "Re-scan the document with better lighting and focus, or import a higher-quality copy."
        }
    }
}
