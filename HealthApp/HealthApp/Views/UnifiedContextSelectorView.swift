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
                            do {
                                try await viewModel.saveChanges()
                                dismiss()
                            } catch {
                                // Error is handled by viewModel.errorMessage
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.loadData()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }
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

                        if viewModel.selectedBloodTestsCount > 0 {
                            HStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 4, height: 4)
                                Text("\(viewModel.selectedBloodTestsCount) lab result\(viewModel.selectedBloodTestsCount == 1 ? "" : "s"): ~\(viewModel.estimatedBloodTestTokens) tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if viewModel.includedDocumentsCount > 0 {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                                Text("\(viewModel.includedDocumentsCount) document\(viewModel.includedDocumentsCount == 1 ? "" : "s"): ~\(viewModel.estimatedDocumentTokens) tokens")
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
        let tokens = viewModel.estimatedTokens
        if tokens < 4000 { return .green }
        if tokens < 8000 { return .orange }
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
            Toggle(isOn: $viewModel.bloodTestsEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: HealthDataType.bloodTest.icon)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HealthDataType.bloodTest.displayName)
                            .font(.headline)

                        let bloodTestCount = viewModel.allBloodTests.count
                        let documentCount = viewModel.bloodTestDocuments.count
                        Text("\(bloodTestCount) lab result\(bloodTestCount == 1 ? "" : "s"), \(documentCount) document\(documentCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Blood test results list (when enabled)
            if viewModel.bloodTestsEnabled && !viewModel.allBloodTests.isEmpty {
                ForEach(viewModel.allBloodTests.sorted(by: { $0.testDate > $1.testDate })) { bloodTest in
                    BloodTestSelectionRow(
                        bloodTest: bloodTest,
                        isSelected: viewModel.isBloodTestSelected(bloodTest),
                        onToggle: {
                            viewModel.toggleBloodTest(bloodTest)
                        }
                    )
                    .disabled(!viewModel.bloodTestsEnabled)
                }
                .animation(.default, value: viewModel.selectedBloodTests)
            }

            // Documents list (when enabled)
            if viewModel.bloodTestsEnabled && !viewModel.bloodTestDocuments.isEmpty {
                ForEach(viewModel.bloodTestDocuments) { document in
                    DocumentSelectionRow(
                        document: document,
                        isSelected: viewModel.isDocumentSelected(document),
                        onToggle: {
                            viewModel.toggleDocument(document)
                        }
                    )
                    .disabled(!viewModel.bloodTestsEnabled)
                }
                .animation(.default, value: viewModel.selectedDocuments)
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
                        onToggle: {
                            viewModel.toggleDocument(document)
                        }
                    )
                    .disabled(!viewModel.imagingReportsEnabled)
                }
                .animation(.default, value: viewModel.selectedDocuments)
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
                        onToggle: {
                            viewModel.toggleDocument(document)
                        }
                    )
                    .disabled(!viewModel.healthCheckupsEnabled)
                }
                .animation(.default, value: viewModel.selectedDocuments)
            }
        }
    }
}

// MARK: - Blood Test Selection Row
struct BloodTestSelectionRow: View {
    let bloodTest: BloodTestResult
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect blood test from \(bloodTest.testDate.formatted(date: .abbreviated, time: .omitted))" : "Select blood test from \(bloodTest.testDate.formatted(date: .abbreviated, time: .omitted))")
            .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") this lab result for AI context")
            .accessibilityIdentifier("bloodTestSelectionToggle_\(bloodTest.id.uuidString)")

            // Blood test info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bloodTest.testDate, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let lab = bloodTest.laboratoryName {
                        Text("•")
                            .foregroundColor(.secondary)
                            .font(.caption2)

                        Text(lab)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Text("\(bloodTest.results.count) result\(bloodTest.results.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if bloodTest.abnormalResults.count > 0 {
                    Text("\(bloodTest.abnormalResults.count) abnormal")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Document Selection Row
struct DocumentSelectionRow: View {
    let document: MedicalDocument
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(document.fileName)" : "Select \(document.fileName)")
            .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") this document for AI context")
            .accessibilityIdentifier("documentSelectionToggle_\(document.id.uuidString)")

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
        }
        .padding(.vertical, 4)
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
    // MARK: - Constants
    private enum Constants {
        static let defaultTokenEstimate = 500
        static let personalInfoTokenEstimate = 200
        static let tokensPerCharacter = 4
        static let tokensPerBloodTestResult = 50  // ~50 tokens per result line
        static let bloodTestHeaderTokens = 50     // Header info (date, lab name)
        static let smallContextDisplayThreshold = 1000
        static let largeContextDisplayThreshold = 10000
    }
    
    // Published properties
    @Published var personalInfoEnabled: Bool = false
    @Published var bloodTestsEnabled: Bool = false
    @Published var imagingReportsEnabled: Bool = false
    @Published var healthCheckupsEnabled: Bool = false

    @Published var bloodTestDocuments: [MedicalDocument] = []
    @Published var imagingReportDocuments: [MedicalDocument] = []
    @Published var healthCheckupDocuments: [MedicalDocument] = []
    @Published var allBloodTests: [BloodTestResult] = []

    // Published state for UI updates (fixes P1 Badge issue)
    @Published var selectedDocuments: Set<UUID> = []
    @Published var selectedBloodTests: Set<UUID> = []
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    
    private var allDocuments: [MedicalDocument] = []
    
    // Cached computed properties
    private var _cachedEstimatedTokens: Int?
    private var _lastTokensCalculationHash: Int?

    private let databaseManager = DatabaseManager.shared
    private let chatManager: AIChatManager
    private let healthDataManager: HealthDataManager

    init(chatManager: AIChatManager) {
        self.chatManager = chatManager
        self.healthDataManager = HealthDataManager.shared
    }

    // Computed properties
    var enabledCategoriesCount: Int {
        [personalInfoEnabled, bloodTestsEnabled, imagingReportsEnabled, healthCheckupsEnabled]
            .filter { $0 }
            .count
    }

    var includedDocumentsCount: Int {
        // Only count documents that are selected AND in an enabled category
        selectedDocuments.filter { docId in
            guard let doc = allDocuments.first(where: { $0.id == docId }) else { return false }
            return isCategoryEnabled(for: doc)
        }.count
    }

    var selectedBloodTestsCount: Int {
        // Only count blood tests if the category is enabled
        bloodTestsEnabled ? selectedBloodTests.count : 0
    }

    var estimatedBloodTestTokens: Int {
        guard bloodTestsEnabled else { return 0 }
        var tokens = 0
        for testId in selectedBloodTests {
            if let test = allBloodTests.first(where: { $0.id == testId }) {
                tokens += test.results.count * Constants.tokensPerBloodTestResult + Constants.bloodTestHeaderTokens
            }
        }
        return tokens
    }

    var estimatedDocumentTokens: Int {
        var tokens = 0
        for docId in selectedDocuments {
            if let doc = allDocuments.first(where: { $0.id == docId }), isCategoryEnabled(for: doc) {
                if let text = doc.extractedText {
                    tokens += text.count / Constants.tokensPerCharacter
                } else {
                    tokens += Constants.defaultTokenEstimate
                }
            }
        }
        return tokens
    }

    var estimatedTokens: Int {
        // Calculate hash of dependencies for cache invalidation
        let currentHash = hashForTokensCalculation()

        // Return cached value if dependencies haven't changed
        if let cached = _cachedEstimatedTokens,
           let lastHash = _lastTokensCalculationHash,
           lastHash == currentHash {
            return cached
        }

        // Calculate tokens
        var tokens = 0

        // Personal info tokens
        if personalInfoEnabled {
            tokens += Constants.personalInfoTokenEstimate
        }

        // Blood tests: estimate based on selected tests, only if enabled
        if bloodTestsEnabled {
            for testId in selectedBloodTests {
                if let test = allBloodTests.first(where: { $0.id == testId }) {
                    // Estimate: ~50 tokens per result line + 50 for headers
                    tokens += test.results.count * Constants.tokensPerBloodTestResult + Constants.bloodTestHeaderTokens
                }
            }
        }

        // Documents: estimate based on selected documents, only if category enabled
        for docId in selectedDocuments {
            if let doc = allDocuments.first(where: { $0.id == docId }), isCategoryEnabled(for: doc) {
                // Rough estimate: 1 token per 4 characters
                if let text = doc.extractedText {
                    tokens += text.count / Constants.tokensPerCharacter
                } else {
                    tokens += Constants.defaultTokenEstimate
                }
            }
        }

        // Cache the result
        _cachedEstimatedTokens = tokens
        _lastTokensCalculationHash = currentHash

        return tokens
    }
    
    private func isCategoryEnabled(for document: MedicalDocument) -> Bool {
        let category = document.documentCategory
        
        if HealthDataType.bloodTest.relatedDocumentCategories.contains(category) {
            return bloodTestsEnabled
        }
        if HealthDataType.imagingReport.relatedDocumentCategories.contains(category) {
            return imagingReportsEnabled
        }
        if HealthDataType.healthCheckup.relatedDocumentCategories.contains(category) {
            return healthCheckupsEnabled
        }
        
        return false
    }
    
    private func hashForTokensCalculation() -> Int {
        var hasher = Hasher()
        hasher.combine(personalInfoEnabled)
        hasher.combine(bloodTestsEnabled)
        hasher.combine(imagingReportsEnabled)
        hasher.combine(healthCheckupsEnabled)
        hasher.combine(selectedDocuments)
        hasher.combine(selectedBloodTests)
        // Include document text lengths in hash for documents in enabled categories
        for docId in selectedDocuments {
            if let doc = allDocuments.first(where: { $0.id == docId }), 
               isCategoryEnabled(for: doc),
               let text = doc.extractedText {
                hasher.combine(text.count)
            }
        }
        return hasher.finalize()
    }

    var estimatedContextSize: String {
        let tokens = estimatedTokens
        if tokens < Constants.smallContextDisplayThreshold { 
            return "\(tokens)" 
        }
        if tokens < Constants.largeContextDisplayThreshold { 
            return String(format: "%.1fK", Double(tokens) / 1000) 
        }
        return String(format: "%.0fK", Double(tokens) / 1000)
    }

    // MARK: - Data Loading
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
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

            // Load all blood tests
            allBloodTests = healthDataManager.bloodTests

            // Load current selections from AIChatManager
            let selectedTypes = chatManager.selectedHealthDataTypes
            personalInfoEnabled = selectedTypes.contains(.personalInfo)
            bloodTestsEnabled = selectedTypes.contains(.bloodTest)
            imagingReportsEnabled = selectedTypes.contains(.imagingReport)
            healthCheckupsEnabled = selectedTypes.contains(.healthCheckup)

            // Load document selections
            selectedDocuments = Set(allDocuments.filter { $0.includeInAIContext }.map { $0.id })

            // Load blood test selections
            selectedBloodTests = Set(allBloodTests.filter { $0.includeInAIContext }.map { $0.id })
            
            // Invalidate cache after loading
            _cachedEstimatedTokens = nil
            _lastTokensCalculationHash = nil

        } catch {
            errorMessage = "Failed to load context data: \(error.localizedDescription)"
            print("❌ Failed to load context data: \(error)")
        }
        
        isLoading = false
    }

    // MARK: - Document Management
    func isDocumentSelected(_ document: MedicalDocument) -> Bool {
        selectedDocuments.contains(document.id)
    }

    func toggleDocument(_ document: MedicalDocument) {
        if selectedDocuments.contains(document.id) {
            selectedDocuments.remove(document.id)
        } else {
            selectedDocuments.insert(document.id)
        }
        // Invalidate cache when selection changes
        _cachedEstimatedTokens = nil
        _lastTokensCalculationHash = nil
        // Note: @Published properties automatically trigger objectWillChange
    }

    // MARK: - Blood Test Management
    func isBloodTestSelected(_ bloodTest: BloodTestResult) -> Bool {
        selectedBloodTests.contains(bloodTest.id)
    }

    func toggleBloodTest(_ bloodTest: BloodTestResult) {
        if selectedBloodTests.contains(bloodTest.id) {
            selectedBloodTests.remove(bloodTest.id)
        } else {
            selectedBloodTests.insert(bloodTest.id)
        }
        // Invalidate cache when selection changes
        _cachedEstimatedTokens = nil
        _lastTokensCalculationHash = nil
        // Note: @Published properties automatically trigger objectWillChange
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
            }
        } else {
            // Remove all documents in this category from selection
            for doc in documentsInCategory {
                selectedDocuments.remove(doc.id)
            }
        }
        // Invalidate cache when selection changes
        _cachedEstimatedTokens = nil
        _lastTokensCalculationHash = nil
        // Note: @Published properties automatically trigger objectWillChange
    }

    // MARK: - Save Changes
    func saveChanges() async throws {
        // Validate before saving
        guard validateSelections() else {
            throw ValidationError.invalidSelection
        }
        
        errorMessage = nil
        isLoading = true
        
        do {
            // Save health data type selections to AIChatManager
            var selectedTypes: Set<HealthDataType> = []
            if personalInfoEnabled { selectedTypes.insert(.personalInfo) }
            if bloodTestsEnabled { selectedTypes.insert(.bloodTest) }
            if imagingReportsEnabled { selectedTypes.insert(.imagingReport) }
            if healthCheckupsEnabled { selectedTypes.insert(.healthCheckup) }

            chatManager.selectHealthDataForContext(selectedTypes)

            // Save document selections
            for document in allDocuments {
                let shouldInclude = selectedDocuments.contains(document.id)

                if document.includeInAIContext != shouldInclude {
                    var updatedDoc = document
                    updatedDoc.includeInAIContext = shouldInclude

                    try await databaseManager.updateMedicalDocument(updatedDoc)
                }
            }

            // Save blood test selections
            for bloodTest in allBloodTests {
                let shouldInclude = selectedBloodTests.contains(bloodTest.id)

                if bloodTest.includeInAIContext != shouldInclude {
                    var updatedTest = bloodTest
                    updatedTest.includeInAIContext = shouldInclude

                    // Save to database via HealthDataManager
                    try await healthDataManager.updateBloodTest(updatedTest)
                }
            }

            print("✅ Context selections saved successfully")
        } catch {
            errorMessage = "Failed to save context selections: \(error.localizedDescription)"
            print("❌ Failed to save context selections: \(error)")
            throw error
        }
        
        isLoading = false
    }
    
    // MARK: - Validation
    private func validateSelections() -> Bool {
        // Validation: If documents are selected, at least one category should be enabled
        if !selectedDocuments.isEmpty {
            let hasEnabledCategory = personalInfoEnabled || 
                                   bloodTestsEnabled || 
                                   imagingReportsEnabled || 
                                   healthCheckupsEnabled
            return hasEnabledCategory
        }
        return true
    }
    
    enum ValidationError: LocalizedError {
        case invalidSelection
        
        var errorDescription: String? {
            switch self {
            case .invalidSelection:
                return "Please enable at least one category when selecting documents."
            }
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
