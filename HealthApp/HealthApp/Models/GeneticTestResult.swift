import Foundation

// MARK: - Genetic Test Result
/// Structured facts reported by a genetic or pharmacogenomic test.
///
/// The app stores the laboratory's reported genotype/phenotype and
/// interpretation. It deliberately does not infer a medication recommendation
/// from a gene symbol alone.
struct GeneticTestResult: HealthDataProtocol, Hashable {
    let id: UUID
    var type: HealthDataType { .geneticProfile }

    // Test information
    var testDate: Date
    var laboratoryName: String?
    var orderingPhysician: String?
    var testName: String?
    var panelName: String?
    var specimen: GeneticSpecimen?
    var testedGenes: [String]
    var results: [GeneticTestItem]
    /// Findings that could not be safely structured without a user checking
    /// the original report. The report text remains stored on the parent
    /// MedicalDocument while these issues are pending.
    var reviewIssues: [GeneticTestReviewIssue]
    var limitations: String?

    // AI context management
    var includeInAIContext: Bool

    // Protocol requirements
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?

    init(
        id: UUID = UUID(),
        testDate: Date,
        laboratoryName: String? = nil,
        orderingPhysician: String? = nil,
        testName: String? = nil,
        panelName: String? = nil,
        specimen: GeneticSpecimen? = nil,
        testedGenes: [String] = [],
        results: [GeneticTestItem] = [],
        reviewIssues: [GeneticTestReviewIssue] = [],
        limitations: String? = nil,
        includeInAIContext: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.testDate = testDate
        self.laboratoryName = laboratoryName
        self.orderingPhysician = orderingPhysician
        self.testName = testName
        self.panelName = panelName
        self.specimen = specimen
        self.testedGenes = testedGenes
        self.results = results
        self.reviewIssues = reviewIssues
        self.limitations = limitations
        self.includeInAIContext = includeInAIContext
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, testDate, laboratoryName, orderingPhysician, testName, panelName
        case specimen, testedGenes, results, reviewIssues, limitations, includeInAIContext
        case createdAt, updatedAt, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        testDate = try container.decode(Date.self, forKey: .testDate)
        laboratoryName = try container.decodeIfPresent(String.self, forKey: .laboratoryName)
        orderingPhysician = try container.decodeIfPresent(String.self, forKey: .orderingPhysician)
        testName = try container.decodeIfPresent(String.self, forKey: .testName)
        panelName = try container.decodeIfPresent(String.self, forKey: .panelName)
        specimen = try container.decodeIfPresent(GeneticSpecimen.self, forKey: .specimen)
        testedGenes = try container.decodeIfPresent([String].self, forKey: .testedGenes) ?? []
        results = try container.decodeIfPresent([GeneticTestItem].self, forKey: .results) ?? []
        reviewIssues = try container.decodeIfPresent([GeneticTestReviewIssue].self, forKey: .reviewIssues) ?? []
        limitations = try container.decodeIfPresent(String.self, forKey: .limitations)
        includeInAIContext = try container.decodeIfPresent(Bool.self, forKey: .includeInAIContext) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }

    var isValid: Bool {
        !testedGenes.isEmpty || !results.isEmpty
    }

    /// True when the importer found a result that needs a human check before
    /// it is treated as a reviewed structured record.
    var needsReview: Bool {
        !reviewIssues.isEmpty || metadata?["pending_review"] == "true"
    }

    /// Applies the user's accept/skip decisions while retaining the original
    /// report text on the parent MedicalDocument for later reference.
    func applyingReview(
        acceptedIssueIDs: Set<UUID>,
        skippedIssueIDs: Set<UUID>
    ) -> GeneticTestResult {
        var resolved = self
        let skippedResultIDs = Set(
            reviewIssues
                .filter { skippedIssueIDs.contains($0.id) }
                .compactMap(\.resultID)
        )
        resolved.results.removeAll { skippedResultIDs.contains($0.id) }
        resolved.reviewIssues = []
        resolved.updatedAt = Date()

        var updatedMetadata = resolved.metadata ?? [:]
        updatedMetadata.removeValue(forKey: "pending_review")
        updatedMetadata["import_review_completed"] = "true"
        updatedMetadata["reviewed_issue_count"] = String(acceptedIssueIDs.union(skippedIssueIDs).count)
        updatedMetadata["skipped_issue_count"] = String(skippedIssueIDs.count)
        updatedMetadata["review_decision"] = skippedIssueIDs.isEmpty ? "accepted" : "accepted_with_skips"
        resolved.metadata = updatedMetadata
        return resolved
    }

    /// A compact, provenance-preserving representation used in document
    /// sections and AI context. Medication implications are included only when
    /// the source report explicitly supplied them.
    var contextSummary: String {
        var lines: [String] = [
            "Structured genetic test data (Reported laboratory findings only):"
        ]

        if let testName, !testName.isEmpty {
            lines.append("Test: \(testName)")
        }
        if let panelName, !panelName.isEmpty {
            lines.append("Panel: \(panelName)")
        }
        if let specimen {
            lines.append("Specimen: \(specimen.displayName)")
        }
        if !testedGenes.isEmpty {
            lines.append("Genes explicitly reported as tested: \(testedGenes.joined(separator: ", "))")
        }

        for result in results {
            var resultLine = "- \(result.gene)"
            if let genotype = result.genotype, !genotype.isEmpty {
                resultLine += "; genotype: \(genotype)"
            }
            if let diplotype = result.diplotype, !diplotype.isEmpty {
                resultLine += "; diplotype: \(diplotype)"
            }
            if let phenotype = result.phenotype, !phenotype.isEmpty {
                resultLine += "; phenotype: \(phenotype)"
            }
            if let variant = result.variant, !variant.isEmpty {
                resultLine += "; variant: \(variant)"
            }
            if let rsID = result.rsID, !rsID.isEmpty {
                resultLine += "; rsID: \(rsID)"
            }
            if let reportedResult = result.reportedResult, !reportedResult.isEmpty {
                resultLine += "; reported result: \(reportedResult)"
            }
            lines.append(resultLine)

            if let interpretation = result.reportedInterpretation, !interpretation.isEmpty {
                lines.append("  Reported interpretation: \(interpretation)")
            }
            if !result.reportedMedicationImplications.isEmpty {
                lines.append("  Reported medication implications: \(result.reportedMedicationImplications.joined(separator: "; "))")
            }
        }

        if let limitations, !limitations.isEmpty {
            lines.append("Limitations reported by the laboratory: \(limitations)")
        }

        lines.append("Do not treat this summary as a diagnosis or prescribing instruction; verify the original report and current clinical guidance.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Genetic Test Review Issue
/// A report-grounded reason why a parsed genetic finding should be checked by
/// the user before it is used as structured context.
struct GeneticTestReviewIssue: Identifiable, Codable, Hashable {
    let id: UUID
    let resultID: UUID?
    let gene: String?
    let reason: String
    let sourceText: String?

    init(
        id: UUID = UUID(),
        resultID: UUID? = nil,
        gene: String? = nil,
        reason: String,
        sourceText: String? = nil
    ) {
        self.id = id
        self.resultID = resultID
        self.gene = gene
        self.reason = reason
        self.sourceText = sourceText
    }

    var displayName: String {
        gene ?? "Genetic report"
    }
}

// MARK: - Genetic Specimen
enum GeneticSpecimen: String, CaseIterable, Codable, Hashable {
    case blood
    case saliva
    case buccalSwab = "buccal_swab"
    case tissue
    case other
    case unknown

    var displayName: String {
        switch self {
        case .blood:
            return "Blood"
        case .saliva:
            return "Saliva"
        case .buccalSwab:
            return "Buccal swab"
        case .tissue:
            return "Tissue"
        case .other:
            return "Other"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - Genetic Marker Category
enum GeneticMarkerCategory: String, CaseIterable, Codable, Hashable {
    case drugMetabolism = "drug_metabolism"
    case drugTransport = "drug_transport"
    case drugResponse = "drug_response"
    case adverseDrugReaction = "adverse_drug_reaction"
    case diseaseRisk = "disease_risk"
    case carrierStatus = "carrier_status"
    case other

    var displayName: String {
        switch self {
        case .drugMetabolism:
            return "Drug metabolism"
        case .drugTransport:
            return "Drug transport"
        case .drugResponse:
            return "Drug response"
        case .adverseDrugReaction:
            return "Adverse drug reaction"
        case .diseaseRisk:
            return "Disease risk"
        case .carrierStatus:
            return "Carrier status"
        case .other:
            return "Other"
        }
    }
}

// MARK: - Pharmacogenomic Gene Catalog
/// A bounded catalog of commonly actionable pharmacogenomic markers. This is
/// intentionally a recognition catalog, not a drug-dosing engine. The report
/// remains the source of truth for the actual result and interpretation.
enum PharmacogenomicGene: String, CaseIterable, Codable, Hashable {
    case cyp2d6 = "CYP2D6"
    case cyp2c19 = "CYP2C19"
    case cyp2c9 = "CYP2C9"
    case cyp2b6 = "CYP2B6"
    case cyp3a5 = "CYP3A5"
    case cyp4f2 = "CYP4F2"
    case dpyd = "DPYD"
    case tpmt = "TPMT"
    case nudt15 = "NUDT15"
    case ugt1a1 = "UGT1A1"
    case nat2 = "NAT2"
    case slco1b1 = "SLCO1B1"
    case abcg2 = "ABCG2"
    case vkorc1 = "VKORC1"
    case hlaA = "HLA-A"
    case hlaB = "HLA-B"
    case g6pd = "G6PD"
    case ifnl3 = "IFNL3/IFNL4"
    case ryr1 = "RYR1"
    case cacna1s = "CACNA1S"
    case cftr = "CFTR"

    var aliases: [String] {
        switch self {
        case .hlaA:
            return ["HLA A"]
        case .hlaB:
            return ["HLA B"]
        case .ifnl3:
            return ["IFNL3", "IFNL4"]
        default:
            return []
        }
    }

    var category: GeneticMarkerCategory {
        switch self {
        case .cyp2d6, .cyp2c19, .cyp2c9, .cyp2b6, .cyp3a5, .cyp4f2,
             .dpyd, .tpmt, .nudt15, .ugt1a1, .nat2:
            return .drugMetabolism
        case .slco1b1, .abcg2:
            return .drugTransport
        case .vkorc1, .ifnl3, .cftr:
            return .drugResponse
        case .hlaA, .hlaB, .g6pd, .ryr1, .cacna1s:
            return .adverseDrugReaction
        }
    }

    static func match(in text: String) -> PharmacogenomicGene? {
        let uppercasedText = text.uppercased()

        for gene in allCases {
            let names = [gene.rawValue] + gene.aliases
            for name in names {
                let escapedName = NSRegularExpression.escapedPattern(for: name.uppercased())
                let pattern = "(?<![A-Z0-9])\(escapedName)(?![A-Z0-9])"
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(uppercasedText.startIndex..., in: uppercasedText)
                if regex.firstMatch(in: uppercasedText, range: range) != nil {
                    return gene
                }
            }
        }

        return nil
    }
}

// MARK: - Genetic Test Item
struct GeneticTestItem: Codable, Identifiable, Hashable {
    let id: UUID
    var gene: String
    var category: GeneticMarkerCategory
    var isKnownPharmacogene: Bool
    var genotype: String?
    var diplotype: String?
    var phenotype: String?
    var variant: String?
    var rsID: String?
    var reportedResult: String?
    var reportedInterpretation: String?
    var reportedMedicationImplications: [String]
    var evidenceLevel: String?
    var sourceText: String?

    init(
        id: UUID = UUID(),
        gene: String,
        category: GeneticMarkerCategory = .other,
        isKnownPharmacogene: Bool = false,
        genotype: String? = nil,
        diplotype: String? = nil,
        phenotype: String? = nil,
        variant: String? = nil,
        rsID: String? = nil,
        reportedResult: String? = nil,
        reportedInterpretation: String? = nil,
        reportedMedicationImplications: [String] = [],
        evidenceLevel: String? = nil,
        sourceText: String? = nil
    ) {
        self.id = id
        self.gene = gene
        self.category = category
        self.isKnownPharmacogene = isKnownPharmacogene
        self.genotype = genotype
        self.diplotype = diplotype
        self.phenotype = phenotype
        self.variant = variant
        self.rsID = rsID
        self.reportedResult = reportedResult
        self.reportedInterpretation = reportedInterpretation
        self.reportedMedicationImplications = reportedMedicationImplications
        self.evidenceLevel = evidenceLevel
        self.sourceText = sourceText
    }
}
