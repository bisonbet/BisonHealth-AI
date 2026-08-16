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

    // AI Context management
    var includeInAIContext: Bool

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
        includeInAIContext: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.testDate = testDate
        self.laboratoryName = laboratoryName
        self.orderingPhysician = orderingPhysician
        self.results = results
        self.includeInAIContext = includeInAIContext
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    // Custom Decodable to handle existing records without includeInAIContext field
    enum CodingKeys: String, CodingKey {
        case id, testDate, laboratoryName, orderingPhysician, results
        case includeInAIContext, createdAt, updatedAt, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        testDate = try container.decode(Date.self, forKey: .testDate)
        laboratoryName = try container.decodeIfPresent(String.self, forKey: .laboratoryName)
        orderingPhysician = try container.decodeIfPresent(String.self, forKey: .orderingPhysician)
        results = try container.decode([BloodTestItem].self, forKey: .results)
        // Default to false for existing records that don't have this field
        includeInAIContext = try container.decodeIfPresent(Bool.self, forKey: .includeInAIContext) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }
}

// MARK: - Lab Measurement Context
/// The specimen and collection context needed to interpret a laboratory value.
/// These fields are optional on persisted records so existing imports remain
/// backward compatible while new imports retain the context inferred from the
/// report.
enum LabSpecimen: String, Codable, Hashable {
    case blood
    case serum
    case plasma
    case wholeBlood = "whole_blood"
    case urine
    case unspecified
}

enum LabCollection: String, Codable, Hashable {
    case notApplicable = "not_applicable"
    case random
    case spot
    case twentyFourHour = "twenty_four_hour"
    case timed
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
    var confidence: Double?
    var specimen: LabSpecimen?
    var collection: LabCollection?
    
    init(
        id: UUID = UUID(),
        name: String,
        value: String,
        unit: String? = nil,
        referenceRange: String? = nil,
        isAbnormal: Bool = false,
        category: BloodTestCategory? = nil,
        notes: String? = nil,
        confidence: Double? = nil,
        specimen: LabSpecimen? = nil,
        collection: LabCollection? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.category = category
        self.notes = notes
        self.confidence = confidence
        self.specimen = specimen
        self.collection = collection
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
    case urinalysis = "urinalysis"
    case urineChemistry = "urine_chemistry"
    case urineMicrobiology = "urine_microbiology"
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
        case .urinalysis:
            return "Urinalysis"
        case .urineChemistry:
            return "Urine Chemistry"
        case .urineMicrobiology:
            return "Urine Microbiology"
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
        case .urinalysis:
            return "drop.triangle"
        case .urineChemistry:
            return "drop.circle.fill"
        case .urineMicrobiology:
            return "bacteria"
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

// MARK: - Standardized Lab Parameter
struct LabParameter: Codable {
    let name: String
    let key: String
    let unit: String?
    let value: String?
    let referenceRange: String?
    let category: BloodTestCategory
    let description: String?

    init(name: String, key: String, unit: String? = nil, value: String? = nil, referenceRange: String? = nil, category: BloodTestCategory, description: String? = nil) {
        self.name = name
        self.key = key
        self.unit = unit
        self.value = value
        self.referenceRange = referenceRange
        self.category = category
        self.description = description
    }
}

extension LabParameter {
    /// A conservative default. The actual report specimen, when present, is
    /// more authoritative than this inferred value.
    var defaultSpecimen: LabSpecimen {
        switch category {
        case .urinalysis, .urineChemistry, .urineMicrobiology:
            return .urine
        default:
            return .blood
        }
    }

    /// Collection defaults are derived from the measurement represented by the
    /// key, not from a generic "urine" label.
    var defaultCollection: LabCollection {
        guard defaultSpecimen == .urine else { return .notApplicable }

        switch key {
        case "urine_urea_nitrogen",
             "urine_creatinine_clearance",
             "urine_calcium",
             "urine_uric_acid",
             "urine_phosphate",
             "urine_magnesium":
            return .twentyFourHour
        case "urine_protein_creatinine_ratio", "urine_albumin_creatinine_ratio":
            return .spot
        default:
            return .random
        }
    }
}

enum LabMeasurementContext {
    /// Infer only what can be supported by the parameter name, report labels,
    /// and explicit specimen/collection fields. Unknown context stays generic.
    static func infer(
        testName: String?,
        parameter: LabParameter,
        unit: String? = nil,
        reportedSpecimen: String? = nil,
        reportedCollection: String? = nil
    ) -> (specimen: LabSpecimen, collection: LabCollection) {
        let normalizedName = BloodTestResult.normalizeLabName(testName ?? "")

        let specimen = parseSpecimen(reportedSpecimen)
            ?? (normalizedName.contains("plasma") ? .plasma : nil)
            ?? (normalizedName.contains("serum") ? .serum : nil)
            ?? (normalizedName.contains("whole_blood") ? .wholeBlood : nil)
            ?? parameter.defaultSpecimen

        var collection = parseCollection(reportedCollection)
        if collection == nil,
           normalizedName.contains("24_hour") || normalizedName.contains("24h") || normalizedName.contains("24_hr") {
            collection = .twentyFourHour
        }
        if collection == nil, normalizedName.contains("spot") {
            collection = .spot
        }
        if collection == nil, normalizedName.contains("random") {
            collection = .random
        }
        if collection == nil,
           unit?.lowercased().replacingOccurrences(of: " ", with: "").contains("/24h") == true {
            collection = .twentyFourHour
        }
        return (specimen, collection ?? parameter.defaultCollection)
    }

    private static func parseSpecimen(_ raw: String?) -> LabSpecimen? {
        guard let raw else { return nil }
        switch BloodTestResult.normalizeLabName(raw) {
        case "blood": return .blood
        case "serum": return .serum
        case "plasma": return .plasma
        case "whole_blood", "wholeblood": return .wholeBlood
        case "urine": return .urine
        default: return nil
        }
    }

    private static func parseCollection(_ raw: String?) -> LabCollection? {
        guard let raw else { return nil }
        let normalized = BloodTestResult.normalizeLabName(raw)
        switch normalized {
        case "random": return .random
        case "spot": return .spot
        case "24h", "24_hr", "24_hour", "twenty_four_hour", "timed_24_hour": return .twentyFourHour
        case "timed": return .timed
        case "na", "not_applicable": return .notApplicable
        default: return nil
        }
    }
}

// MARK: - Comprehensive Lab Parameters (Based on Legacy Schema)
extension BloodTestResult {
    static let standardizedLabParameters: [String: LabParameter] = [
        // Complete Blood Count
        "hemoglobin": LabParameter(name: "Hemoglobin", key: "hemoglobin", unit: "g/dL", referenceRange: "12.0-16.0", category: .completeBloodCount, description: "Hemoglobin (HGB)"),
        "hematocrit": LabParameter(name: "Hematocrit", key: "hematocrit", unit: "%", referenceRange: "36-46", category: .completeBloodCount, description: "Hematocrit (HCT)"),
        "wbc": LabParameter(name: "White Blood Cell Count", key: "wbc", unit: "K/uL", referenceRange: "4.5-11.0", category: .completeBloodCount, description: "White Blood Cell Count"),
        "rbc": LabParameter(name: "Red Blood Cell Count", key: "rbc", unit: "M/uL", referenceRange: "4.2-5.4", category: .completeBloodCount, description: "Red Blood Cell Count"),
        "platelet_count": LabParameter(name: "Platelet Count", key: "platelet_count", unit: "K/uL", referenceRange: "150-450", category: .completeBloodCount, description: "Platelet Count"),
        "mcv": LabParameter(name: "Mean Corpuscular Volume", key: "mcv", unit: "fL", referenceRange: "80-100", category: .completeBloodCount, description: "Mean Corpuscular Volume (MCV)"),
        "mch": LabParameter(name: "Mean Corpuscular Hemoglobin", key: "mch", unit: "pg", referenceRange: "27-32", category: .completeBloodCount, description: "MCH, Mean Corpuscular Hemoglobin"),
        "mchc": LabParameter(name: "Mean Corpuscular Hemoglobin Concentration", key: "mchc", unit: "g/dL", referenceRange: "32-36", category: .completeBloodCount, description: "MCHC, Mean Corpuscular Hemoglobin Concentration"),
        "absolute_neutrophils": LabParameter(name: "Absolute Neutrophils", key: "absolute_neutrophils", unit: "K/uL", referenceRange: "1.8-7.8", category: .completeBloodCount, description: "Absolute Neutrophils, Neutrophil Count"),
        "absolute_lymphocytes": LabParameter(name: "Absolute Lymphocytes", key: "absolute_lymphocytes", unit: "K/uL", referenceRange: "1.0-4.0", category: .completeBloodCount, description: "Absolute Lymphocytes, Lymphocyte Count"),
        "absolute_monocytes": LabParameter(name: "Absolute Monocytes", key: "absolute_monocytes", unit: "K/uL", referenceRange: "0.2-0.8", category: .completeBloodCount, description: "Absolute Monocytes, Monocyte Count"),
        "absolute_eosinophils": LabParameter(name: "Absolute Eosinophils", key: "absolute_eosinophils", unit: "K/uL", referenceRange: "0.0-0.4", category: .completeBloodCount, description: "Absolute Eosinophils, Eosinophil Count"),
        "absolute_basophils": LabParameter(name: "Absolute Basophils", key: "absolute_basophils", unit: "K/uL", referenceRange: "0.0-0.2", category: .completeBloodCount, description: "Absolute Basophils, Basophil Count"),
        "neutrophils": LabParameter(name: "Neutrophils", key: "neutrophils", unit: "%", referenceRange: "40-60", category: .completeBloodCount, description: "Neutrophils, segmented neutrophil percentage"),
        "lymphocytes": LabParameter(name: "Lymphocytes", key: "lymphocytes", unit: "%", referenceRange: "20-40", category: .completeBloodCount, description: "Lymphocytes percentage"),
        "monocytes": LabParameter(name: "Monocytes", key: "monocytes", unit: "%", referenceRange: "2-8", category: .completeBloodCount, description: "Monocytes percentage"),
        "basophils": LabParameter(name: "Basophils", key: "basophils", unit: "%", referenceRange: "0-1", category: .completeBloodCount, description: "Basophils percentage"),
        "eosinophils": LabParameter(name: "Eosinophils", key: "eosinophils", unit: "%", referenceRange: "0-4", category: .completeBloodCount, description: "Eosinophils (Eos), white blood cell type"),
        "rdw": LabParameter(name: "Red Cell Distribution Width", key: "rdw", unit: "%", referenceRange: "11.5-14.5", category: .completeBloodCount, description: "RDW, Red Cell Distribution Width"),
        "mpv": LabParameter(name: "Mean Platelet Volume", key: "mpv", unit: "fL", referenceRange: "7.5-11.5", category: .completeBloodCount, description: "MPV, Mean Platelet Volume"),
        "reticulocyte_count": LabParameter(name: "Reticulocyte Count", key: "reticulocyte_count", unit: "%", referenceRange: "0.5-2.5", category: .completeBloodCount, description: "Reticulocyte percentage"),
        "immature_granulocytes": LabParameter(name: "Immature Granulocytes", key: "immature_granulocytes", unit: "%", referenceRange: "0.0-0.4", category: .completeBloodCount, description: "Immature granulocyte percentage"),

        // Basic/Comprehensive Metabolic Panel
        "glucose": LabParameter(name: "Glucose", key: "glucose", unit: "mg/dL", referenceRange: "70-100", category: .basicMetabolicPanel, description: "Glucose, blood sugar"),
        "sodium": LabParameter(name: "Sodium", key: "sodium", unit: "mmol/L", referenceRange: "136-145", category: .basicMetabolicPanel, description: "Sodium"),
        "potassium": LabParameter(name: "Potassium", key: "potassium", unit: "mmol/L", referenceRange: "3.5-5.0", category: .basicMetabolicPanel, description: "Potassium"),
        "chloride": LabParameter(name: "Chloride", key: "chloride", unit: "mmol/L", referenceRange: "98-107", category: .basicMetabolicPanel, description: "Chloride"),
        "co2_bicarbonate": LabParameter(name: "CO2 (Bicarbonate)", key: "co2_bicarbonate", unit: "mmol/L", referenceRange: "22-29", category: .basicMetabolicPanel, description: "CO2, Serum Bicarbonate"),
        "anion_gap": LabParameter(name: "Anion Gap", key: "anion_gap", unit: "mmol/L", referenceRange: "7-16", category: .basicMetabolicPanel, description: "Anion Gap"),
        "bun": LabParameter(name: "Blood Urea Nitrogen", key: "bun", unit: "mg/dL", referenceRange: "7-20", category: .kidneyFunction, description: "BUN, Blood Urea Nitrogen"),
        "creatinine": LabParameter(name: "Creatinine", key: "creatinine", unit: "mg/dL", referenceRange: "0.6-1.2", category: .kidneyFunction, description: "Creatinine, kidney function indicator"),
        "egfr": LabParameter(name: "eGFR", key: "egfr", unit: "mL/min/1.73m²", referenceRange: ">60", category: .kidneyFunction, description: "eGFR, Estimated Glomerular Filtration Rate"),
        "calcium": LabParameter(name: "Calcium", key: "calcium", unit: "mg/dL", referenceRange: "8.5-10.5", category: .vitaminsAndMinerals, description: "Calcium level"),
        "albumin": LabParameter(name: "Albumin", key: "albumin", unit: "g/dL", referenceRange: "3.5-5.0", category: .liverFunction, description: "Albumin"),
        "total_protein": LabParameter(name: "Total Protein", key: "total_protein", unit: "g/dL", referenceRange: "6.0-8.3", category: .liverFunction, description: "Total Protein"),
        "albumin_globulin_ratio": LabParameter(name: "Albumin/Globulin Ratio", key: "albumin_globulin_ratio", unit: "", referenceRange: "1.1-2.5", category: .liverFunction, description: "Albumin/Globulin Ratio (A/G Ratio)"),
        "phosphorus": LabParameter(name: "Phosphorus", key: "phosphorus", unit: "mg/dL", referenceRange: "2.5-4.5", category: .comprehensiveMetabolicPanel, description: "Phosphorus (Phosphate)"),
        "serum_osmolality": LabParameter(name: "Serum Osmolality", key: "serum_osmolality", unit: "mOsm/kg", referenceRange: "275-295", category: .basicMetabolicPanel, description: "Serum Osmolality"),

        // Lipid Panel
        "cholesterol_total": LabParameter(name: "Total Cholesterol", key: "cholesterol_total", unit: "mg/dL", referenceRange: "<200", category: .lipidPanel, description: "Total Cholesterol"),
        "ldl_cholesterol": LabParameter(name: "LDL Cholesterol", key: "ldl_cholesterol", unit: "mg/dL", referenceRange: "<100", category: .lipidPanel, description: "LDL Cholesterol (Low-Density Lipoprotein)"),
        "hdl_cholesterol": LabParameter(name: "HDL Cholesterol", key: "hdl_cholesterol", unit: "mg/dL", referenceRange: ">40", category: .lipidPanel, description: "HDL Cholesterol (High-Density Lipoprotein)"),
        "triglycerides": LabParameter(name: "Triglycerides", key: "triglycerides", unit: "mg/dL", referenceRange: "<150", category: .lipidPanel, description: "Triglycerides"),
        "ldl_chol_calc": LabParameter(name: "LDL Cholesterol (Calculated)", key: "ldl_chol_calc", unit: "mg/dL", referenceRange: "<100", category: .lipidPanel, description: "Calculated LDL Cholesterol (LDL Chol Calc)"),
        "chol_hdlc_ratio": LabParameter(name: "Cholesterol/HDL Ratio", key: "chol_hdlc_ratio", unit: "", referenceRange: "<5.0", category: .lipidPanel, description: "Cholesterol/HDL-C Ratio, Total Cholesterol/HDL Ratio"),
        "non_hdl_cholesterol": LabParameter(name: "Non-HDL Cholesterol", key: "non_hdl_cholesterol", unit: "mg/dL", referenceRange: "<130", category: .lipidPanel, description: "Non-HDL Cholesterol"),
        "apolipoprotein_b": LabParameter(name: "Apolipoprotein B", key: "apolipoprotein_b", unit: "mg/dL", referenceRange: "<90", category: .lipidPanel, description: "ApoB"),
        "lipoprotein_a": LabParameter(name: "Lipoprotein(a)", key: "lipoprotein_a", unit: "nmol/L", referenceRange: "<75", category: .lipidPanel, description: "Lp(a), Lipoprotein(a)"),

        // Liver Function
        "alt_sgpt": LabParameter(name: "ALT (SGPT)", key: "alt_sgpt", unit: "U/L", referenceRange: "7-56", category: .liverFunction, description: "ALT (SGPT), Alanine Aminotransferase"),
        "ast_sgot": LabParameter(name: "AST (SGOT)", key: "ast_sgot", unit: "U/L", referenceRange: "10-40", category: .liverFunction, description: "AST (SGOT), Aspartate Aminotransferase"),
        "alp": LabParameter(name: "Alkaline Phosphatase", key: "alp", unit: "U/L", referenceRange: "44-147", category: .liverFunction, description: "ALP, Alkaline Phosphatase"),
        "bilirubin_total": LabParameter(name: "Total Bilirubin", key: "bilirubin_total", unit: "mg/dL", referenceRange: "0.3-1.2", category: .liverFunction, description: "Total Bilirubin"),
        "bilirubin_direct": LabParameter(name: "Direct Bilirubin", key: "bilirubin_direct", unit: "mg/dL", referenceRange: "0.0-0.3", category: .liverFunction, description: "Direct Bilirubin"),
        "bilirubin_indirect": LabParameter(name: "Indirect Bilirubin", key: "bilirubin_indirect", unit: "mg/dL", referenceRange: "0.2-0.8", category: .liverFunction, description: "Indirect Bilirubin"),
        "ggt": LabParameter(name: "GGT", key: "ggt", unit: "U/L", referenceRange: "9-48", category: .liverFunction, description: "Gamma-Glutamyl Transferase (GGT)"),
        "ldh": LabParameter(name: "LDH", key: "ldh", unit: "U/L", referenceRange: "140-280", category: .liverFunction, description: "Lactate Dehydrogenase (LDH)"),

        // Thyroid Function
        "tsh": LabParameter(name: "TSH", key: "tsh", unit: "mIU/L", referenceRange: "0.4-4.0", category: .thyroidFunction, description: "TSH, Thyroid Stimulating Hormone"),
        "free_t4": LabParameter(name: "Free T4", key: "free_t4", unit: "ng/dL", referenceRange: "0.8-1.8", category: .thyroidFunction, description: "Free T4, Free Thyroxine"),
        "free_t3": LabParameter(name: "Free T3", key: "free_t3", unit: "pg/mL", referenceRange: "2.3-4.2", category: .thyroidFunction, description: "Free T3, Free Triiodothyronine"),
        "total_t4": LabParameter(name: "Total T4", key: "total_t4", unit: "μg/dL", referenceRange: "4.5-12.0", category: .thyroidFunction, description: "Total Thyroxine (T4)"),
        "total_t3": LabParameter(name: "Total T3", key: "total_t3", unit: "ng/dL", referenceRange: "80-200", category: .thyroidFunction, description: "Total Triiodothyronine (T3)"),
        "reverse_t3": LabParameter(name: "Reverse T3", key: "reverse_t3", unit: "ng/dL", referenceRange: "9.0-24.0", category: .thyroidFunction, description: "Reverse T3"),
        "thyroid_peroxidase_antibodies": LabParameter(name: "Thyroid Peroxidase Antibodies", key: "thyroid_peroxidase_antibodies", unit: "IU/mL", referenceRange: "<35", category: .thyroidFunction, description: "TPO Antibodies"),
        "thyroglobulin_antibody": LabParameter(name: "Thyroglobulin Antibody", key: "thyroglobulin_antibody", unit: "IU/mL", referenceRange: "<4", category: .thyroidFunction, description: "Thyroglobulin Antibody"),

        // Diabetes Markers
        "hemoglobin_a1c": LabParameter(name: "Hemoglobin A1c", key: "hemoglobin_a1c", unit: "%", referenceRange: "<5.7", category: .diabetesMarkers, description: "Hemoglobin A1c (HbA1c), glycated hemoglobin"),
        "insulin": LabParameter(name: "Insulin", key: "insulin", unit: "μIU/mL", referenceRange: "2.6-24.9", category: .diabetesMarkers, description: "Insulin"),
        "c_peptide": LabParameter(name: "C-Peptide", key: "c_peptide", unit: "ng/mL", referenceRange: "0.8-3.1", category: .diabetesMarkers, description: "C-Peptide"),
        "fructosamine": LabParameter(name: "Fructosamine", key: "fructosamine", unit: "µmol/L", referenceRange: "200-285", category: .diabetesMarkers, description: "Fructosamine"),

        // Inflammatory Markers
        "crp_c_reactive_protein": LabParameter(name: "C-Reactive Protein", key: "crp_c_reactive_protein", unit: "mg/L", referenceRange: "<3.0", category: .inflammatoryMarkers, description: "C-Reactive Protein (CRP), inflammation marker"),
        "hs_crp": LabParameter(name: "High-Sensitivity CRP", key: "hs_crp", unit: "mg/L", referenceRange: "<1.0", category: .inflammatoryMarkers, description: "High-Sensitivity C-Reactive Protein"),
        "esr": LabParameter(name: "ESR", key: "esr", unit: "mm/hr", referenceRange: "0-30", category: .inflammatoryMarkers, description: "Erythrocyte Sedimentation Rate (ESR)"),
        "procalcitonin": LabParameter(name: "Procalcitonin", key: "procalcitonin", unit: "ng/mL", referenceRange: "<0.1", category: .inflammatoryMarkers, description: "Procalcitonin"),

        // Vitamins and Minerals
        "vitamin_d": LabParameter(name: "Vitamin D", key: "vitamin_d", unit: "ng/mL", referenceRange: "30-100", category: .vitaminsAndMinerals, description: "25-Hydroxyvitamin D"),
        "vitamin_b12": LabParameter(name: "Vitamin B12", key: "vitamin_b12", unit: "pg/mL", referenceRange: "300-900", category: .vitaminsAndMinerals, description: "Vitamin B12 (Cobalamin)"),
        "folate": LabParameter(name: "Folate", key: "folate", unit: "ng/mL", referenceRange: "3-17", category: .vitaminsAndMinerals, description: "Folate"),
        "folate_rbc": LabParameter(name: "Folate (RBC)", key: "folate_rbc", unit: "ng/mL", referenceRange: "280-900", category: .vitaminsAndMinerals, description: "Folate RBC (Red Blood Cell Folate)"),
        "iron": LabParameter(name: "Iron", key: "iron", unit: "μg/dL", referenceRange: "60-170", category: .vitaminsAndMinerals, description: "Iron"),
        "ferritin": LabParameter(name: "Ferritin", key: "ferritin", unit: "ng/mL", referenceRange: "15-200", category: .vitaminsAndMinerals, description: "Ferritin, iron storage protein"),
        "tibc": LabParameter(name: "TIBC", key: "tibc", unit: "μg/dL", referenceRange: "250-450", category: .vitaminsAndMinerals, description: "Total Iron Binding Capacity (TIBC)"),
        "percent_saturation": LabParameter(name: "Iron Saturation", key: "percent_saturation", unit: "%", referenceRange: "20-50", category: .vitaminsAndMinerals, description: "Percent Saturation (TSAT), iron saturation, transferrin saturation"),
        "magnesium": LabParameter(name: "Magnesium", key: "magnesium", unit: "mg/dL", referenceRange: "1.7-2.2", category: .vitaminsAndMinerals, description: "Magnesium"),
        "zinc": LabParameter(name: "Zinc", key: "zinc", unit: "µg/dL", referenceRange: "60-120", category: .vitaminsAndMinerals, description: "Zinc"),
        "copper": LabParameter(name: "Copper", key: "copper", unit: "µg/dL", referenceRange: "80-155", category: .vitaminsAndMinerals, description: "Copper"),
        "selenium": LabParameter(name: "Selenium", key: "selenium", unit: "µg/L", referenceRange: "70-150", category: .vitaminsAndMinerals, description: "Selenium"),
        "vitamin_a": LabParameter(name: "Vitamin A", key: "vitamin_a", unit: "µg/dL", referenceRange: "20-60", category: .vitaminsAndMinerals, description: "Vitamin A (Retinol)"),
        "vitamin_b6": LabParameter(name: "Vitamin B6", key: "vitamin_b6", unit: "ng/mL", referenceRange: "5-30", category: .vitaminsAndMinerals, description: "Vitamin B6 (Pyridoxal 5-Phosphate)"),
        "vitamin_e": LabParameter(name: "Vitamin E", key: "vitamin_e", unit: "mg/L", referenceRange: "5-18", category: .vitaminsAndMinerals, description: "Vitamin E (Alpha-Tocopherol)"),
        "vitamin_c": LabParameter(name: "Vitamin C", key: "vitamin_c", unit: "mg/dL", referenceRange: "0.4-2.0", category: .vitaminsAndMinerals, description: "Vitamin C (Ascorbic Acid)"),
        "iodine": LabParameter(name: "Iodine", key: "iodine", unit: "µg/L", referenceRange: "40-90", category: .vitaminsAndMinerals, description: "Iodine"),
        "coenzyme_q10": LabParameter(name: "Coenzyme Q10", key: "coenzyme_q10", unit: "µg/mL", referenceRange: "0.5-1.5", category: .vitaminsAndMinerals, description: "Coenzyme Q10"),

        // Hormones
        "testosterone": LabParameter(name: "Testosterone", key: "testosterone", unit: "ng/dL", referenceRange: "300-1000", category: .hormones, description: "Testosterone"),
        "estradiol": LabParameter(name: "Estradiol", key: "estradiol", unit: "pg/mL", referenceRange: "15-350", category: .hormones, description: "Estradiol, female hormone"),
        "cortisol": LabParameter(name: "Cortisol", key: "cortisol", unit: "μg/dL", referenceRange: "6.2-19.4", category: .hormones, description: "Cortisol, stress hormone"),
        "cortisol_am": LabParameter(name: "Cortisol (AM)", key: "cortisol_am", unit: "μg/dL", referenceRange: "6.2-19.4", category: .hormones, description: "Cortisol AM, morning cortisol"),
        "parathyroid_hormone": LabParameter(name: "Parathyroid Hormone", key: "parathyroid_hormone", unit: "pg/mL", referenceRange: "15-65", category: .hormones, description: "Parathyroid Hormone (PTH)"),

        // Cardiac Markers
        "troponin_i": LabParameter(name: "Troponin I", key: "troponin_i", unit: "ng/mL", referenceRange: "<0.04", category: .cardiacMarkers, description: "Troponin I"),
        "bnp": LabParameter(name: "BNP", key: "bnp", unit: "pg/mL", referenceRange: "<100", category: .cardiacMarkers, description: "B-type Natriuretic Peptide (BNP)"),
        "nt_pro_bnp": LabParameter(name: "NT-proBNP", key: "nt_pro_bnp", unit: "pg/mL", referenceRange: "<125", category: .cardiacMarkers, description: "N-terminal pro-B-type Natriuretic Peptide"),
        "ck_mb": LabParameter(name: "CK-MB", key: "ck_mb", unit: "ng/mL", referenceRange: "<5.0", category: .cardiacMarkers, description: "Creatine Kinase-MB"),
        "homocysteine": LabParameter(name: "Homocysteine", key: "homocysteine", unit: "µmol/L", referenceRange: "4-15", category: .cardiacMarkers, description: "Homocysteine"),

        // Coagulation
        "pt": LabParameter(name: "Prothrombin Time", key: "pt", unit: "sec", referenceRange: "11-13", category: .coagulation, description: "Prothrombin Time (PT)"),
        "inr": LabParameter(name: "INR", key: "inr", unit: "", referenceRange: "0.8-1.1", category: .coagulation, description: "International Normalized Ratio (INR)"),
        "ptt": LabParameter(name: "Partial Thromboplastin Time", key: "ptt", unit: "sec", referenceRange: "25-35", category: .coagulation, description: "Partial Thromboplastin Time (PTT)"),
        "fibrinogen": LabParameter(name: "Fibrinogen", key: "fibrinogen", unit: "mg/dL", referenceRange: "200-400", category: .coagulation, description: "Fibrinogen, blood clotting factor"),
        "d_dimer": LabParameter(name: "D-Dimer", key: "d_dimer", unit: "µg/mL FEU", referenceRange: "<0.5", category: .coagulation, description: "D-Dimer"),

        // Additional Markers
        "uric_acid": LabParameter(name: "Uric Acid", key: "uric_acid", unit: "mg/dL", referenceRange: "3.5-7.2", category: .other, description: "Uric Acid"),
        "creatine_kinase": LabParameter(name: "Creatine Kinase", key: "creatine_kinase", unit: "U/L", referenceRange: "30-200", category: .other, description: "Creatine Kinase (CK, CPK total)"),
        "amylase": LabParameter(name: "Amylase", key: "amylase", unit: "U/L", referenceRange: "30-110", category: .other, description: "Amylase"),
        "lipase": LabParameter(name: "Lipase", key: "lipase", unit: "U/L", referenceRange: "10-140", category: .other, description: "Lipase"),
        "bun_creatinine_ratio": LabParameter(name: "BUN/Creatinine Ratio", key: "bun_creatinine_ratio", unit: "", referenceRange: "10-20", category: .kidneyFunction, description: "BUN/Creatinine Ratio"),
        "cystatin_c": LabParameter(name: "Cystatin C", key: "cystatin_c", unit: "mg/L", referenceRange: "0.6-1.3", category: .kidneyFunction, description: "Cystatin C"),

        // Blood Type and Immunology
        "abo_blood_type": LabParameter(name: "ABO Blood Type", key: "abo_blood_type", unit: "", referenceRange: "", category: .immunology, description: "ABO Blood Type, ABO Group"),
        "rh_factor": LabParameter(name: "Rh Factor", key: "rh_factor", unit: "", referenceRange: "", category: .immunology, description: "Rh Factor"),
        "total_ige": LabParameter(name: "Total IgE", key: "total_ige", unit: "IU/mL", referenceRange: "0-100", category: .immunology, description: "Total Immunoglobulin E"),
        "iga": LabParameter(name: "IgA", key: "iga", unit: "mg/dL", referenceRange: "70-400", category: .immunology, description: "Immunoglobulin A"),
        "igg": LabParameter(name: "IgG", key: "igg", unit: "mg/dL", referenceRange: "700-1600", category: .immunology, description: "Immunoglobulin G"),
        "igm": LabParameter(name: "IgM", key: "igm", unit: "mg/dL", referenceRange: "40-230", category: .immunology, description: "Immunoglobulin M"),
        
        // Additional CBC Parameters
        "nucleated_rbc": LabParameter(name: "Nucleated RBC", key: "nucleated_rbc", unit: "/100 WBC", referenceRange: "0", category: .completeBloodCount, description: "Nucleated Red Blood Cells"),
        "platelet_distribution_width": LabParameter(name: "Platelet Distribution Width", key: "platelet_distribution_width", unit: "fL", referenceRange: "9-17", category: .completeBloodCount, description: "PDW, Platelet Distribution Width"),
        "mean_cell_hemoglobin_concentration": LabParameter(name: "Mean Cell Hemoglobin Concentration", key: "mean_cell_hemoglobin_concentration", unit: "g/dL", referenceRange: "32-36", category: .completeBloodCount, description: "MCHC"),
        
        // Additional Metabolic Panel Tests
        "lactate": LabParameter(name: "Lactate", key: "lactate", unit: "mmol/L", referenceRange: "0.5-2.2", category: .basicMetabolicPanel, description: "Lactic Acid, Lactate"),
        "osmolal_gap": LabParameter(name: "Osmolal Gap", key: "osmolal_gap", unit: "mOsm/kg", referenceRange: "-10 to 10", category: .basicMetabolicPanel, description: "Osmolal Gap"),
        
        // Additional Kidney Function Tests
        "microalbumin": LabParameter(name: "Microalbumin", key: "microalbumin", unit: "mg/L", referenceRange: "<30", category: .kidneyFunction, description: "Microalbuminuria"),
        
        // Additional Liver Function Tests
        "aptt": LabParameter(name: "APTT", key: "aptt", unit: "sec", referenceRange: "25-35", category: .liverFunction, description: "Activated Partial Thromboplastin Time"),
        "protein_electrophoresis": LabParameter(name: "Protein Electrophoresis", key: "protein_electrophoresis", unit: "g/dL", referenceRange: "", category: .liverFunction, description: "Protein Electrophoresis"),
        "ammonia": LabParameter(name: "Ammonia", key: "ammonia", unit: "μmol/L", referenceRange: "11-32", category: .liverFunction, description: "Blood Ammonia"),
        
        // Additional Thyroid Tests
        "thyroglobulin": LabParameter(name: "Thyroglobulin", key: "thyroglobulin", unit: "ng/mL", referenceRange: "1.4-29.2", category: .thyroidFunction, description: "Thyroglobulin"),
        "tsh_receptor_antibodies": LabParameter(name: "TSH Receptor Antibodies", key: "tsh_receptor_antibodies", unit: "IU/L", referenceRange: "<1.75", category: .thyroidFunction, description: "TSH Receptor Antibodies"),
        
        // Additional Diabetes Markers
        "glucose_tolerance_test_2hr": LabParameter(name: "Glucose Tolerance Test (2hr)", key: "glucose_tolerance_test_2hr", unit: "mg/dL", referenceRange: "<140", category: .diabetesMarkers, description: "2-Hour Glucose Tolerance Test"),
        "fasting_glucose": LabParameter(name: "Fasting Glucose", key: "fasting_glucose", unit: "mg/dL", referenceRange: "70-100", category: .diabetesMarkers, description: "Fasting Blood Glucose"),
        "random_glucose": LabParameter(name: "Random Glucose", key: "random_glucose", unit: "mg/dL", referenceRange: "<140", category: .diabetesMarkers, description: "Random Blood Glucose"),
        
        // Additional Cardiac Markers
        "troponin_t": LabParameter(name: "Troponin T", key: "troponin_t", unit: "ng/mL", referenceRange: "<0.01", category: .cardiacMarkers, description: "Troponin T"),
        "ck_total": LabParameter(name: "Creatine Kinase Total", key: "ck_total", unit: "U/L", referenceRange: "30-200", category: .cardiacMarkers, description: "Total Creatine Kinase"),
        "myoglobin": LabParameter(name: "Myoglobin", key: "myoglobin", unit: "ng/mL", referenceRange: "17-106", category: .cardiacMarkers, description: "Myoglobin"),
        
        // Additional Coagulation Tests
        "protein_c": LabParameter(name: "Protein C", key: "protein_c", unit: "%", referenceRange: "70-140", category: .coagulation, description: "Protein C Activity"),
        "protein_s": LabParameter(name: "Protein S", key: "protein_s", unit: "%", referenceRange: "60-140", category: .coagulation, description: "Protein S Activity"),
        "antithrombin_iii": LabParameter(name: "Antithrombin III", key: "antithrombin_iii", unit: "%", referenceRange: "80-120", category: .coagulation, description: "Antithrombin III"),
        "factor_viii": LabParameter(name: "Factor VIII", key: "factor_viii", unit: "%", referenceRange: "50-200", category: .coagulation, description: "Factor VIII Activity"),
        "factor_ix": LabParameter(name: "Factor IX", key: "factor_ix", unit: "%", referenceRange: "50-200", category: .coagulation, description: "Factor IX Activity"),
        "von_willebrand_factor": LabParameter(name: "Von Willebrand Factor", key: "von_willebrand_factor", unit: "%", referenceRange: "50-200", category: .coagulation, description: "Von Willebrand Factor"),
        
        // Additional Hormones
        "progesterone": LabParameter(name: "Progesterone", key: "progesterone", unit: "ng/mL", referenceRange: "0.1-25", category: .hormones, description: "Progesterone"),
        "prolactin": LabParameter(name: "Prolactin", key: "prolactin", unit: "ng/mL", referenceRange: "2-18", category: .hormones, description: "Prolactin"),
        "lh": LabParameter(name: "LH", key: "lh", unit: "mIU/mL", referenceRange: "1-18", category: .hormones, description: "Luteinizing Hormone"),
        "fsh": LabParameter(name: "FSH", key: "fsh", unit: "mIU/mL", referenceRange: "1-18", category: .hormones, description: "Follicle Stimulating Hormone"),
        "gh": LabParameter(name: "Growth Hormone", key: "gh", unit: "ng/mL", referenceRange: "<3", category: .hormones, description: "Growth Hormone (GH)"),
        "igf1": LabParameter(name: "IGF-1", key: "igf1", unit: "ng/mL", referenceRange: "117-329", category: .hormones, description: "Insulin-like Growth Factor 1"),
        "aldosterone": LabParameter(name: "Aldosterone", key: "aldosterone", unit: "ng/dL", referenceRange: "3-16", category: .hormones, description: "Aldosterone"),
        "renin": LabParameter(name: "Renin", key: "renin", unit: "ng/mL/hr", referenceRange: "0.5-4.0", category: .hormones, description: "Renin Activity"),
        
        // Additional Inflammatory Markers
        "il6": LabParameter(name: "Interleukin-6", key: "il6", unit: "pg/mL", referenceRange: "<3", category: .inflammatoryMarkers, description: "Interleukin-6 (IL-6)"),
        "tnf_alpha": LabParameter(name: "TNF-α", key: "tnf_alpha", unit: "pg/mL", referenceRange: "<8.1", category: .inflammatoryMarkers, description: "Tumor Necrosis Factor Alpha"),
        "ferritin_acute_phase": LabParameter(name: "Ferritin (Acute Phase)", key: "ferritin_acute_phase", unit: "ng/mL", referenceRange: "15-200", category: .inflammatoryMarkers, description: "Ferritin as acute phase reactant"),
        
        // Additional Vitamins and Minerals
        "vitamin_b1": LabParameter(name: "Vitamin B1", key: "vitamin_b1", unit: "ng/mL", referenceRange: "2.5-7.5", category: .vitaminsAndMinerals, description: "Thiamine (Vitamin B1)"),
        "vitamin_b2": LabParameter(name: "Vitamin B2", key: "vitamin_b2", unit: "ng/mL", referenceRange: "4-24", category: .vitaminsAndMinerals, description: "Riboflavin (Vitamin B2)"),
        "vitamin_b3": LabParameter(name: "Vitamin B3", key: "vitamin_b3", unit: "mg/dL", referenceRange: "0.5-8.5", category: .vitaminsAndMinerals, description: "Niacin (Vitamin B3)"),
        "vitamin_b9": LabParameter(name: "Vitamin B9", key: "vitamin_b9", unit: "ng/mL", referenceRange: "3-17", category: .vitaminsAndMinerals, description: "Folic Acid (Vitamin B9)"),
        "vitamin_k": LabParameter(name: "Vitamin K", key: "vitamin_k", unit: "ng/mL", referenceRange: "0.1-2.2", category: .vitaminsAndMinerals, description: "Vitamin K"),
        "manganese": LabParameter(name: "Manganese", key: "manganese", unit: "µg/L", referenceRange: "4-15", category: .vitaminsAndMinerals, description: "Manganese"),
        "chromium": LabParameter(name: "Chromium", key: "chromium", unit: "µg/L", referenceRange: "0.05-0.5", category: .vitaminsAndMinerals, description: "Chromium"),
        "molybdenum": LabParameter(name: "Molybdenum", key: "molybdenum", unit: "µg/L", referenceRange: "0.3-1.2", category: .vitaminsAndMinerals, description: "Molybdenum"),
        
        // Tumor Markers (Other category)
        "psa": LabParameter(name: "PSA", key: "psa", unit: "ng/mL", referenceRange: "<4.0", category: .other, description: "Prostate-Specific Antigen"),
        "cea": LabParameter(name: "CEA", key: "cea", unit: "ng/mL", referenceRange: "<3.0", category: .other, description: "Carcinoembryonic Antigen"),
        "ca125": LabParameter(name: "CA 125", key: "ca125", unit: "U/mL", referenceRange: "<35", category: .other, description: "Cancer Antigen 125"),
        "ca199": LabParameter(name: "CA 19-9", key: "ca199", unit: "U/mL", referenceRange: "<37", category: .other, description: "Cancer Antigen 19-9"),
        "afp": LabParameter(name: "AFP", key: "afp", unit: "ng/mL", referenceRange: "<10", category: .other, description: "Alpha-Fetoprotein"),
        
        // Additional Metabolic Tests
        "lactate_dehydrogenase": LabParameter(name: "Lactate Dehydrogenase", key: "lactate_dehydrogenase", unit: "U/L", referenceRange: "140-280", category: .other, description: "LDH, Lactate Dehydrogenase"),
        "alkaline_phosphatase_bone": LabParameter(name: "Alkaline Phosphatase (Bone)", key: "alkaline_phosphatase_bone", unit: "U/L", referenceRange: "44-147", category: .other, description: "Bone-specific Alkaline Phosphatase"),
        
        // Urinalysis (UA) - Physical/Chemical
        "urine_color": LabParameter(name: "Urine Color", key: "urine_color", unit: "", referenceRange: "Yellow", category: .urinalysis, description: "Urine color"),
        "urine_appearance": LabParameter(name: "Urine Appearance", key: "urine_appearance", unit: "", referenceRange: "Clear", category: .urinalysis, description: "Urine appearance/clarity"),
        "urine_specific_gravity": LabParameter(name: "Urine Specific Gravity", key: "urine_specific_gravity", unit: "", referenceRange: "1.005-1.030", category: .urinalysis, description: "Urine specific gravity"),
        "urine_ph": LabParameter(name: "Urine pH", key: "urine_ph", unit: "", referenceRange: "5.0-8.0", category: .urinalysis, description: "Urine pH"),
        "urine_protein": LabParameter(name: "Urine Protein", key: "urine_protein", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine protein (dipstick)"),
        "urine_glucose": LabParameter(name: "Urine Glucose", key: "urine_glucose", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine glucose (dipstick)"),
        "urine_ketones": LabParameter(name: "Urine Ketones", key: "urine_ketones", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine ketones (dipstick)"),
        "urine_blood": LabParameter(name: "Urine Blood", key: "urine_blood", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine blood (hematuria)"),
        "urine_bilirubin": LabParameter(name: "Urine Bilirubin", key: "urine_bilirubin", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine bilirubin"),
        "urine_urobilinogen": LabParameter(name: "Urine Urobilinogen", key: "urine_urobilinogen", unit: "mg/dL", referenceRange: "0.2-1.0", category: .urinalysis, description: "Urine urobilinogen"),
        "urine_nitrite": LabParameter(name: "Urine Nitrite", key: "urine_nitrite", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine nitrite"),
        "urine_leukocyte_esterase": LabParameter(name: "Urine Leukocyte Esterase", key: "urine_leukocyte_esterase", unit: "", referenceRange: "Negative", category: .urinalysis, description: "Urine leukocyte esterase"),
        
        // Urinalysis - Microscopic
        "urine_wbc": LabParameter(name: "Urine White Blood Cells", key: "urine_wbc", unit: "/HPF", referenceRange: "0-5", category: .urinalysis, description: "Urine white blood cells per high power field"),
        "urine_rbc": LabParameter(name: "Urine Red Blood Cells", key: "urine_rbc", unit: "/HPF", referenceRange: "0-3", category: .urinalysis, description: "Urine red blood cells per high power field"),
        "urine_epithelial_cells": LabParameter(name: "Urine Epithelial Cells", key: "urine_epithelial_cells", unit: "/HPF", referenceRange: "0-5", category: .urinalysis, description: "Urine epithelial cells"),
        "urine_bacteria": LabParameter(name: "Urine Bacteria", key: "urine_bacteria", unit: "", referenceRange: "None", category: .urinalysis, description: "Urine bacteria"),
        "urine_casts": LabParameter(name: "Urine Casts", key: "urine_casts", unit: "/LPF", referenceRange: "0-2", category: .urinalysis, description: "Urine casts per low power field"),
        "urine_crystals": LabParameter(name: "Urine Crystals", key: "urine_crystals", unit: "", referenceRange: "None", category: .urinalysis, description: "Urine crystals"),
        "urine_mucus": LabParameter(name: "Urine Mucus", key: "urine_mucus", unit: "", referenceRange: "None", category: .urinalysis, description: "Urine mucus"),
        "urine_yeast": LabParameter(name: "Urine Yeast", key: "urine_yeast", unit: "", referenceRange: "None", category: .urinalysis, description: "Urine yeast"),
        
        // Urine Chemistry
        "urine_creatinine": LabParameter(name: "Urine Creatinine", key: "urine_creatinine", unit: "mg/dL", referenceRange: "20-320", category: .urineChemistry, description: "Urine creatinine"),
        "urine_protein_quantitative": LabParameter(name: "Urine Protein (Concentration)", key: "urine_protein_quantitative", unit: "mg/dL", referenceRange: nil, category: .urineChemistry, description: "Quantitative urine protein concentration; collection context required"),
        "urine_albumin": LabParameter(name: "Urine Albumin (Concentration)", key: "urine_albumin", unit: "mg/dL", referenceRange: nil, category: .urineChemistry, description: "Urine albumin concentration; collection context required"),
        "urine_microalbumin": LabParameter(name: "Urine Microalbumin (Concentration)", key: "urine_microalbumin", unit: "mg/dL", referenceRange: nil, category: .urineChemistry, description: "Urine microalbumin concentration; do not confuse with ACR"),
        "urine_protein_creatinine_ratio": LabParameter(name: "Urine Protein/Creatinine Ratio", key: "urine_protein_creatinine_ratio", unit: "mg/g", referenceRange: "<150", category: .urineChemistry, description: "Urine protein to creatinine ratio"),
        "urine_albumin_creatinine_ratio": LabParameter(name: "Urine Albumin/Creatinine Ratio", key: "urine_albumin_creatinine_ratio", unit: "mg/g", referenceRange: "<30", category: .urineChemistry, description: "Urine albumin to creatinine ratio (ACR)"),
        "urine_sodium": LabParameter(name: "Urine Sodium", key: "urine_sodium", unit: "mmol/L", referenceRange: nil, category: .urineChemistry, description: "Urine sodium concentration; spot versus timed collection required"),
        "urine_potassium": LabParameter(name: "Urine Potassium", key: "urine_potassium", unit: "mmol/L", referenceRange: nil, category: .urineChemistry, description: "Urine potassium concentration; spot versus timed collection required"),
        "urine_chloride": LabParameter(name: "Urine Chloride", key: "urine_chloride", unit: "mmol/L", referenceRange: nil, category: .urineChemistry, description: "Urine chloride concentration; spot versus timed collection required"),
        "urine_osmolality": LabParameter(name: "Urine Osmolality", key: "urine_osmolality", unit: "mOsm/kg", referenceRange: nil, category: .urineChemistry, description: "Urine osmolality; hydration and collection context required"),
        "urine_urea_nitrogen": LabParameter(name: "Urine Urea Nitrogen", key: "urine_urea_nitrogen", unit: "g/24h", referenceRange: nil, category: .urineChemistry, description: "Urine urea nitrogen, 24-hour collection"),
        "urine_creatinine_clearance": LabParameter(name: "Creatinine Clearance", key: "urine_creatinine_clearance", unit: "mL/min", referenceRange: nil, category: .urineChemistry, description: "Creatinine clearance, 24-hour urine; distinct from indexed eGFR"),
        "urine_calcium": LabParameter(name: "Urine Calcium", key: "urine_calcium", unit: "mg/24h", referenceRange: nil, category: .urineChemistry, description: "24-hour urine calcium"),
        "urine_uric_acid": LabParameter(name: "Urine Uric Acid", key: "urine_uric_acid", unit: "mg/24h", referenceRange: nil, category: .urineChemistry, description: "24-hour urine uric acid"),
        "urine_phosphate": LabParameter(name: "Urine Phosphate", key: "urine_phosphate", unit: "mg/24h", referenceRange: nil, category: .urineChemistry, description: "24-hour urine phosphate"),
        "urine_magnesium": LabParameter(name: "Urine Magnesium", key: "urine_magnesium", unit: "mg/24h", referenceRange: nil, category: .urineChemistry, description: "24-hour urine magnesium"),
        
        // Urine Microbiology
        "urine_culture": LabParameter(name: "Urine Culture", key: "urine_culture", unit: "", referenceRange: "No growth", category: .urineMicrobiology, description: "Urine culture result"),
        "urine_bacteria_count": LabParameter(name: "Urine Bacteria Count", key: "urine_bacteria_count", unit: "CFU/mL", referenceRange: "<10,000", category: .urineMicrobiology, description: "Urine bacterial colony count")
    ]

    // MARK: - Lab Parameter Aliases
    /// Known aliases for standardized lab parameters, in normalized form
    /// (lowercased, punctuation collapsed to underscores — see `normalizeLabName`).
    /// The single source of truth for name-variation matching; consumed by `matchLabParameter`.
    static let labParameterAliases: [String: [String]] = [
        // Glucose
        "glucose": ["blood_sugar", "blood_glucose", "glucose_serum", "glucose_plasma", "gluc"],
        "fasting_glucose": ["fasting_blood_glucose", "fbg", "glucose_fasting"],
        "random_glucose": ["random_blood_glucose", "rbg", "glucose_random"],
        "glucose_tolerance_test_2hr": ["2_hour_glucose", "gtt_2hr", "glucose_tolerance_2hr", "2hr_glucose"],
        // Hemoglobin / CBC
        "hemoglobin": ["hgb", "hb", "hemoglobin_concentration"],
        "hematocrit": ["hct", "crit", "packed_cell_volume", "pcv"],
        "hemoglobin_a1c": ["hba1c", "a1c", "glycated_hemoglobin", "glycosylated_hemoglobin", "hemoglobin_a1c_hba1c", "hgb_a1c"],
        "wbc": ["white_blood_cell_count", "white_blood_cells", "white_blood_cell", "leukocytes", "leukocyte_count", "wbc_count"],
        "rbc": ["red_blood_cell_count", "red_blood_cells", "red_blood_cell", "erythrocytes", "erythrocyte_count", "rbc_count"],
        "platelet_count": ["platelets", "plt", "platelet", "thrombocytes", "thrombocyte_count"],
        "mcv": ["mean_corpuscular_volume", "mean_cell_volume"],
        "mch": ["mean_corpuscular_hemoglobin", "mean_cell_hemoglobin"],
        "mchc": ["mean_corpuscular_hemoglobin_concentration"],
        "rdw": ["red_cell_distribution_width", "rdw_cv", "rdw_sd", "red_blood_cell_distribution_width"],
        "mpv": ["mean_platelet_volume"],
        "reticulocyte_count": ["retic", "retics", "reticulocytes", "reticulocyte"],
        "immature_granulocytes": ["ig", "immature_grans", "immature_granulocyte"],
        "nucleated_rbc": ["nrbc", "nucleated_red_blood_cells", "nucleated_rbcs"],
        "platelet_distribution_width": ["pdw"],
        // CBC differential — absolute vs percent must stay distinct
        "absolute_neutrophils": ["abs_neutrophils", "neutrophils_absolute", "neutrophil_count", "neutrophils_abs", "absolute_neutrophil_count", "anc", "neut_abs", "neutrophils_number"],
        "absolute_lymphocytes": ["abs_lymphocytes", "lymphocytes_absolute", "lymphocyte_count", "lymphocytes_abs", "absolute_lymphocyte_count", "lymphs_abs", "lymphocytes_number"],
        "absolute_monocytes": ["abs_monocytes", "monocytes_absolute", "monocyte_count", "monocytes_abs", "absolute_monocyte_count", "monos_abs", "monocytes_number"],
        "absolute_eosinophils": ["abs_eosinophils", "eosinophils_absolute", "eosinophil_count", "eosinophils_abs", "absolute_eosinophil_count", "eos_abs", "eosinophils_number"],
        "absolute_basophils": ["abs_basophils", "basophils_absolute", "basophil_count", "basophils_abs", "absolute_basophil_count", "basos_abs", "basophils_number"],
        "neutrophils": ["neutrophils_percent", "neutrophil", "neut", "neuts", "segs", "segmented_neutrophils", "polys"],
        "lymphocytes": ["lymphocytes_percent", "lymphocyte", "lymphs", "lymph"],
        "monocytes": ["monocytes_percent", "monocyte", "monos", "mono"],
        "eosinophils": ["eosinophils_percent", "eosinophil", "eos"],
        "basophils": ["basophils_percent", "basophil", "basos", "baso"],
        // Metabolic panel
        "sodium": ["na", "sodium_serum"],
        "potassium": ["k", "potassium_serum"],
        "chloride": ["cl", "chloride_serum"],
        "co2_bicarbonate": ["co2", "bicarbonate", "carbon_dioxide", "hco3", "co2_total", "total_co2"],
        "anion_gap": ["agap", "anion_gap_calculated"],
        "bun": ["blood_urea_nitrogen", "urea_nitrogen", "urea"],
        "creatinine": ["creat", "serum_creatinine", "cr", "creatinine_serum"],
        "egfr": ["estimated_gfr", "gfr", "egfr_estimated", "glomerular_filtration_rate", "egfr_non_african_american", "egfr_african_american"],
        "bun_creatinine_ratio": ["bun_cr_ratio", "bun_creat_ratio", "urea_creatinine_ratio"],
        "abo_blood_type": ["abo", "abo_group", "abo_rh", "abo_rh_type", "blood_group", "blood_group_and_rh", "blood_type"],
        "rh_factor": ["rh", "rhesus", "rhesus_factor", "rh_type"],
        "cystatin_c": ["cys_c"],
        "calcium": ["ca", "calcium_serum", "calcium_total", "total_calcium"],
        "albumin": ["alb", "albumin_serum"],
        "total_protein": ["protein_total", "tp", "protein_serum"],
        "albumin_globulin_ratio": ["a_g_ratio", "ag_ratio", "albumin_globulin"],
        "phosphorus": ["phosphate", "phos", "inorganic_phosphorus"],
        "magnesium": ["mg", "magnesium_serum"],
        "uric_acid": ["urate"],
        "lactate": ["lactic_acid"],
        // Lipids
        "cholesterol_total": ["total_cholesterol", "cholesterol", "chol_total", "chol"],
        "ldl_cholesterol": ["ldl", "ldl_chol", "low_density_lipoprotein", "ldl_c"],
        "hdl_cholesterol": ["hdl", "hdl_chol", "high_density_lipoprotein", "hdl_c"],
        "ldl_chol_calc": ["ldl_calculated", "ldl_calc", "calculated_ldl", "ldl_cholesterol_calc"],
        "non_hdl_cholesterol": ["non_hdl", "non_hdl_c"],
        "chol_hdlc_ratio": ["cholesterol_hdl_ratio", "chol_hdl_ratio", "tc_hdl_ratio"],
        "triglycerides": ["tg", "trig", "trigs", "triglyceride"],
        "apolipoprotein_b": ["apob", "apo_b"],
        "lipoprotein_a": ["lpa", "lp_a", "lp_little_a"],
        // Liver
        "alt_sgpt": ["alt", "sgpt", "alanine_aminotransferase", "alanine_transaminase"],
        "ast_sgot": ["ast", "sgot", "aspartate_aminotransferase", "aspartate_transaminase"],
        "alp": ["alkaline_phosphatase", "alk_phos", "alk_phosphatase"],
        "ggt": ["gamma_glutamyl_transferase", "gamma_gt", "ggtp"],
        "ldh": ["lactate_dehydrogenase", "ld"],
        "bilirubin_total": ["total_bilirubin", "tbili", "t_bili", "bilirubin"],
        "bilirubin_direct": ["direct_bilirubin", "dbili", "d_bili", "conjugated_bilirubin"],
        "bilirubin_indirect": ["indirect_bilirubin", "unconjugated_bilirubin"],
        "ammonia": ["nh3", "blood_ammonia"],
        // Thyroid
        "tsh": ["thyroid_stimulating_hormone", "thyrotropin"],
        "free_t4": ["ft4", "free_thyroxine", "t4_free", "thyroxine_free"],
        "free_t3": ["ft3", "free_triiodothyronine", "t3_free", "triiodothyronine_free"],
        "total_t4": ["t4", "total_thyroxine", "thyroxine", "t4_total"],
        "total_t3": ["t3", "total_triiodothyronine", "triiodothyronine", "t3_total"],
        "reverse_t3": ["rt3", "reverse_triiodothyronine", "t3_reverse"],
        "thyroid_peroxidase_antibodies": ["tpo_ab", "tpo_antibodies", "anti_tpo", "tpo"],
        "thyroglobulin_antibody": ["tg_ab", "thyroglobulin_ab", "anti_tg", "anti_thyroglobulin"],
        "tsh_receptor_antibodies": ["trab", "tsh_receptor_ab"],
        // Diabetes
        "insulin": ["serum_insulin", "insulin_level", "insulin_fasting", "fasting_insulin"],
        "c_peptide": ["cpeptide", "connecting_peptide"],
        // Cardiac
        "troponin_i": ["trop_i", "ctni", "troponin_i_high_sensitivity", "hs_troponin_i"],
        "troponin_t": ["trop_t", "ctnt", "troponin_t_high_sensitivity", "hs_troponin_t"],
        "bnp": ["b_type_natriuretic_peptide", "bnp_level", "brain_natriuretic_peptide"],
        "nt_pro_bnp": ["nt_probnp", "ntprobnp", "n_terminal_pro_bnp", "pro_bnp", "probnp"],
        "ck_mb": ["ckmb", "creatine_kinase_mb"],
        "ck_total": ["cpk", "total_ck", "creatine_phosphokinase"],
        "creatine_kinase": ["ck", "cpk_total"],
        "homocysteine": ["hcy", "homocysteine_level"],
        // Inflammatory
        "crp_c_reactive_protein": ["crp", "c_reactive_protein", "reactive_protein"],
        "hs_crp": ["high_sensitivity_crp", "hs_c_reactive_protein", "cardiac_crp", "crp_high_sensitivity"],
        "esr": ["erythrocyte_sedimentation_rate", "sed_rate", "sedimentation_rate", "westergren"],
        "il6": ["interleukin_6", "il_6"],
        "tnf_alpha": ["tumor_necrosis_factor_alpha", "tnf_a", "tnf"],
        // Coagulation
        "pt": ["prothrombin_time", "pro_time", "protime"],
        "ptt": ["partial_thromboplastin_time"],
        "aptt": ["activated_partial_thromboplastin_time"],
        "inr": ["international_normalized_ratio"],
        "d_dimer": ["ddimer"],
        "fibrinogen": ["fibrinogen_level", "fibrinogen_activity"],
        // Vitamins & minerals
        "vitamin_d": ["25_oh_vitamin_d", "25_hydroxyvitamin_d", "vit_d", "25ohd", "vitamin_d_25_hydroxy", "vitamin_d3", "25_hydroxy_vitamin_d"],
        "vitamin_b12": ["b12", "cobalamin", "vitamin_b_12", "vit_b12"],
        "folate": ["folic_acid", "folate_serum"],
        "folate_rbc": ["rbc_folate", "red_blood_cell_folate"],
        "iron": ["serum_iron", "fe", "iron_serum", "iron_total"],
        "ferritin": ["ferritin_level", "ferritin_serum"],
        "tibc": ["total_iron_binding_capacity", "iron_binding_capacity"],
        "percent_saturation": ["iron_saturation", "tsat", "transferrin_saturation", "iron_sat", "saturation"],
        "zinc": ["zn", "zinc_serum"],
        "copper": ["cu", "copper_serum"],
        "vitamin_b6": ["b6", "pyridoxal_5_phosphate", "pyridoxine"],
        "vitamin_b1": ["b1", "thiamine"],
        "vitamin_b2": ["b2", "riboflavin"],
        "vitamin_a": ["retinol"],
        "vitamin_e": ["alpha_tocopherol", "tocopherol"],
        "vitamin_c": ["ascorbic_acid"],
        // Hormones
        "testosterone": ["total_testosterone", "testosterone_total"],
        "estradiol": ["e2", "estradiol_level"],
        "cortisol": ["cortisol_level", "serum_cortisol"],
        "cortisol_am": ["morning_cortisol", "am_cortisol"],
        "parathyroid_hormone": ["pth", "intact_pth", "pth_intact"],
        "progesterone": ["prog", "progesterone_level"],
        "prolactin": ["prl", "prolactin_level"],
        "lh": ["luteinizing_hormone"],
        "fsh": ["follicle_stimulating_hormone"],
        "gh": ["growth_hormone", "hgh", "somatotropin"],
        "igf1": ["igf_1", "insulin_like_growth_factor_1", "somatomedin_c"],
        "aldosterone": ["aldosterone_serum"],
        "renin": ["renin_activity", "plasma_renin_activity", "pra"],
        // Immunology / tumor markers
        "total_ige": ["ige", "immunoglobulin_e"],
        "iga": ["immunoglobulin_a"],
        "igg": ["immunoglobulin_g"],
        "igm": ["immunoglobulin_m"],
        "psa": ["prostate_specific_antigen", "total_psa", "psa_total"],
        "cea": ["carcinoembryonic_antigen"],
        "ca125": ["ca_125", "cancer_antigen_125"],
        "ca199": ["ca_19_9", "cancer_antigen_19_9"],
        "afp": ["alpha_fetoprotein", "alpha_feto_protein"],
        // Urinalysis
        "urine_specific_gravity": ["specific_gravity", "sp_gr", "sg", "spec_grav"],
        "urine_ph": ["ph"],
        "urine_protein": ["protein_dipstick", "protein_qualitative", "protein"],
        "urine_glucose": ["glucose_dipstick", "glucose"],
        "urine_ketones": ["ketones", "ketone"],
        "urine_blood": ["blood", "occult_blood", "hemoglobin_dipstick"],
        "urine_bilirubin": ["bilirubin"],
        "urine_urobilinogen": ["urobilinogen"],
        "urine_nitrite": ["nitrite", "nitrites"],
        "urine_leukocyte_esterase": ["leukocyte_esterase", "leuk_esterase", "leukocytes"],
        "urine_color": ["color"],
        "urine_appearance": ["appearance", "clarity"],
        "urine_wbc": ["wbc", "white_blood_cells", "wbc_hpf", "wbcs"],
        "urine_rbc": ["rbc", "red_blood_cells", "rbc_hpf", "rbcs"],
        "urine_epithelial_cells": ["epithelial_cells", "squamous_epithelial_cells", "epithelial"],
        "urine_bacteria": ["bacteria"],
        "urine_casts": ["casts", "hyaline_casts"],
        "urine_crystals": ["crystals"],
        "urine_mucus": ["mucus", "mucus_threads"],
        "urine_yeast": ["yeast"],
        "urine_creatinine": ["creatinine"],
        "urine_microalbumin": ["microalbumin"],
        "urine_albumin_creatinine_ratio": ["acr", "albumin_creatinine_ratio", "microalbumin_creatinine_ratio", "alb_creat_ratio"],
        "urine_protein_creatinine_ratio": ["protein_creatinine_ratio", "prot_creat_ratio", "upcr"],
        "urine_creatinine_clearance": ["creatinine_clearance", "crcl"],
        "urine_culture": ["culture"]
    ]

    // MARK: - Lab Test Type
    enum LabTestType: String {
        case blood = "BLOOD"
        case urine = "URINE"
    }

    private static let urineLabCategories: Set<BloodTestCategory> = [.urinalysis, .urineChemistry, .urineMicrobiology]

    /// Normalize a lab test name for matching: lowercase, µ→u, punctuation/whitespace
    /// collapsed to single underscores.
    static func normalizeLabName(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: "µ", with: "u")
        s = s.replacingOccurrences(of: "μ", with: "u")
        s = s.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Alias → standard key index, built once from `labParameterAliases`.
    private static let aliasIndex: [String: String] = {
        var index: [String: String] = [:]
        for (key, aliases) in labParameterAliases {
            for alias in aliases {
                index[normalizeLabName(alias)] = key
            }
        }
        return index
    }()

    /// Normalized display name → standard key index.
    private static let nameIndex: [String: String] = {
        var index: [String: String] = [:]
        for (key, parameter) in standardizedLabParameters {
            index[normalizeLabName(parameter.name)] = key
        }
        return index
    }()

    // MARK: - Shared Lab Parameter Matcher
    /// Match a raw test name (as extracted from a document) to a standardized lab parameter.
    ///
    /// Matching order: exact key → exact alias → exact display name → urine-prefixed key →
    /// bounded containment (longest key wins) → bounded edit distance. Urine and blood
    /// parameters never cross-match, and CBC percent vs absolute pairs stay distinct
    /// because their aliases are enumerated explicitly.
    static func matchLabParameter(
        name: String,
        testType: LabTestType = .blood
    ) -> (key: String, parameter: LabParameter, matchConfidence: Double)? {
        let normalized = normalizeLabName(name)
        guard !normalized.isEmpty else { return nil }

        func typeMatches(_ parameter: LabParameter) -> Bool {
            testType == .urine
                ? urineLabCategories.contains(parameter.category)
                : !urineLabCategories.contains(parameter.category)
        }

        // For urine tests, prefer the urine_-prefixed parameter for bare names
        // ("Glucose" on a urinalysis panel means urine_glucose, not serum glucose).
        if testType == .urine {
            let prefixed = normalized.hasPrefix("urine_") ? normalized : "urine_" + normalized
            if let parameter = standardizedLabParameters[prefixed] {
                return (prefixed, parameter, 0.95)
            }
        }

        // 1. Exact key match
        if let parameter = standardizedLabParameters[normalized], typeMatches(parameter) {
            return (normalized, parameter, 1.0)
        }

        // 2. Exact alias match
        if let key = aliasIndex[normalized], let parameter = standardizedLabParameters[key], typeMatches(parameter) {
            return (key, parameter, 0.95)
        }

        // 3. Exact display-name match
        if let key = nameIndex[normalized], let parameter = standardizedLabParameters[key], typeMatches(parameter) {
            return (key, parameter, 0.95)
        }

        // 4. Bounded containment — longest matching key wins so specific parameters
        //    beat generic ones. Requires the shorter side ≥ 4 chars to avoid
        //    accidental hits from short abbreviations.
        var bestContainment: (key: String, parameter: LabParameter)?
        for (key, parameter) in standardizedLabParameters where typeMatches(parameter) {
            guard min(normalized.count, key.count) >= 4 else { continue }
            if normalized.contains(key) || key.contains(normalized) {
                if bestContainment == nil || key.count > bestContainment!.key.count {
                    bestContainment = (key, parameter)
                }
            }
        }
        if let match = bestContainment {
            return (match.key, match.parameter, 0.6)
        }

        // 5. Bounded edit distance against keys and aliases (OCR typo tolerance)
        let maxDistance = normalized.count >= 10 ? 2 : (normalized.count >= 6 ? 1 : 0)
        if maxDistance > 0 {
            var bestEdit: (key: String, parameter: LabParameter, distance: Int)?
            func consider(candidate: String, key: String) {
                guard abs(candidate.count - normalized.count) <= maxDistance else { return }
                guard let parameter = standardizedLabParameters[key], typeMatches(parameter) else { return }
                let distance = editDistance(normalized, candidate, limit: maxDistance)
                if distance <= maxDistance, bestEdit == nil || distance < bestEdit!.distance {
                    bestEdit = (key, parameter, distance)
                }
            }
            for key in standardizedLabParameters.keys {
                consider(candidate: key, key: key)
            }
            for (alias, key) in aliasIndex {
                consider(candidate: alias, key: key)
            }
            if let match = bestEdit {
                return (match.key, match.parameter, 0.55)
            }
        }

        return nil
    }

    /// Levenshtein distance with early exit once `limit` is exceeded.
    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        for i in 1...aChars.count {
            var current = [i] + Array(repeating: 0, count: bChars.count)
            var rowMin = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[bChars.count]
    }

    static var bloodTestExtractionHint: String {
        let grouped = Dictionary(grouping: standardizedLabParameters.values) { $0.category }
        let sortedGroups = grouped.sorted { lhs, rhs in
            lhs.key.displayName < rhs.key.displayName
        }

        let categorySummaries = sortedGroups.map { group -> String in
            let categoryName = group.key.displayName
            let testNames = group.value.map { $0.name }.sorted().joined(separator: ", ")
            return "\(categoryName): \(testNames)"
        }

        // Create a comprehensive list of all test names and common abbreviations
        _ = standardizedLabParameters.values.map { $0.name }.sorted() // Available for future use
        let commonAbbreviations = [
            "CBC", "CMP", "BMP", "HGB", "HCT", "WBC", "RBC", "PLT", "MCV", "MCH", "MCHC",
            "RDW", "MPV", "ALT", "AST", "ALP", "GGT", "LDH", "TSH", "T4", "T3", "FT4", "FT3",
            "HbA1c", "A1C", "CRP", "ESR", "PT", "PTT", "INR", "BNP", "CK", "CK-MB", "Troponin",
            "LDL", "HDL", "TG", "Chol", "BUN", "Cr", "eGFR", "Na", "K", "Cl", "CO2", "Ca", "Mg", "P"
        ]
        
        return """
        EXTRACT ALL LABORATORY VALUES FROM THIS DOCUMENT (BOTH BLOOD AND URINE TESTS)
        
        CRITICAL: IGNORE ALL IMAGES - ONLY EXTRACT TEXT
        - Do NOT extract, return, or include any image data
        - Perform OCR on images to extract text, but discard the image data itself
        - Only return text content - no image files, no base64 image data, no image references
        - If text is embedded in images, extract it via OCR but exclude the image
        
        Instructions:
        1. Identify ALL numerical laboratory test results in the document - BOTH blood tests AND urine tests
        2. For each test, extract:
           - Test name (exactly as written, including abbreviations)
           - Test type: "BLOOD" or "URINE" (determine from section header, test name, or context)
           - Numerical value (or "Negative"/"Positive" for qualitative urine tests)
           - Unit of measurement (mg/dL, g/dL, %, U/L, /HPF, /LPF, etc.)
           - Reference range (normal range) if provided
           - Abnormal flag (High, Low, Critical, H, L, *, Positive, Negative, etc.) if present
        
        3. Look for sections labeled:
           - Blood tests: "Chemistry", "Hematology", "Serum", "Plasma", "Blood"
           - Urine tests: "Urinalysis", "UA", "Urine", "Urine Analysis", "Urine Chemistry"
        
        4. Common test categories to look for:
        \(categorySummaries.joined(separator: "\n"))
        
        4. Common abbreviations to recognize:
        \(commonAbbreviations.joined(separator: ", "))
        
        5. Pay special attention to:
           - Tables with test results (often have columns: Test Name | Value | Unit | Reference Range | Flag)
           - Sections labeled "Results", "Laboratory Results", "Test Results", "Lab Values"
           - Both absolute values and percentages for CBC differentials
           - Calculated values (e.g., LDL calculated, ratios)
           - Multiple panels (CBC, CMP, Lipid Panel, etc.) in the same document
        
        6. Format requirements:
           - Preserve exact test names as they appear (don't normalize)
           - Include all variations (e.g., "HbA1c", "A1C", "Hemoglobin A1c" are all valid)
           - Capture reference ranges exactly as shown (e.g., "<200", "70-100", ">40")
           - Note any flags or indicators of abnormal values
        
        7. Important: Extract EVERY numerical lab value you find, even if it's not in the standard list above.
        """
    }
}

// MARK: - Common Blood Test Items
extension BloodTestItem {
    static let commonTests: [BloodTestItem] = Array(BloodTestResult.standardizedLabParameters.values.prefix(20)).map { param in
        BloodTestItem(
            name: param.name,
            value: param.value ?? "",
            unit: param.unit,
            referenceRange: param.referenceRange,
            category: param.category
        )
    }
}
