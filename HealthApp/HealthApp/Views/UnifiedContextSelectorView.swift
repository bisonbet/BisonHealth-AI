import SwiftUI

// MARK: - Unified Context Selector View
struct UnifiedContextSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatManager: AIChatManager
    @StateObject private var viewModel: UnifiedContextSelectorViewModel

    init(chatManager: AIChatManager) {
        self.chatManager = chatManager
        self._viewModel = StateObject(wrappedValue: UnifiedContextSelectorViewModel(chatManager: chatManager))
    }

    var body: some View {
        NavigationStack {
            List {
                // Context Summary Section
                contextSummarySection

                // Personal Information Section
                personalInfoSection

                // Blood Tests Section
                bloodTestsSection

                // Imaging Reports Section
                imagingReportsSection

                // Health Checkups Section
                healthCheckupsSection
            }
            .navigationTitle("AI Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Task {
                            await viewModel.saveChanges()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                await viewModel.loadData()
            }
        }
    }

    // MARK: - Context Summary Section
    private var contextSummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)

                    Text("Select health data to share with AI")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Stats
                HStack(spacing: 20) {
                    StatBox(
                        value: "\(viewModel.enabledCategoriesCount)",
                        label: "Categories",
                        color: .blue
                    )

                    StatBox(
                        value: "\(viewModel.includedDocumentsCount)",
                        label: "Documents",
                        color: .green
                    )

                    StatBox(
                        value: viewModel.estimatedContextSize,
                        label: "Context",
                        color: sizeColor
                    )
                }

                // Size breakdown (when there's content)
                if viewModel.estimatedTokens > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Context breakdown:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(viewModel.estimatedTokens) tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if viewModel.personalInfoEnabled {
                            HStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                Text("Personal info: ~200 tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if viewModel.includedDocumentsCount > 0 {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                                Text("\(viewModel.includedDocumentsCount) document\(viewModel.includedDocumentsCount == 1 ? "" : "s"): ~\(viewModel.estimatedTokens - (viewModel.personalInfoEnabled ? 200 : 0)) tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var sizeColor: Color {
        if viewModel.estimatedTokens < 4000 { return .green }
        if viewModel.estimatedTokens < 8000 { return .orange }
        return .red
    }

    // MARK: - Personal Information Section
    private var personalInfoSection: some View {
        Section {
            Toggle(isOn: $viewModel.personalInfoEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: HealthDataType.personalInfo.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HealthDataType.personalInfo.displayName)
                            .font(.headline)

                        Text("Demographics, allergies, medications, medical history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Health Data")
        }
    }

    // MARK: - Blood Tests Section
    private var bloodTestsSection: some View {
        Section {
            // Category toggle
            Toggle(isOn: Binding(
                get: { viewModel.bloodTestsEnabled },
                set: { newValue in
                    viewModel.bloodTestsEnabled = newValue
                    // Auto-select/deselect all documents in this category
                    viewModel.toggleAllDocuments(in: .bloodTest, enabled: newValue)
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: HealthDataType.bloodTest.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HealthDataType.bloodTest.displayName)
                            .font(.headline)

                        Text("\(viewModel.bloodTestDocuments.count) documents available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Documents list (when enabled)
            if viewModel.bloodTestsEnabled && !viewModel.bloodTestDocuments.isEmpty {
                ForEach(viewModel.bloodTestDocuments) { document in
                    DocumentSelectionRow(
                        document: document,
                        isSelected: viewModel.isDocumentSelected(document),
                        priority: viewModel.getDocumentPriority(document),
                        onToggle: {
                            viewModel.toggleDocument(document)
                        },
                        onPriorityChange: { priority in
                            viewModel.updateDocumentPriority(document, priority: priority)
                        }
                    )
                    .disabled(!viewModel.bloodTestsEnabled)
                }
            }
        }
    }

    // MARK: - Imaging Reports Section
    private var imagingReportsSection: some View {
        Section {
            // Category toggle
            Toggle(isOn: Binding(
                get: { viewModel.imagingReportsEnabled },
                set: { newValue in
                    viewModel.imagingReportsEnabled = newValue
                    // Auto-select/deselect all documents in this category
                    viewModel.toggleAllDocuments(in: .imagingReport, enabled: newValue)
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: HealthDataType.imagingReport.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HealthDataType.imagingReport.displayName)
                            .font(.headline)

                        Text("\(viewModel.imagingReportDocuments.count) documents available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Documents list (when enabled)
            if viewModel.imagingReportsEnabled && !viewModel.imagingReportDocuments.isEmpty {
                ForEach(viewModel.imagingReportDocuments) { document in
                    DocumentSelectionRow(
                        document: document,
                        isSelected: viewModel.isDocumentSelected(document),
                        priority: viewModel.getDocumentPriority(document),
                        onToggle: {
                            viewModel.toggleDocument(document)
                        },
                        onPriorityChange: { priority in
                            viewModel.updateDocumentPriority(document, priority: priority)
                        }
                    )
                    .disabled(!viewModel.imagingReportsEnabled)
                }
            }
        }
    }

    // MARK: - Health Checkups Section
    private var healthCheckupsSection: some View {
        Section {
            // Category toggle
            Toggle(isOn: Binding(
                get: { viewModel.healthCheckupsEnabled },
                set: { newValue in
                    viewModel.healthCheckupsEnabled = newValue
                    // Auto-select/deselect all documents in this category
                    viewModel.toggleAllDocuments(in: .healthCheckup, enabled: newValue)
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: HealthDataType.healthCheckup.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HealthDataType.healthCheckup.displayName)
                            .font(.headline)

                        Text("\(viewModel.healthCheckupDocuments.count) documents available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Documents list (when enabled)
            if viewModel.healthCheckupsEnabled && !viewModel.healthCheckupDocuments.isEmpty {
                ForEach(viewModel.healthCheckupDocuments) { document in
                    DocumentSelectionRow(
                        document: document,
                        isSelected: viewModel.isDocumentSelected(document),
                        priority: viewModel.getDocumentPriority(document),
                        onToggle: {
                            viewModel.toggleDocument(document)
                        },
                        onPriorityChange: { priority in
                            viewModel.updateDocumentPriority(document, priority: priority)
                        }
                    )
                    .disabled(!viewModel.healthCheckupsEnabled)
                }
            }
        }
    }
}

// MARK: - Document Selection Row
struct DocumentSelectionRow: View {
    let document: MedicalDocument
    let isSelected: Bool
    let priority: Int
    let onToggle: () -> Void
    let onPriorityChange: (Int) -> Void

    @State private var showingPriorityPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack(spacing: 12) {
                // Checkbox
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                // Document info
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.fileName)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let date = document.documentDate {
                            Text(date, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let provider = document.providerName {
                            Text(provider)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Priority indicator
                if isSelected {
                    Button(action: { showingPriorityPicker.toggle() }) {
                        HStack(spacing: 4) {
                            ForEach(1...priority, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            // Priority picker (when shown)
            if showingPriorityPicker && isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Priority")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        ForEach(1...5, id: \.self) { level in
                            Button(action: {
                                onPriorityChange(level)
                                showingPriorityPicker = false
                            }) {
                                HStack(spacing: 2) {
                                    ForEach(1...level, id: \.self) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                    }
                                }
                                .foregroundColor(priority == level ? .orange : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(priority == level ? Color.orange.opacity(0.2) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Higher priority documents are included first when AI context is limited")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingPriorityPicker)
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - View Model
@MainActor
class UnifiedContextSelectorViewModel: ObservableObject {
    // Published properties
    @Published var personalInfoEnabled: Bool = false
    @Published var bloodTestsEnabled: Bool = false
    @Published var imagingReportsEnabled: Bool = false
    @Published var healthCheckupsEnabled: Bool = false

    @Published var bloodTestDocuments: [MedicalDocument] = []
    @Published var imagingReportDocuments: [MedicalDocument] = []
    @Published var healthCheckupDocuments: [MedicalDocument] = []

    // Private state
    private var selectedDocuments: Set<UUID> = []
    private var documentPriorities: [UUID: Int] = [:]
    private var allDocuments: [MedicalDocument] = []

    private let databaseManager = DatabaseManager.shared
    private let chatManager: AIChatManager

    init(chatManager: AIChatManager) {
        self.chatManager = chatManager
    }

    // Computed properties
    var enabledCategoriesCount: Int {
        [personalInfoEnabled, bloodTestsEnabled, imagingReportsEnabled, healthCheckupsEnabled]
            .filter { $0 }
            .count
    }

    var includedDocumentsCount: Int {
        selectedDocuments.count
    }

    var estimatedTokens: Int {
        var tokens = 0

        // Personal info: ~200 tokens
        if personalInfoEnabled {
            tokens += 200
        }

        // Documents: estimate based on selected documents
        for docId in selectedDocuments {
            if let doc = allDocuments.first(where: { $0.id == docId }) {
                // Rough estimate: 1 token per 4 characters
                if let text = doc.extractedText {
                    tokens += text.count / 4
                } else {
                    tokens += 500 // Default estimate
                }
            }
        }

        return tokens
    }

    var estimatedContextSize: String {
        let tokens = estimatedTokens
        if tokens < 1000 { return "\(tokens)" }
        if tokens < 10000 { return String(format: "%.1fK", Double(tokens) / 1000) }
        return String(format: "%.0fK", Double(tokens) / 1000)
    }

    // MARK: - Data Loading
    func loadData() async {
        do {
            // Load all medical documents
            allDocuments = try await databaseManager.fetchMedicalDocuments()
                .filter { $0.processingStatus == .completed }

            // Categorize documents
            bloodTestDocuments = allDocuments.filter {
                HealthDataType.bloodTest.relatedDocumentCategories.contains($0.documentCategory)
            }

            imagingReportDocuments = allDocuments.filter {
                HealthDataType.imagingReport.relatedDocumentCategories.contains($0.documentCategory)
            }

            healthCheckupDocuments = allDocuments.filter {
                HealthDataType.healthCheckup.relatedDocumentCategories.contains($0.documentCategory)
            }

            // Load current selections from AIChatManager
            let selectedTypes = chatManager.selectedHealthDataTypes
            personalInfoEnabled = selectedTypes.contains(.personalInfo)
            bloodTestsEnabled = selectedTypes.contains(.bloodTest)
            imagingReportsEnabled = selectedTypes.contains(.imagingReport)
            healthCheckupsEnabled = selectedTypes.contains(.healthCheckup)

            // Load document selections
            selectedDocuments = Set(allDocuments.filter { $0.includeInAIContext }.map { $0.id })

            // Load priorities
            for doc in allDocuments where doc.includeInAIContext {
                documentPriorities[doc.id] = doc.contextPriority
            }

        } catch {
            print("❌ Failed to load context data: \(error)")
        }
    }

    // MARK: - Document Management
    func isDocumentSelected(_ document: MedicalDocument) -> Bool {
        selectedDocuments.contains(document.id)
    }

    func getDocumentPriority(_ document: MedicalDocument) -> Int {
        documentPriorities[document.id] ?? 3
    }

    func toggleDocument(_ document: MedicalDocument) {
        if selectedDocuments.contains(document.id) {
            selectedDocuments.remove(document.id)
            documentPriorities.removeValue(forKey: document.id)
        } else {
            selectedDocuments.insert(document.id)
            documentPriorities[document.id] = 3 // Default priority
        }
    }

    func updateDocumentPriority(_ document: MedicalDocument, priority: Int) {
        documentPriorities[document.id] = priority
    }

    func toggleAllDocuments(in category: HealthDataType, enabled: Bool) {
        let documentsInCategory: [MedicalDocument]

        switch category {
        case .bloodTest:
            documentsInCategory = bloodTestDocuments
        case .imagingReport:
            documentsInCategory = imagingReportDocuments
        case .healthCheckup:
            documentsInCategory = healthCheckupDocuments
        case .personalInfo:
            return // No documents for personal info
        }

        if enabled {
            // Add all documents in this category to selection
            for doc in documentsInCategory {
                selectedDocuments.insert(doc.id)
                if documentPriorities[doc.id] == nil {
                    documentPriorities[doc.id] = 3 // Default priority
                }
            }
        } else {
            // Remove all documents in this category from selection
            for doc in documentsInCategory {
                selectedDocuments.remove(doc.id)
                documentPriorities.removeValue(forKey: doc.id)
            }
        }
    }

    // MARK: - Save Changes
    func saveChanges() async {
        do {
            // Save health data type selections to AIChatManager
            var selectedTypes: Set<HealthDataType> = []
            if personalInfoEnabled { selectedTypes.insert(.personalInfo) }
            if bloodTestsEnabled { selectedTypes.insert(.bloodTest) }
            if imagingReportsEnabled { selectedTypes.insert(.imagingReport) }
            if healthCheckupsEnabled { selectedTypes.insert(.healthCheckup) }

            chatManager.selectHealthDataForContext(selectedTypes)

            // Save document selections and priorities
            for document in allDocuments {
                let shouldInclude = selectedDocuments.contains(document.id)
                let priority = documentPriorities[document.id] ?? 3

                if document.includeInAIContext != shouldInclude || document.contextPriority != priority {
                    var updatedDoc = document
                    updatedDoc.includeInAIContext = shouldInclude
                    updatedDoc.contextPriority = priority

                    try await databaseManager.updateMedicalDocument(updatedDoc)
                }
            }

            print("✅ Context selections saved successfully")
        } catch {
            print("❌ Failed to save context selections: \(error)")
        }
    }
}

// MARK: - Preview
#Preview {
    UnifiedContextSelectorView(
        chatManager: AIChatManager(
            healthDataManager: HealthDataManager.shared,
            databaseManager: DatabaseManager.shared
        )
    )
}
