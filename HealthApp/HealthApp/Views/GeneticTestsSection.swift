import SwiftUI

// MARK: - Genetic Tests Section
struct GeneticTestsSection: View {
    @Binding var geneticTests: [MedicalDocument]

    var body: some View {
        Section {
            if geneticTests.isEmpty {
                EmptyGeneticTestsView()
            } else {
                ForEach(geneticTests.prefix(2)) { document in
                    NavigationLink {
                        GeneticTestRecordView(document: document)
                    } label: {
                        GeneticTestRowView(document: document)
                    }
                }

                if geneticTests.count > 2 {
                    NavigationLink {
                        GeneticTestsListView(geneticTests: $geneticTests)
                    } label: {
                        HStack {
                            Text("More")
                                .font(.subheadline)
                                .foregroundColor(BisonTheme.gold)
                            Spacer()
                            Text("\(geneticTests.count) total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Label("Genetic Tests", systemImage: HealthDataType.geneticProfile.icon)
                Spacer()
            }
        }
    }
}

// MARK: - Genetic Test Row
struct GeneticTestRowView: View {
    let document: MedicalDocument

    private var geneticTest: GeneticTestResult? {
        document.geneticTestResult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    if let date = geneticTest?.testDate ?? document.documentDate {
                        Text(DateFormatter.mediumDate.string(from: date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Imported \(DateFormatter.mediumDate.string(from: document.importedAt))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let laboratory = geneticTest?.laboratoryName ?? document.providerName {
                        Text(laboratory)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if geneticTest?.needsReview == true {
                        GeneticTestReviewBadge()
                    } else {
                        ProcessingStatusBadge(status: document.processingStatus)
                    }

                    if let geneticTest {
                        let geneCount = max(geneticTest.testedGenes.count, geneticTest.results.count)
                        Text("\(geneCount) gene\(geneCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let geneticTest, !geneticTest.results.isEmpty {
                let summary = geneticTest.results.prefix(2).map { item in
                    if let phenotype = item.phenotype, !phenotype.isEmpty {
                        return "\(item.gene): \(phenotype)"
                    }
                    if let reportedResult = item.reportedResult, !reportedResult.isEmpty {
                        return "\(item.gene): \(reportedResult)"
                    }
                    return item.gene
                }.joined(separator: "  •  ")

                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if geneticTest?.needsReview == true {
                Text("Review the original report to confirm the extracted findings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GeneticTestReviewBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("Needs Review")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.2))
        .foregroundColor(.orange)
        .cornerRadius(4)
    }
}

struct EmptyGeneticTestsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: HealthDataType.geneticProfile.icon)
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No genetic tests")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Import a genetic or pharmacogenomic report from Documents")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Genetic Test List
struct GeneticTestsListView: View {
    @Binding var geneticTests: [MedicalDocument]

    var body: some View {
        List {
            ForEach(geneticTests) { document in
                NavigationLink {
                    GeneticTestRecordView(document: document)
                } label: {
                    GeneticTestRowView(document: document)
                }
            }
        }
        .navigationTitle("Genetic Tests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Genetic Test Record
struct GeneticTestRecordView: View {
    @ObservedObject private var documentProcessor: DocumentProcessor
    @State private var currentDocument: MedicalDocument
    @State private var activeReview: PendingGeneticTestReview?

    init(document: MedicalDocument, documentProcessor: DocumentProcessor = .shared) {
        self.documentProcessor = documentProcessor
        self._currentDocument = State(initialValue: document)
    }

    private var geneticTest: GeneticTestResult? {
        currentDocument.geneticTestResult
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recordHeader

                if let geneticTest {
                    if geneticTest.needsReview {
                        reviewBanner(for: geneticTest)
                    }

                    testInformationSection(geneticTest)
                    testedGenesSection(geneticTest)
                    findingsSection(geneticTest)

                    if let limitations = geneticTest.limitations, !limitations.isEmpty {
                        labeledTextSection(title: "Reported Limitations", text: limitations)
                    }
                } else {
                    ContentUnavailableView(
                        "No Structured Genetic Result",
                        systemImage: HealthDataType.geneticProfile.icon,
                        description: Text("The original report is still available in Documents, but no structured finding has been extracted yet.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Genetic Test")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeReview) { review in
            GeneticTestImportReviewView(review: review) { acceptedIssueIDs, skippedIssueIDs in
                completeReview(
                    review,
                    acceptedIssueIDs: acceptedIssueIDs,
                    skippedIssueIDs: skippedIssueIDs
                )
            }
        }
    }

    private var recordHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: HealthDataType.geneticProfile.icon)
                    .font(.system(size: 28))
                    .foregroundColor(BisonTheme.gold)

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentDocument.fileName)
                        .font(.headline)
                        .lineLimit(2)

                    Text(currentDocument.documentCategory.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack {
                if geneticTest?.needsReview == true {
                    GeneticTestReviewBadge()
                } else {
                    ProcessingStatusBadge(status: currentDocument.processingStatus)
                }

                Spacer()

                Text("Source report retained")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func reviewBanner(for geneticTest: GeneticTestResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review before relying on this record", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)

            Text("The importer preserved the laboratory wording, but some findings need confirmation against the original report. Accept a finding to keep it structured, or skip it to leave it out of the genetic profile.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Review Findings") {
                activeReview = PendingGeneticTestReview(
                    documentId: currentDocument.id,
                    documentName: currentDocument.fileName,
                    geneticTestResult: geneticTest
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func testInformationSection(_ geneticTest: GeneticTestResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test Information")
                .font(.headline)

            if let testName = geneticTest.testName, !testName.isEmpty {
                DocumentInfoRow(label: "Test", value: testName)
            }
            if let panelName = geneticTest.panelName, !panelName.isEmpty {
                DocumentInfoRow(label: "Panel", value: panelName)
            }
            DocumentInfoRow(label: "Test Date", value: geneticTest.testDate.formatted(date: .abbreviated, time: .omitted))
            if let laboratoryName = geneticTest.laboratoryName, !laboratoryName.isEmpty {
                DocumentInfoRow(label: "Laboratory", value: laboratoryName)
            }
            if let specimen = geneticTest.specimen {
                DocumentInfoRow(label: "Specimen", value: specimen.displayName)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func testedGenesSection(_ geneticTest: GeneticTestResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Genes Tested")
                .font(.headline)

            if geneticTest.testedGenes.isEmpty {
                Text("No gene list was recognized.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text(geneticTest.testedGenes.joined(separator: ", "))
                    .font(.body)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func findingsSection(_ geneticTest: GeneticTestResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reported Findings")
                .font(.headline)

            if geneticTest.results.isEmpty {
                Text("No structured findings were recognized. Review the original report before using this test for medication questions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(geneticTest.results) { item in
                    GeneticTestFindingRow(item: item)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func labeledTextSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func completeReview(
        _ review: PendingGeneticTestReview,
        acceptedIssueIDs: Set<UUID>,
        skippedIssueIDs: Set<UUID>
    ) {
        let resolvedResult = review.geneticTestResult.applyingReview(
            acceptedIssueIDs: acceptedIssueIDs,
            skippedIssueIDs: skippedIssueIDs
        )

        var updatedDocument = currentDocument
        if let encodedResult = try? AnyHealthData(resolvedResult),
           let index = updatedDocument.extractedHealthData.firstIndex(where: { $0.type == .geneticProfile }) {
            updatedDocument.extractedHealthData[index] = encodedResult
        }
        currentDocument = updatedDocument

        Task {
            _ = await documentProcessor.saveGeneticTestResult(
                resolvedResult,
                for: review.documentId
            )
            activeReview = nil
        }
    }
}

struct GeneticTestFindingRow: View {
    let item: GeneticTestItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.gene)
                    .font(.headline)
                Spacer()
                Text(item.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let genotype = item.genotype, !genotype.isEmpty {
                LabeledContent("Genotype", value: genotype)
            }
            if let diplotype = item.diplotype, !diplotype.isEmpty {
                LabeledContent("Diplotype", value: diplotype)
            }
            if let phenotype = item.phenotype, !phenotype.isEmpty {
                LabeledContent("Phenotype", value: phenotype)
            }
            if let variant = item.variant, !variant.isEmpty {
                LabeledContent("Variant", value: variant)
            }
            if let rsID = item.rsID, !rsID.isEmpty {
                LabeledContent("rsID", value: rsID)
            }
            if let reportedResult = item.reportedResult, !reportedResult.isEmpty {
                LabeledContent("Reported result", value: reportedResult)
            }
            if let interpretation = item.reportedInterpretation, !interpretation.isEmpty {
                Text("Reported interpretation: \(interpretation)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if !item.reportedMedicationImplications.isEmpty {
                Text("Reported medication implications: \(item.reportedMedicationImplications.joined(separator: "; "))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Genetic Test Import Review
struct GeneticTestImportReviewView: View {
    let review: PendingGeneticTestReview
    let onComplete: (Set<UUID>, Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var skippedIssueIDs: Set<UUID> = []

    private var allIssueIDs: Set<UUID> {
        Set(review.geneticTestResult.reviewIssues.map(\.id))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The importer found \(review.geneticTestResult.reviewIssues.count) item\(review.geneticTestResult.reviewIssues.count == 1 ? "" : "s") that should be checked against the original report. Findings are kept report-grounded; no medication advice is inferred here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text(review.documentName)
                }

                Section("Findings to review") {
                    ForEach(review.geneticTestResult.reviewIssues) { issue in
                        Button {
                            toggle(issue.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: skippedIssueIDs.contains(issue.id) ? "xmark.circle" : "checkmark.circle.fill")
                                    .foregroundColor(skippedIssueIDs.contains(issue.id) ? .secondary : .green)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(issue.reason)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if let sourceText = issue.sourceText, !sourceText.isEmpty {
                                        Text(sourceText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(4)
                                    }
                                    Text(skippedIssueIDs.contains(issue.id) ? "Skip this finding" : "Keep this finding")
                                        .font(.caption)
                                        .foregroundColor(skippedIssueIDs.contains(issue.id) ? .secondary : .green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Review Genetic Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save Review") {
                        let acceptedIssueIDs = allIssueIDs.subtracting(skippedIssueIDs)
                        onComplete(acceptedIssueIDs, skippedIssueIDs)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggle(_ issueID: UUID) {
        if skippedIssueIDs.contains(issueID) {
            skippedIssueIDs.remove(issueID)
        } else {
            skippedIssueIDs.insert(issueID)
        }
    }
}

private extension MedicalDocument {
    var geneticTestResult: GeneticTestResult? {
        extractedHealthData.compactMap { try? $0.decode(as: GeneticTestResult.self) }.first
    }
}
