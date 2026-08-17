import Foundation

// MARK: - Blood Test Mapping Service
@MainActor
class BloodTestMappingService: ObservableObject {

    // MARK: - Dependencies
    private let aiClient: any AIProviderInterface

    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var lastMappingResult: BloodTestMappingResult?
    @Published var mappingErrors: [BloodTestMappingError] = []

    // MARK: - Configuration
    private let maxRetryAttempts = 3
    private let mappingTimeout: TimeInterval = 600 // 10 minutes for large documents


    // MARK: - Initialization
    init(aiClient: any AIProviderInterface) {
        self.aiClient = aiClient
    }

    // MARK: - Main Mapping Function
    func mapDocumentToBloodTest(
        _ documentText: String,
        suggestedTestDate: Date? = nil,
        patientName: String? = nil
    ) async throws -> BloodTestMappingResult {

        AppLog.shared.healthData("Starting AI-powered blood test mapping...")
        AppLog.shared.healthData("Document text length: \(documentText.count) characters")

        isProcessing = true
        processingProgress = 0.0

        defer {
            isProcessing = false
            processingProgress = 1.0
        }

        do {
            // Phase 1: Extract basic document information (20% progress)
            AppLog.shared.healthData("Phase 1 - Extracting basic document information...")
            let basicInfo = try await extractBasicInformation(from: documentText)
            processingProgress = 0.2
            AppLog.shared.healthData("Basic info extracted - hasDate: \(basicInfo.testDate != nil), hasLab: \(basicInfo.laboratoryName != nil)")

            // Phase 2: Extract all lab values using AI (60% progress)
            AppLog.shared.healthData("Phase 2 - Extracting lab values using AI...")
            let extractedValues = try await extractLabValuesWithAI(from: documentText)
            processingProgress = 0.8
            AppLog.shared.healthData("Extracted \(extractedValues.count) lab values")

            // Phase 3: Map to standardized parameters (80% progress)
            AppLog.shared.healthData("Phase 3 - Mapping to standardized parameters...")
            let importGroups = await mapToStandardizedParameters(extractedValues)
            processingProgress = 0.9
            AppLog.shared.healthData("Created \(importGroups.count) import groups for review")

            // Phase 4: Create final BloodTestResult (100% progress)
            AppLog.shared.healthData("Phase 4 - Creating draft BloodTestResult...")
            let finalTestDate = basicInfo.testDate ?? suggestedTestDate ?? Date()
            
            // Create draft results from the selected candidates in import groups
            var draftResults: [StandardizedLabValue] = []
            for group in importGroups {
                if let selectedId = group.selectedCandidateId,
                   let candidate = group.candidates.first(where: { $0.id == selectedId }) {
                    
                    // Reconstruct StandardizedLabValue from candidate
                    // Note: We need to find the category again or store it in the candidate
                    // For now, look it up from the standard parameters
                    let category = BloodTestResult.standardizedLabParameters[group.standardKey]?.category ?? .other
                    
                    let standardizedValue = StandardizedLabValue(
                        standardKey: group.standardKey,
                        standardName: group.standardTestName,
                        value: candidate.value,
                        unit: candidate.unit,
                        referenceRange: candidate.referenceRange,
                        isAbnormal: candidate.isAbnormal,
                        category: category,
                        confidence: candidate.confidence,
                        originalTestName: candidate.originalTestName,
                        specimen: candidate.specimen,
                        collection: candidate.collection
                    )
                    draftResults.append(standardizedValue)
                }
            }
            
            AppLog.shared.healthData("Final test date selected: \(finalTestDate.formatted()) (AI: \(basicInfo.testDate?.formatted() ?? "none"), Suggested: \(suggestedTestDate?.formatted() ?? "none"))")
            
            let bloodTestResult = createBloodTestResult(
                from: draftResults,
                basicInfo: basicInfo,
                testDate: finalTestDate,
                patientName: patientName,
                model: "AI Provider"
            )

            let result = BloodTestMappingResult(
                bloodTestResult: bloodTestResult,
                extractedRawValues: extractedValues,
                importGroups: importGroups, // REPLACED duplicateGroups
                confidence: calculateOverallConfidence(draftResults),
                processingTime: Date().timeIntervalSince1970,
                aiModel: "AI Provider"
            )

            lastMappingResult = result
            processingProgress = 1.0

            AppLog.shared.healthData("Mapping completed successfully!")
            AppLog.shared.healthData("Final result - \(bloodTestResult.results.count) test items, confidence: \(result.confidence)%")

            return result

        } catch {
            AppLog.shared.healthData("Mapping failed with error: \(error)", level: .error)
            let mappingError = BloodTestMappingError(
                error: error,
                documentText: documentText.prefix(500).description,
                timestamp: Date()
            )
            mappingErrors.append(mappingError)
            throw error
        }
    }

    // MARK: - Phase 1: Extract Basic Information
    private func extractBasicInformation(from text: String) async throws -> BasicTestInfo {
        // Truncate text to prevent OOM on local devices
        // Basic info (header, patient, date) is usually in the first few pages
        let truncatedText = String(text.prefix(3000))
        
        let prompt = """
        Analyze this medical document and extract the following basic information. Return your response in a structured format:

        Document text (first section):
        \(truncatedText)

        Please extract:
        1. Test/Report Date (look for dates near "Date:", "Report Date:", "Collection Date:", etc.)
        2. Laboratory Name (look for lab company names)
        3. Ordering Physician (look for doctor names)
        4. Patient Name (if clearly visible and not redacted)

        Return your response in this exact format:
        TEST_DATE: YYYY-MM-DD or "unknown"
        LAB_NAME: Laboratory name or "unknown"
        PHYSICIAN: Doctor name or "unknown"
        PATIENT: Patient name or "unknown"
        """

        let aiResponse = try await aiClient.sendMessage(prompt, context: "")
        let response = aiResponse.content
        return parseBasicInfo(from: response)
    }

    private func parseBasicInfo(from response: String) -> BasicTestInfo {
        var testDate: Date?
        var labName: String?
        var physician: String?
        var patientName: String?

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("TEST_DATE:") {
                let dateString = String(trimmedLine.dropFirst("TEST_DATE:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if dateString != "unknown" {
                    testDate = parseDate(from: dateString)
                }
            } else if trimmedLine.hasPrefix("LAB_NAME:") {
                let name = String(trimmedLine.dropFirst("LAB_NAME:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if name != "unknown" {
                    labName = name
                }
            } else if trimmedLine.hasPrefix("PHYSICIAN:") {
                let name = String(trimmedLine.dropFirst("PHYSICIAN:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if name != "unknown" {
                    physician = name
                }
            } else if trimmedLine.hasPrefix("PATIENT:") {
                let name = String(trimmedLine.dropFirst("PATIENT:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if name != "unknown" {
                    patientName = name
                }
            }
        }

        return BasicTestInfo(
            testDate: testDate,
            laboratoryName: labName,
            orderingPhysician: physician,
            patientName: patientName
        )
    }

    // MARK: - Candidate Extraction (reconciler pipeline)
    /// Extract lab value candidates for the multi-pass reconciliation pipeline.
    /// Unlike `mapDocumentToBloodTest`, invalid values are NOT filtered out —
    /// they become review items per the auto-accept rule (single, valid, normal,
    /// strongly matched, and high-confidence → auto; everything else → review).
    func extractCandidates(
        from documentText: String,
        source: CandidateSource
    ) async throws -> (candidates: [LabValueCandidate], basicInfo: BasicTestInfo) {
        AppLog.shared.healthData("Extracting LLM lab candidates (source: \(source.rawValue), \(documentText.count) chars)")

        let basicInfo = try await extractBasicInformation(from: documentText)
        let extractedValues = try await extractLabValuesWithAI(from: documentText, filterInvalid: false)

        var candidates: [LabValueCandidate] = []
        for value in extractedValues {
            let testType: BloodTestResult.LabTestType = value.testType.uppercased() == "URINE" ? .urine : .blood
            guard let match = BloodTestResult.matchLabParameter(name: value.testName, testType: testType) else {
                AppLog.shared.healthData("LLM value '\(value.testName)' did not match any standardized parameter", level: .debug)
                continue
            }

            var validation = BloodTestValueValidator.validateValue(
                value.value,
                testName: match.parameter.name,
                referenceRange: value.referenceRange ?? match.parameter.referenceRange,
                standardParam: match.parameter
            )
            validation = BloodTestValueValidator.applyingUnitValidation(validation, unit: value.unit, for: match.parameter)

            let context = LabMeasurementContext.infer(
                testName: value.testName,
                parameter: match.parameter,
                unit: value.unit,
                reportedSpecimen: value.specimen,
                reportedCollection: value.collection
            )

            candidates.append(LabValueCandidate(
                standardKey: match.key,
                parameter: match.parameter,
                originalTestName: value.testName,
                value: value.value,
                unit: value.unit,
                referenceRange: value.referenceRange,
                abnormalFlag: value.abnormalFlag,
                testType: testType,
                source: source,
                pageNumber: nil,
                sourceSnippet: "AI extracted: \(value.testName) = \(value.value)\(value.unit.map { " \($0)" } ?? "")",
                confidence: value.confidence * match.matchConfidence,
                validation: validation,
                matchConfidence: match.matchConfidence,
                specimen: context.specimen,
                collection: context.collection
            ))
        }

        AppLog.shared.healthData("LLM pass produced \(candidates.count) candidates from \(extractedValues.count) extracted values")
        return (candidates, basicInfo)
    }

    // MARK: - Phase 2: Extract Lab Values with AI
    private func extractLabValuesWithAI(from text: String, filterInvalid: Bool = false) async throws -> [ExtractedLabValue] {
        // Check if document is too large and needs chunking
        // Reduced from 15000 to 2000 to prevent OOM on iOS devices running local LLMs
        let maxChunkSize = 2000
        let chunks = chunkDocument(text, maxChunkSize: maxChunkSize)

        AppLog.shared.healthData("Document split into \(chunks.count) chunks for processing")

        var allExtractedValues: [ExtractedLabValue] = []

        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            AppLog.shared.healthData("Processing chunk \(index + 1)/\(chunks.count) (\(chunk.count) characters)")

            let chunkValues = try await extractLabValuesFromChunk(chunk, chunkIndex: index, totalChunks: chunks.count)
            allExtractedValues.append(contentsOf: chunkValues)
        }

        // Structural filtering is opt-in for callers that explicitly need it.
        // The import path retains parseable abnormal values and unit warnings
        // so the review UI can make the final decision.
        let validValues: [ExtractedLabValue]
        if filterInvalid {
            validValues = BloodTestValueValidator.filterInvalidValues(
                allExtractedValues,
                standardParams: BloodTestResult.standardizedLabParameters
            )
            AppLog.shared.healthData("Filtered to \(validValues.count) valid values from \(allExtractedValues.count) extracted")
        } else {
            validValues = allExtractedValues
        }

        // Deduplicate values (same test name and value)
        let deduplicatedValues = deduplicateLabValues(validValues)
        AppLog.shared.healthData("Extracted \(allExtractedValues.count) total values, \(deduplicatedValues.count) after deduplication and validation")

        return deduplicatedValues
    }
    
    // MARK: - Document Chunking
    private func chunkDocument(_ text: String, maxChunkSize: Int) -> [String] {
        // If document is small enough, return as single chunk
        if text.count <= maxChunkSize {
            return [text]
        }
        
        var chunks: [String] = []
        let lines = text.components(separatedBy: .newlines)
        var currentChunk: [String] = []
        var currentSize = 0
        
        for line in lines {
            let lineSize = line.count + 1 // +1 for newline
            
            // If adding this line would exceed max size, start a new chunk
            if currentSize + lineSize > maxChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: "\n"))
                currentChunk = []
                currentSize = 0
            }
            
            currentChunk.append(line)
            currentSize += lineSize
        }
        
        // Add remaining chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: "\n"))
        }
        
        return chunks
    }
    
    // MARK: - Extract Lab Values from Chunk
    private func extractLabValuesFromChunk(_ chunk: String, chunkIndex: Int, totalChunks: Int) async throws -> [ExtractedLabValue] {
        let chunkContext = totalChunks > 1 ? " (Chunk \(chunkIndex + 1) of \(totalChunks))" : ""
        
        // Build comprehensive list of test names for the prompt
        // Note: Available for future use in prompt enhancement
        _ = BloodTestResult.standardizedLabParameters.values.map { $0.name }.sorted().prefix(100).joined(separator: ", ")
        
        let prompt = """
        You are a medical AI assistant. Extract ALL laboratory values from this lab report section\(chunkContext).

        Extract ALL lab values from this document (both blood and urine tests).
        Determine test type (BLOOD or URINE) from section headers or test names.
        Include both absolute values and percentages when present (e.g., "Neutrophils: 3.5 K/uL" AND "Neutrophils: 55%").

        Document text\(chunkContext):
        \(chunk)

        For each lab value extract:
        1. Test name (exactly as written, preserve abbreviations)
        2. Test type: "BLOOD" or "URINE"
        3. Value (number, or "Negative"/"Positive" for qualitative tests)
        4. Unit (mg/dL, %, /HPF, etc. - leave empty if none)
        5. Reference range (e.g., "70-100", "<200", "Negative")
        6. Abnormal flag (High, Low, H, L, *, ↑, ↓, or "Normal" if none)
        7. Specimen (SERUM, PLASMA, WHOLE_BLOOD, URINE, or "unknown")
        8. Collection (RANDOM, SPOT, 24_HOUR, TIMED, or "unknown")

        Format (pipe-delimited, one per line):
        TEST_NAME|TEST_TYPE|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG|SPECIMEN|COLLECTION

        Examples:
        Glucose|BLOOD|95|mg/dL|70-100|Normal|SERUM|unknown
        Total Cholesterol|BLOOD|220|mg/dL|<200|High|SERUM|unknown
        Urine Protein|URINE|Negative||Negative|Normal|URINE|RANDOM
        Neutrophils|BLOOD|55|%|40-60|Normal|WHOLE_BLOOD|unknown

        Rules:
        - Preserve test names exactly as written
        - Use "unknown" for missing data, "Normal" for missing abnormal flags
        - Extract ALL values including calculated values and ratios

        CRITICAL - AVOID DUPLICATES:
        - If the same test+value appears multiple times, extract it ONLY ONCE
        - If a test appears in multiple sections (e.g., "Glucose" in Chemistry and Summary), extract once
        - If the same test has different values, extract both (different time points)

        Return ONLY the extracted values in the specified format:
        """

        do {
            let aiResponse = try await aiClient.sendMessage(prompt, context: "")
            let response = aiResponse.content
            return parseExtractedLabValues(from: response)
        } catch {
            AppLog.shared.healthData("Failed to extract from chunk \(chunkIndex + 1): \(error)", level: .error)
            // If chunk processing fails, return empty array rather than failing entirely
            // This allows other chunks to still be processed
            return []
        }
    }
    
    // MARK: - Deduplicate Lab Values
    private func deduplicateLabValues(_ values: [ExtractedLabValue]) -> [ExtractedLabValue] {
        var seen: Set<String> = []
        var deduplicated: [ExtractedLabValue] = []
        
        for value in values {
            // Normalize identity without merging different units, specimens,
            // collections, or test types.
            let testType = value.testType.uppercased()
            let normalizedName = normalizeTestName(value.testName)
            let normalizedValue = BloodTestValueValidator.normalizedValue(value.value)
            let normalizedUnit = value.unit.map { BloodTestValueValidator.canonicalUnit($0) } ?? ""
            let normalizedSpecimen = value.specimen?.lowercased() ?? ""
            let normalizedCollection = value.collection?.lowercased() ?? ""

            let key = "\(testType)|\(normalizedName)|\(normalizedValue)|\(normalizedUnit)|\(normalizedSpecimen)|\(normalizedCollection)"
            
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(value)
            } else {
                AppLog.shared.healthData("Skipping duplicate lab value", level: .debug)
            }
        }
        
        return deduplicated
    }
    
    // MARK: - Normalize Test Name for Deduplication
    private func normalizeTestName(_ name: String) -> String {
        var normalized = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common prefixes/suffixes that don't change the test identity
        let prefixes = ["test:", "lab:", "laboratory:", "result:"]
        for prefix in prefixes {
            if normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Remove common suffixes
        let suffixes = [" (calculated)", " (calc)", " - calculated", " - calc"]
        for suffix in suffixes {
            if normalized.hasSuffix(suffix.lowercased()) {
                normalized = String(normalized.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Normalize whitespace
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return normalized
    }
    
    private func parseExtractedLabValues(from response: String) -> [ExtractedLabValue] {
        var values: [ExtractedLabValue] = []

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let components = trimmedLine.components(separatedBy: "|")
            
            // Support both old format (5 components) and new format (6 components with TEST_TYPE)
            let testName: String
            let testType: String?
            let valueString: String
            let unit: String
            let referenceRange: String
            let abnormalFlag: String
            let reportedSpecimen: String?
            let reportedCollection: String?
            
            if components.count >= 6 {
                // New format: TEST_NAME|TEST_TYPE|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG
                testName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                testType = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                valueString = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                unit = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                referenceRange = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
                abnormalFlag = components[5].trimmingCharacters(in: .whitespacesAndNewlines)
                reportedSpecimen = components.count >= 7 ? components[6].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                reportedCollection = components.count >= 8 ? components[7].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            } else if components.count >= 5 {
                // Old format: TEST_NAME|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG (backward compatibility)
                testName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                testType = nil // Will be inferred from test name
                valueString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                unit = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                referenceRange = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                abnormalFlag = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
                reportedSpecimen = nil
                reportedCollection = nil
            } else {
                continue
            }

            guard !testName.isEmpty && !valueString.isEmpty else { continue }
            
            // Infer test type from name if not provided
            let inferredTestType = testType ?? inferTestType(from: testName)

            let normalizedFlag = abnormalFlag.trimmingCharacters(in: .whitespacesAndNewlines)
            let extractedValue = ExtractedLabValue(
                testName: testName,
                value: valueString,
                unit: unit == "unknown" || unit.isEmpty ? nil : unit,
                referenceRange: referenceRange == "unknown" || referenceRange.isEmpty ? nil : referenceRange,
                isAbnormal: BloodTestValueValidator.isAbnormal(
                    value: valueString,
                    referenceRange: referenceRange == "unknown" || referenceRange.isEmpty ? nil : referenceRange,
                    flag: normalizedFlag.isEmpty || normalizedFlag.caseInsensitiveCompare("normal") == .orderedSame ? nil : normalizedFlag
                ),
                abnormalFlag: normalizedFlag.isEmpty || normalizedFlag.caseInsensitiveCompare("normal") == .orderedSame ? nil : normalizedFlag,
                confidence: 0.8, // Could be calculated based on text clarity
                testType: inferredTestType,
                specimen: reportedSpecimen == "unknown" || reportedSpecimen?.isEmpty == true ? nil : reportedSpecimen,
                collection: reportedCollection == "unknown" || reportedCollection?.isEmpty == true ? nil : reportedCollection
            )

            values.append(extractedValue)
        }

        return values
    }
    
    // MARK: - Infer Test Type
    private func inferTestType(from testName: String) -> String {
        let lowercased = testName.lowercased()
        
        // Check for urine test indicators
        if lowercased.contains("urine") || 
           lowercased.contains("ua ") || 
           lowercased.hasPrefix("ua ") ||
           lowercased.contains("urinalysis") ||
           lowercased.contains("urine ") {
            return "URINE"
        }
        
        // Default to blood
        return "BLOOD"
    }

    // MARK: - Phase 3: Map to Standardized Parameters
    private func mapToStandardizedParameters(_ extractedValues: [ExtractedLabValue]) async -> [BloodTestImportGroup] {
        var mappedValues: [StandardizedLabValue] = []

        for extractedValue in extractedValues {
            // Find standardized parameter, filtering by test type (blood vs urine)
            if let standardParam = findStandardizedParameter(
                for: extractedValue.testName,
                testType: extractedValue.testType
            ) {
                let context = LabMeasurementContext.infer(
                    testName: extractedValue.testName,
                    parameter: standardParam,
                    unit: extractedValue.unit,
                    reportedSpecimen: extractedValue.specimen,
                    reportedCollection: extractedValue.collection
                )
                let mappedValue = StandardizedLabValue(
                    standardKey: standardParam.key,
                    standardName: standardParam.name,
                    value: extractedValue.value,
                    unit: extractedValue.unit ?? standardParam.unit,
                    referenceRange: extractedValue.referenceRange ?? standardParam.referenceRange,
                    isAbnormal: BloodTestValueValidator.isAbnormal(
                        value: extractedValue.value,
                        referenceRange: extractedValue.referenceRange ?? standardParam.referenceRange,
                        flag: extractedValue.abnormalFlag
                    ),
                    category: standardParam.category,
                    confidence: calculateMappingConfidence(
                        original: extractedValue.testName,
                        standard: standardParam.name
                    ),
                    originalTestName: extractedValue.testName,
                    specimen: context.specimen,
                    collection: context.collection,
                    testType: extractedValue.testType
                )
                mappedValues.append(mappedValue)
            } else {
                // Log unmapped values for debugging
                AppLog.shared.healthData("Could not map extracted value (type: \(extractedValue.testType)) to standardized parameter", level: .warning)
            }
        }

        // Create import groups for ALL values (both unique and duplicates)
        let importGroups = createImportGroups(mappedValues)
        AppLog.shared.healthData("Mapped \(mappedValues.count) values to \(importGroups.count) import groups")
        
        return importGroups
    }
    
    // MARK: - Create Import Groups
    /// Groups all values by standard key for user review
    private func createImportGroups(_ values: [StandardizedLabValue]) -> [BloodTestImportGroup] {
        // Group by standard key (the unique identifier for the test)
        var grouped: [String: [StandardizedLabValue]] = [:]
        
        for value in values {
            let key = value.standardKey
            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(value)
        }
        
        var importGroups: [BloodTestImportGroup] = []
        
        for (key, group) in grouped {
            // Convert all values to candidates
            let candidates = group.map { value in
                // Validate each candidate
                var validation = BloodTestValueValidator.validateValue(
                    value.value,
                    testName: value.standardName,
                    referenceRange: value.referenceRange,
                    standardParam: BloodTestResult.standardizedLabParameters[key]
                )

                if let parameter = BloodTestResult.standardizedLabParameters[key] {
                    validation = BloodTestValueValidator.applyingUnitValidation(validation, unit: value.unit, for: parameter)
                }
                
                let (status, reason) = validationToStatus(validation)
                
                return BloodTestImportCandidate(
                    testName: value.standardName,
                    value: value.value,
                    unit: value.unit,
                    referenceRange: value.referenceRange,
                    isAbnormal: value.isAbnormal,
                    originalTestName: value.originalTestName,
                    confidence: value.confidence,
                    validationStatus: status,
                    reason: reason,
                    specimen: value.specimen,
                    collection: value.collection
                )
            }
            
            let importGroup = BloodTestImportGroup(
                standardTestName: group.first?.standardName ?? key,
                standardKey: key,
                candidates: candidates
                // selectedCandidateId is automatically handled in init
            )
            
            importGroups.append(importGroup)
        }
        
        return importGroups
    }
    
    // MARK: - Select Best Candidate
    private func selectBestCandidate(from group: [StandardizedLabValue]) -> StandardizedLabValue? {
        // Filter to only valid values first
        let validValues = group.filter { value in
            let validation = BloodTestValueValidator.validateValue(
                value.value,
                testName: value.standardName,
                referenceRange: value.referenceRange,
                standardParam: BloodTestResult.standardizedLabParameters[value.standardKey]
            )
            
            if case .valid = validation {
                return true
            }
            return false
        }
        
        // If no valid values, return the first one anyway (user will see it's invalid)
        guard !validValues.isEmpty else {
            return group.first
        }
        
        // Select best from valid values
        // Priority: 1) Highest confidence, 2) Has unit, 3) Has reference range, 4) Most complete original name
        return validValues.max { val1, val2 in
            // Compare confidence first
            if abs(val1.confidence - val2.confidence) > 0.1 {
                return val1.confidence < val2.confidence
            }
            
            // If confidence is similar, prefer value with unit
            let val1HasUnit = val1.unit != nil && !val1.unit!.isEmpty
            let val2HasUnit = val2.unit != nil && !val2.unit!.isEmpty
            if val1HasUnit != val2HasUnit {
                return !val1HasUnit
            }
            
            // Prefer value with reference range
            let val1HasRange = val1.referenceRange != nil && !val1.referenceRange!.isEmpty
            let val2HasRange = val2.referenceRange != nil && !val2.referenceRange!.isEmpty
            if val1HasRange != val2HasRange {
                return !val1HasRange
            }
            
            // Prefer more complete original name (longer, more descriptive)
            return val1.originalTestName.count < val2.originalTestName.count
        }
    }
    
    // MARK: - Convert Validation Result to Status
    private func validationToStatus(_ validation: BloodTestValueValidator.ValidationResult) -> (
        BloodTestImportCandidate.ValidationStatus,
        String?
    ) {
        switch validation {
        case .valid:
            return (.valid, nil)
        case .unitMismatch(let reason):
            return (.unitMismatch, reason)
        case .ocrUnitMismatch(let reason):
            return (.ocrUnitMismatch, reason)
        case .invalidType(let reason):
            return (.invalidType, reason)
        case .outOfRange(let reason, _):
            return (.outOfRange, reason)
        case .missingData(let reason):
            return (.missingData, reason)
        }
    }

    private func findStandardizedParameter(for testName: String, testType: String = "BLOOD") -> LabParameter? {
        let labTestType: BloodTestResult.LabTestType = testType.uppercased() == "URINE" ? .urine : .blood
        return BloodTestResult.matchLabParameter(name: testName, testType: labTestType)?.parameter
    }

    private func calculateMappingConfidence(original: String, standard: String) -> Double {
        let normalizedOriginal = original.lowercased().replacingOccurrences(of: " ", with: "")
        let normalizedStandard = standard.lowercased().replacingOccurrences(of: " ", with: "")

        if normalizedOriginal == normalizedStandard {
            return 1.0
        }

        if normalizedOriginal.contains(normalizedStandard) || normalizedStandard.contains(normalizedOriginal) {
            return 0.8
        }

        // Calculate string similarity (simplified Levenshtein-like approach)
        let maxLength = max(normalizedOriginal.count, normalizedStandard.count)
        let commonPrefixLength = zip(normalizedOriginal, normalizedStandard)
            .prefix(while: { $0.0 == $0.1 })
            .count

        return Double(commonPrefixLength) / Double(maxLength)
    }

    // MARK: - Phase 4: Create Final BloodTestResult
    private func createBloodTestResult(
        from mappedParameters: [StandardizedLabValue],
        basicInfo: BasicTestInfo,
        testDate: Date,
        patientName: String?,
        model: String
    ) -> BloodTestResult {

        let bloodTestItems = mappedParameters.map { mappedValue in
            BloodTestItem(
                name: mappedValue.standardName,
                value: mappedValue.value,
                unit: mappedValue.unit,
                referenceRange: mappedValue.referenceRange,
                isAbnormal: mappedValue.isAbnormal,
                category: mappedValue.category,
                notes: mappedValue.originalTestName != mappedValue.standardName
                    ? "Original name: \(mappedValue.originalTestName)"
                    : nil,
                confidence: mappedValue.confidence,
                specimen: mappedValue.specimen,
                collection: mappedValue.collection
            )
        }

        var metadata: [String: String] = [:]
        metadata["mapping_confidence"] = String(format: "%.2f", calculateOverallConfidence(mappedParameters))
        metadata["ai_model"] = model
        metadata["extracted_count"] = String(mappedParameters.count)
        if let patientName = patientName {
            metadata["patient_name"] = patientName
        }

        return BloodTestResult(
            testDate: testDate,
            laboratoryName: basicInfo.laboratoryName,
            orderingPhysician: basicInfo.orderingPhysician,
            results: bloodTestItems,
            metadata: metadata
        )
    }

    // MARK: - Helper Functions
    private func calculateOverallConfidence(_ mappedParameters: [StandardizedLabValue]) -> Double {
        guard !mappedParameters.isEmpty else { return 0.0 }

        let totalConfidence = mappedParameters.reduce(0.0) { $0 + $1.confidence }
        return (totalConfidence / Double(mappedParameters.count)) * 100
    }

    private func parseDate(from dateString: String) -> Date? {
        let formatters = [
            createDateFormatter("yyyy-MM-dd"),
            createDateFormatter("MM/dd/yyyy"),
            createDateFormatter("MM-dd-yyyy"),
            createDateFormatter("dd/MM/yyyy"),
            createDateFormatter("dd-MM-yyyy"),
            createDateFormatter("MMMM dd, yyyy"),
            createDateFormatter("MMM dd, yyyy")
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    private func createDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

}

// MARK: - Supporting Data Structures

struct BasicTestInfo {
    let testDate: Date?
    let laboratoryName: String?
    let orderingPhysician: String?
    let patientName: String?
}

struct ExtractedLabValue: LabValueLike {
    let testName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
    let abnormalFlag: String?
    let confidence: Double
    let testType: String // "BLOOD" or "URINE"
    let specimen: String?
    let collection: String?
    
    init(
        testName: String,
        value: String,
        unit: String? = nil,
        referenceRange: String? = nil,
        isAbnormal: Bool = false,
        abnormalFlag: String? = nil,
        confidence: Double = 0.8,
        testType: String = "BLOOD",
        specimen: String? = nil,
        collection: String? = nil
    ) {
        self.testName = testName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.abnormalFlag = abnormalFlag
        self.confidence = confidence
        self.testType = testType
        self.specimen = specimen
        self.collection = collection
    }
}

struct StandardizedLabValue: LabValueLike {
    let standardKey: String
    let standardName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
    let category: BloodTestCategory
    let confidence: Double
    let originalTestName: String
    let specimen: LabSpecimen?
    let collection: LabCollection?
    let testType: String
    
    // LabValueLike conformance
    var testName: String { standardName }

    init(
        standardKey: String,
        standardName: String,
        value: String,
        unit: String?,
        referenceRange: String?,
        isAbnormal: Bool,
        category: BloodTestCategory,
        confidence: Double,
        originalTestName: String,
        specimen: LabSpecimen? = nil,
        collection: LabCollection? = nil,
        testType: String = "BLOOD"
    ) {
        self.standardKey = standardKey
        self.standardName = standardName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.category = category
        self.confidence = confidence
        self.originalTestName = originalTestName
        self.specimen = specimen
        self.collection = collection
        self.testType = testType
    }
}

struct BloodTestMappingResult {
    let bloodTestResult: BloodTestResult
    let extractedRawValues: [ExtractedLabValue]
    let importGroups: [BloodTestImportGroup]
    let confidence: Double
    let processingTime: TimeInterval
    let aiModel: String

    var summary: String {
        return "\(bloodTestResult.results.count) tests mapped with \(String(format: "%.1f", confidence))% confidence"
    }
    
    var needsReview: Bool {
        return !importGroups.isEmpty
    }
}

enum BloodTestMappingServiceError: Error, LocalizedError {
    case visionModelNotAvailable(String)
    case documentModelNotAvailable(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .visionModelNotAvailable(let message):
            return "Vision Model Not Available: \(message)"
        case .documentModelNotAvailable(let message):
            return "Document Model Not Available: \(message)"
        case .processingFailed(let message):
            return "Processing Failed: \(message)"
        }
    }
}

struct BloodTestMappingError: Identifiable {
    let id = UUID()
    let error: Error
    let documentText: String
    let timestamp: Date

    var displayMessage: String {
        return error.localizedDescription
    }
}
