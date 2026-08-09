import Foundation

// MARK: - Medical Document Extractor
/// Service that extracts structured medical information from plain text produced on-device
/// (PDFKit direct text or Vision OCR).
class MedicalDocumentExtractor {

    // MARK: - Extraction Result
    struct ExtractionResult {
        var documentDate: Date?
        var providerName: String?
        var providerType: ProviderType?
        var documentCategory: DocumentCategory
        var extractedText: String
        var extractedSections: [DocumentSection]
    }

    // MARK: - On-Device Extraction Method (Plain Text path)
    /// Extract medical information from plain text (from NativeDocumentExtractor).
    ///
    /// - Parameters:
    ///   - text: Plain text extracted via PDFKit/Vision OCR
    ///   - fileName: Original document filename
    ///   - aiClient: Optional AI client for enhanced extraction
    ///   - extractionConfidence: Confidence from the OCR/extraction step (0-1)
    /// - Returns: Structured extraction result
    func extractFromText(
        text: String,
        fileName: String,
        aiClient: (any AIProviderInterface)?,
        extractionConfidence: Double = 0.9
    ) async throws -> ExtractionResult {
        AppLog.shared.documents("On-device medical extraction started — plain text input: \(text.count) chars, file: \(fileName)")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Return minimal result for empty text
            return ExtractionResult(
                documentDate: extractDateFromFileName(fileName),
                providerName: nil,
                providerType: nil,
                documentCategory: .other,
                extractedText: "",
                extractedSections: []
            )
        }

        // Try to detect sections from plain text using heuristic patterns
        let sections = extractSectionsFromPlainText(text)

        // Use AI to enhance extraction if available
        if let aiClient = aiClient {
            do {
                let aiEnhanced = try await enhanceWithAI(
                    text: text,
                    fileName: fileName,
                    aiClient: aiClient
                )

                AppLog.shared.documents("AI-enhanced extraction complete — category: \(aiEnhanced.documentCategory.rawValue), sections: \(aiEnhanced.sections.count), provider: \(aiEnhanced.providerName ?? "unknown")")
                return ExtractionResult(
                    documentDate: aiEnhanced.documentDate,
                    providerName: aiEnhanced.providerName,
                    providerType: aiEnhanced.providerType,
                    documentCategory: aiEnhanced.documentCategory,
                    extractedText: text,
                    extractedSections: aiEnhanced.sections.isEmpty ? sections : aiEnhanced.sections
                )
            } catch {
                AppLog.shared.documents("AI enhancement failed, falling back to basic extraction: \(error.localizedDescription)", level: .warning)
                // Fall through to basic extraction
            }
        }

        // Basic extraction without AI
        let basicInfo = extractBasicInfo(from: text, fileName: fileName)

        return ExtractionResult(
            documentDate: basicInfo.date,
            providerName: basicInfo.providerName,
            providerType: basicInfo.providerType,
            documentCategory: basicInfo.category,
            extractedText: text,
            extractedSections: sections
        )
    }

    // MARK: - Section Extraction from Plain Text
    /// Detect sections in plain text using common medical document heading patterns.
    private func extractSectionsFromPlainText(_ text: String) -> [DocumentSection] {
        var sections: [DocumentSection] = []
        let lines = text.components(separatedBy: .newlines)

        // Common medical document section headers (case-insensitive)
        let sectionPatterns: [(pattern: String, type: String)] = [
            // Lab report sections
            ("(?i)^\\s*(test\\s*results?|lab(?:oratory)?\\s*results?)\\s*:?\\s*$", "Test Results"),
            ("(?i)^\\s*(reference\\s*ranges?)\\s*:?\\s*$", "Reference Ranges"),
            ("(?i)^\\s*(specimen\\s*(?:information|details?)?)\\s*:?\\s*$", "Specimen Information"),
            ("(?i)^\\s*(comments?|notes?)\\s*:?\\s*$", "Comments"),
            // Clinical note sections
            ("(?i)^\\s*(chief\\s*complaint)\\s*:?\\s*$", "Chief Complaint"),
            ("(?i)^\\s*(history\\s*of\\s*present\\s*illness)\\s*:?\\s*$", "History of Present Illness"),
            ("(?i)^\\s*(physical\\s*exam(?:ination)?)\\s*:?\\s*$", "Physical Examination"),
            ("(?i)^\\s*(assessment\\s*(?:and|&)?\\s*plan)\\s*:?\\s*$", "Assessment and Plan"),
            ("(?i)^\\s*(vital\\s*signs?)\\s*:?\\s*$", "Vital Signs"),
            ("(?i)^\\s*(medications?)\\s*:?\\s*$", "Medications"),
            ("(?i)^\\s*(allergies)\\s*:?\\s*$", "Allergies"),
            // Imaging sections
            ("(?i)^\\s*(clinical\\s*indication)\\s*:?\\s*$", "Clinical Indication"),
            ("(?i)^\\s*(technique)\\s*:?\\s*$", "Technique"),
            ("(?i)^\\s*(findings?)\\s*:?\\s*$", "Findings"),
            ("(?i)^\\s*(impression)\\s*:?\\s*$", "Impression"),
            ("(?i)^\\s*(comparison)\\s*:?\\s*$", "Comparison"),
            // Discharge/operative
            ("(?i)^\\s*(hospital\\s*course)\\s*:?\\s*$", "Hospital Course"),
            ("(?i)^\\s*(discharge\\s*(?:medications|instructions|diagnosis))\\s*:?\\s*$", "Discharge Information"),
            ("(?i)^\\s*((?:pre|post)operative\\s*diagnosis)\\s*:?\\s*$", "Diagnosis"),
            ("(?i)^\\s*(procedure(?:\\s*performed)?)\\s*:?\\s*$", "Procedure"),
        ]

        var currentSectionType: String? = nil
        var currentContent: [String] = []
        var currentStartLine = 0

        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            // Check if this line matches a section header
            var matchedSection: String? = nil
            for (pattern, sectionType) in sectionPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) != nil {
                    matchedSection = sectionType
                    break
                }
            }

            // Also detect ALL-CAPS lines as potential section headers (common in medical docs)
            if matchedSection == nil && trimmedLine.count >= 3 && trimmedLine.count <= 60 {
                let alphaOnly = trimmedLine.filter { $0.isLetter }
                if !alphaOnly.isEmpty && alphaOnly == alphaOnly.uppercased() && alphaOnly.count >= 3 {
                    matchedSection = trimmedLine.capitalized
                }
            }

            if let newSection = matchedSection {
                // Save previous section
                if let prevType = currentSectionType, !currentContent.isEmpty {
                    let content = currentContent.joined(separator: "\n")
                    sections.append(DocumentSection(
                        sectionType: prevType,
                        content: content,
                        confidence: 0.7,
                        startPosition: currentStartLine
                    ))
                }
                currentSectionType = newSection
                currentContent = []
                currentStartLine = lineIndex
            } else if currentSectionType != nil {
                currentContent.append(trimmedLine)
            } else if sections.isEmpty {
                // Content before any section header - add as "Header" or "Content"
                if currentSectionType == nil {
                    currentSectionType = "Content"
                    currentStartLine = lineIndex
                }
                currentContent.append(trimmedLine)
            }
        }

        // Save final section
        if let lastType = currentSectionType, !currentContent.isEmpty {
            let content = currentContent.joined(separator: "\n")
            sections.append(DocumentSection(
                sectionType: lastType,
                content: content,
                confidence: 0.7,
                startPosition: currentStartLine
            ))
        }

        // If no sections were detected, create a single "Content" section with all text
        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(DocumentSection(
                sectionType: "Content",
                content: text.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: 0.5
            ))
        }

        AppLog.shared.documents("Plain text section detection complete — found \(sections.count) sections")
        return sections
    }

    // MARK: - Basic Information Extraction
    private func extractBasicInfo(from text: String, fileName: String) -> (date: Date?, providerName: String?, providerType: ProviderType?, category: DocumentCategory) {

        var extractedDate: Date? = nil
        var providerName: String? = nil
        var providerType: ProviderType? = nil
        var category: DocumentCategory = .other

        // Try to extract date from filename first
        extractedDate = extractDateFromFileName(fileName)

        // Try to extract date from text if not found in filename
        if extractedDate == nil {
            extractedDate = extractDateFromText(text)
        }

        // Try to detect document category from keywords
        category = detectDocumentCategory(from: text)

        // Try to extract provider information
        let providerInfo = extractProviderInfo(from: text, category: category)
        providerName = providerInfo.name
        providerType = providerInfo.type

        return (extractedDate, providerName, providerType, category)
    }

    // MARK: - Date Extraction
    private func extractDateFromFileName(_ fileName: String) -> Date? {
        // Common date formats in filenames: YYYY-MM-DD, MM-DD-YYYY, YYYYMMDD
        let patterns = [
            "(\\d{4})[-_](\\d{2})[-_](\\d{2})",  // YYYY-MM-DD
            "(\\d{2})[-_](\\d{2})[-_](\\d{4})",  // MM-DD-YYYY
            "(\\d{4})(\\d{2})(\\d{2})"           // YYYYMMDD
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)) {

                let components = (1..<match.numberOfRanges).compactMap { index -> String? in
                    guard let range = Range(match.range(at: index), in: fileName) else { return nil }
                    return String(fileName[range])
                }

                if components.count == 3 {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"

                    // Try different component orders
                    if let date = parseDate(components: components, formatter: formatter) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func parseDate(components: [String], formatter: DateFormatter) -> Date? {
        // Try YYYY-MM-DD
        if let year = Int(components[0]), year > 1900, year < 2100 {
            let dateString = "\(components[0])-\(components[1])-\(components[2])"
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // Try MM-DD-YYYY
        if let year = Int(components[2]), year > 1900, year < 2100 {
            let dateString = "\(components[2])-\(components[0])-\(components[1])"
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    private func extractDateFromText(_ text: String) -> Date? {
        // Look for common date patterns in text
        let patterns = [
            "(\\d{1,2})/(\\d{1,2})/(\\d{4})",                                    // MM/DD/YYYY
            "(\\d{4})-(\\d{2})-(\\d{2})",                                        // YYYY-MM-DD
            "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2}),?\\s+(\\d{4})",  // Month DD, YYYY
            "(\\d{1,2})\\s+(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{4})"    // DD Month YYYY
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                if let range = Range(match.range, in: text) {
                    let dateString = String(text[range])
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM/dd/yyyy"

                    // Try various formats
                    let formats = ["MM/dd/yyyy", "yyyy-MM-dd", "MMMM d, yyyy", "d MMMM yyyy", "MMMM dd, yyyy"]
                    for format in formats {
                        formatter.dateFormat = format
                        formatter.locale = Locale(identifier: "en_US")
                        if let date = formatter.date(from: dateString) {
                            return date
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Document Category Detection
    private func detectDocumentCategory(from text: String) -> DocumentCategory {
        let lowercasedText = text.lowercased()

        // Imaging report keywords
        if lowercasedText.contains("radiology") ||
           lowercasedText.contains("ct scan") ||
           lowercasedText.contains("mri") ||
           lowercasedText.contains("x-ray") ||
           lowercasedText.contains("ultrasound") ||
           lowercasedText.contains("imaging") ||
           lowercasedText.contains("impression:") ||
           lowercasedText.contains("findings:") {
            return .imagingReport
        }

        // Lab report keywords
        if lowercasedText.contains("laboratory") ||
           lowercasedText.contains("lab results") ||
           lowercasedText.contains("test results") ||
           lowercasedText.contains("specimen") ||
           lowercasedText.contains("reference range") {
            return .labReport
        }

        // Prescription keywords
        if lowercasedText.contains("prescription") ||
           lowercasedText.contains("rx:") ||
           lowercasedText.contains("medication:") ||
           lowercasedText.contains("dispense") ||
           lowercasedText.contains("sig:") {
            return .prescription
        }

        // Discharge summary keywords
        if lowercasedText.contains("discharge summary") ||
           lowercasedText.contains("hospital course") ||
           lowercasedText.contains("admission date") ||
           lowercasedText.contains("discharge date") {
            return .dischargeSummary
        }

        // Operative report keywords
        if lowercasedText.contains("operative report") ||
           lowercasedText.contains("procedure performed") ||
           lowercasedText.contains("operation:") ||
           lowercasedText.contains("surgeon:") {
            return .operativeReport
        }

        // Pathology report keywords
        if lowercasedText.contains("pathology") ||
           lowercasedText.contains("biopsy") ||
           lowercasedText.contains("histology") ||
           lowercasedText.contains("microscopic description") {
            return .pathologyReport
        }

        // Consultation keywords
        if lowercasedText.contains("consultation") ||
           lowercasedText.contains("consult note") ||
           lowercasedText.contains("reason for consultation") {
            return .consultation
        }

        // Vaccine record keywords
        if lowercasedText.contains("vaccine") ||
           lowercasedText.contains("immunization") ||
           lowercasedText.contains("vaccination") {
            return .vaccineRecord
        }

        // Default to doctor's note if it has typical clinical note sections
        if lowercasedText.contains("chief complaint") ||
           lowercasedText.contains("history of present illness") ||
           lowercasedText.contains("physical examination") ||
           lowercasedText.contains("assessment and plan") {
            return .doctorsNote
        }

        return .other
    }

    // MARK: - Provider Information Extraction
    private func extractProviderInfo(from text: String, category: DocumentCategory) -> (name: String?, type: ProviderType?) {
        var providerName: String? = nil
        var providerType: ProviderType? = nil

        // Try to extract provider name from common patterns
        let patterns = [
            "(?:Dr\\.|Doctor)\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)",
            "Physician:\\s*([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)",
            "Provider:\\s*([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)",
            "Radiologist:\\s*([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                if let range = Range(match.range(at: 1), in: text) {
                    providerName = String(text[range])
                    break
                }
            }
        }

        // Infer provider type from document category
        switch category {
        case .imagingReport:
            providerType = .imagingCenter
        case .labReport:
            providerType = .laboratory
        case .prescription:
            providerType = .pharmacy
        case .dischargeSummary, .operativeReport:
            providerType = .hospital
        case .consultation:
            providerType = .specialist
        default:
            providerType = .primaryCarePhysician
        }

        return (providerName, providerType)
    }

    // MARK: - AI-Enhanced Extraction
    private struct AIEnhancedInfo {
        var documentDate: Date?
        var providerName: String?
        var providerType: ProviderType?
        var documentCategory: DocumentCategory
        var sections: [DocumentSection]
    }

    private func enhanceWithAI(
        text: String,
        fileName: String,
        aiClient: any AIProviderInterface
    ) async throws -> AIEnhancedInfo {

        // Chunk the FULL text instead of truncating — small chunks for the
        // on-device model (memory bound), larger for cloud providers.
        let chunkSize = aiClient is MLXOnDeviceClient ? 2000 : 12000
        let maxChunks = 6 // bound latency on very long documents
        let chunks = chunkText(text, maxChunkSize: chunkSize)
        let analysisChunks = Array(chunks.prefix(maxChunks))
        if chunks.count > analysisChunks.count {
            AppLog.shared.documents("AI enhancement: analyzing first \(analysisChunks.count) of \(chunks.count) chunks (\(text.count) chars total)", level: .warning)
        }

        // First chunk: metadata + sections. Remaining chunks: sections only.
        var merged = try await enhanceChunk(
            analysisChunks[0],
            fileName: fileName,
            aiClient: aiClient,
            fallbackText: text,
            includeMetadata: true
        )

        for chunk in analysisChunks.dropFirst() {
            do {
                let chunkInfo = try await enhanceChunk(
                    chunk,
                    fileName: fileName,
                    aiClient: aiClient,
                    fallbackText: chunk,
                    includeMetadata: merged.documentDate == nil || merged.providerName == nil
                )
                merged.sections.append(contentsOf: chunkInfo.sections)
                if merged.documentDate == nil { merged.documentDate = chunkInfo.documentDate }
                if merged.providerName == nil { merged.providerName = chunkInfo.providerName }
                if merged.providerType == nil { merged.providerType = chunkInfo.providerType }
                if merged.documentCategory == .other, chunkInfo.documentCategory != .other {
                    merged.documentCategory = chunkInfo.documentCategory
                }
            } catch {
                AppLog.shared.documents("AI enhancement failed for a chunk, continuing with partial results: \(error.localizedDescription)", level: .warning)
            }
        }

        // Merge duplicate section types produced by different chunks
        merged.sections = mergeSections(merged.sections)
        return merged
    }

    private func enhanceChunk(
        _ chunk: String,
        fileName: String,
        aiClient: any AIProviderInterface,
        fallbackText: String,
        includeMetadata: Bool
    ) async throws -> AIEnhancedInfo {
        let metadataFields = includeMetadata ? """
          "document_date": "YYYY-MM-DD or null",
          "provider_name": "name or null",
          "provider_type": "primary_care, specialist, imaging_center, laboratory, hospital, urgent_care, pharmacy, or other",
          "document_category": "doctors_note, imaging_report, lab_report, prescription, discharge_summary, operative_report, pathology_report, consultation, vaccine_record, referral, or other",
        """ : ""

        let prompt = """
        Analyze this medical document and extract key information. Respond ONLY with a valid JSON object, no other text.

        Document filename: \(fileName)

        Document text:
        \(chunk)

        Extract the following information as JSON:
        {
        \(metadataFields)
          "sections": [
            {
              "section_type": "section name",
              "content": "section text"
            }
          ]
        }

        Identify the most relevant sections in the document (e.g., Chief Complaint, Findings, Impression, Medications, etc.).
        """

        let responseContent = try await Self.requestCompletion(prompt, from: aiClient)
        return try parseAIResponse(responseContent, fallbackText: fallbackText, fileName: fileName)
    }

    /// Bridges to the main-actor-isolated AI clients and returns only the response text.
    /// `AIResponse` carries a `[String: Any]` metadata bag and so is not `Sendable`; keeping
    /// it on the main actor lets the surrounding extraction and parsing stay off it.
    @MainActor
    private static func requestCompletion(
        _ prompt: String,
        from aiClient: any AIProviderInterface
    ) async throws -> String {
        try await aiClient.sendMessage(prompt, context: "").content
    }

    /// Split text into chunks on line boundaries.
    private func chunkText(_ text: String, maxChunkSize: Int) -> [String] {
        guard text.count > maxChunkSize else { return [text] }

        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentSize = 0

        for line in text.components(separatedBy: .newlines) {
            let lineSize = line.count + 1
            if currentSize + lineSize > maxChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk.joined(separator: "\n"))
                currentChunk = []
                currentSize = 0
            }
            currentChunk.append(line)
            currentSize += lineSize
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: "\n"))
        }
        return chunks
    }

    /// Merge sections with the same type (from different chunks) into one.
    private func mergeSections(_ sections: [DocumentSection]) -> [DocumentSection] {
        var merged: [DocumentSection] = []
        var indexByType: [String: Int] = [:]

        for section in sections {
            let typeKey = section.sectionType.lowercased()
            if let existingIndex = indexByType[typeKey] {
                merged[existingIndex].content += "\n" + section.content
            } else {
                indexByType[typeKey] = merged.count
                merged.append(section)
            }
        }
        return merged
    }

    private func parseAIResponse(_ response: String, fallbackText: String, fileName: String) throws -> AIEnhancedInfo {
        // Try to extract JSON from response (AI might include extra text)
        guard let jsonData = extractJSON(from: response)?.data(using: .utf8) else {
            // Fallback to basic extraction
            let basicInfo = extractBasicInfo(from: fallbackText, fileName: fileName)
            return AIEnhancedInfo(
                documentDate: basicInfo.date,
                providerName: basicInfo.providerName,
                providerType: basicInfo.providerType,
                documentCategory: basicInfo.category,
                sections: []
            )
        }

        do {
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

            let documentDate: Date?
            if let dateString = json?["document_date"] as? String,
               let date = ISO8601DateFormatter().date(from: dateString) {
                documentDate = date
            } else {
                documentDate = extractDateFromFileName(fileName) ?? extractDateFromText(fallbackText)
            }

            let providerName = json?["provider_name"] as? String
            let providerTypeString = json?["provider_type"] as? String
            let providerType = providerTypeString.flatMap { ProviderType(rawValue: $0) }

            let categoryString = json?["document_category"] as? String ?? "other"
            let category = DocumentCategory(rawValue: categoryString) ?? .other

            var sections: [DocumentSection] = []
            if let sectionsArray = json?["sections"] as? [[String: Any]] {
                for sectionDict in sectionsArray {
                    if let sectionType = sectionDict["section_type"] as? String,
                       let content = sectionDict["content"] as? String {
                        sections.append(DocumentSection(
                            sectionType: sectionType,
                            content: content
                        ))
                    }
                }
            }

            return AIEnhancedInfo(
                documentDate: documentDate,
                providerName: providerName,
                providerType: providerType,
                documentCategory: category,
                sections: sections
            )
        } catch {
            // Fallback to basic extraction
            let basicInfo = extractBasicInfo(from: fallbackText, fileName: fileName)
            return AIEnhancedInfo(
                documentDate: basicInfo.date,
                providerName: basicInfo.providerName,
                providerType: basicInfo.providerType,
                documentCategory: basicInfo.category,
                sections: []
            )
        }
    }

    private func extractJSON(from text: String) -> String? {
        // Strip <think> reasoning blocks and markdown code fences first
        var cleaned = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"```(?:json)?"#,
            with: "",
            options: .regularExpression
        )

        // Balanced-brace scan from the first '{' — robust against trailing prose
        guard let startIndex = cleaned.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var index = startIndex

        while index < cleaned.endIndex {
            let char = cleaned[index]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(cleaned[startIndex...index])
                    }
                }
            }
            index = cleaned.index(after: index)
        }

        // Unbalanced (truncated response) — fall back to first-{ / last-} slice
        if let endIndex = cleaned.lastIndex(of: "}"), endIndex > startIndex {
            return String(cleaned[startIndex...endIndex])
        }
        return nil
    }
}
