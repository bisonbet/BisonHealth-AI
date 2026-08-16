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

    // Provenance (which extraction pass produced this, and from where)
    let sources: [CandidateSource]
    let pageNumber: Int?
    let sourceSnippet: String?
    let specimen: LabSpecimen?
    let collection: LabCollection?

    enum ValidationStatus: Hashable {
        case valid
        case unitMismatch
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
        reason: String? = nil,
        sources: [CandidateSource] = [],
        pageNumber: Int? = nil,
        sourceSnippet: String? = nil,
        specimen: LabSpecimen? = nil,
        collection: LabCollection? = nil
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
        self.sources = sources
        self.pageNumber = pageNumber
        self.sourceSnippet = sourceSnippet
        self.specimen = specimen
        self.collection = collection
    }

    /// Short provenance summary for the review UI, e.g. "Table structure + On-device AI, page 2"
    var provenanceDescription: String? {
        guard !sources.isEmpty else { return nil }
        var parts = sources.map { $0.displayName }.joined(separator: " + ")
        if let pageNumber {
            parts += ", page \(pageNumber)"
        }
        return parts
    }
    
    var displayValue: String {
        var result = value
        if let unit = unit {
            result += " \(unit)"
        }
        return result
    }
    
    var isRecommended: Bool {
        return validationStatus == .valid && !isAbnormal && confidence > 0.7
    }

    /// A unit warning can be imported only after the user explicitly chooses
    /// it. Structurally invalid values remain non-selectable.
    var isSelectable: Bool {
        switch validationStatus {
        case .valid, .unitMismatch, .outOfRange:
            return true
        case .invalidType, .missingData:
            return false
        }
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
    /// True when the reconciler auto-accepted this group (single candidate that passed validation)
    var isAutoAccepted: Bool = false

    /// Multiple distinct values were extracted for the same test — most likely an
    /// OCR/extraction duplicate; the user must pick the right one.
    var hasMultipleDistinctValues: Bool {
        candidates.count > 1
    }

    init(
        id: UUID = UUID(),
        standardTestName: String,
        standardKey: String,
        candidates: [BloodTestImportCandidate],
        selectedCandidateId: UUID? = nil,
        isAutoAccepted: Bool = false
    ) {
        self.id = id
        self.standardTestName = standardTestName
        self.standardKey = standardKey
        self.candidates = candidates
        self.isAutoAccepted = isAutoAccepted
        // Default selection:
        // 1. If explicit selectedCandidateId provided, use it
        // 2. Else find the recommended candidate
        // 3. Else if only one candidate is valid and normal, use it
        // 4. Otherwise nil (user must choose/review)
        if let selectedId = selectedCandidateId {
            self.selectedCandidateId = selectedId
        } else if let recommended = candidates.first(where: { $0.isRecommended }) {
            self.selectedCandidateId = recommended.id
        } else if candidates.count == 1,
                  candidates[0].validationStatus == .valid,
                  !candidates[0].isAbnormal {
            self.selectedCandidateId = candidates[0].id
        } else {
            self.selectedCandidateId = nil
        }
    }
    
    var recommendedCandidate: BloodTestImportCandidate? {
        return candidates.first(where: { $0.isRecommended })
    }
    
    var hasValidCandidates: Bool {
        return candidates.contains { $0.isSelectable }
    }
}
