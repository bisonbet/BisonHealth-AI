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
            let mappedParameters = await mapToStandardizedParameters(extractedValues)
            processingProgress = 0.9
            print("✅ BloodTestMappingService: Mapped \(mappedParameters.count) standardized parameters")

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
        
        // Deduplicate values (same test name and value)
        let deduplicatedValues = deduplicateLabValues(allExtractedValues)
        print("🧪 BloodTestMappingService: Extracted \(allExtractedValues.count) total values, \(deduplicatedValues.count) after deduplication")
        
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
        You are a medical AI assistant specializing in laboratory report analysis. Analyze this lab report section\(chunkContext) and extract ALL laboratory values.

        CRITICAL INSTRUCTIONS:
        1. Extract EVERY numerical laboratory test result you find
        2. Look for test results in tables, lists, and paragraph form
        3. Pay attention to sections labeled: "Results", "Laboratory Results", "Test Results", "Lab Values", "Chemistry", "Hematology", etc.
        4. Extract both absolute values AND percentages (e.g., both "Neutrophils: 3.5 K/uL" and "Neutrophils: 55%")
        
        Document text\(chunkContext):
        \(chunk)

        For each lab value you find, extract:
        1. Test name (exactly as written in the document, preserve abbreviations)
        2. Numerical value (the actual number)
        3. Unit (mg/dL, g/dL, %, U/L, ng/mL, pg/mL, μIU/mL, etc.)
        4. Reference range (normal range) if provided (e.g., "70-100", "<200", ">40")
        5. Abnormal flag if present (High, Low, Critical, H, L, *, ↑, ↓, etc. - use "Normal" if none)

        Return ONLY lab values in this exact format, one per line:
        TEST_NAME|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG

        Examples of correct format:
        Glucose|95|mg/dL|70-100|Normal
        Hemoglobin|14.2|g/dL|12.0-16.0|Normal
        Total Cholesterol|220|mg/dL|<200|High
        Hemoglobin A1c|6.2|%|<5.7|High
        TSH|2.5|mIU/L|0.4-4.0|Normal
        LDL Cholesterol|135|mg/dL|<100|High
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
        
        Common test categories to look for:
        - Complete Blood Count (CBC): Hemoglobin, Hematocrit, WBC, RBC, Platelets, MCV, MCH, MCHC, RDW, MPV, differentials
        - Metabolic Panel: Glucose, Sodium, Potassium, Chloride, CO2, BUN, Creatinine, eGFR, Calcium, Albumin, Total Protein
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
            // Create a unique key from test name and value
            let key = "\(value.testName.lowercased().trimmingCharacters(in: .whitespaces))|\(value.value.trimmingCharacters(in: .whitespaces))"
            
            if !seen.contains(key) {
                seen.insert(key)
                deduplicated.append(value)
            }
        }
        
        return deduplicated
    }

    private func parseExtractedLabValues(from response: String) -> [ExtractedLabValue] {
        var values: [ExtractedLabValue] = []

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let components = trimmedLine.components(separatedBy: "|")
            guard components.count >= 5 else { continue }

            let testName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let referenceRange = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let abnormalFlag = components[4].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !testName.isEmpty && !valueString.isEmpty else { continue }

            let extractedValue = ExtractedLabValue(
                testName: testName,
                value: valueString,
                unit: unit == "unknown" ? nil : unit,
                referenceRange: referenceRange == "unknown" ? nil : referenceRange,
                isAbnormal: abnormalFlag.lowercased() != "normal",
                abnormalFlag: abnormalFlag == "Normal" ? nil : abnormalFlag,
                confidence: 0.8 // Could be calculated based on text clarity
            )

            values.append(extractedValue)
        }

        return values
    }

    // MARK: - Phase 3: Map to Standardized Parameters
    private func mapToStandardizedParameters(_ extractedValues: [ExtractedLabValue]) async -> [StandardizedLabValue] {
        var mappedValues: [StandardizedLabValue] = []

        for extractedValue in extractedValues {
            if let standardParam = findStandardizedParameter(for: extractedValue.testName) {
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
            }
        }

        return mappedValues
    }

    private func findStandardizedParameter(for testName: String) -> LabParameter? {
        let normalizedTestName = testName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        // Direct key match
        if let parameter = BloodTestResult.standardizedLabParameters[normalizedTestName] {
            return parameter
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
                return BloodTestResult.standardizedLabParameters[standardKey]
            }
        }

        // Partial matching
        for (key, parameter) in BloodTestResult.standardizedLabParameters {
            if normalizedTestName.contains(key) || key.contains(normalizedTestName) {
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

struct ExtractedLabValue {
    let testName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
    let abnormalFlag: String?
    let confidence: Double
}

struct StandardizedLabValue {
    let standardKey: String
    let standardName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
    let category: BloodTestCategory
    let confidence: Double
    let originalTestName: String
}

struct BloodTestMappingResult {
    let bloodTestResult: BloodTestResult
    let extractedRawValues: [ExtractedLabValue]
    let mappedParameters: [StandardizedLabValue]
    let confidence: Double
    let processingTime: TimeInterval
    let aiModel: String

    var summary: String {
        return "\(bloodTestResult.results.count) tests mapped with \(String(format: "%.1f", confidence))% confidence"
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