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

// MARK: - Personal Info Subcategories
/// Subcategories for granular personal information context selection
enum PersonalInfoCategory: String, CaseIterable, Codable {
    case basicInfo = "basic_info"
    case medicalHistory = "medical_history"
    case coreVitals = "core_vitals"
    case extendedVitals = "extended_vitals"

    var displayName: String {
        switch self {
        case .basicInfo:
            return "Basic Info"
        case .medicalHistory:
            return "Medical History"
        case .coreVitals:
            return "Core Vitals"
        case .extendedVitals:
            return "Extended Vitals"
        }
    }

    var icon: String {
        switch self {
        case .basicInfo:
            return "person.text.rectangle"
        case .medicalHistory:
            return "heart.text.square"
        case .coreVitals:
            return "waveform.path.ecg"
        case .extendedVitals:
            return "bed.double"
        }
    }

    var description: String {
        switch self {
        case .basicInfo:
            return "Demographics, allergies, medications, supplements"
        case .medicalHistory:
            return "Personal conditions, family history"
        case .coreVitals:
            return "Blood pressure, heart rate"
        case .extendedVitals:
            return "Sleep, temperature, oxygen, weight"
        }
    }

    /// Estimated base tokens for this category (actual varies with data)
    var estimatedBaseTokens: Int {
        switch self {
        case .basicInfo:
            return 50  // Base demographics
        case .medicalHistory:
            return 30  // Base structure
        case .coreVitals:
            return 80  // BP + HR readings
        case .extendedVitals:
            return 100 // Multiple vital types + sleep
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