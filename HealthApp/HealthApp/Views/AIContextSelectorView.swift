import SwiftUI

// MARK: - AI Context Selector View
struct AIContextSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AIContextSelectorViewModel()

    @State private var searchText: String = ""
    @State private var selectedCategory: DocumentCategory? = nil
    @State private var showOnlyIncluded: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with context summary
                contextSummaryHeader

                Divider()

                // Filter bar
                filterBar

                // Document list
                documentList
            }
            .navigationTitle("AI Context Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Select All", systemImage: "checkmark.circle") {
                            viewModel.selectAll()
                        }

                        Button("Deselect All", systemImage: "circle") {
                            viewModel.deselectAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadDocuments()
            }
        }
    }

    // MARK: - Context Summary Header
    private var contextSummaryHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.includedCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

                    Text("Included")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.totalCount)")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)

            if viewModel.includedCount > 0 {
                Text("These documents will be shared with the AI doctor during conversations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        VStack(spacing: 8) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search documents", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        onTap: { selectedCategory = nil }
                    )

                    FilterChip(
                        title: "Included Only",
                        isSelected: showOnlyIncluded,
                        onTap: { showOnlyIncluded.toggle() }
                    )

                    ForEach([DocumentCategory.doctorsNote, .imagingReport, .labReport, .prescription, .dischargeSummary], id: \.self) { category in
                        FilterChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category,
                            onTap: {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Document List
    private var documentList: some View {
        List {
            ForEach(filteredDocuments) { document in
                AIContextDocumentRow(
                    document: document,
                    onToggle: {
                        Task {
                            await viewModel.toggleDocument(document)
                        }
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }

    // MARK: - Filtered Documents
    private var filteredDocuments: [MedicalDocument] {
        var documents = viewModel.documents

        // Filter by search text
        if !searchText.isEmpty {
            documents = documents.filter { document in
                document.fileName.localizedCaseInsensitiveContains(searchText) ||
                (document.providerName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                document.documentCategory.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by category
        if let category = selectedCategory {
            documents = documents.filter { $0.documentCategory == category }
        }

        // Filter by included status
        if showOnlyIncluded {
            documents = documents.filter { $0.includeInAIContext }
        }

        // Sort by selection status and date (newest first)
        return documents.sorted { doc1, doc2 in
            if doc1.includeInAIContext != doc2.includeInAIContext {
                return doc1.includeInAIContext
            }
            guard let date1 = doc1.documentDate, let date2 = doc2.documentDate else {
                return doc1.documentDate != nil
            }
            return date1 > date2
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// MARK: - AI Context Document Row
struct AIContextDocumentRow: View {
    let document: MedicalDocument
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Selection toggle
            Button(action: onToggle) {
                Image(systemName: document.includeInAIContext ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(document.includeInAIContext ? .blue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())

            // Document icon
            Image(systemName: document.documentCategory.icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            // Document info
            VStack(alignment: .leading, spacing: 4) {
                Text(document.fileName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.documentCategory.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)

                    if let date = document.documentDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let provider = document.providerName {
                        Text(provider)
                            .font(.caption)
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

// MARK: - AI Context Selector View Model
@MainActor
class AIContextSelectorViewModel: ObservableObject {
    @Published var documents: [MedicalDocument] = []
    @Published var includedCount: Int = 0
    @Published var totalCount: Int = 0

    private let databaseManager = DatabaseManager.shared

    func loadDocuments() async {
        do {
            // Only load completed documents
            let allDocs = try await databaseManager.fetchMedicalDocuments()
            documents = allDocs.filter { $0.processingStatus == .completed }
            totalCount = documents.count
            updateIncludedCount()
        } catch {
            print("❌ Failed to load documents: \(error)")
        }
    }

    func toggleDocument(_ document: MedicalDocument) async {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        let newValue = !documents[index].includeInAIContext
        documents[index].includeInAIContext = newValue

        do {
            try await databaseManager.updateDocumentAIContextStatus(document.id, includeInContext: newValue)
            updateIncludedCount()
        } catch {
            print("❌ Failed to update context status: \(error)")
            // Revert on error
            documents[index].includeInAIContext = !newValue
        }
    }

    func selectAll() {
        Task {
            for index in documents.indices {
                documents[index].includeInAIContext = true
            }

            let documentIds = documents.map { $0.id }
            do {
                try await databaseManager.updateDocumentsAIContextStatus(documentIds, includeInContext: true)
                updateIncludedCount()
            } catch {
                print("❌ Failed to select all: \(error)")
            }
        }
    }

    func deselectAll() {
        Task {
            for index in documents.indices {
                documents[index].includeInAIContext = false
            }

            let documentIds = documents.map { $0.id }
            do {
                try await databaseManager.updateDocumentsAIContextStatus(documentIds, includeInContext: false)
                updateIncludedCount()
            } catch {
                print("❌ Failed to deselect all: \(error)")
            }
        }
    }

    private func updateIncludedCount() {
        includedCount = documents.filter { $0.includeInAIContext }.count
    }
}
