import Foundation

// MARK: - Health Document Model
struct HealthDocument: Identifiable, Codable {
    let id: UUID
    var fileName: String
    var fileType: DocumentType
    var filePath: URL
    var thumbnailPath: URL?
    var processingStatus: ProcessingStatus
    var extractedData: [AnyHealthData]
    let importedAt: Date
    var processedAt: Date?
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
        extractedData: [AnyHealthData] = [],
        importedAt: Date = Date(),
        processedAt: Date? = nil,
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
        self.extractedData = extractedData
        self.importedAt = importedAt
        self.processedAt = processedAt
        self.fileSize = fileSize
        self.tags = tags
        self.notes = notes
    }
}

// MARK: - Document Type
enum DocumentType: String, CaseIterable, Codable {
    case pdf = "pdf"
    case doc = "doc"
    case docx = "docx"
    case jpeg = "jpeg"
    case jpg = "jpg"
    case png = "png"
    case heic = "heic"
    case other = "other"
    
    var displayName: String {
        return rawValue.uppercased()
    }
    
    var icon: String {
        switch self {
        case .pdf:
            return "doc.richtext"
        case .doc, .docx:
            return "doc.text"
        case .jpeg, .jpg, .png, .heic:
            return "photo"
        case .other:
            return "doc"
        }
    }
    
    var isImage: Bool {
        switch self {
        case .jpeg, .jpg, .png, .heic:
            return true
        default:
            return false
        }
    }
    
    var isDocument: Bool {
        switch self {
        case .pdf, .doc, .docx:
            return true
        default:
            return false
        }
    }
    
    static func from(fileExtension: String) -> DocumentType {
        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "doc":
            return .doc
        case "docx":
            return .docx
        case "jpeg":
            return .jpeg
        case "jpg":
            return .jpg
        case "png":
            return .png
        case "heic":
            return .heic
        default:
            return .other
        }
    }
}

// MARK: - Processing Status
enum ProcessingStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case queued = "queued"
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
        }
    }
    
    var icon: String {
        switch self {
        case .pending:
            return "clock"
        case .processing:
            return "gear"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        case .queued:
            return "list.bullet"
        }
    }
}

// MARK: - Type-Erased Health Data
struct AnyHealthData: Codable {
    let type: HealthDataType
    let id: UUID
    private let _data: Data
    
    init<T: HealthDataProtocol>(_ healthData: T) throws {
        self.type = healthData.type
        self.id = healthData.id
        self._data = try JSONEncoder().encode(healthData)
    }
    
    func decode<T: HealthDataProtocol>(as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: _data)
    }
}

// MARK: - Document Extensions
extension HealthDocument {
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
    
    var extractedDataSummary: String {
        if extractedData.isEmpty {
            return "No data extracted"
        }
        
        let groupedData = Dictionary(grouping: extractedData) { $0.type }
        let summary = groupedData.map { type, items in
            "\(items.count) \(type.displayName.lowercased())"
        }.joined(separator: ", ")
        
        return summary
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
}