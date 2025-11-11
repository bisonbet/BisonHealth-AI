import SwiftUI

// MARK: - Document Type Selector View
struct DocumentTypeSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let fileName: String
    @Binding var selectedCategory: DocumentCategory?
    let onConfirm: (DocumentCategory) -> Void
    
    @State private var tempSelection: DocumentCategory = .other
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Document:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(fileName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } header: {
                    Text("Select Document Type")
                } footer: {
                    Text("This helps the app process your document correctly. You can change this later.")
                }
                
                Section {
                    ForEach(DocumentCategory.allCases, id: \.self) { category in
                        Button {
                            tempSelection = category
                        } label: {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                Text(category.displayName)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if tempSelection == category {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Document Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        // Use current selection (defaults to .other) when skipping
                        onConfirm(tempSelection)
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onConfirm(tempSelection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempSelection = selectedCategory ?? .other
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

