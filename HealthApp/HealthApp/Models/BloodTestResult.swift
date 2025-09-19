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
        "sodium": LabParameter(name: "Sodium", key: "sodium", unit: "mEq/L", referenceRange: "136-145", category: .basicMetabolicPanel, description: "Sodium"),
        "potassium": LabParameter(name: "Potassium", key: "potassium", unit: "mEq/L", referenceRange: "3.5-5.0", category: .basicMetabolicPanel, description: "Potassium"),
        "chloride": LabParameter(name: "Chloride", key: "chloride", unit: "mEq/L", referenceRange: "98-107", category: .basicMetabolicPanel, description: "Chloride"),
        "co2_bicarbonate": LabParameter(name: "CO2 (Bicarbonate)", key: "co2_bicarbonate", unit: "mEq/L", referenceRange: "22-29", category: .basicMetabolicPanel, description: "CO2, Serum Bicarbonate"),
        "anion_gap": LabParameter(name: "Anion Gap", key: "anion_gap", unit: "mEq/L", referenceRange: "7-16", category: .basicMetabolicPanel, description: "Anion Gap"),
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
        "total_ige": LabParameter(name: "Total IgE", key: "total_ige", unit: "IU/mL", referenceRange: "0-100", category: .immunology, description: "Total Immunoglobulin E")
    ]

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

        return """
        Focus on extracting quantitative lab analytes from the following panels: \(categorySummaries.joined(separator: " | ")). Capture the reported value, units, reference ranges, and abnormal flags for each analyte you encounter.
        """.trimmingCharacters(in: .whitespacesAndNewlines)
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