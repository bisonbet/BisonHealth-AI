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

    /// Inserts or updates one structured finding and adds its gene to the
    /// report's tested-gene list when needed. The report-level list is kept
    /// separate so deleting a finding does not erase evidence that the gene
    /// was tested.
    mutating func upsertResult(_ item: GeneticTestItem) {
        let normalizedGene = item.gene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedGene.isEmpty else { return }

        var updatedItem = item
        updatedItem.gene = PharmacogenomicGene.match(in: normalizedGene)?.rawValue ?? normalizedGene.uppercased()

        if let index = results.firstIndex(where: { $0.id == item.id }) {
            results[index] = updatedItem
        } else {
            results.append(updatedItem)
        }

        if !testedGenes.contains(where: { $0.caseInsensitiveCompare(updatedItem.gene) == .orderedSame }) {
            testedGenes.append(updatedItem.gene)
        }

        reviewIssues.removeAll { $0.resultID == updatedItem.id }
        if reviewIssues.isEmpty {
            var updatedMetadata = metadata ?? [:]
            updatedMetadata.removeValue(forKey: "pending_review")
            updatedMetadata["manual_edit_completed"] = "true"
            metadata = updatedMetadata
        }
        updatedAt = Date()
    }

    /// Removes one structured finding but deliberately leaves the source
    /// document, extracted report text, and report-level tested-gene list intact.
    @discardableResult
    mutating func removeResult(id: UUID) -> GeneticTestItem? {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return nil }
        let removedItem = results.remove(at: index)
        reviewIssues.removeAll { issue in
            if issue.resultID == id {
                return true
            }
            guard issue.resultID == nil,
                  issue.gene?.caseInsensitiveCompare(removedItem.gene) == .orderedSame else {
                return false
            }
            return !results.contains {
                $0.gene.caseInsensitiveCompare(removedItem.gene) == .orderedSame
            }
        }

        if reviewIssues.isEmpty {
            var updatedMetadata = metadata ?? [:]
            updatedMetadata.removeValue(forKey: "pending_review")
            updatedMetadata["manual_edit_completed"] = "true"
            metadata = updatedMetadata
        }
        updatedAt = Date()
        return removedItem
    }

    /// A compact, provenance-preserving representation used in document
    /// sections and AI context. Medication implications are included only when
    /// the source report explicitly supplied them.
    var contextSummary: String {
        var lines: [String] = [
            "Structured genetic test data (Reported laboratory findings only):"
        ]
        lines.append("App catalog labels are suggestions for review, not laboratory interpretations.")

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
            if let catalogPhenotype = result.curatedPhenotype, !catalogPhenotype.isEmpty {
                resultLine += "; app catalog suggestion: \(catalogPhenotype)"
            } else if let catalogSuggestion = result.catalogSuggestion,
                      let phenotype = catalogSuggestion.phenotype,
                      !phenotype.isEmpty {
                resultLine += "; app catalog suggestion: \(phenotype)"
            }
            lines.append(resultLine)

            if let interpretation = result.reportedInterpretation, !interpretation.isEmpty {
                lines.append("  Reported interpretation: \(interpretation)")
            }
            if !result.reportedMedicationImplications.isEmpty {
                lines.append("  Reported medication implications: \(result.reportedMedicationImplications.joined(separator: "; "))")
            }
            if let catalogSummary = result.catalogSummary, !catalogSummary.isEmpty {
                lines.append("  Catalog summary (not a laboratory interpretation): \(catalogSummary)")
            }
            if let pharmGKBURL = result.pharmGKBURL {
                lines.append("  PharmGKB: \(pharmGKBURL.absoluteString)")
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
    case cyp1a2 = "CYP1A2"
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
        case .cyp1a2, .cyp2d6, .cyp2c19, .cyp2c9, .cyp2b6, .cyp3a5, .cyp4f2,
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

    /// Short, conservative suggestions for common pharmacogenomic diplotypes.
    /// These are prompts for review, not dosing advice or a replacement for a
    /// laboratory-reported phenotype.
    var catalogOptions: [GeneticCatalogOption] {
        switch self {
        case .cyp1a2:
            return [
                GeneticCatalogOption(
                    gene: self,
                    diplotype: "*1A/*1A",
                    phenotype: "Normal inducibility",
                    summary: "No common *1F allele is present in this diplotype; CYP1A2 activity still depends on exposures and other factors."
                ),
                GeneticCatalogOption(
                    gene: self,
                    diplotype: "*1A/*1F",
                    phenotype: "Higher inducibility (context-dependent)",
                    summary: "One *1F allele may be associated with higher inducibility in some settings; smoking, diet, medicines, and other factors can change activity."
                ),
                GeneticCatalogOption(
                    gene: self,
                    diplotype: "*1F/*1F",
                    phenotype: "Higher inducibility (context-dependent)",
                    summary: "Two *1F alleles may be associated with higher inducibility in some settings; this is not a universal rapid-metabolizer call."
                )
            ]
        case .cyp2d6:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal CYP2D6 activity under standard allele-function conventions."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*4", phenotype: "Normal or intermediate (guideline-dependent)", summary: "An activity score around 1.0 is classified differently by some guidelines and laboratories; preserve the reported phenotype when available."),
                GeneticCatalogOption(gene: self, diplotype: "*4/*4", phenotype: "Poor Metabolizer", summary: "Two no-function alleles are commonly assigned very low CYP2D6 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*1xN/*1", phenotype: "Ultrarapid Metabolizer", summary: "A duplicated functional allele may increase CYP2D6 activity; copy-number testing and current guidance are essential.")
            ]
        case .cyp2c19:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal CYP2C19 activity under standard allele-function conventions."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*2", phenotype: "Intermediate Metabolizer", summary: "One normal-function and one no-function allele are commonly assigned reduced CYP2C19 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*2/*2", phenotype: "Poor Metabolizer", summary: "Two no-function alleles are commonly assigned very low CYP2C19 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*17", phenotype: "Rapid Metabolizer", summary: "One increased-function allele is commonly assigned higher CYP2C19 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*17/*17", phenotype: "Ultrarapid Metabolizer", summary: "Two increased-function alleles are commonly assigned high CYP2C19 activity.")
            ]
        case .cyp2c9:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal CYP2C9 activity under standard allele-function conventions."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*2", phenotype: "Intermediate Metabolizer", summary: "A decreased-function allele with a normal-function allele is commonly assigned reduced CYP2C9 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*3", phenotype: "Intermediate Metabolizer", summary: "A no-function allele with a normal-function allele is commonly assigned reduced CYP2C9 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*2/*3", phenotype: "Poor Metabolizer", summary: "Two reduced or no-function alleles are commonly assigned very low CYP2C9 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*3/*3", phenotype: "Poor Metabolizer", summary: "Two no-function alleles are commonly assigned very low CYP2C9 activity.")
            ]
        case .cyp2b6:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal CYP2B6 activity under standard allele-function conventions."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*6", phenotype: "Intermediate Metabolizer", summary: "A commonly reduced-function CYP2B6 allele is paired with a normal-function allele."),
                GeneticCatalogOption(gene: self, diplotype: "*6/*6", phenotype: "Poor Metabolizer", summary: "Two commonly reduced-function CYP2B6 alleles may produce lower activity.")
            ]
        case .cyp3a5:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Expressor", summary: "At least one *1 allele is commonly associated with CYP3A5 expression."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*3", phenotype: "Expressor", summary: "At least one *1 allele is commonly associated with CYP3A5 expression."),
                GeneticCatalogOption(gene: self, diplotype: "*3/*3", phenotype: "Non-expresser", summary: "Two *3 alleles are commonly associated with little or no CYP3A5 expression.")
            ]
        case .dpyd:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal DPD Activity", summary: "No listed decreased-function allele is present in this common diplotype."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*2A", phenotype: "Intermediate DPD Activity", summary: "One commonly decreased-function allele may reduce DPD activity."),
                GeneticCatalogOption(gene: self, diplotype: "*2A/*2A", phenotype: "Poor DPD Activity", summary: "Two commonly decreased-function alleles may produce very low DPD activity.")
            ]
        case .tpmt:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal TPMT activity."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*3A", phenotype: "Intermediate Metabolizer", summary: "One commonly nonfunctional TPMT allele may reduce TPMT activity."),
                GeneticCatalogOption(gene: self, diplotype: "*3A/*3A", phenotype: "Poor Metabolizer", summary: "Two commonly nonfunctional TPMT alleles may produce very low TPMT activity.")
            ]
        case .nudt15:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1/*1", phenotype: "Normal Metabolizer", summary: "Commonly assigned normal NUDT15 activity."),
                GeneticCatalogOption(gene: self, diplotype: "*1/*3", phenotype: "Intermediate Metabolizer", summary: "One commonly decreased-function NUDT15 allele may reduce activity."),
                GeneticCatalogOption(gene: self, diplotype: "*3/*3", phenotype: "Poor Metabolizer", summary: "Two commonly decreased-function NUDT15 alleles may produce very low activity.")
            ]
        case .nat2:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*4/*4", phenotype: "Rapid Acetylator", summary: "This common NAT2 diplotype is generally associated with faster acetylation."),
                GeneticCatalogOption(gene: self, diplotype: "*4/*5", phenotype: "Intermediate Acetylator", summary: "One rapid and one slow NAT2 allele are generally associated with intermediate acetylation."),
                GeneticCatalogOption(gene: self, diplotype: "*5/*5", phenotype: "Slow Acetylator", summary: "Two slow NAT2 alleles are generally associated with slower acetylation.")
            ]
        case .slco1b1:
            return [
                GeneticCatalogOption(gene: self, diplotype: "*1A/*1A", phenotype: "Normal Function", summary: "Commonly assigned normal SLCO1B1 transporter function."),
                GeneticCatalogOption(gene: self, diplotype: "*1A/*5", phenotype: "Decreased Function", summary: "One commonly decreased-function SLCO1B1 allele may reduce transporter activity."),
                GeneticCatalogOption(gene: self, diplotype: "*5/*5", phenotype: "Poor Function", summary: "Two commonly decreased-function SLCO1B1 alleles may produce substantially reduced activity.")
            ]
        case .cyp4f2, .ugt1a1, .abcg2, .vkorc1, .hlaA, .hlaB, .g6pd, .ifnl3, .ryr1, .cacna1s, .cftr:
            return []
        }
    }
}

// MARK: - Pharmacogenomic Catalog Option
/// A selectable, report-editing suggestion. It is intentionally not a dosing
/// recommendation and is kept separate from laboratory-reported fields.
struct GeneticCatalogOption: Identifiable, Hashable {
    let gene: PharmacogenomicGene
    let diplotype: String?
    let genotype: String?
    let phenotype: String?
    let summary: String

    init(
        gene: PharmacogenomicGene,
        diplotype: String? = nil,
        genotype: String? = nil,
        phenotype: String? = nil,
        summary: String
    ) {
        self.gene = gene
        self.diplotype = diplotype
        self.genotype = genotype
        self.phenotype = phenotype
        self.summary = summary
    }

    var id: String {
        [gene.rawValue, diplotype, genotype, phenotype].compactMap { $0 }.joined(separator: "|")
    }

    var displayName: String {
        let value = diplotype ?? genotype ?? "Catalog entry"
        if let phenotype, !phenotype.isEmpty {
            return "\(value) — \(phenotype)"
        }
        return value
    }

    var pharmGKBURL: URL? {
        PharmGKBLink.url(gene: gene.rawValue, result: diplotype ?? genotype)
    }

    func matches(_ item: GeneticTestItem) -> Bool {
        let expectedDiplotype = diplotype?.normalizedGeneticValue
        let expectedGenotype = genotype?.normalizedGeneticValue
        let actualDiplotype = item.diplotype?.normalizedGeneticValue
        let actualGenotype = item.genotype?.normalizedGeneticValue

        if let expectedDiplotype {
            return actualDiplotype == expectedDiplotype
        }
        if let expectedGenotype {
            return actualGenotype == expectedGenotype
        }
        return false
    }
}

private enum PharmGKBLink {
    static func url(gene: String, result: String?) -> URL? {
        let query = [gene, result].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: " ")

        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.pharmgkb.org/search")
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        return components?.url
    }
}

private extension String {
    var normalizedGeneticValue: String {
        lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
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
    /// Optional app-curated metadata. Laboratory-reported fields remain
    /// separate so a catalog suggestion is never mistaken for a lab result.
    var curatedPhenotype: String?
    var curatedSummary: String?
    var curatedSourceURL: String?

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
        sourceText: String? = nil,
        curatedPhenotype: String? = nil,
        curatedSummary: String? = nil,
        curatedSourceURL: String? = nil
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
        self.curatedPhenotype = curatedPhenotype
        self.curatedSummary = curatedSummary
        self.curatedSourceURL = curatedSourceURL
    }

    var catalogSuggestion: GeneticCatalogOption? {
        guard let gene = PharmacogenomicGene.match(in: gene) else { return nil }
        return gene.catalogOptions.first { $0.matches(self) }
    }

    var catalogSummary: String? {
        if let curatedSummary, !curatedSummary.isEmpty {
            return curatedSummary
        }
        return catalogSuggestion?.summary
    }

    var pharmGKBURL: URL? {
        if let curatedSourceURL, let url = URL(string: curatedSourceURL) {
            return url
        }
        return PharmGKBLink.url(
            gene: gene,
            result: diplotype ?? genotype ?? variant ?? rsID
        )
    }
}
