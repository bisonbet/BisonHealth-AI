import Foundation

// MARK: - Duplicate Blood Test Candidate
/// Represents a candidate value for a blood test that may be a duplicate
struct DuplicateBloodTestCandidate: Identifiable, Hashable {
    let id: UUID
    let testName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
    let originalTestName: String
    let confidence: Double
    let validationStatus: ValidationStatus
    let reason: String? // Why this was selected as most likely, or why it's invalid
    
    enum ValidationStatus {
        case valid
        case invalidType
        case outOfRange
        case missingData
    }
    
    init(
        id: UUID = UUID(),
        testName: String,
        value: String,
        unit: String? = nil,
        referenceRange: String? = nil,
        isAbnormal: Bool = false,
        originalTestName: String,
        confidence: Double = 1.0,
        validationStatus: ValidationStatus = .valid,
        reason: String? = nil
    ) {
        self.id = id
        self.testName = testName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.isAbnormal = isAbnormal
        self.originalTestName = originalTestName
        self.confidence = confidence
        self.validationStatus = validationStatus
        self.reason = reason
    }
    
    var displayValue: String {
        var result = value
        if let unit = unit {
            result += " \(unit)"
        }
        return result
    }
    
    var isRecommended: Bool {
        return validationStatus == .valid && confidence > 0.7
    }
}

// MARK: - Duplicate Test Group
/// Groups duplicate candidates for the same test
struct DuplicateTestGroup: Identifiable {
    let id: UUID
    let standardTestName: String
    let standardKey: String
    let candidates: [DuplicateBloodTestCandidate]
    var selectedCandidateId: UUID?
    
    init(
        id: UUID = UUID(),
        standardTestName: String,
        standardKey: String,
        candidates: [DuplicateBloodTestCandidate],
        selectedCandidateId: UUID? = nil
    ) {
        self.id = id
        self.standardTestName = standardTestName
        self.standardKey = standardKey
        self.candidates = candidates
        self.selectedCandidateId = selectedCandidateId ?? candidates.first(where: { $0.isRecommended })?.id
    }
    
    var recommendedCandidate: DuplicateBloodTestCandidate? {
        return candidates.first(where: { $0.isRecommended })
    }
    
    var hasValidCandidates: Bool {
        return candidates.contains { $0.validationStatus == .valid }
    }
}

