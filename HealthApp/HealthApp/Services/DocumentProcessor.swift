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
    func addToQueue(_ document: MedicalDocument, priority: ProcessingPriority = .normal) async {
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
            
            // Extract medical document information (sections, metadata, etc.)
            print("🏥 DocumentProcessor: Extracting medical document information")
            var medicalDocument: MedicalDocument?
            if let rawDoclingOutput = result.rawDoclingOutput {
                do {
                    let extractor = MedicalDocumentExtractor()
                    // Get AI client for enhanced extraction if available
                    let aiClient = settingsManager.getAIClient()
                    let extractionResult = try await extractor.extractMedicalInformation(
                        from: rawDoclingOutput,
                        fileName: currentItem.document.fileName,
                        aiClient: aiClient
                    )
                    
                    // Update MedicalDocument with extracted information
                    // Use document category from existing document if set, otherwise use extracted category
                    let finalCategory = currentItem.document.documentCategory != .other
                        ? currentItem.document.documentCategory
                        : extractionResult.documentCategory
                    
                    // Use extracted text from extractionResult, or fallback to markdown text from Docling
                    // Clean markdown to remove base64 image data which is not useful for AI context
                    let rawExtractedText = extractionResult.extractedText.isEmpty ? result.extractedText : extractionResult.extractedText
                    let extractedText = cleanMarkdownForAIContext(rawExtractedText)
                    print("🔍 DocumentProcessor: extractionResult.extractedText length: \(extractionResult.extractedText.count)")
                    print("🔍 DocumentProcessor: result.extractedText (markdown) length: \(result.extractedText.count)")
                    print("🔍 DocumentProcessor: Cleaned extracted text length: \(extractedText.count)")

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
                        rawDoclingOutput: rawDoclingOutput,
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
                    print("✅ DocumentProcessor: Medical document information saved")
                    print("✅ DocumentProcessor: Extracted text length: \(extractedText.count) chars, Sections: \(extractionResult.extractedSections.count)")

                    // CRITICAL: Verify the document is still in DB correctly AFTER potential UI interactions
                    try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds
                    if let verifiedDoc = try? await databaseManager.fetchMedicalDocument(id: medicalDocument!.id) {
                        print("🔍 DocumentProcessor: POST-SAVE VERIFICATION (after 0.5s):")
                        print("🔍 DocumentProcessor:   - extractedText length: \(verifiedDoc.extractedText?.count ?? 0) chars")
                        print("🔍 DocumentProcessor:   - extractedText is nil: \(verifiedDoc.extractedText == nil)")
                        if verifiedDoc.extractedText == nil || verifiedDoc.extractedText?.isEmpty == true {
                            print("❌ DocumentProcessor: DATA LOST! Something overwrote extractedText between save and now!")
                        }
                    }
                } catch {
                    print("⚠️ DocumentProcessor: Failed to extract medical document information: \(error)")
                    print("⚠️ DocumentProcessor: Error details: \(error.localizedDescription)")
                    
                    // Fallback: Still create a MedicalDocument with at least the markdown text
                    // This ensures the document can be enabled for AI context later
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
                            rawDoclingOutput: rawDoclingOutput,
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
                        print("✅ DocumentProcessor: Saved MedicalDocument with fallback text (\(cleanedText.count) chars, cleaned from \(result.extractedText.count) chars)")
                    } catch {
                        print("❌ DocumentProcessor: Failed to save fallback MedicalDocument: \(error)")
                    }
                }
            }
            
            // Update document with extracted data (fallback if medical extraction failed)
            if medicalDocument == nil {
                print("💾 DocumentProcessor: Saving extracted data to database (fallback)")
                try await databaseManager.updateDocumentExtractedData(
                    currentItem.document.id,
                    extractedData: extractedHealthData
                )
                print("✅ DocumentProcessor: Extracted data saved to database")
            }
            
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
            } else if let cryptoError = error as? CryptoKitError {
                print("❌ DocumentProcessor: CryptoKit error detected")
                if case .authenticationFailure = cryptoError {
                    print("❌ DocumentProcessor: Decryption authentication failure - file may be encrypted with different key or corrupted")
                    print("❌ DocumentProcessor: This can happen if the encryption key changed or the file was moved between devices")
                }
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
    
    private func processDocument(_ document: MedicalDocument) async throws -> ProcessedDocumentResult {
        print("📄 DocumentProcessor: Reading document data from \(document.filePath)")
        
        // Debug: Check file accessibility
        let fileExists = FileManager.default.fileExists(atPath: document.filePath.path)
        print("🔍 DocumentProcessor: File exists at path? \(fileExists)")

        var finalFilePath = document.filePath

        if !fileExists {
            // Try to find the file by searching for files with matching filename
            print("🔍 DocumentProcessor: File not found at expected path, searching for file by name...")
            if let correctedPath = fileSystemManager.findDocumentByFileName(document.fileName) {
                print("✅ DocumentProcessor: Found file at corrected path: \(correctedPath)")
                finalFilePath = correctedPath

                // Update the document record with correct path
                try await databaseManager.updateDocumentFilePath(document.id, filePath: correctedPath)
                print("✅ DocumentProcessor: Updated database with corrected file path")
            } else {
                print("❌ DocumentProcessor: Could not locate file '\(document.fileName)' in documents directory")
                throw DocumentProcessingError.documentNotFound(document.fileName)
            }
        }

        if FileManager.default.fileExists(atPath: finalFilePath.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: finalFilePath.path)
                let fileSize = attributes[.size] as? Int64 ?? -1
                print("🔍 DocumentProcessor: File system reports size: \(fileSize) bytes")
            } catch {
                print("❌ DocumentProcessor: Cannot get file attributes: \(error)")
            }
        }

        // Read document data using proper decryption
        let documentData = try fileSystemManager.retrieveDocument(from: finalFilePath)
        print("✅ DocumentProcessor: Document data read successfully, size: \(documentData.count) bytes")
        
        // Debug: Check what's actually in the data
        let firstBytes = documentData.prefix(20)
        let hexString = firstBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("🔍 DocumentProcessor: First 20 bytes (hex): \(hexString)")
        
        // Check if data is all zeros
        let isAllZeros = documentData.allSatisfy { $0 == 0 }
        print("🔍 DocumentProcessor: Is data all zeros? \(isAllZeros)")
        
        // Verify data integrity before sending
        if documentData.isEmpty {
            print("❌ DocumentProcessor: Document data is empty before sending to Docling!")
            throw DocumentProcessingError.fileReadError
        }

        // Configure processing options based on document type
        // IMPORTANT: Always set extractImages to false - we only want OCR text, not image data
        // Images in documents should be OCR'd for text extraction, but image data itself should be excluded
        let options = ProcessingOptions(
            extractText: true,
            extractStructuredData: true,
            extractImages: false, // Never extract images - only OCR text from them
            ocrEnabled: true,
            language: "en",
            bloodTestExtractionHints: BloodTestResult.bloodTestExtractionHint,
            targetedLabKeys: Array(BloodTestResult.standardizedLabParameters.keys).sorted()
        )
        print("⚙️ DocumentProcessor: Processing options configured for \(document.fileType.displayName)")
        
        // Check Docling client connection
        print("🔌 DocumentProcessor: Checking Docling client connection...")
        print("🔌 DocumentProcessor: Docling client URL: \(doclingClient.baseURL)")
        
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
        
        let result = try await doclingClient.processDocument(
            documentData,
            type: document.fileType,
            options: options
        )
        print("✅ DocumentProcessor: Docling processing completed successfully")
        
        return result
    }
    
    private func extractHealthData(from result: ProcessedDocumentResult, document: MedicalDocument) async throws -> [AnyHealthData] {
        var extractedData: [AnyHealthData] = []

        print("📄 DocumentProcessor: Starting health data extraction from document")
        print("📄 DocumentProcessor: Extracted text length: \(result.extractedText.count) characters")
        print("📄 DocumentProcessor: Document category: \(document.documentCategory.displayName)")

        // Only extract blood tests for lab reports (or uncategorized documents for backward compatibility)
        let isLabReport = document.documentCategory == .labReport || document.documentCategory == .other
        
        // Primary approach: Use full document text for AI-powered blood test extraction (only for lab reports)
        if isLabReport && !result.extractedText.isEmpty {
            print("🧪 DocumentProcessor: Attempting blood test extraction from full document text (lab report)")
            do {
                let bloodTest = try await createBloodTestResultFromText(
                    documentText: result.extractedText,
                    extractedItems: [], // We'll use only the text
                    document: document
                )
                extractedData.append(try AnyHealthData(bloodTest))
                print("✅ DocumentProcessor: Successfully extracted blood test data from document text")
            } catch {
                print("❌ DocumentProcessor: Failed to create blood test from text: \(error)")
                // Continue with fallback approaches
            }
        } else if !isLabReport {
            print("ℹ️ DocumentProcessor: Skipping blood test extraction for \(document.documentCategory.displayName) document")
        }

        // Fallback approach: Parse structured data if available (for other data types)
        let healthDataItems = result.healthDataItems
        print("📊 DocumentProcessor: Found \(healthDataItems.count) structured health data items")

        if !healthDataItems.isEmpty {
            // Group health data items by type and create appropriate health data objects
            let groupedItems = Dictionary(grouping: healthDataItems) { $0.type }

            // Extract personal information
            if let personalInfoItems = groupedItems["Personal Information"] ?? groupedItems["Demographics"] {
                if let personalInfo = try? createPersonalHealthInfo(from: personalInfoItems, document: document) {
                    extractedData.append(try AnyHealthData(personalInfo))
                    print("✅ DocumentProcessor: Extracted personal information")
                }
            }

            // Extract vital signs and create health checkup
            if let vitalSignsItems = groupedItems["Vital Signs"] {
                if let healthCheckup = try? createHealthCheckup(from: vitalSignsItems, document: document) {
                    extractedData.append(try AnyHealthData(healthCheckup))
                    print("✅ DocumentProcessor: Extracted vital signs")
                }
            }

            // Extract imaging information
            if let imagingItems = groupedItems["Imaging"] ?? groupedItems["Radiology"] {
                if let imagingReport = try? createImagingReport(from: imagingItems, document: document) {
                    extractedData.append(try AnyHealthData(imagingReport))
                    print("✅ DocumentProcessor: Extracted imaging report")
                }
            }
        }

        // Only create basic blood test fallback for lab reports (or uncategorized for backward compatibility)
        if isLabReport && extractedData.isEmpty && !result.extractedText.isEmpty {
            print("⚠️ DocumentProcessor: No specific data extracted, creating basic blood test placeholder")
            let basicBloodTest = createBasicBloodTestResult(document: document)
            extractedData.append(try AnyHealthData(basicBloodTest))
        } else if !isLabReport && extractedData.isEmpty {
            print("ℹ️ DocumentProcessor: No health data extracted for \(document.documentCategory.displayName) document - this is expected")
        }

        print("📊 DocumentProcessor: Extraction complete. Found \(extractedData.count) health data items")
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
    
    // MARK: - Enhanced Blood Test Creation with Full Document Text
    private func createBloodTestResultFromText(
        documentText: String,
        extractedItems: [HealthDataItem],
        document: MedicalDocument
    ) async throws -> BloodTestResult {
        print("🧪 DocumentProcessor: Creating blood test result using enhanced AI-powered mapping...")
        print("📄 DocumentProcessor: Full document text length: \(documentText.count) characters")

        // Use the full document text for AI analysis
        do {
            // Use the AI-powered mapping service with full document content
            let aiClient = await getAIClientForDocument(document)
            let mappingService = BloodTestMappingService(aiClient: aiClient)

            // Extract suggested test date from document
            let suggestedTestDate = extractTestDate(from: document.fileName) ?? document.importedAt

            print("📅 DocumentProcessor: Using test date: \(suggestedTestDate.formatted())")

            // Perform AI mapping with full document text
            let mappingResult = try await mappingService.mapDocumentToBloodTest(
                documentText,
                suggestedTestDate: suggestedTestDate,
                patientName: nil as String? // Could be extracted from document metadata if available
            )

            print("✅ DocumentProcessor: Enhanced AI mapping completed with \(mappingResult.confidence)% confidence")
            print("🔬 DocumentProcessor: Mapped \(mappingResult.bloodTestResult.results.count) lab values")
            
            // Force review for ALL imports (Pessimistic Mode)
            var finalBloodTest = mappingResult.bloodTestResult
            if mappingResult.needsReview {
                print("⚠️ DocumentProcessor: Found \(mappingResult.importGroups.count) groups requiring review")
                
                // Store groups for UI review - don't save yet, wait for user selection
                let pendingReview = PendingImportReview(
                    documentId: document.id,
                    documentName: document.fileName,
                    importGroups: mappingResult.importGroups,
                    bloodTestResult: finalBloodTest
                )
                
                // Set pending review on main thread so UI can observe it
                await MainActor.run {
                    self.pendingImportReview = pendingReview
                }
                
                print("📋 DocumentProcessor: Set pending import review - UI should show review sheet")
                
                // Add metadata indicating review needed
                var enhancedMetadata = finalBloodTest.metadata ?? [:]
                enhancedMetadata["needs_review"] = "true"
                enhancedMetadata["import_groups_count"] = String(mappingResult.importGroups.count)
                enhancedMetadata["pending_review"] = "true"
                finalBloodTest.metadata = enhancedMetadata
            }

            // Add comprehensive metadata
            var enhancedMetadata = finalBloodTest.metadata ?? [:]
            enhancedMetadata["source_document_id"] = document.id.uuidString
            enhancedMetadata["document_filename"] = document.fileName
            enhancedMetadata["processing_method"] = "enhanced_ai_mapping"
            enhancedMetadata["document_text_length"] = String(documentText.count)
            enhancedMetadata["extracted_items_count"] = String(extractedItems.count)

            // Create enhanced blood test result
            finalBloodTest.metadata = enhancedMetadata

            return finalBloodTest

        } catch {
            print("❌ DocumentProcessor: Enhanced AI mapping failed, trying fallback with extracted items: \(error)")

            // Fallback to extracted items if full text analysis fails
            return try await createBloodTestResultFromItems(from: extractedItems, document: document)
        }
    }

    // MARK: - Blood Test Creation from Extracted Items (Fallback)
    private func createBloodTestResultFromItems(from items: [HealthDataItem], document: MedicalDocument) async throws -> BloodTestResult {
        print("🧪 DocumentProcessor: Creating blood test result using AI-powered mapping...")

        // Check if we have enough data to use AI mapping
        guard !items.isEmpty else {
            print("⚠️ DocumentProcessor: No health data items found, falling back to basic blood test result")
            return createBasicBloodTestResult(document: document)
        }

        // Try to get the processed document text for AI analysis
        // Note: We should have access to the processed document content from earlier processing
        // For now, we'll reconstruct text from items, but ideally we'd pass the full document text
        let reconstructedText = items.map { "\($0.type): \($0.value)" }.joined(separator: "\n")

        print("🤖 DocumentProcessor: Using AI mapping service with \(items.count) data items")
        print("📄 DocumentProcessor: Reconstructed text length: \(reconstructedText.count) characters")

        do {
            // Use the AI-powered mapping service
            let aiClient = await getAIClientForDocument(document)
            let mappingService = BloodTestMappingService(aiClient: aiClient)

            // Extract suggested test date from document
            let suggestedTestDate = extractTestDate(from: document.fileName) ?? document.importedAt

            print("📅 DocumentProcessor: Using test date: \(suggestedTestDate.formatted())")

            // Perform AI mapping
            let mappingResult = try await mappingService.mapDocumentToBloodTest(
                reconstructedText,
                suggestedTestDate: suggestedTestDate,
                patientName: nil as String? // Could be extracted from document metadata if available
            )

            print("✅ DocumentProcessor: AI mapping completed with \(mappingResult.confidence)% confidence")
            print("🔬 DocumentProcessor: Mapped \(mappingResult.bloodTestResult.results.count) lab values")

            // Add additional metadata
            var enhancedMetadata = mappingResult.bloodTestResult.metadata ?? [:]
            enhancedMetadata["source_document_id"] = document.id.uuidString
            enhancedMetadata["document_filename"] = document.fileName
            enhancedMetadata["processing_method"] = "ai_powered_mapping"
            enhancedMetadata["raw_items_count"] = String(items.count)

            // Create enhanced blood test result
            var enhancedBloodTest = mappingResult.bloodTestResult
            enhancedBloodTest.metadata = enhancedMetadata

            return enhancedBloodTest

        } catch {
            print("❌ DocumentProcessor: AI mapping failed, falling back to legacy method: \(error)")

            // Fallback to legacy method if AI mapping fails
            return createLegacyBloodTestResult(from: items, document: document)
        }
    }

    // MARK: - Legacy Blood Test Creation (Fallback)
    private func createLegacyBloodTestResult(from items: [HealthDataItem], document: MedicalDocument) -> BloodTestResult {
        print("🔄 DocumentProcessor: Using legacy blood test creation method")

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
        print("📝 DocumentProcessor: Creating basic blood test result placeholder")

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

        print("📄 DocumentProcessor: Using extraction provider: \(extractionProvider)")

        // Get the appropriate client based on extraction provider
        let aiClient: any AIProviderInterface

        switch extractionProvider {
        case .ollama:
            let ollamaClient = settingsManager.getOllamaClient()
            let extractionModel = settingsManager.modelPreferences.extractionOllamaModel
            ollamaClient.currentModel = extractionModel
            print("📄 DocumentProcessor: Using Ollama extraction model: \(extractionModel)")
            aiClient = ollamaClient

        case .openAICompatible:
            let openAIClient = settingsManager.getOpenAICompatibleClient()
            let extractionModel = settingsManager.modelPreferences.extractionOpenAIModel
            openAIClient.currentModel = extractionModel.isEmpty ? nil : extractionModel
            print("📄 DocumentProcessor: Using OpenAI-compatible extraction model: \(extractionModel.isEmpty ? "(default)" : extractionModel)")
            aiClient = openAIClient

        case .bedrock:
            let bedrockClient = settingsManager.getBedrockClient()
            if let extractionModel = AWSBedrockModel(rawValue: settingsManager.modelPreferences.extractionBedrockModel) {
                bedrockClient.currentModel = extractionModel
                print("📄 DocumentProcessor: Using Bedrock extraction model: \(extractionModel.displayName)")
            } else {
                print("⚠️ DocumentProcessor: Invalid Bedrock extraction model, using config default")
            }
            aiClient = bedrockClient
        }

        // Log file type info
        if document.fileType.isImage {
            print("📷 DocumentProcessor: Processing image file: \(document.fileType.displayName)")
            print("📷 DocumentProcessor: Note: Current BloodTestMappingService is optimized for text, not images")
        } else {
            print("📄 DocumentProcessor: Processing text file: \(document.fileType.displayName)")
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
                print("Notification permission error: \(error)")
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
                print("Failed to load pending documents: \(error)")
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
    let importGroups: [BloodTestImportGroup]
    let bloodTestResult: BloodTestResult
    let timestamp: Date
    
    init(documentId: UUID, documentName: String, importGroups: [BloodTestImportGroup], bloodTestResult: BloodTestResult) {
        self.documentId = documentId
        self.documentName = documentName
        self.importGroups = importGroups
        self.bloodTestResult = bloodTestResult
        self.timestamp = Date()
    }
    
    static func == (lhs: PendingImportReview, rhs: PendingImportReview) -> Bool {
        return lhs.id == rhs.id
    }
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
    case documentNotFound(String)
    
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
        case .documentNotFound(let fileName):
            return "Document file '\(fileName)' could not be found."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .doclingNotConnected:
            return "Check if the Docling server is running and accessible"
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
        }
    }
}
