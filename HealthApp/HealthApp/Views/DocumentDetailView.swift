import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct DocumentDetailView: View {
    let document: HealthDocument
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var documentProcessor: DocumentProcessor
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingQuickLook = false
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingTagEditor = false
    @State private var showingNotesEditor = false
    @State private var newTag = ""
    @State private var editedNotes = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document Preview Section
                    documentPreviewSection
                    
                    // Processing Status Section
                    processingStatusSection
                    
                    // Document Information Section
                    documentInfoSection
                    
                    // Tags Section
                    tagsSection
                    
                    // Notes Section
                    notesSection
                    
                    // Extracted Data Section
                    if !document.extractedData.isEmpty {
                        extractedDataSection
                    }
                    
                    // Actions Section
                    actionsSection
                }
                .padding()
            }
            .navigationTitle(document.fileName)
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
                            showingShareSheet = true
                        }
                        
                        Button("Quick Look", systemImage: "eye") {
                            showingQuickLook = true
                        }
                        
                        Divider()
                        
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingQuickLook) {
            QuickLookView(url: document.filePath)
        }
        .sheet(isPresented: $showingShareSheet) {
            DocumentShareSheet(items: [document.filePath])
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorSheet(
                document: document,
                documentManager: documentManager,
                isPresented: $showingTagEditor
            )
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorSheet(
                document: document,
                documentManager: documentManager,
                isPresented: $showingNotesEditor
            )
        }
        .alert("Delete Document", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await documentManager.deleteDocument(document)
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(document.fileName)\"? This action cannot be undone.")
        }
    }
    
    // MARK: - Document Preview Section
    
    private var documentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
            
            Button(action: { showingQuickLook = true }) {
                HStack {
                    if let thumbnailPath = document.thumbnailPath,
                       let image = UIImage(contentsOfFile: thumbnailPath.path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                            .clipped()
                    } else {
                        Image(systemName: document.fileType.icon)
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                            .frame(width: 80, height: 80)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.fileName)
                            .font(.headline)
                            .lineLimit(2)
                        
                        Text(document.fileType.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(document.formattedFileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "eye")
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Processing Status Section
    
    private var processingStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Status")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProcessingStatusBadge(status: document.processingStatus)
                    
                    Spacer()
                    
                    if document.processingStatus == .processing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                if document.processingStatus == .failed {
                    Button("Retry Processing") {
                        Task {
                            await documentProcessor.addToQueue(document, priority: .high)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if document.processingStatus == .pending {
                    HStack {
                        Button("Process Now") {
                            Task {
                                await documentProcessor.addToQueue(document, priority: .urgent)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("Add to Queue") {
                            Task {
                                await documentProcessor.addToQueue(document)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                if let processedAt = document.processedAt {
                    Text("Processed: \(processedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Document Information Section
    
    private var documentInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)
            
            VStack(spacing: 0) {
                DocumentInfoRow(label: "File Name", value: document.fileName)
                DocumentInfoRow(label: "File Type", value: document.fileType.displayName)
                DocumentInfoRow(label: "File Size", value: document.formattedFileSize)
                DocumentInfoRow(label: "Imported", value: document.importedAt.formatted(date: .abbreviated, time: .shortened))
                
                if let processedAt = document.processedAt {
                    DocumentInfoRow(label: "Processed", value: processedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.headline)
                
                Spacer()
                
                Button("Edit") {
                    showingTagEditor = true
                }
                .font(.caption)
            }
            
            if document.tags.isEmpty {
                Text("No tags added")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(document.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.headline)
                
                Spacer()
                
                Button("Edit") {
                    editedNotes = document.notes ?? ""
                    showingNotesEditor = true
                }
                .font(.caption)
            }
            
            if let notes = document.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                Text("No notes added")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Extracted Data Section
    
    private var extractedDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted Health Data")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(document.extractedData.enumerated()), id: \.offset) { index, data in
                    ExtractedDataRow(data: data, index: index)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button("Regenerate Thumbnail") {
                Task {
                    await documentManager.regenerateThumbnail(for: document)
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            
            if document.processingStatus == .completed {
                Button("Reprocess Document") {
                    Task {
                        await documentProcessor.addToQueue(document, priority: .high)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Supporting Views

struct DocumentInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct ExtractedDataRow: View {
    let data: AnyHealthData
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Data \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(data.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
            
            Text("Extracted health data of type \(data.type.displayName)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookView
        
        init(_ parent: QuickLookView) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as QLPreviewItem
        }
    }
}

struct DocumentShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TagEditorSheet: View {
    let document: HealthDocument
    let documentManager: DocumentManager
    @Binding var isPresented: Bool
    
    @State private var newTag = ""
    @State private var tags: [String] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section("Add New Tag") {
                    HStack {
                        TextField("Enter tag name", text: $newTag)
                        
                        Button("Add") {
                            let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedTag.isEmpty && !tags.contains(trimmedTag) {
                                tags.append(trimmedTag)
                                newTag = ""
                            }
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                
                Section("Current Tags") {
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button("Remove") {
                                tags.removeAll { $0 == tag }
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            // Update document tags
                            for tag in tags {
                                if !document.tags.contains(tag) {
                                    await documentManager.addTagToDocument(document.id, tag: tag)
                                }
                            }
                            
                            // Remove tags not in the new list
                            for existingTag in document.tags {
                                if !tags.contains(existingTag) {
                                    await documentManager.removeTagFromDocument(document.id, tag: existingTag)
                                }
                            }
                            
                            isPresented = false
                        }
                    }
                }
            }
        }
        .onAppear {
            tags = document.tags
        }
    }
}

struct NotesEditorSheet: View {
    let document: HealthDocument
    let documentManager: DocumentManager
    @Binding var isPresented: Bool
    
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $notes)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await documentManager.updateDocumentNotes(
                                document.id,
                                notes: notes.isEmpty ? nil : notes
                            )
                            isPresented = false
                        }
                    }
                }
            }
        }
        .onAppear {
            notes = document.notes ?? ""
        }
    }
}

#Preview {
    DocumentDetailView(
        document: HealthDocument(
            fileName: "Blood Test Results - January 2024.pdf",
            fileType: .pdf,
            filePath: URL(fileURLWithPath: "/tmp/test.pdf"),
            processingStatus: .completed,
            fileSize: 1024000
        ),
        documentManager: DocumentManager.shared,
        documentProcessor: DocumentProcessor.shared
    )
}