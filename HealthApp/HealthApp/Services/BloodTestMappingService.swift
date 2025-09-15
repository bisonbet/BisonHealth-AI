import Foundation

// MARK: - Blood Test Mapping Service
@MainActor
class BloodTestMappingService: ObservableObject {

    // MARK: - Dependencies
    private let ollamaClient: OllamaClient

    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var lastMappingResult: BloodTestMappingResult?
    @Published var mappingErrors: [BloodTestMappingError] = []

    // MARK: - Configuration
    private let mappingModel = "llama2" // Could be made configurable
    private let maxRetryAttempts = 3
    private let mappingTimeout: TimeInterval = 120 // 2 minutes

    // MARK: - Initialization
    init(ollamaClient: OllamaClient? = nil) {
        self.ollamaClient = ollamaClient ?? OllamaClient.shared
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
            let finalTestDate = suggestedTestDate ?? basicInfo.testDate ?? Date()
            let bloodTestResult = createBloodTestResult(
                from: mappedParameters,
                basicInfo: basicInfo,
                testDate: finalTestDate,
                patientName: patientName
            )

            let result = BloodTestMappingResult(
                bloodTestResult: bloodTestResult,
                extractedRawValues: extractedValues,
                mappedParameters: mappedParameters,
                confidence: calculateOverallConfidence(mappedParameters),
                processingTime: Date().timeIntervalSince1970,
                aiModel: mappingModel
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

        let ollamaResponse = try await ollamaClient.sendChatMessage(prompt, model: mappingModel)
        let response = ollamaResponse.content
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
        let prompt = """
        You are a medical AI assistant specializing in laboratory report analysis. Analyze this lab report and extract ALL laboratory values.

        Document text:
        \(text)

        For each lab value you find, extract:
        1. Test name (exactly as written)
        2. Numerical value
        3. Unit (mg/dL, g/dL, %, etc.)
        4. Reference range (if provided)
        5. Whether it's flagged as abnormal (High, Low, Critical, etc.)

        Return ONLY lab values in this exact format, one per line:
        TEST_NAME|VALUE|UNIT|REFERENCE_RANGE|ABNORMAL_FLAG

        Example:
        Glucose|95|mg/dL|70-100|Normal
        Hemoglobin|14.2|g/dL|12.0-16.0|Normal
        Total Cholesterol|220|mg/dL|<200|High

        Important:
        - Include ALL numerical lab values you can find
        - Use "unknown" for missing information
        - Use "Normal" if no abnormal flag is present
        - Be precise with test names as they appear in the document
        - Include common variations (HbA1c, A1C, Hemoglobin A1c, etc.)
        """

        let ollamaResponse = try await ollamaClient.sendChatMessage(prompt, model: mappingModel)
        let response = ollamaResponse.content
        return parseExtractedLabValues(from: response)
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
            // Hemoglobin variations
            ("hemoglobin", ["hgb", "hb", "hemoglobin_concentration"]),
            ("hemoglobin_a1c", ["hba1c", "a1c", "glycated_hemoglobin", "hemoglobin_a1c_"]),
            // Cholesterol variations
            ("cholesterol_total", ["total_cholesterol", "cholesterol", "chol_total"]),
            ("ldl_cholesterol", ["ldl", "ldl_chol", "low_density_lipoprotein"]),
            ("hdl_cholesterol", ["hdl", "hdl_chol", "high_density_lipoprotein"]),
            // Liver function variations
            ("alt_sgpt", ["alt", "sgpt", "alanine_aminotransferase"]),
            ("ast_sgot", ["ast", "sgot", "aspartate_aminotransferase"]),
            // Kidney function variations
            ("creatinine", ["creat", "serum_creatinine"]),
            ("bun", ["blood_urea_nitrogen", "urea_nitrogen"]),
            // Complete Blood Count variations
            ("wbc", ["white_blood_cell_count", "white_blood_cells", "leukocytes"]),
            ("rbc", ["red_blood_cell_count", "red_blood_cells", "erythrocytes"]),
            ("platelet_count", ["platelets", "plt", "platelet"]),
            // Thyroid variations
            ("tsh", ["thyroid_stimulating_hormone", "thyrotropin"]),
            ("free_t4", ["ft4", "free_thyroxine"]),
            ("free_t3", ["ft3", "free_triiodothyronine"])
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
        patientName: String?
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
        metadata["ai_model"] = mappingModel
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

struct BloodTestMappingError: Identifiable {
    let id = UUID()
    let error: Error
    let documentText: String
    let timestamp: Date

    var displayMessage: String {
        return error.localizedDescription
    }
}