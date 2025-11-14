import Foundation

// MARK: - Base Health Data Protocol
protocol HealthDataProtocol: Identifiable, Codable {
    var id: UUID { get }
    var type: HealthDataType { get }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var metadata: [String: String]? { get set }
}

// MARK: - Health Data Types
enum HealthDataType: String, CaseIterable, Codable {
    case personalInfo = "personal_info"
    case bloodTest = "blood_test"
    case imagingReport = "imaging_report"
    case healthCheckup = "health_checkup"
    
    var displayName: String {
        switch self {
        case .personalInfo:
            return "Personal Information"
        case .bloodTest:
            return "Lab Results"
        case .imagingReport:
            return "Imaging Reports"
        case .healthCheckup:
            return "Medical Visits"
        }
    }
    
    var icon: String {
        switch self {
        case .personalInfo:
            return "person.fill"
        case .bloodTest:
            return "testtube.2"
        case .imagingReport:
            return "camera.metering.matrix"
        case .healthCheckup:
            return "doc.text"
        }
    }
    
    var shortName: String {
        switch self {
        case .personalInfo:
            return "Personal"
        case .bloodTest:
            return "Lab"
        case .imagingReport:
            return "Imaging"
        case .healthCheckup:
            return "Visits"
        }
    }
    
    /// Maps HealthDataType to corresponding DocumentCategory values for filtering medical documents
    var relatedDocumentCategories: [DocumentCategory] {
        switch self {
        case .imagingReport:
            return [.imagingReport]
        case .bloodTest:
            return [.labReport]
        case .healthCheckup:
            return [.doctorsNote, .consultation]
        case .personalInfo:
            // Personal info doesn't map to document categories
            return []
        }
    }
}

// MARK: - Supporting Enums
enum Gender: String, CaseIterable, Codable {
    case male = "male"
    case female = "female"
    case other = "other"
    case preferNotToSay = "prefer_not_to_say"
    
    var displayName: String {
        switch self {
        case .male:
            return "Male"
        case .female:
            return "Female"
        case .other:
            return "Other"
        case .preferNotToSay:
            return "Prefer not to say"
        }
    }
}

enum BloodType: String, CaseIterable, Codable {
    case aPositive = "A+"
    case aNegative = "A-"
    case bPositive = "B+"
    case bNegative = "B-"
    case abPositive = "AB+"
    case abNegative = "AB-"
    case oPositive = "O+"
    case oNegative = "O-"
    case unknown = "unknown"
    
    var displayName: String {
        return rawValue
    }
}