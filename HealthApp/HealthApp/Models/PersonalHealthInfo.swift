import Foundation
import SwiftUI

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
    var supplements: [Supplement] = []
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
        supplements: [Supplement] = [],
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
        self.supplements = supplements
        self.personalMedicalHistory = personalMedicalHistory
        self.familyHistory = familyHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    // Custom Codable implementation for backward compatibility
    private enum CodingKeys: String, CodingKey {
        case id, name, dateOfBirth, gender, height, weight, bloodType
        case allergies, medications, supplements
        case personalMedicalHistory, familyHistory
        case createdAt, updatedAt, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        dateOfBirth = try container.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        height = try container.decodeIfPresent(Measurement<UnitLength>.self, forKey: .height)
        weight = try container.decodeIfPresent(Measurement<UnitMass>.self, forKey: .weight)
        bloodType = try container.decodeIfPresent(BloodType.self, forKey: .bloodType)

        allergies = try container.decode([String].self, forKey: .allergies)
        medications = try container.decode([Medication].self, forKey: .medications)
        // Use decodeIfPresent for backward compatibility with existing data
        supplements = try container.decodeIfPresent([Supplement].self, forKey: .supplements) ?? []
        personalMedicalHistory = try container.decode([MedicalCondition].self, forKey: .personalMedicalHistory)
        familyHistory = try container.decode(FamilyMedicalHistory.self, forKey: .familyHistory)

        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
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

// MARK: - Supplement Structures

struct Supplement: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: SupplementCategory
    var dosage: Dosage
    var frequency: Frequency
    var startDate: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        category: SupplementCategory = .other,
        dosage: Dosage = Dosage(),
        frequency: Frequency = .daily,
        startDate: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.dosage = dosage
        self.frequency = frequency
        self.startDate = startDate
        self.notes = notes
    }

    var displayText: String {
        let dosageText = dosage.displayText
        let frequencyText = frequency.displayName
        return "\(name) - \(dosageText), \(frequencyText)"
    }
}

enum SupplementCategory: String, CaseIterable, Codable, Hashable {
    case vitamin
    case mineral
    case herb
    case aminoAcid
    case fatty acid = "fattyAcid"
    case probiotic
    case protein
    case fiber
    case other

    var displayName: String {
        switch self {
        case .vitamin: return "Vitamin"
        case .mineral: return "Mineral"
        case .herb: return "Herbal"
        case .aminoAcid: return "Amino Acid"
        case .fattyAcid: return "Fatty Acid"
        case .probiotic: return "Probiotic"
        case .protein: return "Protein"
        case .fiber: return "Fiber"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .vitamin: return .purple
        case .mineral: return .orange
        case .herb: return .green
        case .aminoAcid: return .blue
        case .fattyAcid: return .teal
        case .probiotic: return .pink
        case .protein: return .red
        case .fiber: return .brown
        case .other: return .gray
        }
    }
}

// MARK: - Supplement Database

struct SupplementTemplate: Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: SupplementCategory
    let defaultDosage: Dosage
    let defaultFrequency: Frequency
    let commonUses: String

    init(
        id: UUID = UUID(),
        name: String,
        category: SupplementCategory,
        defaultDosage: Dosage,
        defaultFrequency: Frequency = .daily,
        commonUses: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultDosage = defaultDosage
        self.defaultFrequency = defaultFrequency
        self.commonUses = commonUses
    }

    func toSupplement() -> Supplement {
        Supplement(
            name: name,
            category: category,
            dosage: defaultDosage,
            frequency: defaultFrequency,
            startDate: Date()
        )
    }
}

// Comprehensive supplement database
extension SupplementTemplate {
    static let database: [SupplementTemplate] = [
        // Vitamins
        SupplementTemplate(name: "Vitamin A", category: .vitamin, defaultDosage: Dosage(value: 3000, unit: .mcg), commonUses: "Vision, immune function, skin health"),
        SupplementTemplate(name: "Vitamin B1 (Thiamine)", category: .vitamin, defaultDosage: Dosage(value: 1.2, unit: .mg), commonUses: "Energy metabolism, nerve function"),
        SupplementTemplate(name: "Vitamin B2 (Riboflavin)", category: .vitamin, defaultDosage: Dosage(value: 1.3, unit: .mg), commonUses: "Energy production, cellular function"),
        SupplementTemplate(name: "Vitamin B3 (Niacin)", category: .vitamin, defaultDosage: Dosage(value: 16, unit: .mg), commonUses: "Energy metabolism, DNA repair"),
        SupplementTemplate(name: "Vitamin B5 (Pantothenic Acid)", category: .vitamin, defaultDosage: Dosage(value: 5, unit: .mg), commonUses: "Energy metabolism, hormone synthesis"),
        SupplementTemplate(name: "Vitamin B6 (Pyridoxine)", category: .vitamin, defaultDosage: Dosage(value: 1.7, unit: .mg), commonUses: "Protein metabolism, neurotransmitter synthesis"),
        SupplementTemplate(name: "Vitamin B7 (Biotin)", category: .vitamin, defaultDosage: Dosage(value: 30, unit: .mcg), commonUses: "Hair, skin, and nail health"),
        SupplementTemplate(name: "Vitamin B9 (Folate)", category: .vitamin, defaultDosage: Dosage(value: 400, unit: .mcg), commonUses: "DNA synthesis, cell division"),
        SupplementTemplate(name: "Vitamin B12 (Cobalamin)", category: .vitamin, defaultDosage: Dosage(value: 2.4, unit: .mcg), commonUses: "Red blood cell formation, nerve function"),
        SupplementTemplate(name: "Vitamin C", category: .vitamin, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Immune support, antioxidant, collagen synthesis"),
        SupplementTemplate(name: "Vitamin D", category: .vitamin, defaultDosage: Dosage(value: 2000, unit: .iu), commonUses: "Bone health, immune function"),
        SupplementTemplate(name: "Vitamin D3", category: .vitamin, defaultDosage: Dosage(value: 2000, unit: .iu), commonUses: "Bone health, immune function, mood"),
        SupplementTemplate(name: "Vitamin E", category: .vitamin, defaultDosage: Dosage(value: 15, unit: .mg), commonUses: "Antioxidant, skin health"),
        SupplementTemplate(name: "Vitamin K", category: .vitamin, defaultDosage: Dosage(value: 120, unit: .mcg), commonUses: "Blood clotting, bone health"),
        SupplementTemplate(name: "Vitamin K2", category: .vitamin, defaultDosage: Dosage(value: 100, unit: .mcg), commonUses: "Bone and cardiovascular health"),

        // Minerals
        SupplementTemplate(name: "Calcium", category: .mineral, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Bone health, muscle function"),
        SupplementTemplate(name: "Magnesium", category: .mineral, defaultDosage: Dosage(value: 400, unit: .mg), commonUses: "Muscle relaxation, sleep, energy"),
        SupplementTemplate(name: "Zinc", category: .mineral, defaultDosage: Dosage(value: 15, unit: .mg), commonUses: "Immune function, wound healing"),
        SupplementTemplate(name: "Iron", category: .mineral, defaultDosage: Dosage(value: 18, unit: .mg), commonUses: "Red blood cell formation, energy"),
        SupplementTemplate(name: "Selenium", category: .mineral, defaultDosage: Dosage(value: 55, unit: .mcg), commonUses: "Antioxidant, thyroid function"),
        SupplementTemplate(name: "Potassium", category: .mineral, defaultDosage: Dosage(value: 99, unit: .mg), commonUses: "Heart health, blood pressure"),
        SupplementTemplate(name: "Chromium", category: .mineral, defaultDosage: Dosage(value: 35, unit: .mcg), commonUses: "Blood sugar regulation"),
        SupplementTemplate(name: "Copper", category: .mineral, defaultDosage: Dosage(value: 900, unit: .mcg), commonUses: "Iron metabolism, nerve function"),
        SupplementTemplate(name: "Manganese", category: .mineral, defaultDosage: Dosage(value: 2.3, unit: .mg), commonUses: "Bone health, metabolism"),
        SupplementTemplate(name: "Iodine", category: .mineral, defaultDosage: Dosage(value: 150, unit: .mcg), commonUses: "Thyroid function"),

        // Omega Fatty Acids
        SupplementTemplate(name: "Omega-3 Fish Oil", category: .fattyAcid, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Heart health, brain function, inflammation"),
        SupplementTemplate(name: "Omega-3 EPA/DHA", category: .fattyAcid, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Cardiovascular and cognitive health"),
        SupplementTemplate(name: "Flaxseed Oil", category: .fattyAcid, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Omega-3 ALA, heart health"),
        SupplementTemplate(name: "Evening Primrose Oil", category: .fattyAcid, defaultDosage: Dosage(value: 500, unit: .mg), commonUses: "Skin health, hormonal balance"),

        // Probiotics
        SupplementTemplate(name: "Probiotic (General)", category: .probiotic, defaultDosage: Dosage(value: 10, unit: .unit), commonUses: "Digestive health, immune support"),
        SupplementTemplate(name: "Lactobacillus Acidophilus", category: .probiotic, defaultDosage: Dosage(value: 5, unit: .unit), commonUses: "Gut health, digestion"),
        SupplementTemplate(name: "Bifidobacterium", category: .probiotic, defaultDosage: Dosage(value: 5, unit: .unit), commonUses: "Intestinal health, immune function"),

        // Herbs
        SupplementTemplate(name: "Turmeric/Curcumin", category: .herb, defaultDosage: Dosage(value: 500, unit: .mg), commonUses: "Anti-inflammatory, joint health"),
        SupplementTemplate(name: "Ginger", category: .herb, defaultDosage: Dosage(value: 250, unit: .mg), commonUses: "Digestive health, nausea relief"),
        SupplementTemplate(name: "Ginseng", category: .herb, defaultDosage: Dosage(value: 200, unit: .mg), commonUses: "Energy, immune support"),
        SupplementTemplate(name: "Echinacea", category: .herb, defaultDosage: Dosage(value: 400, unit: .mg), commonUses: "Immune support"),
        SupplementTemplate(name: "Garlic Extract", category: .herb, defaultDosage: Dosage(value: 600, unit: .mg), commonUses: "Heart health, immune support"),
        SupplementTemplate(name: "Milk Thistle", category: .herb, defaultDosage: Dosage(value: 150, unit: .mg), commonUses: "Liver health"),
        SupplementTemplate(name: "Saw Palmetto", category: .herb, defaultDosage: Dosage(value: 320, unit: .mg), commonUses: "Prostate health"),
        SupplementTemplate(name: "St. John's Wort", category: .herb, defaultDosage: Dosage(value: 300, unit: .mg), frequency: .threeTimesDaily, commonUses: "Mood support"),
        SupplementTemplate(name: "Valerian Root", category: .herb, defaultDosage: Dosage(value: 300, unit: .mg), commonUses: "Sleep support, relaxation"),
        SupplementTemplate(name: "Ashwagandha", category: .herb, defaultDosage: Dosage(value: 300, unit: .mg), commonUses: "Stress relief, adaptogen"),
        SupplementTemplate(name: "Rhodiola", category: .herb, defaultDosage: Dosage(value: 200, unit: .mg), commonUses: "Energy, stress adaptation"),
        SupplementTemplate(name: "Green Tea Extract", category: .herb, defaultDosage: Dosage(value: 250, unit: .mg), commonUses: "Antioxidant, metabolism"),

        // Amino Acids
        SupplementTemplate(name: "L-Glutamine", category: .aminoAcid, defaultDosage: Dosage(value: 5, unit: .g), commonUses: "Gut health, muscle recovery"),
        SupplementTemplate(name: "L-Arginine", category: .aminoAcid, defaultDosage: Dosage(value: 3, unit: .g), commonUses: "Blood flow, exercise performance"),
        SupplementTemplate(name: "L-Lysine", category: .aminoAcid, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Collagen formation, immune support"),
        SupplementTemplate(name: "L-Theanine", category: .aminoAcid, defaultDosage: Dosage(value: 200, unit: .mg), commonUses: "Relaxation, focus"),
        SupplementTemplate(name: "BCAA (Branched-Chain Amino Acids)", category: .aminoAcid, defaultDosage: Dosage(value: 5, unit: .g), commonUses: "Muscle recovery, exercise performance"),
        SupplementTemplate(name: "L-Carnitine", category: .aminoAcid, defaultDosage: Dosage(value: 500, unit: .mg), commonUses: "Energy metabolism, fat burning"),
        SupplementTemplate(name: "Taurine", category: .aminoAcid, defaultDosage: Dosage(value: 500, unit: .mg), commonUses: "Heart health, energy"),

        // Protein
        SupplementTemplate(name: "Whey Protein", category: .protein, defaultDosage: Dosage(value: 25, unit: .g), commonUses: "Muscle building, recovery"),
        SupplementTemplate(name: "Plant Protein", category: .protein, defaultDosage: Dosage(value: 25, unit: .g), commonUses: "Muscle support, vegan option"),
        SupplementTemplate(name: "Collagen Peptides", category: .protein, defaultDosage: Dosage(value: 10, unit: .g), commonUses: "Skin, joint, and bone health"),

        // Fiber
        SupplementTemplate(name: "Psyllium Husk", category: .fiber, defaultDosage: Dosage(value: 5, unit: .g), commonUses: "Digestive health, regularity"),
        SupplementTemplate(name: "Inulin", category: .fiber, defaultDosage: Dosage(value: 5, unit: .g), commonUses: "Prebiotic, digestive health"),

        // Other Popular Supplements
        SupplementTemplate(name: "Coenzyme Q10 (CoQ10)", category: .other, defaultDosage: Dosage(value: 100, unit: .mg), commonUses: "Heart health, energy production"),
        SupplementTemplate(name: "Alpha-Lipoic Acid", category: .other, defaultDosage: Dosage(value: 300, unit: .mg), commonUses: "Antioxidant, blood sugar support"),
        SupplementTemplate(name: "Glucosamine", category: .other, defaultDosage: Dosage(value: 1500, unit: .mg), commonUses: "Joint health"),
        SupplementTemplate(name: "Chondroitin", category: .other, defaultDosage: Dosage(value: 1200, unit: .mg), commonUses: "Joint health, cartilage support"),
        SupplementTemplate(name: "MSM (Methylsulfonylmethane)", category: .other, defaultDosage: Dosage(value: 1000, unit: .mg), commonUses: "Joint health, inflammation"),
        SupplementTemplate(name: "Melatonin", category: .other, defaultDosage: Dosage(value: 3, unit: .mg), commonUses: "Sleep support"),
        SupplementTemplate(name: "Creatine", category: .other, defaultDosage: Dosage(value: 5, unit: .g), commonUses: "Muscle strength, exercise performance"),
        SupplementTemplate(name: "Beta-Alanine", category: .other, defaultDosage: Dosage(value: 2, unit: .g), commonUses: "Exercise performance, endurance"),
        SupplementTemplate(name: "Resveratrol", category: .other, defaultDosage: Dosage(value: 100, unit: .mg), commonUses: "Antioxidant, cardiovascular health"),
        SupplementTemplate(name: "Lutein", category: .other, defaultDosage: Dosage(value: 10, unit: .mg), commonUses: "Eye health, vision"),
        SupplementTemplate(name: "Zeaxanthin", category: .other, defaultDosage: Dosage(value: 2, unit: .mg), commonUses: "Eye health, macular protection"),
        SupplementTemplate(name: "SAMe (S-Adenosyl Methionine)", category: .other, defaultDosage: Dosage(value: 400, unit: .mg), commonUses: "Mood support, joint health"),
        SupplementTemplate(name: "5-HTP", category: .other, defaultDosage: Dosage(value: 100, unit: .mg), commonUses: "Mood support, sleep"),
        SupplementTemplate(name: "Berberine", category: .other, defaultDosage: Dosage(value: 500, unit: .mg), frequency: .twiceDaily, commonUses: "Blood sugar support, metabolic health"),
    ]
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


