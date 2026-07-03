import Foundation

// MARK: - Blood Test Value Validator
struct BloodTestValueValidator {
    
    // MARK: - Validation Result
    enum ValidationResult {
        case valid
        case invalidType(reason: String)
        case outOfRange(reason: String, standardDeviations: Double)
        case missingData(reason: String)
    }
    
    // MARK: - Qualitative Values
    /// Legitimate non-numeric results (urinalysis dipsticks, cultures, serology)
    private static let qualitativeValues: Set<String> = [
        "negative", "positive", "trace", "none", "not detected", "none seen",
        "reactive", "non-reactive", "nonreactive", "no growth", "clear", "yellow",
        "straw", "amber", "cloudy", "hazy", "turbid", "few", "moderate", "many",
        "rare", "occasional"
    ]

    static func isQualitativeValue(_ value: String) -> Bool {
        qualitativeValues.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    // MARK: - Validate Value
    /// Validates a blood test value for type correctness and range reasonableness
    static func validateValue(
        _ value: String,
        testName: String,
        referenceRange: String?,
        standardParam: LabParameter?
    ) -> ValidationResult {

        // Qualitative results (Negative, Trace, No growth, …) are valid extracted
        // values — normality vs abnormality is a separate concern
        if isQualitativeValue(value) {
            return .valid
        }

        // Check if value is numeric
        guard isNumeric(value) else {
            // Check if it's a range (e.g., "12-15") which we should reject
            if value.contains("-") && value.contains(where: { $0.isNumber }) {
                return .invalidType(reason: "Value appears to be a range, not a single numeric value")
            }
            // Check if it contains letters (alphanumeric)
            if value.rangeOfCharacter(from: CharacterSet.letters) != nil {
                return .invalidType(reason: "Value contains non-numeric characters")
            }
            return .invalidType(reason: "Value is not numeric")
        }
        
        // Parse numeric value
        guard let numericValue = parseNumericValue(value) else {
            return .invalidType(reason: "Could not parse numeric value")
        }
        
        // Validate against reference range if available
        if let referenceRange = referenceRange ?? standardParam?.referenceRange {
            return validateAgainstRange(numericValue, referenceRange: referenceRange, testName: testName)
        }
        
        return .valid
    }
    
    // MARK: - Check if Value is Numeric
    private static func isNumeric(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common formatting
        let cleaned = trimmed
            .replacingOccurrences(of: ",", with: "") // Remove thousands separators
            .replacingOccurrences(of: " ", with: "")
        
        // Check for numeric patterns
        // Allow: numbers, decimals, scientific notation, <, >, ≤, ≥ prefixes
        let numericPattern = #"^[<>≤≥]?\s*[\d.]+([eE][+-]?\d+)?$"#
        let regex = try? NSRegularExpression(pattern: numericPattern)
        let range = NSRange(location: 0, length: cleaned.utf16.count)
        
        return regex?.firstMatch(in: cleaned, range: range) != nil
    }
    
    // MARK: - Parse Numeric Value
    private static func parseNumericValue(_ value: String) -> Double? {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove comparison operators and whitespace
        cleaned = cleaned.replacingOccurrences(of: "<", with: "")
        cleaned = cleaned.replacingOccurrences(of: ">", with: "")
        cleaned = cleaned.replacingOccurrences(of: "≤", with: "")
        cleaned = cleaned.replacingOccurrences(of: "≥", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Double(cleaned)
    }
    
    // MARK: - Validate Against Reference Range
    private static func validateAgainstRange(
        _ value: Double,
        referenceRange: String,
        testName: String
    ) -> ValidationResult {
        
        // Parse reference range
        guard let rangeInfo = parseReferenceRange(referenceRange) else {
            // If we can't parse the range, we can't validate, so accept it
            return .valid
        }
        
        // Calculate if value is within reasonable bounds (within 2 standard deviations)
        // For simplicity, we'll use the range as a proxy for normal distribution
        // Assuming the range covers ~95% (2 SD), values outside 2 SD from center are suspicious
        
        let center = (rangeInfo.min + rangeInfo.max) / 2.0
        let rangeWidth = rangeInfo.max - rangeInfo.min
        let standardDeviation = rangeWidth / 4.0 // Approximate: 95% range ≈ 4 SD
        
        let deviationFromCenter = abs(value - center)
        let standardDeviations = deviationFromCenter / standardDeviation
        
        // Reject if more than 2 standard deviations outside
        if standardDeviations > 2.0 {
            let reason = String(format: "Value %.2f is %.1f standard deviations outside expected range (%.2f - %.2f)",
                               value, standardDeviations, rangeInfo.min, rangeInfo.max)
            return .outOfRange(reason: reason, standardDeviations: standardDeviations)
        }
        
        return .valid
    }
    
    // MARK: - Parse Reference Range
    private static func parseReferenceRange(_ rangeString: String) -> (min: Double, max: Double)? {
        let cleaned = rangeString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle different range formats:
        // "12.0-16.0" -> (12.0, 16.0)
        // "<200" -> (0, 200) (assuming 0 as lower bound)
        // ">40" -> (40, Double.infinity) but we'll use a reasonable max
        // "70-100" -> (70, 100)
        
        // Check for comparison operators
        if cleaned.hasPrefix("<") {
            let valueString = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if let max = Double(valueString) {
                return (min: 0.0, max: max)
            }
        } else if cleaned.hasPrefix(">") {
            let valueString = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if let min = Double(valueString) {
                // Use 3x the min as a reasonable upper bound for validation
                return (min: min, max: min * 3.0)
            }
        } else if cleaned.contains("-") {
            // Range format: "min-max"
            let components = cleaned.components(separatedBy: "-")
            if components.count == 2,
               let min = Double(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
               let max = Double(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (min: min, max: max)
            }
        }
        
        return nil
    }
    
    // MARK: - Unit Plausibility
    /// Check whether an extracted unit is plausible for a parameter.
    /// Missing units (either side) are not treated as failures — many lab
    /// reports omit units for dimensionless values.
    static func validateUnit(_ unit: String?, for parameter: LabParameter) -> Bool {
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
            return true
        }
        guard let expected = parameter.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty else {
            return true
        }
        return canonicalUnit(unit) == canonicalUnit(expected)
    }

    /// Normalize a unit string to a canonical form so notational variants
    /// (K/uL vs 10^3/µL vs x10E3/uL) compare equal.
    static func canonicalUnit(_ unit: String) -> String {
        var normalized = unit.lowercased()
            .replacingOccurrences(of: "µ", with: "u")
            .replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "²", with: "2")

        let equivalents: [String: String] = [
            // Cell-count notations → K/uL and M/uL
            "10^3/ul": "k/ul", "10*3/ul": "k/ul", "x10e3/ul": "k/ul", "10e3/ul": "k/ul",
            "thou/ul": "k/ul", "thousand/ul": "k/ul", "k/mm3": "k/ul", "10^3/mm3": "k/ul",
            "10^9/l": "k/ul", "x10^9/l": "k/ul",
            "10^6/ul": "m/ul", "10*6/ul": "m/ul", "x10e6/ul": "m/ul", "10e6/ul": "m/ul",
            "mill/ul": "m/ul", "million/ul": "m/ul", "m/mm3": "m/ul", "10^6/mm3": "m/ul",
            "10^12/l": "m/ul", "x10^12/l": "m/ul",
            // Other common synonyms
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

    // MARK: - Flag Consistency
    /// Check whether an abnormal flag agrees with the value's position relative
    /// to the reference range. Returns true when there isn't enough information
    /// to judge (unparseable value/range, qualitative results).
    static func flagConsistency(value: String, referenceRange: String?, flag: String?) -> Bool {
        guard let numericValue = parseNumericValue(value),
              let rangeString = referenceRange,
              let range = parseReferenceRange(rangeString) else {
            return true
        }

        let normalizedFlag = flag?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isHigh = numericValue > range.max
        let isLow = numericValue < range.min

        switch normalizedFlag {
        case "H", "HH", "HIGH", "CRITICAL HIGH":
            return isHigh
        case "L", "LL", "LOW", "CRITICAL LOW":
            return isLow
        case nil, "", "NORMAL", "N":
            return !isHigh && !isLow
        default:
            // Generic abnormal markers (*, A, ABN, CRITICAL) — consistent if out of range either way
            return isHigh || isLow
        }
    }

    // MARK: - Filter Invalid Values
    /// Filters out invalid values from a list of extracted lab values
    /// This is a generic version that works with any type that has the required properties
    static func filterInvalidValues<T: LabValueLike>(_ values: [T], standardParams: [String: LabParameter]) -> [T] {
        var validValues: [T] = []
        var invalidCount = 0
        
        for value in values {
            // Find matching standard parameter
            let standardParam = findStandardizedParameter(for: value.testName, in: standardParams)
            
            let validation = validateValue(
                value.value,
                testName: value.testName,
                referenceRange: value.referenceRange,
                standardParam: standardParam
            )
            
            switch validation {
            case .valid:
                validValues.append(value)
            case .invalidType(let reason):
                AppLog.shared.healthData("BloodTestValueValidator: Filtering invalid value: \(reason)", level: .warning)
                invalidCount += 1
            case .outOfRange(let reason, let stdDevs):
                AppLog.shared.healthData("BloodTestValueValidator: Filtering out-of-range value: \(reason) (\(String(format: "%.1f", stdDevs)) SD)", level: .warning)
                invalidCount += 1
            case .missingData(let reason):
                AppLog.shared.healthData("BloodTestValueValidator: Filtering incomplete value: \(reason)", level: .warning)
                invalidCount += 1
            }
        }
        
        if invalidCount > 0 {
            AppLog.shared.healthData("🧪 BloodTestValueValidator: Filtered \(invalidCount) invalid values, kept \(validValues.count) valid values")
        }
        
        return validValues
    }
    
    // MARK: - Find Standardized Parameter
    private static func findStandardizedParameter(for testName: String, in params: [String: LabParameter]) -> LabParameter? {
        // Try blood first, then urine — this call site has no test-type context.
        if let match = BloodTestResult.matchLabParameter(name: testName, testType: .blood) {
            return match.parameter
        }
        return BloodTestResult.matchLabParameter(name: testName, testType: .urine)?.parameter
    }
}

// MARK: - Protocol for Lab Value Types
protocol LabValueLike {
    var testName: String { get }
    var value: String { get }
    var referenceRange: String? { get }
}

