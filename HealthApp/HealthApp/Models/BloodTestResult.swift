import Foundation

// MARK: - Blood Test Result
struct BloodTestResult: HealthDataProtocol {
    let id: UUID
    var type: HealthDataType { .bloodTest }
    
    // Test Information
    var testDate: Date
    var laboratoryName: String?
    var orderingPhysician: String?
    var results: [BloodTestItem]
    
    // Protocol Requirements
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        testDate: Date,
        laboratoryName: String? = nil,
        orderingPhysician: String? = nil,
        results: [BloodTestItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.testDate = testDate
        self.laboratoryName = laboratoryName
        self.orderingPhysician = orderingPhysician
        self.results = results
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

// MARK: - Blood Test Item
struct BloodTestItem: Codable, Identifiable {
    let id: UUID
    var name: String
    var value: String
    var unit: String?
    var referenceRange: String?
    var isAbnormal: Bool
    var category: BloodTestCategory?
    var notes: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        value: String,
        unit: String? = nil,
        referenceRange: String? = nil,
        isAbnormal: Bool = false,
        category: BloodTestCategory? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.category = category
        self.notes = notes
    }
}

// MARK: - Blood Test Categories
enum BloodTestCategory: String, CaseIterable, Codable {
    case completeBloodCount = "complete_blood_count"
    case basicMetabolicPanel = "basic_metabolic_panel"
    case comprehensiveMetabolicPanel = "comprehensive_metabolic_panel"
    case lipidPanel = "lipid_panel"
    case liverFunction = "liver_function"
    case kidneyFunction = "kidney_function"
    case thyroidFunction = "thyroid_function"
    case diabetesMarkers = "diabetes_markers"
    case cardiacMarkers = "cardiac_markers"
    case inflammatoryMarkers = "inflammatory_markers"
    case vitaminsAndMinerals = "vitamins_and_minerals"
    case hormones = "hormones"
    case immunology = "immunology"
    case coagulation = "coagulation"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .completeBloodCount:
            return "Complete Blood Count (CBC)"
        case .basicMetabolicPanel:
            return "Basic Metabolic Panel (BMP)"
        case .comprehensiveMetabolicPanel:
            return "Comprehensive Metabolic Panel (CMP)"
        case .lipidPanel:
            return "Lipid Panel"
        case .liverFunction:
            return "Liver Function Tests"
        case .kidneyFunction:
            return "Kidney Function Tests"
        case .thyroidFunction:
            return "Thyroid Function Tests"
        case .diabetesMarkers:
            return "Diabetes Markers"
        case .cardiacMarkers:
            return "Cardiac Markers"
        case .inflammatoryMarkers:
            return "Inflammatory Markers"
        case .vitaminsAndMinerals:
            return "Vitamins & Minerals"
        case .hormones:
            return "Hormones"
        case .immunology:
            return "Immunology"
        case .coagulation:
            return "Coagulation Studies"
        case .other:
            return "Other Tests"
        }
    }
    
    var icon: String {
        switch self {
        case .completeBloodCount:
            return "drop.circle"
        case .basicMetabolicPanel, .comprehensiveMetabolicPanel:
            return "chart.bar"
        case .lipidPanel:
            return "heart.circle"
        case .liverFunction:
            return "liver"
        case .kidneyFunction:
            return "kidneys"
        case .thyroidFunction:
            return "thyroid"
        case .diabetesMarkers:
            return "glucose"
        case .cardiacMarkers:
            return "heart.pulse"
        case .inflammatoryMarkers:
            return "flame"
        case .vitaminsAndMinerals:
            return "pills"
        case .hormones:
            return "waveform"
        case .immunology:
            return "shield"
        case .coagulation:
            return "timer"
        case .other:
            return "testtube.2"
        }
    }
}

// MARK: - Validation Extensions
extension BloodTestResult {
    var isValid: Bool {
        return !results.isEmpty && results.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    var abnormalResults: [BloodTestItem] {
        return results.filter { $0.isAbnormal }
    }
    
    var resultsByCategory: [BloodTestCategory: [BloodTestItem]] {
        var categorized: [BloodTestCategory: [BloodTestItem]] = [:]
        
        for result in results {
            let category = result.category ?? .other
            if categorized[category] == nil {
                categorized[category] = []
            }
            categorized[category]?.append(result)
        }
        
        return categorized
    }
    
    var summary: String {
        let totalTests = results.count
        let abnormalTests = abnormalResults.count
        
        if abnormalTests == 0 {
            return "\(totalTests) tests - All normal"
        } else {
            return "\(totalTests) tests - \(abnormalTests) abnormal"
        }
    }
}

// MARK: - Common Blood Test Items
extension BloodTestItem {
    static let commonTests: [BloodTestItem] = [
        // Complete Blood Count
        BloodTestItem(name: "White Blood Cell Count", value: "", unit: "K/uL", referenceRange: "4.5-11.0", category: .completeBloodCount),
        BloodTestItem(name: "Red Blood Cell Count", value: "", unit: "M/uL", referenceRange: "4.2-5.4", category: .completeBloodCount),
        BloodTestItem(name: "Hemoglobin", value: "", unit: "g/dL", referenceRange: "12.0-16.0", category: .completeBloodCount),
        BloodTestItem(name: "Hematocrit", value: "", unit: "%", referenceRange: "36-46", category: .completeBloodCount),
        BloodTestItem(name: "Platelet Count", value: "", unit: "K/uL", referenceRange: "150-450", category: .completeBloodCount),
        
        // Basic Metabolic Panel
        BloodTestItem(name: "Glucose", value: "", unit: "mg/dL", referenceRange: "70-100", category: .basicMetabolicPanel),
        BloodTestItem(name: "Sodium", value: "", unit: "mEq/L", referenceRange: "136-145", category: .basicMetabolicPanel),
        BloodTestItem(name: "Potassium", value: "", unit: "mEq/L", referenceRange: "3.5-5.0", category: .basicMetabolicPanel),
        BloodTestItem(name: "Chloride", value: "", unit: "mEq/L", referenceRange: "98-107", category: .basicMetabolicPanel),
        BloodTestItem(name: "BUN", value: "", unit: "mg/dL", referenceRange: "7-20", category: .basicMetabolicPanel),
        BloodTestItem(name: "Creatinine", value: "", unit: "mg/dL", referenceRange: "0.6-1.2", category: .basicMetabolicPanel),
        
        // Lipid Panel
        BloodTestItem(name: "Total Cholesterol", value: "", unit: "mg/dL", referenceRange: "<200", category: .lipidPanel),
        BloodTestItem(name: "LDL Cholesterol", value: "", unit: "mg/dL", referenceRange: "<100", category: .lipidPanel),
        BloodTestItem(name: "HDL Cholesterol", value: "", unit: "mg/dL", referenceRange: ">40", category: .lipidPanel),
        BloodTestItem(name: "Triglycerides", value: "", unit: "mg/dL", referenceRange: "<150", category: .lipidPanel)
    ]
}