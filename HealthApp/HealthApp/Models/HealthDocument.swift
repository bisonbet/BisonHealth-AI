import Foundation

// MARK: - DEPRECATED: HealthDocument has been replaced by MedicalDocument
// This file now only contains shared types used by MedicalDocument and other components

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

// MARK: - End of shared types
// HealthDocument struct and extensions have been removed - use MedicalDocument instead