import Foundation

// MARK: - Medical Document Model
/// Represents a medical document with OCR'd content and structured data from docling
struct MedicalDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var fileName: String
    var fileType: DocumentType
    var filePath: URL
    var thumbnailPath: URL?
    var processingStatus: ProcessingStatus

    // Medical-specific metadata
    var documentDate: Date?              // Date of the medical visit/report
    var providerName: String?            // Doctor or facility name
    var providerType: ProviderType?      // Type of provider
    var documentCategory: DocumentCategory // Type of medical document

    // Document content
    var extractedText: String?           // Full text from OCR
    var rawDoclingOutput: Data?          // Complete DoclingDocument JSON
    var extractedSections: [DocumentSection] // Structured sections

    // AI Context management
    var includeInAIContext: Bool         // Whether to include in AI doctor conversations
    var contextPriority: Int             // Priority for context inclusion (1-5, 5 being highest)

    // Health data linkage
    var extractedHealthData: [AnyHealthData] // Linked health data items

    // Standard metadata
    let importedAt: Date
    var processedAt: Date?
    var lastEditedAt: Date?              // Track when content was manually edited
    var fileSize: Int64
    var tags: [String]
    var notes: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        fileType: DocumentType,
        filePath: URL,
        thumbnailPath: URL? = nil,
        processingStatus: ProcessingStatus = .pending,
        documentDate: Date? = nil,
        providerName: String? = nil,
        providerType: ProviderType? = nil,
        documentCategory: DocumentCategory = .other,
        extractedText: String? = nil,
        rawDoclingOutput: Data? = nil,
        extractedSections: [DocumentSection] = [],
        includeInAIContext: Bool = false,
        contextPriority: Int = 3,
        extractedHealthData: [AnyHealthData] = [],
        importedAt: Date = Date(),
        processedAt: Date? = nil,
        lastEditedAt: Date? = nil,
        fileSize: Int64 = 0,
        tags: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.processingStatus = processingStatus
        self.documentDate = documentDate
        self.providerName = providerName
        self.providerType = providerType
        self.documentCategory = documentCategory
        self.extractedText = extractedText
        self.rawDoclingOutput = rawDoclingOutput
        self.extractedSections = extractedSections
        self.includeInAIContext = includeInAIContext
        self.contextPriority = contextPriority
        self.extractedHealthData = extractedHealthData
        self.importedAt = importedAt
        self.processedAt = processedAt
        self.lastEditedAt = lastEditedAt
        self.fileSize = fileSize
        self.tags = tags
        self.notes = notes
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MedicalDocument, rhs: MedicalDocument) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Provider Type
enum ProviderType: String, CaseIterable, Codable {
    case primaryCarePhysician = "primary_care"
    case specialist = "specialist"
    case imagingCenter = "imaging_center"
    case laboratory = "laboratory"
    case hospital = "hospital"
    case urgentCare = "urgent_care"
    case pharmacy = "pharmacy"
    case other = "other"

    var displayName: String {
        switch self {
        case .primaryCarePhysician:
            return "Primary Care Physician"
        case .specialist:
            return "Specialist"
        case .imagingCenter:
            return "Imaging Center"
        case .laboratory:
            return "Laboratory"
        case .hospital:
            return "Hospital"
        case .urgentCare:
            return "Urgent Care"
        case .pharmacy:
            return "Pharmacy"
        case .other:
            return "Other"
        }
    }

    var icon: String {
        switch self {
        case .primaryCarePhysician, .specialist:
            return "stethoscope"
        case .imagingCenter:
            return "camera.metering.matrix"
        case .laboratory:
            return "testtube.2"
        case .hospital:
            return "cross.case"
        case .urgentCare:
            return "cross.fill"
        case .pharmacy:
            return "pills"
        case .other:
            return "building.2"
        }
    }
}

// MARK: - Document Category
enum DocumentCategory: String, CaseIterable, Codable {
    case doctorsNote = "doctors_note"
    case imagingReport = "imaging_report"
    case labReport = "lab_report"
    case prescription = "prescription"
    case dischargeSummary = "discharge_summary"
    case operativeReport = "operative_report"
    case pathologyReport = "pathology_report"
    case consultation = "consultation"
    case vaccineRecord = "vaccine_record"
    case referral = "referral"
    case other = "other"

    var displayName: String {
        switch self {
        case .doctorsNote:
            return "Doctor's Note"
        case .imagingReport:
            return "Imaging Report"
        case .labReport:
            return "Lab Report"
        case .prescription:
            return "Prescription"
        case .dischargeSummary:
            return "Discharge Summary"
        case .operativeReport:
            return "Operative Report"
        case .pathologyReport:
            return "Pathology Report"
        case .consultation:
            return "Consultation"
        case .vaccineRecord:
            return "Vaccine Record"
        case .referral:
            return "Referral"
        case .other:
            return "Other"
        }
    }

    var icon: String {
        switch self {
        case .doctorsNote:
            return "doc.text"
        case .imagingReport:
            return "photo.on.rectangle"
        case .labReport:
            return "chart.bar.doc.horizontal"
        case .prescription:
            return "pills.circle"
        case .dischargeSummary:
            return "doc.plaintext"
        case .operativeReport:
            return "scissors"
        case .pathologyReport:
            return "microscope"
        case .consultation:
            return "person.2.circle"
        case .vaccineRecord:
            return "syringe"
        case .referral:
            return "arrow.turn.up.right"
        case .other:
            return "doc"
        }
    }

    /// Returns typical sections expected in this document category
    var expectedSections: [String] {
        switch self {
        case .doctorsNote:
            return ["Chief Complaint", "History of Present Illness", "Physical Examination",
                    "Assessment", "Plan", "Vital Signs"]
        case .imagingReport:
            return ["Clinical Indication", "Technique", "Comparison", "Findings", "Impression"]
        case .labReport:
            return ["Test Results", "Reference Ranges", "Abnormal Flags", "Comments"]
        case .prescription:
            return ["Medication", "Dosage", "Frequency", "Duration", "Instructions"]
        case .dischargeSummary:
            return ["Admission Date", "Discharge Date", "Diagnosis", "Hospital Course",
                    "Discharge Medications", "Follow-up Instructions"]
        case .operativeReport:
            return ["Preoperative Diagnosis", "Postoperative Diagnosis", "Procedure",
                    "Findings", "Complications"]
        case .pathologyReport:
            return ["Specimen", "Gross Description", "Microscopic Description",
                    "Diagnosis", "Comments"]
        case .consultation:
            return ["Reason for Consultation", "History", "Review of Systems",
                    "Impression", "Recommendations"]
        case .vaccineRecord:
            return ["Vaccine Name", "Date Administered", "Dose", "Site", "Lot Number"]
        case .referral:
            return ["Referring Provider", "Specialist", "Reason for Referral", "Clinical History"]
        case .other:
            return []
        }
    }
}

// MARK: - Document Section
/// Represents a structured section extracted from a medical document
struct DocumentSection: Identifiable, Codable, Hashable {
    let id: UUID
    var sectionType: String              // e.g., "Findings", "Impression", "Chief Complaint"
    var content: String                  // The actual text content
    var confidence: Double?              // OCR/extraction confidence (0-1)
    var startPosition: Int?              // Character position in full text
    var endPosition: Int?                // Character position in full text
    var metadata: [String: String]       // Additional metadata

    init(
        id: UUID = UUID(),
        sectionType: String,
        content: String,
        confidence: Double? = nil,
        startPosition: Int? = nil,
        endPosition: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sectionType = sectionType
        self.content = content
        self.confidence = confidence
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.metadata = metadata
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DocumentSection, rhs: DocumentSection) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Docling Output Models
/// Represents the DoclingDocument structure returned by docling
struct DoclingDocument: Codable {
    var schema_name: String              // "DoclingDocument"
    var version: String                  // Schema version
    var name: String                     // Document name
    var origin: DocumentOrigin?          // Source information
    var furniture: DocumentContent?      // Headers, footers, page numbers
    var body: DocumentContent?           // Main document content
    var groups: [[String: AnyCodable]]?  // Content groupings (array of dictionaries, not strings)

    
    struct DocumentOrigin: Codable {
        var filename: String?
        var mimetype: String?
        var binary_hash: Int64?  // Changed from String? to Int64? to match actual JSON format
    }
    
    // Custom decoder to handle groups field which may be dictionaries
    enum CodingKeys: String, CodingKey {
        case schema_name
        case version
        case name
        case origin
        case furniture
        case body
        // Skip groups - we don't use it and it has variable structure
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema_name = try container.decode(String.self, forKey: .schema_name)
        version = try container.decode(String.self, forKey: .version)
        name = try container.decode(String.self, forKey: .name)
        origin = try container.decodeIfPresent(DocumentOrigin.self, forKey: .origin)
        furniture = try container.decodeIfPresent(DocumentContent.self, forKey: .furniture)
        body = try container.decodeIfPresent(DocumentContent.self, forKey: .body)
        groups = nil  // Skip groups - not used in our extraction logic
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema_name, forKey: .schema_name)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(furniture, forKey: .furniture)
        try container.encodeIfPresent(body, forKey: .body)
        // Skip groups in encoding too
    }

    struct DocumentContent: Codable {
        var self_ref: String?            // JSON pointer reference
        var name: String?
        var children: [ContentItem]?
    }

    struct ContentItem: Codable {
        var self_ref: String?            // JSON pointer reference
        var text: String?
        var label: String?               // Type of content (paragraph, heading, table, etc.)
        var prov: [ProvenanceInfo]?      // Provenance information
        var children: [ContentItem]?     // Nested content
    }

    struct ProvenanceInfo: Codable {
        var page: Int?
        var bbox: BoundingBox?
        var charspan: [Int]?             // Character span in text
    }

    struct BoundingBox: Codable {
        var l: Double                    // Left
        var t: Double                    // Top
        var r: Double                    // Right
        var b: Double                    // Bottom
    }
}

// MARK: - Medical Document Extensions
extension MedicalDocument {
    var isProcessed: Bool {
        return processingStatus == .completed
    }

    var canBeProcessed: Bool {
        return processingStatus == .pending || processingStatus == .failed
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedDocumentDate: String {
        guard let date = documentDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var formattedProvider: String {
        if let name = providerName, !name.isEmpty {
            if let type = providerType {
                return "\(name) (\(type.displayName))"
            }
            return name
        } else if let type = providerType {
            return type.displayName
        }
        return "Unknown provider"
    }

    var summaryDescription: String {
        var parts: [String] = []

        if let date = documentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            parts.append(formatter.string(from: date))
        }

        parts.append(documentCategory.displayName)

        if let provider = providerName {
            parts.append(provider)
        }

        return parts.joined(separator: " • ")
    }

    var contextDescription: String {
        // Description used when including in AI chat context
        var description = "[\(documentCategory.displayName)"

        if let date = documentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            description += " from \(formatter.string(from: date))"
        }

        if let provider = providerName {
            description += " - \(provider)"
        }

        description += "]"

        return description
    }

    mutating func addTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
            tags.append(trimmedTag)
        }
    }

    mutating func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    mutating func addSection(_ section: DocumentSection) {
        // Add if not already present
        if !extractedSections.contains(where: { $0.id == section.id }) {
            extractedSections.append(section)
        }
    }

    mutating func updateSection(_ section: DocumentSection) {
        if let index = extractedSections.firstIndex(where: { $0.id == section.id }) {
            extractedSections[index] = section
            lastEditedAt = Date()
        }
    }

    mutating func removeSection(id: UUID) {
        extractedSections.removeAll { $0.id == id }
        lastEditedAt = Date()
    }

    func section(ofType type: String) -> DocumentSection? {
        return extractedSections.first { $0.sectionType.lowercased() == type.lowercased() }
    }

    func sections(ofType type: String) -> [DocumentSection] {
        return extractedSections.filter { $0.sectionType.lowercased() == type.lowercased() }
    }
}
