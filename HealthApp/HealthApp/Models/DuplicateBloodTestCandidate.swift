import Foundation

// MARK: - Blood Test Import Candidate
/// Represents a candidate value for a blood test during import review
struct BloodTestImportCandidate: Identifiable, Hashable {
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

// MARK: - Blood Test Import Group
/// Groups candidates for the same test (even if single) for user review
struct BloodTestImportGroup: Identifiable {
    let id: UUID
    let standardTestName: String
    let standardKey: String
    let candidates: [BloodTestImportCandidate]
    var selectedCandidateId: UUID?
    
    init(
        id: UUID = UUID(),
        standardTestName: String,
        standardKey: String,
        candidates: [BloodTestImportCandidate],
        selectedCandidateId: UUID? = nil
    ) {
        self.id = id
        self.standardTestName = standardTestName
        self.standardKey = standardKey
        self.candidates = candidates
        // Default selection:
        // 1. If explicit selectedCandidateId provided, use it
        // 2. Else find the recommended candidate
        // 3. Else if only one candidate and it's valid, use it
        // 4. Otherwise nil (user must choose/review)
        if let selectedId = selectedCandidateId {
            self.selectedCandidateId = selectedId
        } else if let recommended = candidates.first(where: { $0.isRecommended }) {
            self.selectedCandidateId = recommended.id
        } else if candidates.count == 1, candidates[0].validationStatus == .valid {
            self.selectedCandidateId = candidates[0].id
        } else {
            self.selectedCandidateId = nil
        }
    }
    
    var recommendedCandidate: BloodTestImportCandidate? {
        return candidates.first(where: { $0.isRecommended })
    }
    
    var hasValidCandidates: Bool {
        return candidates.contains { $0.validationStatus == .valid }
    }
}

