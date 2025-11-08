import SwiftUI

// MARK: - Section Editor View
struct SectionEditorView: View {
    @State private var sectionType: String
    @State private var content: String

    let onSave: (DocumentSection) -> Void
    let onCancel: () -> Void

    private let originalSection: DocumentSection

    init(section: DocumentSection, onSave: @escaping (DocumentSection) -> Void, onCancel: @escaping () -> Void) {
        self.originalSection = section
        _sectionType = State(initialValue: section.sectionType)
        _content = State(initialValue: section.content)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Section Type", text: $sectionType)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Section Type")
                } footer: {
                    Text("E.g., 'Findings', 'Impression', 'Chief Complaint'")
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                } header: {
                    Text("Content")
                }

                // Common section types (quick selection)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonSectionTypes, id: \.self) { type in
                                Button(type) {
                                    sectionType = type
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Common Section Types")
                }
            }
            .navigationTitle(originalSection.sectionType.isEmpty ? "New Section" : "Edit Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let updatedSection = DocumentSection(
                            id: originalSection.id,
                            sectionType: sectionType,
                            content: content,
                            confidence: originalSection.confidence,
                            startPosition: originalSection.startPosition,
                            endPosition: originalSection.endPosition,
                            metadata: originalSection.metadata
                        )
                        onSave(updatedSection)
                    }
                    .disabled(sectionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var commonSectionTypes: [String] {
        [
            "Chief Complaint",
            "History of Present Illness",
            "Physical Examination",
            "Assessment",
            "Plan",
            "Findings",
            "Impression",
            "Clinical Indication",
            "Technique",
            "Comparison",
            "Recommendations"
        ]
    }
}
