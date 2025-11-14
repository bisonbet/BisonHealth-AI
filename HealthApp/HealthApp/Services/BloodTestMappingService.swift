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

        print("🧪 BloodTestMappingService: Starting AI-powered blood test mapping...")
        print("🧪 BloodTestMappingService: Document text length: \(documentText.count) characters")

        isProcessing = true
        processingProgress = 0.0

        defer {
            isProcessing = false
            processingProgress = 1.0
        }

        do {
            // Phase 1: Extract basic document information (20% progress)
            print("📝 BloodTestMappingService: Phase 1 - Extracting basic document information...")
            let basicInfo = try await extractBasicInformation(from: documentText)
            processingProgress = 0.2
            print("✅ BloodTestMappingService: Basic info extracted - Date: \(basicInfo.testDate?.formatted() ?? "unknown"), Lab: \(basicInfo.laboratoryName ?? "unknown")")

            // Phase 2: Extract all lab values using AI (60% progress)
            print("🔬 BloodTestMappingService: Phase 2 - Extracting lab values using AI...")
            let extractedValues = try await extractLabValuesWithAI(from: documentText)
            processingProgress = 0.8
            print("✅ BloodTestMappingService: Extracted \(extractedValues.count) lab values")

            // Phase 3: Map to standardized parameters (80% progress)
            print("🗺️ BloodTestMappingService: Phase 3 - Mapping to standardized parameters...")
            let (mappedParameters, duplicateGroups) = await mapToStandardizedParameters(extractedValues)
            processingProgress = 0.9
            print("✅ BloodTestMappingService: Mapped \(mappedParameters.count) standardized parameters, \(duplicateGroups.count) duplicate groups found")

            // Phase 4: Create final BloodTestResult (100% progress)
            print("🏗️ BloodTestMappingService: Phase 4 - Creating final BloodTestResult...")
            let finalTestDate = basicInfo.testDate ?? suggestedTestDate ?? Date()
            print("📅 BloodTestMappingService: Final test date selected: \(finalTestDate.formatted()) (AI: \(basicInfo.testDate?.formatted() ?? "none"), Suggested: \(suggestedTestDate?.formatted() ?? "none"))")
            let bloodTestResult = createBloodTestResult(
                from: mappedParameters,
                basicInfo: basicInfo,
                testDate: finalTestDate,
                patientName: patientName,
                model: "AI Provider"
            )

            let result = BloodTestMappingResult(
                bloodTestResult: bloodTestResult,
                extractedRawValues: extractedValues,
                mappedParameters: mappedParameters,
                duplicateGroups: duplicateGroups,
                confidence: calculateOverallConfidence(mappedParameters),
                processingTime: Date().timeIntervalSince1970,
                aiModel: "AI Provider"
            )

            lastMappingResult = result
            processingProgress = 1.0

            print("🎉 BloodTestMappingService: Mapping completed successfully!")
            print("🎉 BloodTestMappingService: Final result - \(bloodTestResult.results.count) test items, confidence: \(result.confidence)%")

            return result

        } catch {
            print("❌ BloodTestMappingService: Mapping failed with error: \(error)")
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
        let prompt = """
        Analyze this medical document and extract the following basic information. Return your response in a structured format:

        Document text:
        \(text)

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

    // MARK: - Phase 2: Extract Lab Values with AI
    private func extractLabValuesWithAI(from text: String) async throws -> [ExtractedLabValue] {
        // Check if document is too large and needs chunking
        let maxChunkSize = 15000 // Conservative estimate for most AI models
        let chunks = chunkDocument(text, maxChunkSize: maxChunkSize)
        
        print("🧪 BloodTestMappingService: Document split into \(chunks.count) chunks for processing")
        
        var allExtractedValues: [ExtractedLabValue] = []
        
        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            print("🧪 BloodTestMappingService: Processing chunk \(index + 1)/\(chunks.count) (\(chunk.count) characters)")
            
            let chunkValues = try await extractLabValuesFromChunk(chunk, chunkIndex: index, totalChunks: chunks.count)
            allExtractedValues.append(contentsOf: chunkValues)
        }
        
        // Filter out invalid values (non-numeric, out of range, etc.)
        let validValues = BloodTestValueValidator.filterInvalidValues(
            allExtractedValues,
            standardParams: BloodTestResult.standardizedLabParameters
        )
        print("🧪 BloodTestMappingService: Filtered to \(validValues.count) valid values from \(allExtractedValues.count) extracted")
        
        // Deduplicate values (same test name and value)
        let deduplicatedValues = deduplicateLabValues(validValues)
        print("🧪 BloodTestMappingService: Extracted \(allExtractedValues.count) total values, \(deduplicatedValues.count) after deduplication and validation")
        
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
        You are a medical AI assistant specializing in laboratory report analysis. Analyze this lab report section\(chunkContext) and extract ALL laboratory values from BOTH blood tests AND urine tests.

        CRITICAL INSTRUCTIONS:
        1. Extract EVERY numerical laboratory test result you find - BOTH blood tests AND urine tests
        2. Look for test results in tables, lists, and paragraph form
        3. Pay attention to sections labeled: "Results", "Laboratory Results", "Test Results", "Lab Values", "Chemistry", "Hematology", "Urinalysis", "UA", "Urine", etc.
        4. Extract both absolute values AND percentages (e.g., both "Neutrophils: 3.5 K/uL" and "Neutrophils: 55%")
        5. IMPORTANT: Differentiate between BLOOD tests and URINE tests:
           - Blood tests: Usually in sections labeled "Chemistry", "Hematology", "Serum", "Plasma", "Blood"
           - Urine tests: Usually in sections labeled "Urinalysis", "UA", "Urine", "Urine Analysis", "Urine Chemistry"
           - Look for context clues: "serum", "plasma", "blood" vs "urine", "UA", "urinalysis"
           - If a test name starts with "Urine" or is clearly a urine parameter (e.g., "Urine Protein", "Urine pH", "Urine WBC"), it's a urine test
           - If unclear, use the section header or context to determine
        
        Document text\(chunkContext):
        \(chunk)

        For each lab value you find, extract:
        1. Test name (exactly as written in the document, preserve abbreviations)
        2. Test type: "BLOOD" or "URINE" (determine from context - section header, test name, or sample type)
        3. Numerical value (the actual number, or "Negative"/"Positive"/"None" for qualitative urine tests)
        4. Unit (mg/dL, g/dL, %, U/L, ng/mL, pg/mL, μIU/mL, /HPF, /LPF, etc. - leave empty for qualitative results)
        5. Reference range (normal range) if provided (e.g., "70-100", "<200", ">40", "Negative", "Clear")
        6. Abnormal flag if present (High, Low, Critical, H, L, *, ↑, ↓, Positive, Negative, etc. - use "Normal" if none)

        Return ONLY lab values in this exact format, one per line:
        TEST_NAME|TEST_TYPE|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG

        Examples of correct format:
        Glucose|BLOOD|95|mg/dL|70-100|Normal
        Hemoglobin|BLOOD|14.2|g/dL|12.0-16.0|Normal
        Total Cholesterol|BLOOD|220|mg/dL|<200|High
        Urine Protein|URINE|Negative||Negative|Normal
        Urine pH|URINE|6.5||5.0-8.0|Normal
        Urine WBC|URINE|8|/HPF|0-5|High
        Urine Glucose|URINE|Negative||Negative|Normal
        Creatinine|BLOOD|1.1|mg/dL|0.6-1.2|Normal
        Urine Creatinine|URINE|120|mg/dL|20-320|Normal
        WBC|7.2|K/uL|4.5-11.0|Normal
        Neutrophils|55|%|40-60|Normal
        Absolute Neutrophils|3.96|K/uL|1.8-7.8|Normal

        IMPORTANT RULES:
        - Include ALL numerical lab values, even if not in standard panels
        - Use "unknown" for missing information (unit, reference range, or flag)
        - Use "Normal" for abnormal flag if no flag is present
        - Preserve test names exactly as written (don't normalize or expand abbreviations)
        - Include common variations: HbA1c, A1C, Hemoglobin A1c are all valid
        - Extract both absolute counts AND percentages for CBC differentials
        - Include calculated values (e.g., "LDL Cholesterol (Calculated)", ratios)
        - Look for values in various formats: tables, lists, inline text
        - Pay attention to footnotes or flags (H, L, *, ↑, ↓) indicating abnormal values
        
        CRITICAL: AVOID DUPLICATES
        - If you see the same test name with the same value, extract it ONLY ONCE
        - If a test appears in multiple sections (e.g., "Glucose" in both "Chemistry" and "Summary"), extract it only once
        - If a test appears with slightly different formatting (e.g., "Glucose" vs "GLUCOSE"), extract it once with the most complete information
        - If you see the same test with different values, extract both (they may be from different time points or different samples)
        - Do NOT extract the same test multiple times just because it appears in different parts of the document
        
        Common test categories to look for:
        - Complete Blood Count (CBC): Hemoglobin, Hematocrit, WBC, RBC, Platelets, MCV, MCH, MCHC, RDW, MPV, differentials
        - Metabolic Panel: Glucose, Sodium, Potassium, Chloride, CO2, BUN, Creatinine, eGFR, Calcium, Albumin, Total Protein
        BLOOD TESTS to look for:
        - Complete Blood Count (CBC): Hemoglobin, Hematocrit, WBC, RBC, Platelets, MCV, MCH, MCHC, differentials
        - Lipid Panel: Total Cholesterol, LDL, HDL, Triglycerides, Non-HDL, ratios
        - Liver Function: ALT, AST, ALP, GGT, LDH, Bilirubin (total, direct, indirect)
        - Kidney Function: BUN, Creatinine, eGFR, Cystatin C, BUN/Creatinine Ratio
        - Thyroid: TSH, Free T4, Free T3, Total T4, Total T3, Reverse T3, antibodies
        - Diabetes: Hemoglobin A1c, Glucose (fasting, random), Insulin, C-Peptide, Fructosamine
        - Cardiac: Troponin I/T, BNP, NT-proBNP, CK-MB, Homocysteine
        - Inflammatory: CRP, High-Sensitivity CRP, ESR, Procalcitonin, IL-6
        - Coagulation: PT, PTT, INR, Fibrinogen, D-Dimer, Protein C/S, Antithrombin III
        - Vitamins/Minerals: Vitamin D, B12, Folate, Iron, Ferritin, TIBC, Magnesium, Zinc, Copper, Selenium
        - Hormones: Testosterone, Estradiol, Cortisol, PTH, Progesterone, Prolactin, LH, FSH, Growth Hormone
        - Immunology: ABO Blood Type, Rh Factor, Total IgE, IgA, IgG, IgM
        - Tumor Markers: PSA, CEA, CA 125, CA 19-9, AFP
        
        URINE TESTS to look for:
        - Urinalysis (UA): Color, Appearance, Specific Gravity, pH, Protein, Glucose, Ketones, Blood, Bilirubin, Urobilinogen, Nitrite, Leukocyte Esterase
        - Urine Microscopic: WBC, RBC, Epithelial Cells, Bacteria, Casts, Crystals, Mucus, Yeast
        - Urine Chemistry: Creatinine, Protein (quantitative), Albumin, Microalbumin, Protein/Creatinine Ratio, Albumin/Creatinine Ratio, Sodium, Potassium, Chloride, Osmolality
        - 24-Hour Urine: Urea Nitrogen, Creatinine Clearance, Calcium, Uric Acid, Phosphate, Magnesium
        - Urine Microbiology: Culture results, Bacterial count (CFU/mL)
        
        Return your response now with ONLY the extracted lab values in the specified format:
        """

        do {
            let aiResponse = try await aiClient.sendMessage(prompt, context: "")
            let response = aiResponse.content
            return parseExtractedLabValues(from: response)
        } catch {
            print("❌ BloodTestMappingService: Failed to extract from chunk \(chunkIndex + 1): \(error)")
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
            // Normalize test name for comparison (remove common prefixes/suffixes, lowercase)
            let normalizedName = normalizeTestName(value.testName)
            let normalizedValue = normalizeValue(value.value)
            
            // Create a unique key from normalized test name and value
            let key = "\(normalizedName)|\(normalizedValue)"
            
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(value)
            } else {
                print("🧪 BloodTestMappingService: Skipping duplicate: '\(value.testName)' = \(value.value)")
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
    
    // MARK: - Normalize Value for Deduplication
    private func normalizeValue(_ value: String) -> String {
        // Remove whitespace and normalize decimal separators
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common formatting characters that don't affect the numeric value
        normalized = normalized.replacingOccurrences(of: ",", with: "") // Remove thousands separators
        normalized = normalized.replacingOccurrences(of: " ", with: "") // Remove spaces
        
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
            
            if components.count >= 6 {
                // New format: TEST_NAME|TEST_TYPE|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG
                testName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                testType = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                valueString = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                unit = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                referenceRange = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
                abnormalFlag = components[5].trimmingCharacters(in: .whitespacesAndNewlines)
            } else if components.count >= 5 {
                // Old format: TEST_NAME|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG (backward compatibility)
                testName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                testType = nil // Will be inferred from test name
                valueString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                unit = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                referenceRange = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                abnormalFlag = components[4].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                continue
            }

            guard !testName.isEmpty && !valueString.isEmpty else { continue }
            
            // Infer test type from name if not provided
            let inferredTestType = testType ?? inferTestType(from: testName)

            let extractedValue = ExtractedLabValue(
                testName: testName,
                value: valueString,
                unit: unit == "unknown" || unit.isEmpty ? nil : unit,
                referenceRange: referenceRange == "unknown" || referenceRange.isEmpty ? nil : referenceRange,
                isAbnormal: abnormalFlag.lowercased() != "normal",
                abnormalFlag: abnormalFlag == "Normal" ? nil : abnormalFlag,
                confidence: 0.8, // Could be calculated based on text clarity
                testType: inferredTestType
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
    private func mapToStandardizedParameters(_ extractedValues: [ExtractedLabValue]) async -> (
        unique: [StandardizedLabValue],
        duplicates: [DuplicateTestGroup]
    ) {
        var mappedValues: [StandardizedLabValue] = []

        for extractedValue in extractedValues {
            // Find standardized parameter, filtering by test type (blood vs urine)
            if let standardParam = findStandardizedParameter(
                for: extractedValue.testName,
                testType: extractedValue.testType
            ) {
                let mappedValue = StandardizedLabValue(
                    standardKey: standardParam.key,
                    standardName: standardParam.name,
                    value: extractedValue.value,
                    unit: extractedValue.unit ?? standardParam.unit,
                    referenceRange: extractedValue.referenceRange ?? standardParam.referenceRange,
                    isAbnormal: extractedValue.isAbnormal,
                    category: standardParam.category,
                    confidence: calculateMappingConfidence(
                        original: extractedValue.testName,
                        standard: standardParam.name
                    ),
                    originalTestName: extractedValue.testName
                )
                mappedValues.append(mappedValue)
            } else {
                // Log unmapped values for debugging
                print("⚠️ BloodTestMappingService: Could not map '\(extractedValue.testName)' (type: \(extractedValue.testType)) to standardized parameter")
            }
        }

        // Deduplicate mapped values: if same standardized parameter appears multiple times,
        // create groups for user review
        let (unique, duplicates) = deduplicateStandardizedValues(mappedValues)
        print("🧪 BloodTestMappingService: Deduplicated \(mappedValues.count) mapped values to \(unique.count) unique parameters, \(duplicates.count) duplicate groups need review")
        
        return (unique: unique, duplicates: duplicates)
    }
    
    // MARK: - Deduplicate Standardized Values
    /// Returns deduplicated values and groups of duplicates that need user review
    private func deduplicateStandardizedValues(_ values: [StandardizedLabValue]) -> (
        unique: [StandardizedLabValue],
        duplicates: [DuplicateTestGroup]
    ) {
        // Group by standard key (the unique identifier for the test)
        var grouped: [String: [StandardizedLabValue]] = [:]
        
        for value in values {
            let key = value.standardKey
            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(value)
        }
        
        // Separate unique values from duplicates
        var unique: [StandardizedLabValue] = []
        var duplicateGroups: [DuplicateTestGroup] = []
        
        for (key, group) in grouped {
            // If only one value, use it
            if group.count == 1 {
                unique.append(group[0])
                continue
            }
            
            // Multiple values for same test - create duplicate group for user review
            let candidates = group.map { value in
                // Validate each candidate
                let validation = BloodTestValueValidator.validateValue(
                    value.value,
                    testName: value.standardName,
                    referenceRange: value.referenceRange,
                    standardParam: BloodTestResult.standardizedLabParameters[key]
                )
                
                let (status, reason) = validationToStatus(validation)
                
                return DuplicateBloodTestCandidate(
                    testName: value.standardName,
                    value: value.value,
                    unit: value.unit,
                    referenceRange: value.referenceRange,
                    isAbnormal: value.isAbnormal,
                    originalTestName: value.originalTestName,
                    confidence: value.confidence,
                    validationStatus: status,
                    reason: reason
                )
            }
            
            // Find the recommended candidate (best valid one)
            let recommended = selectBestCandidate(from: group)
            
            let duplicateGroup = DuplicateTestGroup(
                standardTestName: group.first?.standardName ?? key,
                standardKey: key,
                candidates: candidates,
                selectedCandidateId: recommended.map { candidate in
                    candidates.first(where: { $0.value == candidate.value && $0.originalTestName == candidate.originalTestName })?.id
                } ?? nil
            )
            
            duplicateGroups.append(duplicateGroup)
            
            // Add the recommended value to unique list (user can override)
            if let recommended = recommended {
                unique.append(recommended)
            }
        }
        
        return (unique: unique, duplicates: duplicateGroups)
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
        DuplicateBloodTestCandidate.ValidationStatus,
        String?
    ) {
        switch validation {
        case .valid:
            return (.valid, nil)
        case .invalidType(let reason):
            return (.invalidType, reason)
        case .outOfRange(let reason, _):
            return (.outOfRange, reason)
        case .missingData(let reason):
            return (.missingData, reason)
        }
    }

    private func findStandardizedParameter(for testName: String, testType: String = "BLOOD") -> LabParameter? {
        let normalizedTestName = testName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // Determine which categories to search based on test type
        let isUrineTest = testType.uppercased() == "URINE"
        let urineCategories: Set<BloodTestCategory> = [.urinalysis, .urineChemistry, .urineMicrobiology]

        // Direct key match
        if let parameter = BloodTestResult.standardizedLabParameters[normalizedTestName] {
            // Verify the parameter matches the test type
            if isUrineTest && urineCategories.contains(parameter.category) {
                return parameter
            } else if !isUrineTest && !urineCategories.contains(parameter.category) {
                return parameter
            }
            // If type mismatch, continue to fuzzy matching
        }

        // Fuzzy matching for common variations
        let testNameVariations = [
            // Glucose variations
            ("glucose", ["blood_sugar", "fasting_glucose", "random_glucose"]),
            ("fasting_glucose", ["fasting_blood_glucose", "fbg", "fasting_glucose"]),
            ("random_glucose", ["random_blood_glucose", "rbg", "random_glucose"]),
            ("glucose_tolerance_test_2hr", ["2_hour_glucose", "gtt_2hr", "glucose_tolerance_2hr"]),
            // Hemoglobin variations
            ("hemoglobin", ["hgb", "hb", "hemoglobin_concentration"]),
            ("hemoglobin_a1c", ["hba1c", "a1c", "glycated_hemoglobin", "hemoglobin_a1c_", "hba1c"]),
            // Cholesterol variations
            ("cholesterol_total", ["total_cholesterol", "cholesterol", "chol_total", "chol"]),
            ("ldl_cholesterol", ["ldl", "ldl_chol", "low_density_lipoprotein", "ldl_c"]),
            ("hdl_cholesterol", ["hdl", "hdl_chol", "high_density_lipoprotein", "hdl_c"]),
            ("non_hdl_cholesterol", ["non_hdl", "non_hdl_c", "non_high_density_lipoprotein"]),
            ("apolipoprotein_b", ["apob", "apolipoprotein_b", "apo_b"]),
            ("lipoprotein_a", ["lpa", "lipoprotein_a", "lp_a"]),
            // Liver function variations
            ("alt_sgpt", ["alt", "sgpt", "alanine_aminotransferase"]),
            ("ast_sgot", ["ast", "sgot", "aspartate_aminotransferase"]),
            ("alp", ["alkaline_phosphatase", "alk_phos"]),
            ("ggt", ["gamma_glutamyl_transferase", "gamma_gt", "ggtp"]),
            ("ldh", ["lactate_dehydrogenase", "ld"]),
            ("lactate_dehydrogenase", ["ldh", "ld", "lactate_dehydrogenase"]),
            // Kidney function variations
            ("creatinine", ["creat", "serum_creatinine", "cr"]),
            ("bun", ["blood_urea_nitrogen", "urea_nitrogen", "urea"]),
            ("egfr", ["estimated_gfr", "gfr", "egfr_estimated"]),
            ("cystatin_c", ["cys_c", "cystatin_c"]),
            ("bun_creatinine_ratio", ["bun_cr_ratio", "bun_creat_ratio"]),
            // Complete Blood Count variations
            ("wbc", ["white_blood_cell_count", "white_blood_cells", "leukocytes", "wbc_count"]),
            ("rbc", ["red_blood_cell_count", "red_blood_cells", "erythrocytes", "rbc_count"]),
            ("platelet_count", ["platelets", "plt", "platelet", "platelet_count"]),
            ("mcv", ["mean_corpuscular_volume"]),
            ("mch", ["mean_corpuscular_hemoglobin"]),
            ("mchc", ["mean_corpuscular_hemoglobin_concentration", "mean_cell_hemoglobin_concentration"]),
            ("rdw", ["red_cell_distribution_width", "rdw_cv"]),
            ("mpv", ["mean_platelet_volume"]),
            ("absolute_neutrophils", ["abs_neutrophils", "neutrophil_count", "neutrophils_abs"]),
            ("absolute_lymphocytes", ["abs_lymphocytes", "lymphocyte_count", "lymphocytes_abs"]),
            ("absolute_monocytes", ["abs_monocytes", "monocyte_count", "monocytes_abs"]),
            ("absolute_eosinophils", ["abs_eosinophils", "eosinophil_count", "eosinophils_abs"]),
            ("absolute_basophils", ["abs_basophils", "basophil_count", "basophils_abs"]),
            // Thyroid variations
            ("tsh", ["thyroid_stimulating_hormone", "thyrotropin"]),
            ("free_t4", ["ft4", "free_thyroxine", "t4_free"]),
            ("free_t3", ["ft3", "free_triiodothyronine", "t3_free"]),
            ("total_t4", ["t4", "total_thyroxine", "thyroxine"]),
            ("total_t3", ["t3", "total_triiodothyronine", "triiodothyronine"]),
            ("reverse_t3", ["rt3", "reverse_triiodothyronine"]),
            ("thyroid_peroxidase_antibodies", ["tpo_ab", "tpo_antibodies", "anti_tpo"]),
            ("thyroglobulin_antibody", ["tg_ab", "thyroglobulin_ab", "anti_tg"]),
            // Diabetes markers
            ("insulin", ["serum_insulin", "insulin_level"]),
            ("c_peptide", ["cpeptide", "c_peptide", "connecting_peptide"]),
            // Cardiac markers
            ("troponin_i", ["trop_i", "troponin_i", "ctni"]),
            ("troponin_t", ["trop_t", "troponin_t", "ctnt"]),
            ("bnp", ["b_type_natriuretic_peptide", "bnp_level"]),
            ("nt_pro_bnp", ["nt_probnp", "ntprobnp", "n_terminal_pro_bnp"]),
            ("ck_mb", ["ckmb", "creatine_kinase_mb", "ck_mb"]),
            ("homocysteine", ["hcy", "homocysteine_level"]),
            // Inflammatory markers
            ("crp_c_reactive_protein", ["crp", "c_reactive_protein", "reactive_protein"]),
            ("hs_crp", ["high_sensitivity_crp", "hs_c_reactive_protein", "hs_crp"]),
            ("esr", ["erythrocyte_sedimentation_rate", "sed_rate"]),
            // Coagulation
            ("pt", ["prothrombin_time", "pro_time"]),
            ("ptt", ["partial_thromboplastin_time", "aptt", "ptt"]),
            ("aptt", ["activated_partial_thromboplastin_time", "aptt"]),
            ("inr", ["international_normalized_ratio"]),
            ("d_dimer", ["ddimer", "d_dimer"]),
            ("fibrinogen", ["fibrinogen_level"]),
            // Vitamins and minerals
            ("vitamin_d", ["25_oh_vitamin_d", "25_hydroxyvitamin_d", "vit_d", "25ohd"]),
            ("vitamin_b12", ["b12", "cobalamin", "vitamin_b_12"]),
            ("folate", ["folic_acid", "vitamin_b9"]),
            ("iron", ["serum_iron", "fe"]),
            ("ferritin", ["ferritin_level"]),
            ("tibc", ["total_iron_binding_capacity", "tibc"]),
            ("percent_saturation", ["iron_saturation", "tsat", "transferrin_saturation"]),
            // Hormones
            ("testosterone", ["test", "total_testosterone"]),
            ("estradiol", ["e2", "estradiol_level"]),
            ("cortisol", ["cortisol_level"]),
            ("parathyroid_hormone", ["pth", "parathyroid_hormone"]),
            ("progesterone", ["prog", "progesterone_level"]),
            ("prolactin", ["prl", "prolactin_level"]),
            ("lh", ["luteinizing_hormone", "lh_level"]),
            ("fsh", ["follicle_stimulating_hormone", "fsh_level"]),
            ("gh", ["growth_hormone", "hgh", "somatotropin"]),
            ("igf1", ["igf_1", "insulin_like_growth_factor_1", "somatomedin_c"]),
            // Tumor markers
            ("psa", ["prostate_specific_antigen", "total_psa"]),
            ("cea", ["carcinoembryonic_antigen"]),
            ("ca125", ["ca_125", "cancer_antigen_125"]),
            ("ca199", ["ca_19_9", "cancer_antigen_19_9"]),
            ("afp", ["alpha_fetoprotein", "alpha_feto_protein"])
        ]

        for (standardKey, variations) in testNameVariations {
            if variations.contains(where: { normalizedTestName.contains($0) || $0.contains(normalizedTestName) }) {
                if let parameter = BloodTestResult.standardizedLabParameters[standardKey] {
                    // Verify the parameter matches the test type
                    if isUrineTest && urineCategories.contains(parameter.category) {
                        return parameter
                    } else if !isUrineTest && !urineCategories.contains(parameter.category) {
                        return parameter
                    }
                    // If type mismatch, continue searching
                }
            }
        }
        
        // Add urine test variations for fuzzy matching
        let urineTestVariations: [(String, [String])] = [
            ("urine_protein", ["protein", "urine_protein", "urine_prot", "protein_urine"]),
            ("urine_glucose", ["glucose_urine", "urine_glucose", "glucose_ua"]),
            ("urine_ph", ["ph_urine", "urine_ph", "ph_ua", "urine_p_h"]),
            ("urine_specific_gravity", ["specific_gravity", "urine_sg", "sg_urine", "sp_gr"]),
            ("urine_wbc", ["wbc_urine", "urine_wbc", "white_blood_cells_urine", "leukocytes_urine"]),
            ("urine_rbc", ["rbc_urine", "urine_rbc", "red_blood_cells_urine", "erythrocytes_urine"]),
            ("urine_creatinine", ["creatinine_urine", "urine_creatinine", "urine_creat"]),
            ("urine_microalbumin", ["microalbumin", "urine_microalbumin", "urine_albumin_quantitative"]),
            ("urine_albumin_creatinine_ratio", ["acr", "albumin_creatinine_ratio", "urine_acr", "urine_albumin_creat_ratio"])
        ]
        
        // Try urine test variations if this is a urine test
        if isUrineTest {
            for (key, variations) in urineTestVariations {
                if variations.contains(where: { normalizedTestName.contains($0) || $0.contains(normalizedTestName) }) {
                    if let parameter = BloodTestResult.standardizedLabParameters[key] {
                        return parameter
                    }
                }
            }
        }

        // Partial matching - filter by test type
        for (key, parameter) in BloodTestResult.standardizedLabParameters {
            // Only match if the category matches the test type
            let categoryMatches = isUrineTest ? urineCategories.contains(parameter.category) : !urineCategories.contains(parameter.category)
            
            if categoryMatches && (normalizedTestName.contains(key) || key.contains(normalizedTestName)) {
                return parameter
            }
        }

        return nil
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
                    : nil
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
    
    init(
        testName: String,
        value: String,
        unit: String? = nil,
        referenceRange: String? = nil,
        isAbnormal: Bool = false,
        abnormalFlag: String? = nil,
        confidence: Double = 0.8,
        testType: String = "BLOOD"
    ) {
        self.testName = testName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.abnormalFlag = abnormalFlag
        self.confidence = confidence
        self.testType = testType
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
    
    // LabValueLike conformance
    var testName: String { standardName }
}

struct BloodTestMappingResult {
    let bloodTestResult: BloodTestResult
    let extractedRawValues: [ExtractedLabValue]
    let mappedParameters: [StandardizedLabValue]
    let duplicateGroups: [DuplicateTestGroup]
    let confidence: Double
    let processingTime: TimeInterval
    let aiModel: String

    var summary: String {
        return "\(bloodTestResult.results.count) tests mapped with \(String(format: "%.1f", confidence))% confidence"
    }
    
    var hasDuplicates: Bool {
        return !duplicateGroups.isEmpty
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