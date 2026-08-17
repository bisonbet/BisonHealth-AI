import Foundation
import CoreGraphics

// MARK: - Candidate Source
/// Provenance of an extracted lab value candidate — which extraction pass produced it.
enum CandidateSource: String, Codable {
    case deterministicTable = "deterministic_table"
    case deterministicRow = "deterministic_row"
    case onDeviceLLM = "on_device_llm"
    case onDeviceVision = "on_device_vision"
    case cloudText = "cloud_text"
    case cloudVision = "cloud_vision"

    var displayName: String {
        switch self {
        case .deterministicTable: return "Table structure"
        case .deterministicRow: return "OCR layout"
        case .onDeviceLLM: return "On-device AI"
        case .onDeviceVision: return "On-device AI (vision)"
        case .cloudText: return "Cloud AI (text)"
        case .cloudVision: return "Cloud AI (vision)"
        }
    }
}

// MARK: - Lab Value Candidate
/// A single extracted lab value with full provenance, produced by any extraction
/// pass (deterministic parser, on-device LLM, cloud). Candidates for the same
/// standardized test are merged/arbitrated by `LabCandidateReconciler`.
struct LabValueCandidate {
    let standardKey: String
    let parameter: LabParameter
    let originalTestName: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let abnormalFlag: String?
    let testType: BloodTestResult.LabTestType
    let source: CandidateSource
    let pageNumber: Int?
    /// Raw source text (row/line) this value came from, for the review UI
    let sourceSnippet: String
    let confidence: Double
    let validation: BloodTestValueValidator.ValidationResult
    /// Name-match quality is separate from extraction confidence. Fuzzy name
    /// matches may be reviewed but must not be silently auto-imported.
    let matchConfidence: Double
    let specimen: LabSpecimen?
    let collection: LabCollection?

    init(
        standardKey: String,
        parameter: LabParameter,
        originalTestName: String,
        value: String,
        unit: String?,
        referenceRange: String?,
        abnormalFlag: String?,
        testType: BloodTestResult.LabTestType,
        source: CandidateSource,
        pageNumber: Int?,
        sourceSnippet: String,
        confidence: Double,
        validation: BloodTestValueValidator.ValidationResult,
        matchConfidence: Double = 1.0,
        specimen: LabSpecimen? = nil,
        collection: LabCollection? = nil
    ) {
        self.standardKey = standardKey
        self.parameter = parameter
        self.originalTestName = originalTestName
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.abnormalFlag = abnormalFlag
        self.testType = testType
        self.source = source
        self.pageNumber = pageNumber
        self.sourceSnippet = sourceSnippet
        self.confidence = confidence
        self.validation = validation
        self.matchConfidence = matchConfidence
        self.specimen = specimen
        self.collection = collection
    }

    var isAbnormal: Bool {
        BloodTestValueValidator.isAbnormal(
            value: value,
            referenceRange: referenceRange ?? parameter.referenceRange,
            flag: abnormalFlag
        )
    }

    var isValid: Bool {
        if case .valid = validation { return true }
        return false
    }

    var validationReason: String? {
        switch validation {
        case .valid: return nil
        case .unitMismatch(let reason): return reason
        case .ocrUnitMismatch(let reason): return reason
        case .invalidType(let reason): return reason
        case .outOfRange(let reason, _): return reason
        case .missingData(let reason): return reason
        }
    }

    /// Value + unit normalized for cross-source agreement comparison.
    var normalizedValueKey: String {
        let normalizedValue = BloodTestValueValidator.normalizedValue(value)
        let normalizedUnit = unit.map {
            BloodTestValueValidator.canonicalUnit($0, for: parameter)
        } ?? BloodTestValueValidator.canonicalUnit(parameter.unit ?? "", for: parameter)
        return "\(normalizedValue)|\(normalizedUnit)"
    }
}

// MARK: - Lab Report Parser
/// Deterministic (non-LLM) lab value extraction from OCR geometry, recognized
/// table structures, and plain text. Anchored to the standardized lab registry:
/// only rows whose test name matches a known parameter become candidates, so
/// output is high-precision and every candidate carries provenance.
final class LabReportParser {

    // MARK: - Row/Layout Thresholds (match NativeDocumentExtractor's layout logic)
    private let rowYThreshold: CGFloat = 0.008
    private let columnGapThreshold: CGFloat = 0.03

    // MARK: - Public API

    /// Parse per-page OCR output (observations, tables, or plain page text).
    func parse(pages: [NativeDocumentExtractor.PageText]) -> [LabValueCandidate] {
        var candidates: [LabValueCandidate] = []
        var testType: BloodTestResult.LabTestType = .blood

        for page in pages {
            if let tables = page.tables {
                for table in tables {
                    candidates.append(contentsOf: parseTable(table, testType: &testType))
                }
            }

            if let observations = page.observations, !observations.isEmpty {
                candidates.append(contentsOf: parseObservationRows(
                    observations,
                    pageNumber: page.pageNumber,
                    testType: &testType
                ))
            } else if !page.text.isEmpty {
                candidates.append(contentsOf: parseLines(
                    page.text,
                    pageNumber: page.pageNumber,
                    baseConfidence: 0.9,
                    testType: &testType
                ))
            }
        }

        AppLog.shared.documents("LabReportParser: \(candidates.count) candidates from \(pages.count) page(s)")
        return candidates
    }

    /// Parse plain text (PDFKit-direct path — tab/whitespace-delimited rows).
    func parse(plainText: String) -> [LabValueCandidate] {
        var testType: BloodTestResult.LabTestType = .blood
        var candidates: [LabValueCandidate] = []
        var pageNumber = 1

        // Page markers are inserted by NativeDocumentExtractor when joining pages
        for pageChunk in plainText.components(separatedBy: "--- Page Break ---") {
            candidates.append(contentsOf: parseLines(
                pageChunk,
                pageNumber: pageNumber,
                baseConfidence: 0.9,
                testType: &testType
            ))
            pageNumber += 1
        }

        AppLog.shared.documents("LabReportParser: \(candidates.count) candidates from plain text (\(plainText.count) chars)")
        return candidates
    }

    // MARK: - Table Parsing (iOS 26 document-structure recognition)

    private func parseTable(
        _ table: NativeDocumentExtractor.RecognizedTable,
        testType: inout BloodTestResult.LabTestType
    ) -> [LabValueCandidate] {
        var candidates: [LabValueCandidate] = []
        var pendingName: String?

        for row in table.rows {
            let cells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }

            let joined = cells.joined(separator: " ")
            updateSectionTestType(from: joined, testType: &testType)
            if isHeaderRow(cells) { continue }

            if let candidate = parseRowCells(
                cells,
                testType: testType,
                pageNumber: table.pageNumber,
                source: .deterministicTable,
                baseConfidence: 0.95,
                snippet: joined,
                pendingName: &pendingName
            ) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    // MARK: - Observation Row Parsing (geometry fallback)

    private func parseObservationRows(
        _ observations: [NativeDocumentExtractor.TextObservation],
        pageNumber: Int,
        testType: inout BloodTestResult.LabTestType
    ) -> [LabValueCandidate] {
        var candidates: [LabValueCandidate] = []
        var pendingName: String?

        for row in groupIntoRows(observations) {
            let sorted = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }

            // Split the row into cells at large horizontal gaps
            var cells: [String] = []
            var currentCell: [String] = []
            var previousMaxX: CGFloat = 0
            for (index, obs) in sorted.enumerated() {
                if index > 0, obs.boundingBox.minX - previousMaxX > columnGapThreshold {
                    cells.append(currentCell.joined(separator: " "))
                    currentCell = []
                }
                currentCell.append(obs.text)
                previousMaxX = obs.boundingBox.maxX
            }
            if !currentCell.isEmpty {
                cells.append(currentCell.joined(separator: " "))
            }

            cells = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }

            let joined = cells.joined(separator: " ")
            updateSectionTestType(from: joined, testType: &testType)
            if isHeaderRow(cells) { continue }

            let rowConfidence = sorted.reduce(0.0) { $0 + Double($1.confidence) } / Double(sorted.count)

            if let candidate = parseRowCells(
                cells,
                testType: testType,
                pageNumber: pageNumber,
                source: .deterministicRow,
                baseConfidence: rowConfidence,
                snippet: joined,
                pendingName: &pendingName
            ) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    private func groupIntoRows(
        _ observations: [NativeDocumentExtractor.TextObservation]
    ) -> [[NativeDocumentExtractor.TextObservation]] {
        struct Row {
            var observations: [NativeDocumentExtractor.TextObservation]
            var avgY: CGFloat
        }

        var rows: [Row] = []
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        for obs in sorted {
            let obsY = obs.boundingBox.midY
            if let rowIndex = rows.firstIndex(where: { abs($0.avgY - obsY) < rowYThreshold }) {
                rows[rowIndex].observations.append(obs)
                let count = CGFloat(rows[rowIndex].observations.count)
                rows[rowIndex].avgY = (rows[rowIndex].avgY * (count - 1) + obsY) / count
            } else {
                rows.append(Row(observations: [obs], avgY: obsY))
            }
        }

        rows.sort { $0.avgY > $1.avgY }
        return rows.map { $0.observations }
    }

    // MARK: - Plain Text Line Parsing

    private func parseLines(
        _ text: String,
        pageNumber: Int?,
        baseConfidence: Double,
        testType: inout BloodTestResult.LabTestType
    ) -> [LabValueCandidate] {
        var candidates: [LabValueCandidate] = []
        var pendingName: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                pendingName = nil
                continue
            }

            updateSectionTestType(from: trimmed, testType: &testType)

            // Split by tabs or runs of 2+ spaces; fall back to single-space tokens
            var cells = trimmed
                .components(separatedBy: CharacterSet(charactersIn: "\t"))
                .flatMap { $0.components(separatedBy: "  ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if cells.count == 1 {
                cells = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
            }

            guard !cells.isEmpty, !isHeaderRow(cells) else { continue }

            if let candidate = parseRowCells(
                cells,
                testType: testType,
                pageNumber: pageNumber,
                source: .deterministicRow,
                baseConfidence: baseConfidence,
                snippet: trimmed,
                pendingName: &pendingName
            ) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    // MARK: - Core Row Parsing

    /// Parse one row of cells into a candidate. Handles wrapped test names via
    /// `pendingName`: a row with a name but no value stores the name; a following
    /// row that starts with a value consumes it.
    private func parseRowCells(
        _ cells: [String],
        testType: BloodTestResult.LabTestType,
        pageNumber: Int?,
        source: CandidateSource,
        baseConfidence: Double,
        snippet: String,
        pendingName: inout String?
    ) -> LabValueCandidate? {
        // Locate the first cell that reads as a value (also splitting "98 mg/dL" style cells)
        var valueCellIndex: Int?
        var value: String?
        var inlineUnit: String?

        for (index, cell) in cells.enumerated() {
            if isValueToken(cell) {
                valueCellIndex = index
                value = cell
                break
            }
            if let (splitValue, splitUnit) = splitValueUnit(cell), index > 0 {
                valueCellIndex = index
                value = splitValue
                inlineUnit = splitUnit
                break
            }
        }

        guard var foundValue = value, var foundIndex = valueCellIndex else {
            // No value — if this row is a plausible test name, remember it for wrap handling
            let joined = cells.joined(separator: " ")
            if joined.rangeOfCharacter(from: .letters) != nil && joined.count <= 60 {
                pendingName = joined
            }
            return nil
        }

        // Resolve the test name
        var name = cells[0..<foundIndex].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            guard let wrapped = pendingName else { return nil }
            name = wrapped
        }
        pendingName = nil

        guard name.rangeOfCharacter(from: .letters) != nil else { return nil }

        // Match against the standardized registry — try the name as-is, then
        // extended by one token (handles "CA 125" where "125" looks like a value)
        var match = BloodTestResult.matchLabParameter(name: name, testType: testType)

        // OCR glues superscript footnote markers onto test names ("BUN01",
        // "Chloride °1"). Registry containment needs 4+ characters, so short
        // names like BUN fail outright. Retry without the marker — only after
        // the raw name misses, so "Vitamin B12" and "T3" are never stripped.
        if match == nil, let stripped = Self.strippingFootnoteMarker(from: name) {
            if let strippedMatch = BloodTestResult.matchLabParameter(name: stripped, testType: testType) {
                match = strippedMatch
                name = stripped
            }
        }
        if match == nil, foundIndex + 1 < cells.count,
           isValueToken(cells[foundIndex + 1]) || splitValueUnit(cells[foundIndex + 1]) != nil {
            let extendedName = "\(name) \(foundValue)"
            if let extendedMatch = BloodTestResult.matchLabParameter(name: extendedName, testType: testType) {
                match = extendedMatch
                name = extendedName
                foundIndex += 1
                if isValueToken(cells[foundIndex]) {
                    foundValue = cells[foundIndex]
                    inlineUnit = nil
                } else if let (splitValue, splitUnit) = splitValueUnit(cells[foundIndex]) {
                    foundValue = splitValue
                    inlineUnit = splitUnit
                }
            }
        }
        guard let (standardKey, parameter, matchConfidence) = match else { return nil }

        // Classify the remaining cells as unit / reference range / flag
        var unit: String? = inlineUnit
        var referenceRange: String?
        var flag: String?

        for cell in cells[(foundIndex + 1)...] {
            let trimmedCell = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            if flag == nil, isFlagToken(trimmedCell) {
                flag = trimmedCell
            } else if referenceRange == nil, let range = extractRange(from: trimmedCell) {
                referenceRange = range
                if unit == nil, let embeddedUnit = extractUnit(from: trimmedCell, excludingRange: range) {
                    unit = embeddedUnit
                }
            } else if unit == nil, isUnitToken(trimmedCell) {
                unit = trimmedCell
            }
        }

        // Validate
        var validation = BloodTestValueValidator.validateValue(
            foundValue,
            testName: parameter.name,
            referenceRange: referenceRange ?? parameter.referenceRange,
            standardParam: parameter
        )
        validation = BloodTestValueValidator.applyingUnitValidation(validation, unit: unit, for: parameter)

        // Flag disagreement doesn't invalidate (labs use their own ranges) but lowers confidence
        var confidence = baseConfidence * matchConfidence
        if !BloodTestValueValidator.flagConsistency(value: foundValue, referenceRange: referenceRange, flag: flag) {
            confidence *= 0.85
        }

        let context = LabMeasurementContext.infer(testName: name, parameter: parameter, unit: unit)

        return LabValueCandidate(
            standardKey: standardKey,
            parameter: parameter,
            originalTestName: name,
            value: foundValue,
            unit: unit,
            referenceRange: referenceRange,
            abnormalFlag: flag,
            testType: testType,
            source: source,
            pageNumber: pageNumber,
            sourceSnippet: String(snippet.prefix(200)),
            confidence: confidence,
            validation: validation,
            matchConfidence: matchConfidence,
            specimen: context.specimen,
            collection: context.collection
        )
    }

    /// Drop a trailing footnote marker — a 1-2 digit superscript, optionally
    /// wrapped in the stray punctuation OCR produces for it. Returns nil when
    /// there is nothing to strip or when stripping would leave no name.
    static func strippingFootnoteMarker(from name: String) -> String? {
        let stripped = name.replacingOccurrences(
            of: #"[\s"'`°*†‡]*\d{1,2}[\s"'`°*†‡]*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard stripped != name,
              stripped.count >= 2,
              stripped.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }
        return stripped
    }

    // MARK: - Token Classification

    private static let flagTokens: Set<String> = [
        "H", "L", "HH", "LL", "A", "AB", "ABN", "*", "HIGH", "LOW",
        "CRITICAL", "CRIT", "ABNORMAL", "HI", "LO"
    ]

    func isValueToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if BloodTestValueValidator.isQualitativeValue(trimmed) { return true }

        let pattern = #"^[<>≤≥]?\s*\d{1,7}([.,]\d+)?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Split a combined "98 mg/dL"-style cell into value + unit.
    func splitValueUnit(_ token: String) -> (value: String, unit: String)? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        guard components.count >= 2, isValueToken(components[0]) else { return nil }
        let unitPart = components.dropFirst().joined(separator: " ")
        guard isUnitToken(unitPart) else { return nil }
        return (components[0], unitPart)
    }

    func isUnitToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20 else { return false }

        let canonical = BloodTestValueValidator.canonicalUnit(trimmed)
        if Self.knownCanonicalUnits.contains(canonical) { return true }

        // Structural check: something/something (e.g. unusual but valid unit strings)
        let structural = #"^[a-z%µμ][a-z0-9^*/.%()µμ]*$"#
        return canonical.contains("/") && canonical.range(of: structural, options: .regularExpression) != nil
    }

    private static let knownCanonicalUnits: Set<String> = {
        var units = Set<String>()
        for parameter in BloodTestResult.standardizedLabParameters.values {
            if let unit = parameter.unit, !unit.isEmpty {
                units.insert(BloodTestValueValidator.canonicalUnit(unit))
            }
        }
        units.formUnion(["%", "sec", "pg", "fl", "k/ul", "m/ul", "mg/dl", "g/dl", "mg/l", "g/l",
                         "meq/l", "mmol/l", "umol/l", "ug/dl", "ug/l", "ug/ml", "uiu/ml", "miu/l",
                         "miu/ml", "iu/ml", "u/l", "u/ml", "ng/ml", "ng/dl", "pg/ml", "mm/hr",
                         "mosm/kg", "ml/min", "ml/min/1.73m2", "cfu/ml", "/hpf", "/lpf", "nmol/l"])
        return units
    }()

    func isFlagToken(_ token: String) -> Bool {
        Self.flagTokens.contains(token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    /// Extract a reference range from a cell ("70-100", "< 200", "3.5 - 5.0 g/dL").
    func extractRange(from token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        let intervalPattern = #"\d{1,7}(\.\d+)?\s*[-–—]\s*\d{1,7}(\.\d+)?"#
        if let match = trimmed.range(of: intervalPattern, options: .regularExpression) {
            return String(trimmed[match]).replacingOccurrences(of: " ", with: "")
        }

        let boundPattern = #"^[<>≤≥]\s*\d{1,7}(\.\d+)?$"#
        if trimmed.range(of: boundPattern, options: .regularExpression) != nil {
            return trimmed.replacingOccurrences(of: " ", with: "")
        }

        let qualitative = trimmed.lowercased()
        if ["negative", "none", "not detected", "no growth", "clear"].contains(qualitative) {
            return trimmed
        }

        return nil
    }

    /// Extract a trailing/leading unit from a combined range+unit cell.
    private func extractUnit(from token: String, excludingRange range: String) -> String? {
        var remainder = token
        // Remove the range portion (it was normalized without spaces; remove both forms)
        remainder = remainder.replacingOccurrences(of: range, with: "")
        let intervalPattern = #"\d{1,7}(\.\d+)?\s*[-–—]\s*\d{1,7}(\.\d+)?"#
        remainder = remainder.replacingOccurrences(of: intervalPattern, with: "", options: .regularExpression)
        remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        guard !remainder.isEmpty, isUnitToken(remainder) else { return nil }
        return remainder
    }

    // MARK: - Section / Header Detection

    private func updateSectionTestType(from line: String, testType: inout BloodTestResult.LabTestType) {
        let lowered = line.lowercased()

        let urineMarkers = ["urinalysis", "urine analysis", "urine chemistry", "urine microbiology",
                            "urine culture", "microscopic examination"]
        if urineMarkers.contains(where: { lowered.contains($0) }) || lowered == "urine" || lowered.hasPrefix("ua ") {
            testType = .urine
            return
        }

        let bloodMarkers = ["hematology", "chemistry", "complete blood count", "metabolic panel",
                            "lipid panel", "serum", "plasma", "cbc", "cmp", "bmp", "thyroid panel",
                            "coagulation", "immunology"]
        // Only treat as a section switch when the line looks like a heading, not a data row
        let looksLikeHeading = line.count <= 50 && !line.contains(where: { $0.isNumber })
        if looksLikeHeading && bloodMarkers.contains(where: { lowered.contains($0) }) {
            testType = .blood
        }
    }

    private func isHeaderRow(_ cells: [String]) -> Bool {
        let joined = cells.joined(separator: " ").lowercased()
        let headerWords = ["test name", "analyte", "component", "result", "reference range",
                           "reference interval", "units", "flag", "current result"]
        let matches = headerWords.filter { joined.contains($0) }.count
        // A real header row mentions at least two column labels and carries no numbers
        return matches >= 2 && !joined.contains(where: { $0.isNumber })
    }
}

// MARK: - Reconciled Lab Results
/// Output of `LabCandidateReconciler`: groups partitioned by the auto-accept rule.
struct ReconciledLabResults {
    /// Exactly one distinct, valid, normal, strongly matched, high-confidence
    /// value — imported without user review.
    var autoAccepted: [BloodTestImportGroup]
    /// Multiple distinct values (likely OCR/extraction duplicates), or a single
    /// value failing an auto-accept check — the user must decide.
    var needsReview: [BloodTestImportGroup]

    var isEmpty: Bool { autoAccepted.isEmpty && needsReview.isEmpty }
}

// MARK: - Lab Candidate Reconciler
/// Merges lab value candidates from all extraction passes (deterministic parser,
/// on-device LLM, cloud) and applies the auto-accept rule:
///   - Candidates for the same test with the SAME normalized value+unit are merged —
///     cross-pass agreement is confirmation, not duplication.
///   - Exactly 1 distinct, valid, normal, strongly matched, high-confidence value
///     → auto-accepted (silent import).
///   - 2+ distinct values, or a value failing any auto-accept check → needs review.
enum LabCandidateReconciler {

    static func reconcile(_ candidates: [LabValueCandidate]) -> ReconciledLabResults {
        var byKey: [String: [LabValueCandidate]] = [:]
        for candidate in candidates {
            byKey[candidate.standardKey, default: []].append(candidate)
        }

        var results = ReconciledLabResults(autoAccepted: [], needsReview: [])

        for (standardKey, group) in byKey.sorted(by: { $0.key < $1.key }) {
            // Merge candidates whose normalized value+unit agree across passes
            var mergedByValue: [String: (representative: LabValueCandidate, sources: [CandidateSource], confidence: Double)] = [:]
            var valueOrder: [String] = []

            for candidate in group {
                let valueKey = candidate.normalizedValueKey
                if var existing = mergedByValue[valueKey] {
                    let isIndependentSource = !existing.sources.contains(candidate.source)
                    if isIndependentSource {
                        existing.sources.append(candidate.source)
                    }
                    // Prefer the more complete representative (has unit/range) and
                    // boost confidence when independent passes agree
                    if representativeScore(candidate) > representativeScore(existing.representative) {
                        existing = (candidate, existing.sources, existing.confidence)
                    }
                    let highestConfidence = max(existing.confidence, candidate.confidence)
                    existing.confidence = isIndependentSource
                        ? min(0.99, highestConfidence + 0.05)
                        : highestConfidence
                    mergedByValue[valueKey] = existing
                } else {
                    mergedByValue[valueKey] = (candidate, [candidate.source], candidate.confidence)
                    valueOrder.append(valueKey)
                }
            }

            let distinct = valueOrder.compactMap { mergedByValue[$0] }
            let importCandidates = distinct.map { entry -> BloodTestImportCandidate in
                let candidate = entry.representative
                return BloodTestImportCandidate(
                    testName: candidate.parameter.name,
                    value: candidate.value,
                    unit: candidate.unit ?? candidate.parameter.unit,
                    referenceRange: candidate.referenceRange ?? candidate.parameter.referenceRange,
                    isAbnormal: candidate.isAbnormal,
                    originalTestName: candidate.originalTestName,
                    confidence: entry.confidence,
                    validationStatus: validationStatus(for: candidate),
                    reason: candidate.validationReason,
                    sources: entry.sources,
                    pageNumber: candidate.pageNumber,
                    sourceSnippet: candidate.sourceSnippet,
                    specimen: candidate.specimen ?? candidate.parameter.defaultSpecimen,
                    collection: candidate.collection ?? candidate.parameter.defaultCollection
                )
            }

            guard let parameterName = group.first?.parameter.name else { continue }

            // A value must be structurally valid, have a strong name match, and
            // have enough extraction confidence before it can be silently imported.
            // Abnormal values remain importable but require an explicit review.
            let representative = distinct[0].representative
            let isAutoAccepted = distinct.count == 1
                && representative.isValid
                && representative.matchConfidence >= 0.7
                && distinct[0].confidence > 0.7
                && !representative.isAbnormal

            let importGroup = BloodTestImportGroup(
                standardTestName: parameterName,
                standardKey: standardKey,
                candidates: importCandidates,
                selectedCandidateId: isAutoAccepted ? importCandidates.first?.id : nil,
                isAutoAccepted: isAutoAccepted
            )

            if isAutoAccepted {
                results.autoAccepted.append(importGroup)
            } else {
                results.needsReview.append(importGroup)
            }
        }

        AppLog.shared.healthData("Reconciler: \(candidates.count) candidates → \(results.autoAccepted.count) auto-accepted, \(results.needsReview.count) need review")
        return results
    }

    /// Completeness score used to pick the best representative among agreeing candidates.
    private static func representativeScore(_ candidate: LabValueCandidate) -> Int {
        var score = 0
        if candidate.unit != nil { score += 2 }
        if candidate.referenceRange != nil { score += 2 }
        if candidate.abnormalFlag != nil { score += 1 }
        if candidate.isValid { score += 4 }
        return score
    }

    private static func validationStatus(for candidate: LabValueCandidate) -> BloodTestImportCandidate.ValidationStatus {
        switch candidate.validation {
        case .valid: return .valid
        case .unitMismatch: return .unitMismatch
        case .ocrUnitMismatch: return .ocrUnitMismatch
        case .invalidType: return .invalidType
        case .outOfRange: return .outOfRange
        case .missingData: return .missingData
        }
    }
}

// MARK: - Cloud Vision Lab Extraction
/// Schema prompt and response parsing for the vision-model extraction pass.
/// The prompt demands strict JSON; parsing tolerates fences and trailing prose.
enum CloudVisionLabExtraction {

    struct Result {
        var candidates: [LabValueCandidate]
        var documentDate: Date?
        var laboratoryName: String?
        var orderingPhysician: String?
    }

    static var schemaPrompt: String {
        """
        Read the attached lab report page images and extract EVERY laboratory value \
        (blood AND urine). Respond with ONLY this JSON structure — no other text:

        {
          "labValues": [
            {
              "testName": "exact test name as printed",
              "testType": "BLOOD or URINE",
              "value": "numeric value, or Negative/Positive/Trace for qualitative tests",
              "unit": "unit as printed, or null",
              "referenceRange": "range as printed (e.g. 70-100, <200), or null",
              "flag": "H, L, High, Low, Critical, or null",
              "specimen": "SERUM, PLASMA, WHOLE_BLOOD, URINE, or null",
              "collection": "RANDOM, SPOT, 24_HOUR, TIMED, or null",
              "page": 1
            }
          ],
          "documentDate": "YYYY-MM-DD or null",
          "laboratoryName": "lab name or null",
          "orderingPhysician": "physician name or null"
        }

        Rules:
        - Extract every value exactly once; if the same test truly appears twice with \
        different values (different draw times), include both.
        - Preserve test names, values, units, and ranges exactly as printed.
        - Include both percent and absolute CBC differential values as separate entries.
        - Preserve explicit specimen and urine collection context when printed; do not invent it.
        - "page" is the 1-based index of the attached image the value appears on.
        """
    }

    static func parse(_ response: String, source: CandidateSource = .cloudVision) -> Result {
        var result = Result(candidates: [], documentDate: nil, laboratoryName: nil, orderingPhysician: nil)

        guard let jsonString = extractJSONObject(from: response),
              let jsonData = jsonString.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            AppLog.shared.documents("Cloud vision extraction: could not parse JSON from response (\(response.count) chars)", level: .warning)
            return result
        }

        if let dateString = json["documentDate"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            result.documentDate = formatter.date(from: dateString)
        }
        result.laboratoryName = json["laboratoryName"] as? String
        result.orderingPhysician = json["orderingPhysician"] as? String

        guard let labValues = json["labValues"] as? [[String: Any]] else { return result }

        for entry in labValues {
            guard let testName = entry["testName"] as? String,
                  !testName.isEmpty else { continue }

            let value: String
            if let stringValue = entry["value"] as? String {
                value = stringValue
            } else if let numberValue = entry["value"] as? NSNumber {
                value = numberValue.stringValue
            } else {
                continue
            }

            let testTypeString = (entry["testType"] as? String)?.uppercased() ?? "BLOOD"
            let testType: BloodTestResult.LabTestType = testTypeString == "URINE" ? .urine : .blood

            guard let match = BloodTestResult.matchLabParameter(name: testName, testType: testType) else {
                continue
            }

            let unit = entry["unit"] as? String
            let referenceRange = entry["referenceRange"] as? String
            let flag = entry["flag"] as? String
            let page = entry["page"] as? Int

            var validation = BloodTestValueValidator.validateValue(
                value,
                testName: match.parameter.name,
                referenceRange: referenceRange ?? match.parameter.referenceRange,
                standardParam: match.parameter
            )
            validation = BloodTestValueValidator.applyingUnitValidation(validation, unit: unit, for: match.parameter)

            let context = LabMeasurementContext.infer(
                testName: testName,
                parameter: match.parameter,
                unit: unit,
                reportedSpecimen: entry["specimen"] as? String,
                reportedCollection: entry["collection"] as? String
            )

            result.candidates.append(LabValueCandidate(
                standardKey: match.key,
                parameter: match.parameter,
                originalTestName: testName,
                value: value,
                unit: unit,
                referenceRange: referenceRange,
                abnormalFlag: flag,
                testType: testType,
                source: source,
                pageNumber: page,
                sourceSnippet: "Vision model: \(testName) = \(value)\(unit.map { " \($0)" } ?? "")",
                confidence: 0.9 * match.matchConfidence,
                validation: validation,
                matchConfidence: match.matchConfidence,
                specimen: context.specimen,
                collection: context.collection
            ))
        }

        return result
    }

    /// Balanced-brace JSON extraction tolerant of markdown fences and prose.
    private static func extractJSONObject(from text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: #"```(?:json)?"#, with: "", options: .regularExpression)
        guard let startIndex = cleaned.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var index = startIndex

        while index < cleaned.endIndex {
            let char = cleaned[index]
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" { depth += 1 }
                if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(cleaned[startIndex...index])
                    }
                }
            }
            index = cleaned.index(after: index)
        }

        if let endIndex = cleaned.lastIndex(of: "}"), endIndex > startIndex {
            return String(cleaned[startIndex...endIndex])
        }
        return nil
    }
}
