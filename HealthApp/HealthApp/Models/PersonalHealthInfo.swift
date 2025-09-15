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
    var personalMedicalHistory: [MedicalCondition]
    var familyHistory: FamilyMedicalHistory
    
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
        personalMedicalHistory: [MedicalCondition] = [],
        familyHistory: FamilyMedicalHistory = FamilyMedicalHistory(),
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
        self.personalMedicalHistory = personalMedicalHistory
        self.familyHistory = familyHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Medication Structures

struct Medication: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var dosage: Dosage
    var frequency: Frequency
    var prescribedBy: String?
    var startDate: Date?
    var endDate: MedicationEndDate?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        dosage: Dosage = Dosage(),
        frequency: Frequency = .daily,
        prescribedBy: String? = nil,
        startDate: Date? = nil,
        endDate: MedicationEndDate? = nil,
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

    var isOngoing: Bool {
        switch endDate {
        case .ongoing, .none:
            return true
        case .specific:
            return false
        }
    }

    var displayText: String {
        let dosageText = dosage.displayText
        let frequencyText = frequency.displayName
        return "\(name) - \(dosageText), \(frequencyText)"
    }
}

enum MedicationEndDate: Codable, Hashable {
    case ongoing
    case specific(Date)

    var displayText: String {
        switch self {
        case .ongoing:
            return "Ongoing"
        case .specific(let date):
            return DateFormatter.mediumDate.string(from: date)
        }
    }

    // Codable conformance
    private enum CodingKeys: String, CodingKey {
        case type, date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ongoing:
            try container.encode("ongoing", forKey: .type)
        case .specific(let date):
            try container.encode("specific", forKey: .type)
            try container.encode(date, forKey: .date)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ongoing":
            self = .ongoing
        case "specific":
            let date = try container.decode(Date.self, forKey: .date)
            self = .specific(date)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid medication end date type")
        }
    }
}

struct Dosage: Codable, Hashable {
    var value: Double = 0.0
    var unit: DosageUnit = .mg

    var displayText: String {
        if value == 0.0 {
            return "Dosage not specified"
        }
        return "\(value.cleanString) \(unit.displayName)"
    }
}

enum DosageUnit: String, CaseIterable, Codable, Hashable {
    case mg, ml, g, mcg, iu, tablet, capsule, drop, patch, puff, unit
    
    var displayName: String {
        return rawValue.capitalized
    }
}

enum Frequency: Codable, Hashable {
    case daily
    case twiceDaily
    case threeTimesDaily
    case weekly
    case other(String)

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .twiceDaily: return "Twice a day"
        case .threeTimesDaily: return "Three times a day"
        case .weekly: return "Weekly"
        case .other(let custom): return custom.isEmpty ? "Other" : custom
        }
    }
    
    // Codable conformance
    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily: try container.encode("daily", forKey: .type)
        case .twiceDaily: try container.encode("twiceDaily", forKey: .type)
        case .threeTimesDaily: try container.encode("threeTimesDaily", forKey: .type)
        case .weekly: try container.encode("weekly", forKey: .type)
        case .other(let value):
            try container.encode("other", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "daily": self = .daily
        case "twiceDaily": self = .twiceDaily
        case "threeTimesDaily": self = .threeTimesDaily
        case "weekly": self = .weekly
        case "other":
            let value = try container.decode(String.self, forKey: .value)
            self = .other(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid frequency type")
        }
    }
}

// MARK: - Medical History

struct MedicalCondition: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var diagnosedDate: Date?
    var status: MedicalConditionStatus
    var severity: MedicalConditionSeverity?
    var notes: String?
    var treatingPhysician: String?

    init(
        id: UUID = UUID(),
        name: String,
        diagnosedDate: Date? = nil,
        status: MedicalConditionStatus = .active,
        severity: MedicalConditionSeverity? = nil,
        notes: String? = nil,
        treatingPhysician: String? = nil
    ) {
        self.id = id
        self.name = name
        self.diagnosedDate = diagnosedDate
        self.status = status
        self.severity = severity
        self.notes = notes
        self.treatingPhysician = treatingPhysician
    }

    var displayText: String {
        var text = name
        if let severity = severity {
            text += " (\(severity.displayName))"
        }
        text += " - \(status.displayName)"
        return text
    }
}

enum MedicalConditionStatus: String, CaseIterable, Codable, Hashable {
    case active = "active"
    case resolved = "resolved"
    case chronic = "chronic"
    case monitoring = "monitoring"
    case inactive = "inactive"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .resolved: return "Resolved"
        case .chronic: return "Chronic"
        case .monitoring: return "Monitoring"
        case .inactive: return "Inactive"
        }
    }
}

enum MedicalConditionSeverity: String, CaseIterable, Codable, Hashable {
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"

    var displayName: String {
        return rawValue.capitalized
    }
}

// MARK: - Family Medical History

struct FamilyMedicalHistory: Codable, Hashable {
    var mother: String? = ""
    var father: String? = ""
    var maternalGrandmother: String? = ""
    var maternalGrandfather: String? = ""
    var paternalGrandmother: String? = ""
    var paternalGrandfather: String? = ""
    var siblings: String? = ""
    var other: String? = ""
}

// MARK: - Other Supporting Structures

// MARK: - Extensions

extension Double {
    var cleanString: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
}


