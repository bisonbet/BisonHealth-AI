import SwiftUI

// MARK: - Medical Document Detail View
struct MedicalDocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MedicalDocumentDetailViewModel

    @State private var showingSectionEditor: Bool = false
    @State private var editingSection: DocumentSection?
    @State private var showingDeleteConfirmation: Bool = false

    init(document: MedicalDocument) {
        _viewModel = StateObject(wrappedValue: MedicalDocumentDetailViewModel(document: document))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    categoryAndProviderSection
                    aiContextSection
                    sectionsSection
                    tagsSection
                    notesSection
                }
                .padding()
            }
            .navigationTitle(viewModel.document.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Share", systemImage: "square.and.arrow.up") {
                            // Share functionality
                        }

                        Divider()

                        Button("Delete", systemImage: "trash", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingSectionEditor) {
                if let section = editingSection {
                    SectionEditorView(
                        section: section,
                        onSave: { updatedSection in
                            viewModel.updateSection(updatedSection)
                            showingSectionEditor = false
                        },
                        onCancel: {
                            showingSectionEditor = false
                        }
                    )
                }
            }
            .confirmationDialog("Delete Document?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteDocument()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Document Information", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 12) {
                // Document Date
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Document Date")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        DatePicker(
                            "",
                            selection: Binding(
                                get: { viewModel.document.documentDate ?? Date() },
                                set: { viewModel.updateDocumentDate($0) }
                            ),
                            in: Date.distantPast...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // File Info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.document.fileType.displayName)
                            .font(.body)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("File Size")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.document.formattedFileSize)
                            .font(.body)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Processing Status
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    ProcessingStatusBadge(status: viewModel.document.processingStatus)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Category and Provider Section
    private var categoryAndProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Medical Details", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 12) {
                // Document Category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Document Type")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Menu {
                        ForEach(DocumentCategory.allCases, id: \.self) { category in
                            Button {
                                viewModel.updateCategory(category)
                            } label: {
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: viewModel.document.documentCategory.icon)
                                .foregroundColor(.blue)
                            Text(viewModel.document.documentCategory.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }

                // Provider Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider / Facility")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Dr. Smith or City MRI Center", text: Binding(
                        get: { viewModel.document.providerName ?? "" },
                        set: { viewModel.updateProviderName($0) }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Provider Type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider Type")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Menu {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Button {
                                viewModel.updateProviderType(type)
                            } label: {
                                HStack {
                                    Image(systemName: type.icon)
                                    Text(type.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: viewModel.document.providerType?.icon ?? "building.2")
                                .foregroundColor(.blue)
                            Text(viewModel.document.providerType?.displayName ?? "Select Type")
                                .foregroundColor(viewModel.document.providerType != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - AI Context Section
    private var aiContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Doctor Context", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 12) {
                // Include in AI Context Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.document.includeInAIContext },
                    set: { viewModel.toggleAIContext($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Include in AI Conversations")
                            .font(.body)

                        Text("When enabled, this document will be available to the AI doctor during chat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Priority Slider (only shown when included)
                if viewModel.document.includeInAIContext {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Priority")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(viewModel.document.contextPriority) / 5")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.document.contextPriority) },
                                set: { viewModel.updatePriority(Int($0)) }
                            ),
                            in: 1...5,
                            step: 1
                        )

                        Text("Higher priority documents are included first when talking to the AI doctor")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.document.includeInAIContext)
    }

    // MARK: - Sections Section
    private var sectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Document Sections", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)

                Spacer()

                Button("Add Section") {
                    editingSection = DocumentSection(sectionType: "New Section", content: "")
                    showingSectionEditor = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.document.extractedSections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)

                    Text("No sections extracted")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Tap 'Add Section' to manually add document sections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.document.extractedSections) { section in
                        SectionRowView(
                            section: section,
                            onTap: {
                                editingSection = section
                                showingSectionEditor = true
                            },
                            onDelete: {
                                viewModel.deleteSection(section.id)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                Spacer()
            }

            TagInputView(tags: Binding(
                get: { viewModel.document.tags },
                set: { viewModel.updateTags($0) }
            ))
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
            }

            TextEditor(text: Binding(
                get: { viewModel.document.notes ?? "" },
                set: { viewModel.updateNotes($0) }
            ))
            .frame(minHeight: 100)
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Section Row View
struct SectionRowView: View {
    let section: DocumentSection
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.sectionType)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(section.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                onTap()
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - Tag Input View
struct TagInputView: View {
    @Binding var tags: [String]
    @State private var newTagText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Existing tags
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(tag: tag) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Add new tag
            HStack(spacing: 8) {
                TextField("Add tag", text: $newTagText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        addTag()
                    }

                Button("Add") {
                    addTag()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTagText = ""
            isInputFocused = true
        }
    }
}

// MARK: - Tag Chip View
struct TagChipView: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout (for tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
