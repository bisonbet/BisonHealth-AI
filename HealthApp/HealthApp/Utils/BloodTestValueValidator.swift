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
    
    // MARK: - Validate Value
    /// Validates a blood test value for type correctness and range reasonableness
    static func validateValue(
        _ value: String,
        testName: String,
        referenceRange: String?,
        standardParam: LabParameter?
    ) -> ValidationResult {
        
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
                print("⚠️ BloodTestValueValidator: Filtering invalid value '\(value.testName)' = '\(value.value)': \(reason)")
                invalidCount += 1
            case .outOfRange(let reason, let stdDevs):
                print("⚠️ BloodTestValueValidator: Filtering out-of-range value '\(value.testName)' = '\(value.value)': \(reason) (\(String(format: "%.1f", stdDevs)) SD)")
                invalidCount += 1
            case .missingData(let reason):
                print("⚠️ BloodTestValueValidator: Filtering incomplete value '\(value.testName)': \(reason)")
                invalidCount += 1
            }
        }
        
        if invalidCount > 0 {
            print("🧪 BloodTestValueValidator: Filtered \(invalidCount) invalid values, kept \(validValues.count) valid values")
        }
        
        return validValues
    }
    
    // MARK: - Find Standardized Parameter
    private static func findStandardizedParameter(for testName: String, in params: [String: LabParameter]) -> LabParameter? {
        let normalized = testName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // Direct match
        if let param = params[normalized] {
            return param
        }
        
        // Partial match
        for (key, param) in params {
            if normalized.contains(key) || key.contains(normalized) {
                return param
            }
        }
        
        return nil
    }
}

// MARK: - Protocol for Lab Value Types
protocol LabValueLike {
    var testName: String { get }
    var value: String { get }
    var referenceRange: String? { get }
}

