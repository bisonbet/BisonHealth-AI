import Foundation

// MARK: - Blood Test Value Validator
struct BloodTestValueValidator {

    // MARK: - Validation Result
    enum ValidationResult {
        case valid
        /// The value is parseable and can be imported with an explicit warning,
        /// but the reported unit does not match the parameter policy.
        case unitMismatch(reason: String)
        /// The extracted value itself is not a usable single result.
        case invalidType(reason: String)
        /// Retained for compatibility with older callers. New numeric values
        /// are not rejected solely because they are outside a reference range.
        case outOfRange(reason: String, standardDeviations: Double)
        case missingData(reason: String)
    }

    private struct ParsedReferenceRange {
        let minimum: Double?
        let maximum: Double?
    }

    // MARK: - Qualitative Values
    private static let genericQualitativeValues: Set<String> = [
        "negative", "positive", "trace", "none", "notdetected", "noneseen",
        "reactive", "non-reactive", "nonreactive", "nogrowth", "normal", "clear", "yellow",
        "straw", "amber", "cloudy", "hazy", "turbid", "few", "moderate", "many",
        "rare", "occasional", "small", "large", "1+", "2+", "3+", "4+"
    ]

    private static let parameterQualitativeValues: [String: Set<String>] = [
        "urine_protein": ["negative", "trace", "1+", "2+", "3+", "4+"],
        "urine_glucose": ["negative", "trace", "1+", "2+", "3+", "4+"],
        "urine_ketones": ["negative", "trace", "small", "moderate", "large", "1+", "2+", "3+", "4+"],
        "urine_blood": ["negative", "trace", "small", "moderate", "large", "1+", "2+", "3+", "4+"],
        "urine_bilirubin": ["negative", "small", "moderate", "large", "1+", "2+", "3+", "4+"],
        "urine_nitrite": ["negative", "positive"],
        "urine_leukocyte_esterase": ["negative", "trace", "small", "moderate", "large", "1+", "2+", "3+", "4+"],
        "urine_color": ["yellow", "straw", "amber", "clear", "red", "brown", "orange", "pink"],
        "urine_appearance": ["clear", "cloudy", "hazy", "turbid"],
        "urine_bacteria": ["none", "few", "moderate", "many", "rare", "occasional"],
        "urine_casts": ["none", "few", "moderate", "many", "hyaline"],
        "urine_crystals": ["none", "few", "moderate", "many"],
        "urine_mucus": ["none", "few", "moderate", "many"],
        "urine_yeast": ["none", "few", "moderate", "many"],
        "urine_culture": ["nogrowth", "negative", "positive"],
        "abo_blood_type": ["a", "b", "ab", "o", "a+", "a-", "b+", "b-", "ab+", "ab-", "o+", "o-"],
        "rh_factor": ["positive", "negative", "+", "-"]
    ]

    static func isQualitativeValue(_ value: String) -> Bool {
        genericQualitativeValues.contains(normalizeQualitativeValue(value))
    }

    private static func isQualitativeValue(_ value: String, for parameter: LabParameter?) -> Bool {
        let normalized = normalizeQualitativeValue(value)
        guard let parameter else { return genericQualitativeValues.contains(normalized) }

        if let allowed = parameterQualitativeValues[parameter.key] {
            if allowed.contains(normalized) {
                return true
            }

            if parameter.key == "abo_blood_type" {
                let compact = normalized
                    .replacingOccurrences(of: "rhesus", with: "")
                    .replacingOccurrences(of: "rh", with: "")
                let bloodTypePattern = #"^(a|b|ab|o)(\+|-|positive|negative|pos|neg)$"#
                let regex = try? NSRegularExpression(pattern: bloodTypePattern)
                let range = NSRange(location: 0, length: compact.utf16.count)
                return regex?.firstMatch(in: compact, range: range) != nil
            }

            if parameter.key == "rh_factor" {
                let compact = normalized
                    .replacingOccurrences(of: "rhesus", with: "")
                    .replacingOccurrences(of: "rh", with: "")
                return ["positive", "negative", "+", "-", "pos", "neg"].contains(compact)
            }

            return false
        }

        // Qualitative values are valid for urinalysis/microbiology by default,
        // but not for an arbitrary numeric serum analyte.
        switch parameter.category {
        case .urinalysis, .urineChemistry, .urineMicrobiology:
            return genericQualitativeValues.contains(normalized)
        default:
            return false
        }
    }

    private static func normalizeQualitativeValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    // MARK: - Validate Value
    /// Validates whether the extracted result is structurally importable.
    /// Reference ranges are used for interpretation, not for rejecting a real
    /// numeric result: abnormal results are still medical data.
    static func validateValue(
        _ value: String,
        testName: String,
        referenceRange: String?,
        standardParam: LabParameter?
    ) -> ValidationResult {
        _ = testName
        _ = referenceRange

        if isQualitativeValue(value, for: standardParam) {
            return .valid
        }

        guard isNumeric(value) else {
            if value.contains("-") && value.contains(where: { $0.isNumber }) {
                return .invalidType(reason: "Value appears to be a range, not a single numeric value")
            }
            if value.rangeOfCharacter(from: CharacterSet.letters) != nil {
                return .invalidType(reason: "Value contains non-numeric characters")
            }
            return .invalidType(reason: "Value is not numeric")
        }

        guard numericValue(value) != nil else {
            return .invalidType(reason: "Could not parse numeric value")
        }

        return .valid
    }

    // MARK: - Numeric Helpers
    private static func isNumeric(_ value: String) -> Bool {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        let numericPattern = #"^[<>≤≥]?\s*[+-]?[\d.]+([eE][+-]?\d+)?$"#
        let regex = try? NSRegularExpression(pattern: numericPattern)
        let range = NSRange(location: 0, length: cleaned.utf16.count)
        return regex?.firstMatch(in: cleaned, range: range) != nil
    }

    static func numericValue(_ value: String) -> Double? {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "≤", with: "")
            .replacingOccurrences(of: "≥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    /// Normalizes equivalent numeric spellings for cross-extraction merging.
    /// Comparison operators remain part of the key because `<0.04` is not the
    /// same assertion as `0.04`.
    static func normalizedValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let operatorPrefix = trimmed.first.map { "<>≤≥".contains($0) ? String($0) : "" } ?? ""
        if let numeric = numericValue(trimmed) {
            return "\(operatorPrefix)\(numeric)"
        }
        return normalizeQualitativeValue(trimmed)
    }

    // MARK: - Reference Range Interpretation
    /// Returns true/false when the supplied numeric value can be compared to
    /// the supplied range, and nil when either side is not interpretable.
    static func isOutsideReferenceRange(value: String, referenceRange: String?) -> Bool? {
        guard let numeric = numericValue(value),
              let referenceRange,
              let range = parseReferenceRange(referenceRange) else {
            return nil
        }

        let belowMinimum = range.minimum.map { numeric < $0 } ?? false
        let aboveMaximum = range.maximum.map { numeric > $0 } ?? false
        return belowMinimum || aboveMaximum
    }

    static func isAbnormal(value: String, referenceRange: String?, flag: String?) -> Bool {
        let normalizedFlag = flag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let rangeAbnormality = isOutsideReferenceRange(value: value, referenceRange: referenceRange)
            ?? isOutsideQualitativeReference(value: value, referenceRange: referenceRange)
            ?? false

        switch normalizedFlag {
        case "H", "HH", "HIGH", "CRITICAL HIGH", "L", "LL", "LOW", "CRITICAL LOW":
            return true
        case "NORMAL", "N", "":
            return rangeAbnormality
        case nil:
            return rangeAbnormality
        default:
            return true
        }
    }

    /// Compares textual reference ranges used by urinalysis and microbiology
    /// (for example, Positive versus Negative). Numeric ranges are handled by
    /// `isOutsideReferenceRange` and intentionally do not reach this helper.
    private static func isOutsideQualitativeReference(value: String, referenceRange: String?) -> Bool? {
        guard let referenceRange,
              !referenceRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              referenceRange.rangeOfCharacter(from: .decimalDigits) == nil else {
            return nil
        }

        if let numeric = numericValue(value) {
            // A numeric zero is the common quantitative spelling of a
            // negative/none qualitative result; any positive quantity is
            // outside that qualitative reference.
            return numeric != 0
        }

        let normalizedValue = normalizeQualitativeValue(value)
        let normalizedReference = normalizeQualitativeValue(referenceRange)
        guard !normalizedValue.isEmpty, !normalizedReference.isEmpty else { return nil }

        if normalizedValue == normalizedReference {
            return false
        }

        // Negative/no-growth/none/not-detected are common equivalent normal
        // spellings across laboratory systems.
        let normalQualitativeValues: Set<String> = [
            "negative", "none", "notdetected", "nonreactive", "nogrowth"
        ]
        if normalQualitativeValues.contains(normalizedValue),
           normalQualitativeValues.contains(normalizedReference) {
            return false
        }

        return true
    }

    private static func parseReferenceRange(_ rangeString: String) -> ParsedReferenceRange? {
        let cleaned = rangeString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        if cleaned.hasPrefix("<") || cleaned.hasPrefix("≤") {
            let value = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(value).map { ParsedReferenceRange(minimum: nil, maximum: $0) }
        }

        if cleaned.hasPrefix(">") || cleaned.hasPrefix("≥") {
            let value = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(value).map { ParsedReferenceRange(minimum: $0, maximum: nil) }
        }

        let rangePattern = #"^\s*(-?[0-9]+(?:\.[0-9]+)?)\s*(?:-|–|—|to)\s*(-?[0-9]+(?:\.[0-9]+)?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive) else {
            return nil
        }
        let nsRange = NSRange(location: 0, length: cleaned.utf16.count)
        guard let match = regex.firstMatch(in: cleaned, range: nsRange),
              let minimumRange = Range(match.range(at: 1), in: cleaned),
              let maximumRange = Range(match.range(at: 2), in: cleaned),
              let minimum = Double(cleaned[minimumRange]),
              let maximum = Double(cleaned[maximumRange]) else {
            return nil
        }
        return ParsedReferenceRange(minimum: min(minimum, maximum), maximum: max(minimum, maximum))
    }

    // MARK: - Unit Plausibility
    enum UnitValidation {
        case valid
        case mismatch(reason: String)
    }

    static func validateUnit(_ unit: String?, for parameter: LabParameter) -> Bool {
        if case .valid = unitValidation(unit, for: parameter) {
            return true
        }
        return false
    }

    static func unitValidation(_ unit: String?, for parameter: LabParameter) -> UnitValidation {
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
            // Missing units remain acceptable because many reports omit units
            // in table columns and for dimensionless values.
            return .valid
        }

        guard let expected = parameter.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty else {
            return .mismatch(reason: "Reported unit '\(unit)' is not valid for dimensionless \(parameter.name)")
        }

        let allowedUnits = allowedCanonicalUnits(for: parameter)
        let canonical = canonicalUnit(unit, for: parameter)
        guard allowedUnits.contains(canonical) else {
            let expectedDescription = allowedUnits.sorted().joined(separator: " or ")
            return .mismatch(reason: "Unit '\(unit)' does not match expected unit '\(expectedDescription)' for \(parameter.name)")
        }
        return .valid
    }

    private static func allowedCanonicalUnits(for parameter: LabParameter) -> Set<String> {
        var units: Set<String> = []
        if let expected = parameter.unit, !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            units.insert(canonicalUnit(expected, for: parameter))
        }

        switch parameter.key {
        case "sodium", "potassium", "chloride", "co2_bicarbonate", "anion_gap",
             "urine_sodium", "urine_potassium", "urine_chloride":
            // Analyzer reports commonly use either notation for these
            // monovalent electrolyte measurements. This is intentionally not a
            // global mmol/L ↔ mEq/L equivalence for divalent analytes.
            units.insert("mmol/l")
            units.insert("meq/l")
        case "egfr":
            units.insert("ml/min/1.73m2")
        case "urine_protein_quantitative", "urine_albumin", "urine_microalbumin":
            units.formUnion(["mg/dl", "mg/l", "ug/ml", "ug/l"])
        default:
            break
        }

        return units
    }

    /// Normalize notational variants without applying unsafe global unit
    /// conversions. Parameter-specific policies are handled above.
    static func canonicalUnit(_ unit: String) -> String {
        var normalized = unit.lowercased()
            .replacingOccurrences(of: "µ", with: "u")
            .replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "²", with: "2")

        let equivalents: [String: String] = [
            "10^3/ul": "k/ul", "10*3/ul": "k/ul", "x10e3/ul": "k/ul", "10e3/ul": "k/ul",
            "thou/ul": "k/ul", "thousand/ul": "k/ul", "k/mm3": "k/ul", "10^3/mm3": "k/ul",
            "10^9/l": "k/ul", "x10^9/l": "k/ul",
            "10^6/ul": "m/ul", "10*6/ul": "m/ul", "x10e6/ul": "m/ul", "10e6/ul": "m/ul",
            "mill/ul": "m/ul", "million/ul": "m/ul", "m/mm3": "m/ul", "10^6/mm3": "m/ul",
            "10^12/l": "m/ul", "x10^12/l": "m/ul",
            "seconds": "sec", "s": "sec",
            "iu/l": "u/l",
            "mcg/dl": "ug/dl", "mcg/l": "ug/l", "mcg/ml": "ug/ml",
            "mm/h": "mm/hr"
        ]
        if let canonical = equivalents[normalized] {
            normalized = canonical
        }
        return normalized
    }

    static func canonicalUnit(_ unit: String, for parameter: LabParameter) -> String {
        let normalized = canonicalUnit(unit)
        guard parameter.key == "egfr" else { return normalized }

        if normalized == "ml/min/1.73"
            || normalized == "ml/min/1.73m"
            || normalized == "ml/min/1.73m2"
            || normalized == "ml/min/1.73m^2" {
            return "ml/min/1.73m2"
        }
        return normalized
    }

    // MARK: - Flag Consistency
    /// Check whether an abnormal flag agrees with the report's range. A false
    /// result lowers extraction confidence but never invalidates the value.
    static func flagConsistency(value: String, referenceRange: String?, flag: String?) -> Bool {
        guard let numericValue = numericValue(value),
              let referenceRange,
              let range = parseReferenceRange(referenceRange) else {
            return true
        }

        let normalizedFlag = flag?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isHigh = range.maximum.map { numericValue > $0 } ?? false
        let isLow = range.minimum.map { numericValue < $0 } ?? false

        switch normalizedFlag {
        case "H", "HH", "HIGH", "CRITICAL HIGH":
            return isHigh
        case "L", "LL", "LOW", "CRITICAL LOW":
            return isLow
        case nil, "", "NORMAL", "N":
            return !isHigh && !isLow
        default:
            return isHigh || isLow
        }
    }

    // MARK: - Structural Filtering
    /// Retains parseable values, including abnormal values and unit warnings.
    /// Only values that cannot represent one result are filtered.
    static func filterInvalidValues<T: LabValueLike>(_ values: [T], standardParams: [String: LabParameter]) -> [T] {
        var retainedValues: [T] = []
        var invalidCount = 0

        for value in values {
            let testType: BloodTestResult.LabTestType = value.testType.uppercased() == "URINE" ? .urine : .blood
            let standardParam = BloodTestResult.matchLabParameter(name: value.testName, testType: testType)?.parameter
                ?? standardParams.values.first { $0.name.caseInsensitiveCompare(value.testName) == .orderedSame }

            let validation = validateValue(
                value.value,
                testName: value.testName,
                referenceRange: value.referenceRange,
                standardParam: standardParam
            )

            switch validation {
            case .valid:
                retainedValues.append(value)
            case .unitMismatch(let reason):
                AppLog.shared.healthData("BloodTestValueValidator: retaining value with unit warning: \(reason)", level: .warning)
                retainedValues.append(value)
            case .outOfRange:
                retainedValues.append(value)
            case .invalidType(let reason), .missingData(let reason):
                AppLog.shared.healthData("BloodTestValueValidator: Filtering structurally invalid value: \(reason)", level: .warning)
                invalidCount += 1
            }
        }

        if invalidCount > 0 {
            AppLog.shared.healthData("🧪 BloodTestValueValidator: Filtered \(invalidCount) structurally invalid values, kept \(retainedValues.count) values")
        }

        return retainedValues
    }
}

// MARK: - Protocol for Lab Value Types
protocol LabValueLike {
    var testName: String { get }
    var value: String { get }
    var unit: String? { get }
    var referenceRange: String? { get }
    var testType: String { get }
}
