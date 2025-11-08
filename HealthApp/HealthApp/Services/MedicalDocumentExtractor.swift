import Foundation

// MARK: - Medical Document Extractor
/// Service that extracts structured medical information from docling output
class MedicalDocumentExtractor {

    // MARK: - Extraction Result
    struct ExtractionResult {
        var documentDate: Date?
        var providerName: String?
        var providerType: ProviderType?
        var documentCategory: DocumentCategory
        var extractedText: String
        var extractedSections: [DocumentSection]
        var rawDoclingOutput: Data?
    }

    // MARK: - Main Extraction Method
    func extractMedicalInformation(
        from doclingOutput: Data,
        fileName: String,
        aiClient: AIProviderProtocol?
    ) async throws -> ExtractionResult {

        // Parse docling JSON output
        let doclingDocument = try JSONDecoder().decode(DoclingDocument.self, from: doclingOutput)

        // Extract full text
        let fullText = extractFullText(from: doclingDocument)

        // Try to extract structured sections
        var sections = extractSections(from: doclingDocument)

        // Use AI to enhance extraction if available
        if let aiClient = aiClient, !fullText.isEmpty {
            let aiEnhanced = try await enhanceWithAI(
                text: fullText,
                fileName: fileName,
                aiClient: aiClient
            )

            return ExtractionResult(
                documentDate: aiEnhanced.documentDate,
                providerName: aiEnhanced.providerName,
                providerType: aiEnhanced.providerType,
                documentCategory: aiEnhanced.documentCategory,
                extractedText: fullText,
                extractedSections: aiEnhanced.sections.isEmpty ? sections : aiEnhanced.sections,
                rawDoclingOutput: doclingOutput
            )
        } else {
            // Fallback to basic extraction
            let basicInfo = extractBasicInfo(from: fullText, fileName: fileName)

            return ExtractionResult(
                documentDate: basicInfo.date,
                providerName: basicInfo.providerName,
                providerType: basicInfo.providerType,
                documentCategory: basicInfo.category,
                extractedText: fullText,
                extractedSections: sections,
                rawDoclingOutput: doclingOutput
            )
        }
    }

    // MARK: - Extract Full Text from Docling Output
    private func extractFullText(from doclingDocument: DoclingDocument) -> String {
        var textParts: [String] = []

        // Extract from body
        if let body = doclingDocument.body {
            extractTextRecursive(from: body, into: &textParts)
        }

        return textParts.joined(separator: "\n\n")
    }

    private func extractTextRecursive(from content: DoclingDocument.DocumentContent, into textParts: inout [String]) {
        if let children = content.children {
            for child in children {
                if let text = child.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    textParts.append(text)
                }

                // Recurse if there are nested children
                if let nestedChildren = child.children {
                    for nested in nestedChildren {
                        if let nestedText = nested.text, !nestedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            textParts.append(nestedText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Extract Sections from Docling Output
    private func extractSections(from doclingDocument: DoclingDocument) -> [DocumentSection] {
        var sections: [DocumentSection] = []
        var currentSection: (type: String, content: [String])? = nil

        if let body = doclingDocument.body, let children = body.children {
            for child in children {
                // Check if this is a heading (potential section start)
                if let label = child.label, label.lowercased().contains("heading") || label.lowercased().contains("title") {
                    // Save previous section if exists
                    if let prevSection = currentSection, !prevSection.content.isEmpty {
                        sections.append(DocumentSection(
                            sectionType: prevSection.type,
                            content: prevSection.content.joined(separator: "\n")
                        ))
                    }

                    // Start new section
                    currentSection = (type: child.text ?? "Unknown Section", content: [])
                } else if let text = child.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Add text to current section
                    if currentSection != nil {
                        currentSection?.content.append(text)
                    } else {
                        // No section yet, create a default one
                        currentSection = (type: "Content", content: [text])
                    }
                }
            }
        }

        // Add final section
        if let finalSection = currentSection, !finalSection.content.isEmpty {
            sections.append(DocumentSection(
                sectionType: finalSection.type,
                content: finalSection.content.joined(separator: "\n")
            ))
        }

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
        aiClient: AIProviderProtocol
    ) async throws -> AIEnhancedInfo {

        // Truncate text if too long (keep first ~4000 characters for analysis)
        let analysisText = String(text.prefix(4000))

        let prompt = """
        Analyze this medical document and extract key information. Respond ONLY with a valid JSON object, no other text.

        Document filename: \(fileName)

        Document text:
        \(analysisText)

        Extract the following information as JSON:
        {
          "document_date": "YYYY-MM-DD or null",
          "provider_name": "name or null",
          "provider_type": "primary_care, specialist, imaging_center, laboratory, hospital, urgent_care, pharmacy, or other",
          "document_category": "doctors_note, imaging_report, lab_report, prescription, discharge_summary, operative_report, pathology_report, consultation, vaccine_record, referral, or other",
          "sections": [
            {
              "section_type": "section name",
              "content": "section text"
            }
          ]
        }

        Identify the most relevant sections in the document (e.g., Chief Complaint, Findings, Impression, Medications, etc.).
        """

        let response = try await aiClient.sendMessage(prompt)

        // Parse AI response
        return try parseAIResponse(response, fallbackText: text, fileName: fileName)
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
        // Try to find JSON object in text
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }
        return nil
    }
}
