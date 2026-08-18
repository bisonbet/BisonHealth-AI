import Foundation

// MARK: - Genetic Test Parser
/// Deterministically extracts explicit genetic findings from a report.
///
/// Genetic reports vary substantially by laboratory. This parser recognizes
/// common pharmacogenomic gene symbols and preserves the original document
/// text for anything it cannot safely structure. It never derives a phenotype
/// or medication recommendation from a gene symbol alone.
final class GeneticTestParser {

    private struct GeneBlock {
        let gene: String
        let catalogGene: PharmacogenomicGene?
        var lines: [String]
    }

    // MARK: - Public API

    static func looksLikeGeneticTest(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let strongMarkers = [
            "pharmacogenomic",
            "pharmacogenetic",
            "genetic test",
            "genetic testing",
            "genotyping",
            "diplotype",
            "metabolizer",
            "genes tested",
            "genes analyzed",
            "gene panel"
        ]

        if strongMarkers.contains(where: { lowercased.contains($0) }) {
            return true
        }

        return PharmacogenomicGene.allCases.contains { gene in
            lowercased.contains(gene.rawValue.lowercased())
        }
    }

    func parse(plainText: String, document: MedicalDocument) -> GeneticTestResult? {
        let trimmedText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let lines = trimmedText.components(separatedBy: .newlines)
        let blocks = makeGeneBlocks(from: lines)
        let parsedItems = blocks.compactMap(parseItem(from:))
        let testedGenes = parseTestedGenes(from: trimmedText, blocks: blocks)
        let geneticReportDetected = document.documentCategory == .geneticTest
            || Self.looksLikeGeneticTest(trimmedText)

        // Keep a genetic document in Records even when OCR did not produce a
        // structured gene line. The original extracted text is still useful,
        // and the resulting review issue gives the user a clear next step.
        guard !parsedItems.isEmpty || !testedGenes.isEmpty || geneticReportDetected else {
            return nil
        }

        let reportedDate = extractDate(from: trimmedText)
        let testDate = document.documentDate ?? reportedDate ?? document.importedAt
        let reviewIssues = makeReviewIssues(for: parsedItems, testedGenes: testedGenes)
        var metadata: [String: String] = [
            "source_document_id": document.id.uuidString,
            "parser": "deterministic_genetic_test_parser",
            "reported_findings_only": "true",
            "standard_gene_catalog": "common CPIC and FDA-referenced pharmacogenomic markers"
        ]
        if !reviewIssues.isEmpty {
            metadata["pending_review"] = "true"
            metadata["review_issue_count"] = String(reviewIssues.count)
        }
        if document.documentDate != nil {
            metadata["test_date_source"] = "document_metadata"
        } else if reportedDate != nil {
            metadata["test_date_source"] = "report_text"
        } else {
            metadata["test_date_source"] = "imported_at_fallback"
        }

        return GeneticTestResult(
            id: document.id,
            testDate: testDate,
            laboratoryName: extractLabeledValue(from: trimmedText, labels: ["laboratory", "lab", "laboratory name"]) ?? document.providerName,
            orderingPhysician: extractLabeledValue(from: trimmedText, labels: ["ordering physician", "ordering provider", "physician", "provider"]),
            testName: extractLabeledValue(from: trimmedText, labels: ["test name", "assay", "test performed"]),
            panelName: extractLabeledValue(from: trimmedText, labels: ["panel", "panel name", "gene panel"]),
            specimen: parseSpecimen(from: trimmedText),
            testedGenes: testedGenes,
            results: parsedItems,
            reviewIssues: reviewIssues,
            limitations: extractLabeledValue(from: trimmedText, labels: ["limitations", "test limitations", "limitations of the test"]),
            metadata: metadata
        )
    }

    private func makeReviewIssues(
        for items: [GeneticTestItem],
        testedGenes: [String]
    ) -> [GeneticTestReviewIssue] {
        var issues: [GeneticTestReviewIssue] = []

        for item in items {
            let reportedValues = [
                item.genotype,
                item.diplotype,
                item.phenotype,
                item.variant,
                item.rsID,
                item.reportedResult,
                item.reportedInterpretation
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

            if !item.isKnownPharmacogene {
                issues.append(GeneticTestReviewIssue(
                    resultID: item.id,
                    gene: item.gene,
                    reason: "This gene is outside the app's standard pharmacogenomic catalog. Verify the gene, result type, and whether the report contains medication guidance before using it in a medicine discussion.",
                    sourceText: item.sourceText
                ))
            }

            if reportedValues.isEmpty {
                issues.append(GeneticTestReviewIssue(
                    resultID: item.id,
                    gene: item.gene,
                    reason: "The importer found the gene but could not recognize a genotype, diplotype, phenotype, variant, or reported result.",
                    sourceText: item.sourceText
                ))
            }

            let combinedText = reportedValues.joined(separator: " ").lowercased()
            let uncertainMarkers = [
                "uncertain",
                "indeterminate",
                "inconclusive",
                "ambiguous",
                "no call",
                "unable to determine",
                "insufficient",
                "pending",
                "not reportable"
            ]
            if uncertainMarkers.contains(where: { combinedText.contains($0) }) {
                issues.append(GeneticTestReviewIssue(
                    resultID: item.id,
                    gene: item.gene,
                    reason: "The report uses an uncertain or incomplete status. Check the original laboratory wording before relying on this finding.",
                    sourceText: item.sourceText
                ))
            }
        }

        let parsedGeneNames = Set(items.map { $0.gene.lowercased() })
        for testedGene in testedGenes where !parsedGeneNames.contains(testedGene.lowercased()) {
            issues.append(GeneticTestReviewIssue(
                gene: testedGene,
                reason: "The report lists this gene as tested, but no corresponding result was recognized.",
                sourceText: nil
            ))
        }

        if items.isEmpty && testedGenes.isEmpty {
            issues.append(GeneticTestReviewIssue(
                reason: "The document looks like a genetic test, but no gene or result was recognized. Review the original report and keep it as document context until the finding can be confirmed.",
                sourceText: nil
            ))
        }

        return issues
    }

    // MARK: - Gene Blocks

    private func makeGeneBlocks(from lines: [String]) -> [GeneBlock] {
        var blocks: [GeneBlock] = []
        var current: GeneBlock?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if let geneStart = matchGeneStart(in: trimmedLine) {
                if let current {
                    blocks.append(current)
                }
                current = GeneBlock(
                    gene: geneStart.gene,
                    catalogGene: geneStart.catalogGene,
                    lines: [trimmedLine]
                )
            } else if current != nil {
                current?.lines.append(trimmedLine)
            }
        }

        if let current {
            blocks.append(current)
        }

        return blocks
    }

    private func matchGeneStart(in line: String) -> (gene: String, catalogGene: PharmacogenomicGene?)? {
        if let catalogGene = matchCatalogGeneStart(in: line) {
            return (catalogGene.rawValue, catalogGene)
        }

        // Capture explicitly tabular gene symbols such as "BRCA1\tPositive"
        // without treating all-caps section headings as genes.
        let pattern = "^\\s*([A-Z][A-Z0-9-]{1,9})(?=\\s*(?::|\\t|\\||-|positive\\b|negative\\b|normal\\b|abnormal\\b|pathogenic\\b|carrier\\b))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let geneRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let gene = String(line[geneRange]).uppercased()
        let excludedHeadings: Set<String> = [
            "RESULT", "RESULTS", "REPORT", "SUMMARY", "TEST", "PANEL",
            "GENE", "GENES", "METHOD", "SPECIMEN", "COMMENTS", "NOTES",
            "STATUS", "FINDINGS", "INTERPRETATION", "LIMITATIONS", "LABORATORY", "LAB",
            "ASSAY", "ORDERING", "PHYSICIAN", "PROVIDER", "SAMPLE", "DATE", "GENETIC",
            "GENOMIC", "PHARMACOGENOMIC", "PHARMACOGENETIC", "PHENOTYPE", "DIPLOTYPE",
            "GENOTYPE", "VARIANT", "VARIANTS", "ALLELE", "ALLELES", "EVIDENCE", "CALL",
            "RESULTS", "FINDING", "MEDICATION", "DRUG", "THERAPEUTIC"
        ]
        guard !excludedHeadings.contains(gene) else { return nil }
        return (gene, nil)
    }

    private func matchCatalogGeneStart(in line: String) -> PharmacogenomicGene? {
        for gene in PharmacogenomicGene.allCases {
            let names = [gene.rawValue] + gene.aliases
            for name in names {
                let escapedName = NSRegularExpression.escapedPattern(for: name)
                let pattern = "^\\s*\(escapedName)(?=\\s|$|:|\\t|\\|)"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    continue
                }

                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    return gene
                }
            }
        }

        return nil
    }

    private func parseTestedGenes(from text: String, blocks: [GeneBlock]) -> [String] {
        var genes: [String] = []

        if let explicitGenes = extractLabeledValue(
            from: text,
            labels: ["genes tested", "genes analyzed", "genes included", "panel genes"]
        ) {
            let parts = explicitGenes.components(separatedBy: CharacterSet(charactersIn: ",;|\n"))
            for part in parts {
                let cleaned = part
                    .replacingOccurrences(of: "(full gene)", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                appendUnique(canonicalGeneName(cleaned), to: &genes)
            }
        }

        for block in blocks {
            appendUnique(block.gene, to: &genes)
        }

        return genes
    }

    private func canonicalGeneName(_ value: String) -> String {
        if let catalogGene = PharmacogenomicGene.match(in: value) {
            return catalogGene.rawValue
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.uppercased()
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        guard !value.isEmpty, !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            return
        }
        values.append(value)
    }

    // MARK: - Item Parsing

    private func parseItem(from block: GeneBlock) -> GeneticTestItem? {
        let blockText = block.lines.joined(separator: "\n")
        let firstLine = block.lines.first ?? block.gene
        let inlineText = removingGene(block.gene, from: firstLine)

        var genotype = extractLabeledValue(from: blockText, labels: ["genotype", "genotypic result", "allele call"])
        var diplotype = extractLabeledValue(from: blockText, labels: ["diplotype", "star allele", "star alleles", "allele pair"])
        var phenotype = extractLabeledValue(from: blockText, labels: ["phenotype", "metabolizer status", "metabolizer phenotype"])
        var variant = extractLabeledValue(from: blockText, labels: ["variant", "variants", "snp", "mutation"])
        let rsID = extractFirstMatch(in: blockText, pattern: "\\brs[0-9]+\\b")
        var reportedResult = extractLabeledValue(from: blockText, labels: ["result", "status", "finding", "call"])
        var reportedInterpretation = extractLabeledValue(
            from: blockText,
            labels: ["interpretation", "clinical significance", "comment", "comments", "note", "notes"]
        )
        let evidenceLevel = extractLabeledValue(from: blockText, labels: ["evidence", "evidence level", "level of evidence"])
        var medicationImplications = extractAllLabeledValues(
            from: blockText,
            labels: ["medication implication", "medication implications", "drug implication", "drug implications", "therapeutic implication"]
        )

        if diplotype == nil {
            diplotype = extractFirstMatch(in: inlineText, pattern: "\\*[0-9]+[A-Z]?\\s*/\\s*\\*[0-9]+[A-Z]?")
        }
        if phenotype == nil {
            phenotype = extractFirstMatch(
                in: inlineText,
                pattern: "(?i)\\b(?:ultra[- ]rapid|rapid|normal|intermediate|poor|indeterminate|no[- ]function|decreased[- ]function|increased[- ]function)\\s+metabolizer\\b"
            )
        }
        if genotype == nil {
            genotype = extractFirstMatch(in: inlineText, pattern: "\\b[ACGT]{1,2}\\s*(?:/|\\|)\\s*[ACGT]{1,2}\\b")
        }
        if variant == nil {
            variant = extractFirstMatch(in: inlineText, pattern: "\\b(?:c|g|p)\\.[^\\s;,]+")
        }

        if reportedResult == nil {
            let cleanedInlineText = inlineText
                .replacingOccurrences(of: "\\*\\d+[A-Z]?\\s*/\\s*\\*\\d+[A-Z]?", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !cleanedInlineText.isEmpty,
               cleanedInlineText.caseInsensitiveCompare(block.gene) != .orderedSame {
                reportedResult = cleanedInlineText
            }
        }

        if medicationImplications.isEmpty,
           let reportedInterpretation,
           reportedInterpretation.localizedCaseInsensitiveContains("medication") {
            medicationImplications = [reportedInterpretation]
        }

        if reportedInterpretation == nil, !medicationImplications.isEmpty {
            reportedInterpretation = medicationImplications.joined(separator: "; ")
        }

        let catalogGene = block.catalogGene
        let sourceText = blockText.count > 2_000 ? String(blockText.prefix(2_000)) + "..." : blockText

        return GeneticTestItem(
            gene: block.gene,
            category: catalogGene?.category ?? .other,
            isKnownPharmacogene: catalogGene != nil,
            genotype: cleaned(genotype),
            diplotype: cleaned(diplotype),
            phenotype: cleaned(phenotype),
            variant: cleaned(variant),
            rsID: rsID,
            reportedResult: cleaned(reportedResult),
            reportedInterpretation: cleaned(reportedInterpretation),
            reportedMedicationImplications: medicationImplications.compactMap(cleaned),
            evidenceLevel: cleaned(evidenceLevel),
            sourceText: sourceText
        )
    }

    private func removingGene(_ gene: String, from line: String) -> String {
        let escapedGene = NSRegularExpression.escapedPattern(for: gene)
        guard let regex = try? NSRegularExpression(pattern: escapedGene, options: .caseInsensitive) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: " ")
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    // MARK: - Metadata Parsing

    private func parseSpecimen(from text: String) -> GeneticSpecimen? {
        guard let value = extractLabeledValue(from: text, labels: ["specimen", "sample type", "sample"]) else {
            return nil
        }

        let lowercased = value.lowercased()
        if lowercased.contains("buccal") || lowercased.contains("cheek") {
            return .buccalSwab
        }
        if lowercased.contains("saliva") || lowercased.contains("spit") {
            return .saliva
        }
        if lowercased.contains("blood") {
            return .blood
        }
        if lowercased.contains("tissue") {
            return .tissue
        }
        return .other
    }

    private func extractDate(from text: String) -> Date? {
        let patterns = [
            "\\b\\d{4}-\\d{2}-\\d{2}\\b",
            "\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b",
            "\\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},?\\s+\\d{4}\\b"
        ]

        for pattern in patterns {
            guard let dateString = extractFirstMatch(in: text, pattern: pattern) else { continue }
            for format in ["yyyy-MM-dd", "M/d/yyyy", "MM/dd/yyyy", "MMMM d, yyyy", "MMMM dd, yyyy"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }

        return nil
    }

    // MARK: - Regex Helpers

    private func extractLabeledValue(from text: String, labels: [String]) -> String? {
        extractAllLabeledValues(from: text, labels: labels).first
    }

    private func extractAllLabeledValues(from text: String, labels: [String]) -> [String] {
        let escapedLabels = labels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "^\\s*(?:\(escapedLabels))\\s*(?::|-|\\t)\\s*(.+?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    private func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
