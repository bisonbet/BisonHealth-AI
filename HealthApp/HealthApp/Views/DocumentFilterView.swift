import SwiftUI

struct DocumentFilterView: View {
    @ObservedObject var documentManager: DocumentManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search documents...", text: $documentManager.searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                        
                        if !documentManager.searchText.isEmpty {
                            Button("Clear") {
                                documentManager.searchText = ""
                            }
                            .font(.caption)
                        }
                    }
                }
                
                Section("Filter by Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ProcessingStatus.allCases, id: \.self) { status in
                            FilterOptionRow(
                                title: status.displayName,
                                icon: status.icon,
                                color: status.color,
                                isSelected: documentManager.filterStatus == status,
                                count: documentManager.documents.filter { $0.processingStatus == status }.count
                            ) {
                                if documentManager.filterStatus == status {
                                    documentManager.filterStatus = nil
                                } else {
                                    documentManager.filterStatus = status
                                }
                            }
                        }
                        
                        FilterOptionRow(
                            title: "All Documents",
                            icon: "doc.fill",
                            color: .primary,
                            isSelected: documentManager.filterStatus == nil,
                            count: documentManager.documents.count
                        ) {
                            documentManager.filterStatus = nil
                        }
                    }
                }
                
                Section("Filter by Type") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DocumentType.allCases, id: \.self) { type in
                            FilterOptionRow(
                                title: type.displayName,
                                icon: type.icon,
                                color: .blue,
                                isSelected: documentManager.filterType == type,
                                count: documentManager.documents.filter { $0.fileType == type }.count
                            ) {
                                if documentManager.filterType == type {
                                    documentManager.filterType = nil
                                } else {
                                    documentManager.filterType = type
                                }
                            }
                        }
                        
                        FilterOptionRow(
                            title: "All Types",
                            icon: "doc.fill",
                            color: .primary,
                            isSelected: documentManager.filterType == nil,
                            count: documentManager.documents.count
                        ) {
                            documentManager.filterType = nil
                        }
                    }
                }
                
                Section("Sort Order") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DocumentSortOrder.allCases, id: \.self) { sortOrder in
                            SortOptionRow(
                                title: sortOrder.displayName,
                                isSelected: documentManager.sortOrder == sortOrder
                            ) {
                                documentManager.sortOrder = sortOrder
                            }
                        }
                    }
                }
                
                Section("Quick Actions") {
                    Button("Clear All Filters") {
                        documentManager.clearAllFilters()
                    }
                    .foregroundColor(.blue)
                    
                    Button("Select All Visible") {
                        documentManager.selectAllDocuments()
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear All") {
                        documentManager.clearAllFilters()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct FilterOptionRow: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SortOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Extensions for Filter Support

extension ProcessingStatus {
    var color: Color {
        switch self {
        case .pending:
            return .orange
        case .queued:
            return .gray
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    DocumentFilterView(documentManager: DocumentManager.shared)
}
