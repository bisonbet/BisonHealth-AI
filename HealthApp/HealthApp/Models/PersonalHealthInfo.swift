import Foundation

// MARK: - Personal Health Information
struct PersonalHealthInfo: HealthDataProtocol {
    let id: UUID
    var type: HealthDataType { .personalInfo }
    
    // Basic Information
    var name: String?
    var dateOfBirth: Date?
    var gender: Gender?
    var height: Measurement<UnitLength>?
    var weight: Measurement<UnitMass>?
    var bloodType: BloodType?
    
    // Medical Information
    var allergies: [String]
    var medications: [Medication]
    var medicalHistory: [MedicalCondition]
    var emergencyContacts: [EmergencyContact]
    
    // Protocol Requirements
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        name: String? = nil,
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        height: Measurement<UnitLength>? = nil,
        weight: Measurement<UnitMass>? = nil,
        bloodType: BloodType? = nil,
        allergies: [String] = [],
        medications: [Medication] = [],
        medicalHistory: [MedicalCondition] = [],
        emergencyContacts: [EmergencyContact] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.height = height
        self.weight = weight
        self.bloodType = bloodType
        self.allergies = allergies
        self.medications = medications
        self.medicalHistory = medicalHistory
        self.emergencyContacts = emergencyContacts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Supporting Structures
struct Medication: Codable, Identifiable {
    let id: UUID
    var name: String
    var dosage: String?
    var frequency: String?
    var prescribedBy: String?
    var startDate: Date?
    var endDate: Date?
    var notes: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        dosage: String? = nil,
        frequency: String? = nil,
        prescribedBy: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.prescribedBy = prescribedBy
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
    }
}

struct MedicalCondition: Codable, Identifiable {
    let id: UUID
    var name: String
    var diagnosedDate: Date?
    var diagnosedBy: String?
    var severity: ConditionSeverity?
    var status: ConditionStatus
    var notes: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        diagnosedDate: Date? = nil,
        diagnosedBy: String? = nil,
        severity: ConditionSeverity? = nil,
        status: ConditionStatus = .active,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.diagnosedDate = diagnosedDate
        self.diagnosedBy = diagnosedBy
        self.severity = severity
        self.status = status
        self.notes = notes
    }
}

struct EmergencyContact: Codable, Identifiable {
    let id: UUID
    var name: String
    var relationship: String?
    var phoneNumber: String
    var email: String?
    var isPrimary: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        relationship: String? = nil,
        phoneNumber: String,
        email: String? = nil,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.phoneNumber = phoneNumber
        self.email = email
        self.isPrimary = isPrimary
    }
}

// MARK: - Supporting Enums
enum ConditionSeverity: String, CaseIterable, Codable {
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"
    case critical = "critical"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

enum ConditionStatus: String, CaseIterable, Codable {
    case active = "active"
    case resolved = "resolved"
    case chronic = "chronic"
    case monitoring = "monitoring"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

// MARK: - Validation Extensions
extension PersonalHealthInfo {
    var isValid: Bool {
        // Basic validation - at least name should be provided
        return name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    
    var completionPercentage: Double {
        var completedFields = 0
        let totalFields = 6 // name, dob, gender, height, weight, bloodType
        
        if name?.isEmpty == false { completedFields += 1 }
        if dateOfBirth != nil { completedFields += 1 }
        if gender != nil { completedFields += 1 }
        if height != nil { completedFields += 1 }
        if weight != nil { completedFields += 1 }
        if bloodType != nil { completedFields += 1 }
        
        return Double(completedFields) / Double(totalFields)
    }
}