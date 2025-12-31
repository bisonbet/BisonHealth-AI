//
//  JSONKeyMapping.swift
//  HealthApp
//
//  JSON key mapping extensions for health data enums
//  Provides snake_case JSON representations for all enum types
//

import Foundation

// MARK: - Health Data Type JSON Mapping
extension HealthDataType {
    /// JSON key representation (already snake_case in raw value)
    var jsonKey: String {
        return self.rawValue
    }
}

// MARK: - Gender JSON Mapping
extension Gender {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Blood Type JSON Mapping
extension BloodType {
    /// JSON value representation (convert symbols to snake_case)
    var jsonValue: String {
        switch self {
        case .aPositive: return "a_positive"
        case .aNegative: return "a_negative"
        case .bPositive: return "b_positive"
        case .bNegative: return "b_negative"
        case .abPositive: return "ab_positive"
        case .abNegative: return "ab_negative"
        case .oPositive: return "o_positive"
        case .oNegative: return "o_negative"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Vital Source JSON Mapping
extension VitalSource {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Medication Frequency JSON Mapping
extension Frequency {
    /// JSON representation (returns object for .other case)
    func jsonValue() -> Any {
        switch self {
        case .daily:
            return "daily"
        case .twiceDaily:
            return "twice_daily"
        case .threeTimesDaily:
            return "three_times_daily"
        case .weekly:
            return "weekly"
        case .other(let customValue):
            return ["type": "other", "value": customValue]
        }
    }
}

// MARK: - Medication End Date JSON Mapping
extension MedicationEndDate {
    /// JSON representation (returns string or object)
    func jsonValue() -> Any {
        switch self {
        case .ongoing:
            return "ongoing"
        case .specific(let date):
            return ["type": "specific", "date": ISO8601DateFormatter().string(from: date)]
        }
    }
}

// MARK: - Dosage Unit JSON Mapping
extension DosageUnit {
    /// JSON value representation
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Supplement Category JSON Mapping
extension SupplementCategory {
    /// JSON value representation (convert to snake_case)
    var jsonValue: String {
        switch self {
        case .vitamin: return "vitamin"
        case .mineral: return "mineral"
        case .herb: return "herb"
        case .aminoAcid: return "amino_acid"
        case .fattyAcid: return "fatty_acid"
        case .probiotic: return "probiotic"
        case .protein: return "protein"
        case .fiber: return "fiber"
        case .other: return "other"
        }
    }
}

// MARK: - Medical Condition Status JSON Mapping
extension MedicalConditionStatus {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Medical Condition Severity JSON Mapping
extension MedicalConditionSeverity {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Blood Test Category JSON Mapping
extension BloodTestCategory {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Document Category JSON Mapping
extension DocumentCategory {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Provider Type JSON Mapping
extension ProviderType {
    /// JSON value representation (already snake_case in raw value)
    var jsonValue: String {
        return self.rawValue
    }
}

// MARK: - Helper Extensions for JSON Encoding

extension Double {
    /// Clean string representation (remove .0 from whole numbers)
    var jsonValue: Any {
        if self.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(self)
        }
        return self
    }
}

extension Measurement where UnitType == UnitLength {
    /// JSON representation in centimeters
    var jsonValue: [String: Any] {
        let valueInCm = self.converted(to: .centimeters).value
        return [
            "value": valueInCm.jsonValue,
            "unit": "cm"
        ]
    }
}

extension Measurement where UnitType == UnitMass {
    /// JSON representation in kilograms
    var jsonValue: [String: Any] {
        let valueInKg = self.converted(to: .kilograms).value
        return [
            "value": valueInKg.jsonValue,
            "unit": "kg"
        ]
    }
}
