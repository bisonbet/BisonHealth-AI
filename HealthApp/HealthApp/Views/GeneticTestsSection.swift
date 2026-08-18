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
    @ObservedObject private var documentManager: DocumentManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentDocument: MedicalDocument
    @State private var activeReview: PendingGeneticTestReview?
    @State private var editingTest: GeneticTestResult?
    @State private var editingItem: GeneticTestItem?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(
        document: MedicalDocument,
        documentProcessor: DocumentProcessor = .shared,
        documentManager: DocumentManager = .shared
    ) {
        self.documentProcessor = documentProcessor
        self.documentManager = documentManager
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
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "No Structured Genetic Result",
                            systemImage: HealthDataType.geneticProfile.icon,
                            description: Text("The original report is still available in Documents, but no structured finding has been extracted yet.")
                        )

                        Button("Create Structured Result", systemImage: "plus") {
                            beginTestEditing()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Genetic Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Test Information", systemImage: "pencil") {
                        beginTestEditing()
                    }
                    Divider()
                    Button("Delete Genetic Test", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $activeReview) { review in
            GeneticTestImportReviewView(review: review) { acceptedIssueIDs, skippedIssueIDs in
                completeReview(
                    review,
                    acceptedIssueIDs: acceptedIssueIDs,
                    skippedIssueIDs: skippedIssueIDs
                )
            }
        }
        .sheet(item: $editingTest) { result in
            GeneticTestEditorView(result: result) { updatedResult in
                persist(updatedResult)
            }
        }
        .sheet(item: $editingItem) { item in
            GeneticTestItemEditorView(item: item) { updatedItem in
                persist(updatedItem: updatedItem)
            }
        }
        .alert("Delete Genetic Test?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Test and Source Report", role: .destructive) {
                deleteTest()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the structured test, its source document, and the imported file from this device.")
        }
        .alert("Could Not Save Genetic Test", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
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
            HStack {
                Text("Genetic Findings")
                    .font(.headline)
                Spacer()
                Button("Add Result", systemImage: "plus") {
                    editingItem = GeneticTestItem(
                        gene: PharmacogenomicGene.allCases.first?.rawValue ?? "",
                        category: PharmacogenomicGene.allCases.first?.category ?? .other,
                        isKnownPharmacogene: true
                    )
                }
                .font(.subheadline)
            }

            if geneticTest.results.isEmpty {
                Text("No structured findings are saved. Add a result or review the original report before using this test for medication questions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(geneticTest.results) { item in
                    GeneticTestFindingRow(
                        item: item,
                        onEdit: { editingItem = item },
                        onDelete: { deleteFinding(item) }
                    )
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

        persist(resolvedResult)
        activeReview = nil
    }

    private func beginTestEditing() {
        editingTest = geneticTest ?? GeneticTestResult(
            id: currentDocument.id,
            testDate: currentDocument.documentDate ?? currentDocument.importedAt,
            laboratoryName: currentDocument.providerName,
            testedGenes: []
        )
    }

    private func persist(updatedItem: GeneticTestItem) {
        guard var result = geneticTest else {
            errorMessage = "Create the structured genetic result before adding individual findings."
            return
        }
        result.upsertResult(updatedItem)
        persist(result)
    }

    private func persist(_ result: GeneticTestResult) {
        var updatedDocument = currentDocument
        if let encodedResult = try? AnyHealthData(result) {
            if let index = updatedDocument.extractedHealthData.firstIndex(where: { $0.type == .geneticProfile }) {
                updatedDocument.extractedHealthData[index] = encodedResult
            } else {
                updatedDocument.extractedHealthData.append(encodedResult)
            }
            updatedDocument.documentCategory = .geneticTest
            updatedDocument.lastEditedAt = Date()
            currentDocument = updatedDocument
        }

        let documentID = currentDocument.id
        Task { @MainActor in
            guard let savedDocument = await documentProcessor.saveGeneticTestResult(result, for: documentID) else {
                errorMessage = "The source document could not be updated. Your original report was not changed."
                return
            }
            currentDocument = savedDocument
        }
    }

    private func deleteFinding(_ item: GeneticTestItem) {
        guard var result = geneticTest else { return }
        guard result.removeResult(id: item.id) != nil else { return }
        persist(result)
    }

    private func deleteTest() {
        Task { @MainActor in
            guard await documentManager.deleteDocument(currentDocument) else {
                errorMessage = "The genetic test could not be deleted. Please try again."
                return
            }
            dismiss()
        }
    }
}

struct GeneticTestFindingRow: View {
    let item: GeneticTestItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

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

            HStack {
                Spacer()
                Button("Edit", systemImage: "pencil", action: onEdit)
                    .font(.caption)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .font(.caption)
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
            if let catalogSummary = item.catalogSummary, !catalogSummary.isEmpty {
                Text("Catalog summary: \(catalogSummary)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let pharmGKBURL = item.pharmGKBURL {
                Link(destination: pharmGKBURL) {
                    Label("View gene and result on PharmGKB", systemImage: "link")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .confirmationDialog("Delete \(item.gene) result?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Result", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The source report will remain available, but this structured finding will be removed from the test.")
        }
    }
}

// MARK: - Genetic Test Editor
struct GeneticTestEditorView: View {
    let onSave: (GeneticTestResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: GeneticTestResult
    @State private var testedGenesText: String

    init(result: GeneticTestResult, onSave: @escaping (GeneticTestResult) -> Void) {
        self.onSave = onSave
        self._draft = State(initialValue: result)
        self._testedGenesText = State(initialValue: result.testedGenes.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Information") {
                    DatePicker("Test Date", selection: $draft.testDate, displayedComponents: .date)
                    TextField("Test name", text: optionalStringBinding(\.testName))
                    TextField("Panel name", text: optionalStringBinding(\.panelName))
                    TextField("Laboratory", text: optionalStringBinding(\.laboratoryName))
                    TextField("Ordering physician", text: optionalStringBinding(\.orderingPhysician))
                    Picker("Specimen", selection: Binding(
                        get: { draft.specimen ?? .unknown },
                        set: { draft.specimen = $0 == .unknown ? nil : $0 }
                    )) {
                        ForEach(GeneticSpecimen.allCases, id: \.self) { specimen in
                            Text(specimen.displayName).tag(specimen)
                        }
                    }
                }

                Section("Genes Tested") {
                    TextField("CYP2D6, CYP2C19", text: $testedGenesText, axis: .vertical)
                        .lineLimit(2...5)
                    Text("Separate gene symbols with commas or new lines. Known symbols are normalized when saved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Reported Limitations") {
                    TextEditor(text: optionalStringBinding(\.limitations))
                        .frame(minHeight: 90)
                }
            }
            .navigationTitle("Edit Genetic Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<GeneticTestResult, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : value
            }
        )
    }

    private func save() {
        draft.testedGenes = testedGenesText
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { PharmacogenomicGene.match(in: $0)?.rawValue ?? $0.uppercased() }
            .reduce(into: [String]()) { values, gene in
                guard !values.contains(where: { $0.caseInsensitiveCompare(gene) == .orderedSame }) else { return }
                values.append(gene)
            }
        draft.updatedAt = Date()
        onSave(draft)
        dismiss()
    }
}

// MARK: - Genetic Finding Editor
struct GeneticTestItemEditorView: View {
    private static let otherGeneKey = "__other_gene__"
    private static let customOptionKey = "__custom_option__"

    let onSave: (GeneticTestItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: GeneticTestItem
    @State private var selectedGene: String
    @State private var customGene: String
    @State private var selectedCatalogOptionID: String
    @State private var validationMessage: String?

    init(item: GeneticTestItem, onSave: @escaping (GeneticTestItem) -> Void) {
        self.onSave = onSave
        self._draft = State(initialValue: item)

        let matchedGene = PharmacogenomicGene.match(in: item.gene)
        let geneSelection = matchedGene?.rawValue ?? Self.otherGeneKey
        self._selectedGene = State(initialValue: geneSelection)
        self._customGene = State(initialValue: matchedGene == nil ? item.gene : "")
        let matchingOption = matchedGene?.catalogOptions.first(where: { $0.matches(item) })
        self._selectedCatalogOptionID = State(initialValue: matchingOption?.id ?? Self.customOptionKey)
    }

    private var selectedCatalogGene: PharmacogenomicGene? {
        PharmacogenomicGene(rawValue: selectedGene)
    }

    private var catalogOptions: [GeneticCatalogOption] {
        selectedCatalogGene?.catalogOptions ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gene") {
                    Picker("Gene", selection: $selectedGene) {
                        ForEach(PharmacogenomicGene.allCases, id: \.rawValue) { gene in
                            Text(gene.rawValue).tag(gene.rawValue)
                        }
                        Text("Other").tag(Self.otherGeneKey)
                    }

                    if selectedGene == Self.otherGeneKey {
                        TextField("Gene symbol", text: $customGene)
                            .textInputAutocapitalization(.characters)
                    }
                }

                if !catalogOptions.isEmpty {
                    Section("Pre-configured Suggestion") {
                        Picker("Genotype / phenotype", selection: $selectedCatalogOptionID) {
                            Text("Custom / keep current values")
                                .tag(Self.customOptionKey)
                            ForEach(catalogOptions) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }

                        if let selectedOption = catalogOptions.first(where: { $0.id == selectedCatalogOptionID }) {
                            Text(selectedOption.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("This is a conservative catalog suggestion, not a laboratory interpretation or dosing recommendation.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Structured Result") {
                    Picker("Category", selection: $draft.category) {
                        ForEach(GeneticMarkerCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    TextField("Diplotype / star alleles", text: binding(for: \.diplotype))
                    TextField("Genotype", text: binding(for: \.genotype))
                    TextField("Phenotype / metabolic status", text: binding(for: \.phenotype))
                    TextField("Variant", text: binding(for: \.variant))
                    TextField("rsID", text: binding(for: \.rsID))
                    TextField("Reported result", text: binding(for: \.reportedResult))
                    TextField("Evidence level", text: binding(for: \.evidenceLevel))
                }

                Section("Reported Interpretation") {
                    TextEditor(text: binding(for: \.reportedInterpretation))
                        .frame(minHeight: 90)
                    TextEditor(text: medicationImplicationsBinding)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if draft.reportedMedicationImplications.isEmpty {
                                Text("Medication implications, one per line")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let sourceText = draft.sourceText, !sourceText.isEmpty {
                    Section("Imported Source Text") {
                        Text(sourceText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Genetic Result")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedGene) { _, value in
                applyGeneSelection(value)
            }
            .onChange(of: customGene) { _, value in
                guard selectedGene == Self.otherGeneKey else { return }
                draft.gene = value
                draft.isKnownPharmacogene = false
            }
            .onChange(of: selectedCatalogOptionID) { _, value in
                applyCatalogSelection(value)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for keyPath: WritableKeyPath<GeneticTestItem, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : value
            }
        )
    }

    private var medicationImplicationsBinding: Binding<String> {
        Binding(
            get: { draft.reportedMedicationImplications.joined(separator: "\n") },
            set: { value in
                draft.reportedMedicationImplications = value
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func applyGeneSelection(_ value: String) {
        guard value != Self.otherGeneKey else {
            draft.gene = customGene
            draft.isKnownPharmacogene = false
            selectedCatalogOptionID = Self.customOptionKey
            draft.curatedPhenotype = nil
            draft.curatedSummary = nil
            draft.curatedSourceURL = nil
            return
        }

        guard let gene = PharmacogenomicGene(rawValue: value) else { return }
        draft.gene = gene.rawValue
        draft.category = gene.category
        draft.isKnownPharmacogene = true
        customGene = ""
        selectedCatalogOptionID = Self.customOptionKey
        draft.curatedPhenotype = nil
        draft.curatedSummary = nil
        draft.curatedSourceURL = nil
    }

    private func applyCatalogSelection(_ value: String) {
        guard let option = catalogOptions.first(where: { $0.id == value }) else {
            if value == Self.customOptionKey {
                draft.curatedPhenotype = nil
                draft.curatedSummary = nil
                draft.curatedSourceURL = nil
            }
            return
        }

        draft.gene = option.gene.rawValue
        draft.category = option.gene.category
        draft.isKnownPharmacogene = true
        draft.diplotype = option.diplotype
        draft.genotype = option.genotype
        draft.phenotype = option.phenotype
        draft.curatedPhenotype = option.phenotype
        draft.curatedSummary = option.summary
        draft.curatedSourceURL = option.pharmGKBURL?.absoluteString
    }

    private func save() {
        let geneValue = (selectedGene == Self.otherGeneKey ? customGene : selectedGene)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !geneValue.isEmpty else {
            validationMessage = "Enter a gene symbol or choose a known pharmacogenomic gene."
            return
        }

        draft.gene = PharmacogenomicGene.match(in: geneValue)?.rawValue ?? geneValue.uppercased()
        if let knownGene = PharmacogenomicGene.match(in: draft.gene) {
            draft.isKnownPharmacogene = true
            if draft.category == .other {
                draft.category = knownGene.category
            }
        } else {
            draft.isKnownPharmacogene = false
        }

        if let option = catalogOptions.first(where: { $0.id == selectedCatalogOptionID }),
           option.matches(draft),
           draft.phenotype == option.phenotype {
            draft.curatedPhenotype = option.phenotype
            draft.curatedSummary = option.summary
            draft.curatedSourceURL = option.pharmGKBURL?.absoluteString
        } else {
            draft.curatedPhenotype = nil
            draft.curatedSummary = nil
            draft.curatedSourceURL = nil
        }

        onSave(draft)
        dismiss()
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
