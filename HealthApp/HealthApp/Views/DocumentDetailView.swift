import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct DocumentDetailView: View {
    let document: MedicalDocument
    @ObservedObject var documentManager: DocumentManager
    @ObservedObject var documentProcessor: DocumentProcessor
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingQuickLook = false
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingTagEditor = false
    @State private var showingNotesEditor = false
    @State private var showingImportReview = false
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
                    if !document.extractedHealthData.isEmpty {
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
        .sheet(isPresented: $showingImportReview) {
            if let review = documentProcessor.pendingImportReview,
               review.documentId == document.id {
                BloodTestImportReviewView(
                    importGroups: Binding(
                        get: { review.importGroups },
                        set: { _ in }
                    ),
                    onComplete: { selectedGroups in
                        Task {
                            await handleImportReviewComplete(review: review, selectedGroups: selectedGroups)
                            showingImportReview = false
                        }
                    }
                )
            }
        }
        .onChange(of: documentProcessor.pendingImportReview) { oldValue, newValue in
            // Show review sheet when pending review is set for this document
            if let review = newValue, review.documentId == document.id {
                showingImportReview = true
            } else if newValue == nil {
                showingImportReview = false
            }
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
                ForEach(Array(document.extractedHealthData.enumerated()), id: \.element.id) { index, data in
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
    
    // MARK: - Import Review Handler
    private func handleImportReviewComplete(review: PendingImportReview, selectedGroups: [BloodTestImportGroup]) async {
        print("✅ DocumentDetailView: User completed import review for \(selectedGroups.count) groups")
        
        // Update the blood test result with user's selections
        var updatedBloodTest = review.bloodTestResult
        
        // Create a map of selected candidates by standard key
        // Only include non-nil selections (nil means ignore)
        var selectedCandidatesByKey: [String: BloodTestImportCandidate] = [:]
        for group in selectedGroups {
            if let selectedId = group.selectedCandidateId,
               let selectedCandidate = group.candidates.first(where: { $0.id == selectedId }) {
                selectedCandidatesByKey[group.standardKey] = selectedCandidate
                print("📋 DocumentDetailView: User selected '\(selectedCandidate.originalTestName)' = \(selectedCandidate.value) for '\(group.standardTestName)'")
            } else {
                print("🚫 DocumentDetailView: User ignored group '\(group.standardTestName)'")
            }
        }
        
        // Reconstruct the results list based ONLY on selected candidates
        var updatedResults: [BloodTestItem] = []
        var processedKeys: Set<String> = []
        
        for (standardKey, selectedCandidate) in selectedCandidatesByKey {
             if let standardParam = BloodTestResult.standardizedLabParameters[standardKey] {
                
                var notes = selectedCandidate.originalTestName != standardParam.name ? "Original: \(selectedCandidate.originalTestName)" : nil
                if selectedCandidate.originalTestName.lowercased().contains("calc") {
                    notes = (notes == nil ? "" : notes! + "\n") + "Calculated"
                }

                let newItem = BloodTestItem(
                    name: standardParam.name,
                    value: selectedCandidate.value,
                    unit: selectedCandidate.unit ?? standardParam.unit,
                    referenceRange: selectedCandidate.referenceRange ?? standardParam.referenceRange,
                    isAbnormal: selectedCandidate.isAbnormal,
                    category: standardParam.category,
                    notes: notes,
                    confidence: selectedCandidate.confidence
                )
                updatedResults.append(newItem)
                processedKeys.insert(standardKey)
            }
        }
        
        updatedBloodTest.results = updatedResults
        
        // Remove pending review flag
        var metadata = updatedBloodTest.metadata ?? [:]
        metadata.removeValue(forKey: "pending_review")
        metadata["import_review_completed"] = "true"
        metadata["reviewed_groups_count"] = String(selectedGroups.count)
        metadata["imported_items_count"] = String(updatedResults.count)
        updatedBloodTest.metadata = metadata
        
        // Save the updated blood test
        do {
            try await healthDataManager.addBloodTest(updatedBloodTest)
            print("✅ DocumentDetailView: Saved blood test after import review with \(updatedResults.count) results")
            
            // Clear pending review
            await MainActor.run {
                documentProcessor.pendingImportReview = nil
            }
        } catch {
            print("❌ DocumentDetailView: Failed to save blood test after review: \(error)")
        }
    }
    
    private func findStandardKey(for testName: String) -> String? {
        // Try to find the standard key for this test name
        let normalized = testName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        // Direct match
        if BloodTestResult.standardizedLabParameters[normalized] != nil {
            return normalized
        }
        
        // Check if it matches any standard parameter name
        for (key, param) in BloodTestResult.standardizedLabParameters {
            if param.name.lowercased() == testName.lowercased() {
                return key
            }
        }
        
        // Partial match
        for (key, param) in BloodTestResult.standardizedLabParameters {
            let paramNameNormalized = param.name.lowercased().replacingOccurrences(of: " ", with: "_")
            if normalized.contains(paramNameNormalized) || paramNameNormalized.contains(normalized) {
                return key
            }
        }
        
        return nil
    }
    
    private var healthDataManager: HealthDataManager {
        HealthDataManager.shared
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
        private var tempFileURL: URL?

        init(_ parent: QuickLookView) {
            self.parent = parent
            super.init()
            prepareDecryptedFile()
        }

        deinit {
            // Clean up temporary file
            if let tempURL = tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        private func prepareDecryptedFile() {
            // Synchronously prepare the decrypted file
            do {
                // Check if file exists first
                let fileExists = FileManager.default.fileExists(atPath: parent.url.path)

                if !fileExists {
                    // Check for container ID mismatch
                    let currentAppDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let currentContainerPath = currentAppDocuments.path
                    let documentContainerPath = parent.url.path

                    if !documentContainerPath.hasPrefix(currentContainerPath.components(separatedBy: "/Documents").first ?? "") {
                        print("🔄 QuickLookView: Container migration detected - searching in current container...")

                        // Try to find the file in the current container
                        let currentHealthAppDir = currentAppDocuments.appendingPathComponent("HealthApp/Documents/Imported")
                        let fileName = parent.url.lastPathComponent
                        let possibleNewPath = currentHealthAppDir.appendingPathComponent(fileName)

                        if FileManager.default.fileExists(atPath: possibleNewPath.path) {
                            print("✅ QuickLookView: Found file in current container, decrypting for preview...")

                            // Decrypt the found file
                            let fileManager = FileSystemManager.shared
                            let decryptedData = try fileManager.retrieveDocument(from: possibleNewPath)

                            // Create temporary file for QuickLook
                            let tempDir = FileManager.default.temporaryDirectory
                            let originalFileName = possibleNewPath.lastPathComponent
                            let tempFileName = "quicklook_\(UUID().uuidString)_\(originalFileName)"
                            let tempURL = tempDir.appendingPathComponent(tempFileName)

                            // Write decrypted data to temp file
                            try decryptedData.write(to: tempURL)
                            self.tempFileURL = tempURL

                            print("✅ QuickLookView: Document preview ready")
                            return

                        } else {
                            // Try UUID-based matching as fallback
                            if let currentContents = try? FileManager.default.contentsOfDirectory(atPath: currentHealthAppDir.path) {
                                // Extract UUID from the original filename for matching
                                let pathComponents = parent.url.lastPathComponent.components(separatedBy: "_")
                                if let uuid = pathComponents.first {
                                    let matchingFiles = currentContents.filter { $0.contains(uuid) }
                                    if let match = matchingFiles.first {
                                        print("🎯 QuickLookView: Found file with matching UUID: \(match)")

                                        let matchPath = currentHealthAppDir.appendingPathComponent(match)
                                        if FileManager.default.fileExists(atPath: matchPath.path) {
                                            let fileManager = FileSystemManager.shared
                                            let decryptedData = try fileManager.retrieveDocument(from: matchPath)

                                            // Create temporary file for QuickLook
                                            let tempDir = FileManager.default.temporaryDirectory
                                            let tempFileName = "quicklook_\(UUID().uuidString)_\(match)"
                                            let tempURL = tempDir.appendingPathComponent(tempFileName)

                                            // Write decrypted data to temp file
                                            try decryptedData.write(to: tempURL)
                                            self.tempFileURL = tempURL

                                            print("✅ QuickLookView: Document preview ready from UUID match")
                                            return
                                        }
                                    }
                                }
                                print("❌ QuickLookView: No matching files found in current container (\(currentContents.count) files)")
                            } else {
                                print("❌ QuickLookView: Could not access current container directory")
                            }
                        }
                    }

                    // Final fallback: ensure directories exist and report error
                    do {
                        let fileManager = FileSystemManager.shared
                        try fileManager.ensureDirectoriesExist()
                    } catch {
                        print("❌ QuickLookView: Failed to recreate directories: \(error)")
                    }

                    throw FileSystemError.fileNotFound
                }

                // Decrypt the document (normal path - file exists at expected location)
                let fileManager = FileSystemManager.shared
                let decryptedData = try fileManager.retrieveDocument(from: parent.url)

                // Create temporary file for QuickLook
                let tempDir = FileManager.default.temporaryDirectory
                let originalFileName = parent.url.lastPathComponent
                let tempFileName = "quicklook_\(UUID().uuidString)_\(originalFileName)"
                let tempURL = tempDir.appendingPathComponent(tempFileName)

                // Write decrypted data to temp file
                try decryptedData.write(to: tempURL)
                self.tempFileURL = tempURL

                print("✅ QuickLookView: Document preview ready")

            } catch {
                print("❌ QuickLookView: Failed to decrypt document for preview: \(error)")
            }
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            // Use decrypted temp file if available, otherwise fall back to original (encrypted) URL
            return (tempFileURL ?? parent.url) as QLPreviewItem
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
    let document: MedicalDocument
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
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                        
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
    let document: MedicalDocument
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
        document: MedicalDocument(
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
