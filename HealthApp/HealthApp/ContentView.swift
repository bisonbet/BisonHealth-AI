import SwiftUI
import VisionKit
import PhotosUI

// Import all view components
// Note: These should be automatically available in the same module, 
// but explicit imports help with build issues

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                HealthDataView()
                    .tabItem {
                        Image(systemName: "heart.fill")
                        Text("Health Data")
                    }

                DocumentsView()
                    .tabItem {
                        Image(systemName: "doc.fill")
                        Text("Documents")
                    }

                ChatView()
                    .tabItem {
                        Image(systemName: "message.fill")
                        Text("AI Chat")
                    }

                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
            }
            .accentColor(.blue)

            // Global offline indicator
            VStack {
                OfflineIndicatorView()
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Health Data View
struct HealthDataView: View {
    @StateObject private var healthDataManager = HealthDataManager(
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared
    )
    @State private var showingPersonalInfoEditor = false
    @State private var showingBloodTestEntry = false
    @State private var editingBloodTest: BloodTestResult?
    
    var body: some View {
        NavigationStack {
            List {
                PersonalInfoSection(
                    personalInfo: healthDataManager.personalInfo,
                    onEdit: { showingPersonalInfoEditor = true }
                )
                
                BloodTestsSection(
                    bloodTests: $healthDataManager.bloodTests,
                    onAddNew: { showingBloodTestEntry = true },
                    onEdit: { editingBloodTest = $0 },
                    onDelete: { bloodTest in
                        Task {
                            try await healthDataManager.deleteBloodTest(bloodTest)
                        }
                    }
                )
                
                // Imaging Reports Section
                ImagingReportsSection(
                    imagingReports: $healthDataManager.imagingReports,
                    onDocumentTap: { _ in }
                )
                
                // Medical Visits Section
                HealthCheckupsSection(
                    healthCheckups: $healthDataManager.healthCheckups,
                    onDocumentTap: { _ in }
                )
            }
            .navigationTitle("Health Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Personal Info") {
                            showingPersonalInfoEditor = true
                        }
                        Button("Lab Results") {
                            showingBloodTestEntry = true
                        }
                        Divider()
                        Button("Imaging Report") {
                            // Placeholder for future implementation
                        }
                        .disabled(true)
                        Button("Medical Visit") {
                            // Placeholder for future implementation
                        }
                        .disabled(true)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await healthDataManager.loadHealthData()
            }
            .sheet(isPresented: $showingPersonalInfoEditor) {
                PersonalInfoEditorView(
                    personalInfo: healthDataManager.personalInfo,
                    onSave: { info in
                        Task {
                            try await healthDataManager.savePersonalInfo(info)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingBloodTestEntry) {
                BloodTestEntryView(
                    onSave: { bloodTest in
                        Task {
                            try await healthDataManager.addBloodTest(bloodTest)
                        }
                    }
                )
            }
            .sheet(item: $editingBloodTest) { bloodTest in
                BloodTestEntryView(bloodTest: bloodTest) { updated in
                    Task {
                        try await healthDataManager.updateBloodTest(updated)
                    }
                }
            }
        }
    }
}

// MARK: - Documents View
struct DocumentsView: View {
    @StateObject private var documentManager = DocumentManager(
        documentImporter: DocumentImporter.shared,
        documentProcessor: DocumentProcessor.shared,
        databaseManager: DatabaseManager.shared,
        fileSystemManager: FileSystemManager.shared
    )
    @StateObject private var documentProcessor = DocumentProcessor.shared

    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var showingFilterView = false
    @State private var showingBatchProcessing = false
    @State private var showingDocumentDetail = false
    @State private var selectedDocument: HealthDocument?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var viewMode: DocumentViewMode = .list
    @State private var showingDocumentTypeSelector = false
    @State private var pendingDocumentForCategory: HealthDocument?
    @State private var showingDuplicateReview = false
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if documentManager.documents.isEmpty {
                    DocumentsEmptyStateView(
                        onScanDocument: { 
                            print("📷 ContentView: Showing camera for document scanning")
                            showingCamera = true 
                        },
                        onImportFile: {
                            print("📁 ContentView: Triggering document picker (LaunchServices console errors are normal in development)")
                            showingDocumentPicker = true
                        },
                        onImportPhotos: { 
                            print("🖼️ ContentView: Showing photos picker")
                            showingPhotosPicker = true 
                        }
                    )
                } else {
                    VStack(spacing: 0) {
                        // Search and filter bar
                        if !documentManager.documents.isEmpty {
                            searchAndFilterBar
                        }
                        
                        // Processing progress bar
                        if documentProcessor.isProcessing {
                            processingProgressBar
                        }
                        
                        // Document content
                        documentContent

                        // Backup info footer
                        backupInfoFooter
                    }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if !documentManager.documents.isEmpty {
                        HStack {
                            EditButton()
                            
                            if editMode?.wrappedValue.isEditing == true && !documentManager.selectedDocuments.isEmpty {
                                Button("Batch") {
                                    showingBatchProcessing = true
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !documentManager.documents.isEmpty {
                        // View mode toggle (iPad only)
                        if isIPad {
                            Picker("View Mode", selection: $viewMode) {
                                Image(systemName: "list.bullet").tag(DocumentViewMode.list)
                                Image(systemName: "square.grid.2x2").tag(DocumentViewMode.grid)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                    }
                    
                    Menu {
                        Button("Scan Document", systemImage: "camera.viewfinder") {
                            showingCamera = true
                        }
                        Button("Import File", systemImage: "folder") {
                            print("📁 ContentView: Import File button tapped (LaunchServices console errors are normal)")
                            showingDocumentPicker = true
                        }
                        Button("Import Photos", systemImage: "photo.on.rectangle") {
                            showingPhotosPicker = true
                        }
                        
                        if !documentManager.documents.isEmpty {
                            Divider()
                            
                            Button("Process All Pending", systemImage: "gearshape.2") {
                                Task {
                                    await documentManager.processAllPendingDocuments()
                                }
                            }
                            
                            Button("Retry Failed", systemImage: "arrow.clockwise") {
                                Task {
                                    await documentManager.retryFailedDocuments()
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await documentManager.refreshDocuments()
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentCameraView { scan in
                Task {
                    if let document = await documentManager.importScannedDocument(scan) {
                        pendingDocumentForCategory = document
                        showingDocumentTypeSelector = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .image],
            allowsMultipleSelection: true
        ) { result in
            print("📁 ContentView: File importer result received")
            
            switch result {
            case .success(let urls):
                print("✅ ContentView: File importer successful, \(urls.count) URLs received")
                for (index, url) in urls.enumerated() {
                    print("📄 ContentView: URL \(index + 1): \(url)")
                }
                
                Task {
                    print("🚀 ContentView: Starting document import process...")
                    let importedDocs = await documentManager.importDocuments(from: urls)
                    print("✅ ContentView: Document import process completed")
                    
                    // Show category selector for first document
                    if let firstDoc = importedDocs.first {
                        pendingDocumentForCategory = firstDoc
                        showingDocumentTypeSelector = true
                    }
                }
                
            case .failure(let error):
                print("❌ ContentView: File import failed with error: \(error)")
                print("❌ ContentView: Error type: \(type(of: error))")
                print("❌ ContentView: Error description: \(error.localizedDescription)")
                
                // Check for LaunchServices errors
                if error.localizedDescription.contains("OSStatusErrorDomain Code=-54") ||
                   error.localizedDescription.contains("database") ||
                   error.localizedDescription.contains("LaunchServices") ||
                   error.localizedDescription.contains("permission") {
                    print("ℹ️ ContentView: LaunchServices error detected (normal in development/simulator environment)")
                    print("ℹ️ ContentView: This error doesn't affect document import functionality")
                } else {
                    print("❌ ContentView: Unexpected file import error that may need attention")
                }
            }
        }
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, photos in
            if !photos.isEmpty {
                Task {
                    var importedDocs: [HealthDocument] = []
                    
                    for photo in photos {
                        if let data = try? await photo.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            do {
                                let doc = try await DocumentImporter.shared.importImage(image)
                                importedDocs.append(doc)
                            } catch {
                                print("Failed to import photo: \(error)")
                            }
                        }
                    }
                    
                    // Add to document manager
                    documentManager.documents.append(contentsOf: importedDocs)
                    documentManager.documents.sort { $0.importedAt > $1.importedAt }
                    
                    // Show category selector for first document
                    if let firstDoc = importedDocs.first {
                        pendingDocumentForCategory = firstDoc
                        showingDocumentTypeSelector = true
                    }
                    
                    selectedPhotos = []
                }
            }
        }
        .sheet(isPresented: $showingFilterView) {
            DocumentFilterView(documentManager: documentManager)
        }
        .sheet(isPresented: $showingBatchProcessing) {
            BatchProcessingView(
                documentManager: documentManager,
                documentProcessor: documentProcessor
            )
        }
        .sheet(item: $selectedDocument) { document in
            DocumentDetailView(
                document: document,
                documentManager: documentManager,
                documentProcessor: documentProcessor
            )
        }
        .sheet(isPresented: $showingDuplicateReview) {
            if let review = documentProcessor.pendingDuplicateReview {
                DuplicateBloodTestReviewView(
                    duplicateGroups: Binding(
                        get: { review.duplicateGroups },
                        set: { _ in }
                    ),
                    onComplete: { selectedGroups in
                        Task {
                            await handleDuplicateReviewComplete(review: review, selectedGroups: selectedGroups)
                            showingDuplicateReview = false
                        }
                    }
                )
            }
        }
        .onChange(of: documentProcessor.pendingDuplicateReview) { oldValue, newValue in
            // Show review sheet when pending review is set
            if newValue != nil {
                showingDuplicateReview = true
            } else {
                showingDuplicateReview = false
            }
        }
        .sheet(isPresented: $showingDocumentTypeSelector) {
            if let document = pendingDocumentForCategory {
                DocumentTypeSelectorView(
                    fileName: document.fileName,
                    selectedCategory: Binding(
                        get: { document.documentCategory },
                        set: { _ in }
                    ),
                    onConfirm: { category in
                        Task {
                            await documentManager.setDocumentCategoryAndProcess(document.id, category: category)
                            pendingDocumentForCategory = nil
                        }
                    }
                )
            }
        }

    }
    
    // MARK: - Duplicate Review Handler
    private func handleDuplicateReviewComplete(review: PendingDuplicateReview, selectedGroups: [DuplicateTestGroup]) async {
        print("✅ DocumentsView: User completed duplicate review for \(selectedGroups.count) groups")
        
        // Update the blood test result with user's selections
        var updatedBloodTest = review.bloodTestResult
        
        // Create a map of selected candidates by standard key
        var selectedCandidatesByKey: [String: DuplicateBloodTestCandidate] = [:]
        for group in selectedGroups {
            if let selectedId = group.selectedCandidateId,
               let selectedCandidate = group.candidates.first(where: { $0.id == selectedId }) {
                selectedCandidatesByKey[group.standardKey] = selectedCandidate
                print("📋 DocumentsView: User selected '\(selectedCandidate.originalTestName)' = \(selectedCandidate.value) for '\(group.standardTestName)'")
            }
        }
        
        // Update blood test items - replace items that match duplicate groups
        var updatedResults: [BloodTestItem] = []
        var processedKeys: Set<String> = []
        
        for item in updatedBloodTest.results {
            // Try to find matching duplicate group by standard key
            if let standardKey = findStandardKey(for: item.name),
               let selectedCandidate = selectedCandidatesByKey[standardKey],
               !processedKeys.contains(standardKey) {
                // Replace with user's selected value
                var updatedItem = item
                updatedItem.value = selectedCandidate.value
                updatedItem.unit = selectedCandidate.unit ?? item.unit
                updatedItem.referenceRange = selectedCandidate.referenceRange ?? item.referenceRange
                updatedItem.isAbnormal = selectedCandidate.isAbnormal
                if selectedCandidate.originalTestName != item.name {
                    updatedItem.notes = (updatedItem.notes ?? "") + (updatedItem.notes != nil ? "\n" : "") + "Original: \(selectedCandidate.originalTestName)"
                }
                updatedResults.append(updatedItem)
                processedKeys.insert(standardKey)
                print("✅ DocumentsView: Updated '\(item.name)' with selected value: \(selectedCandidate.value) \(selectedCandidate.unit ?? "")")
            } else {
                // Keep original value (not in duplicate groups or already processed)
                updatedResults.append(item)
            }
        }
        
        // Add any selected candidates that weren't in the original results
        for (standardKey, selectedCandidate) in selectedCandidatesByKey {
            if !processedKeys.contains(standardKey) {
                // This is a new item from duplicates
                if let standardParam = BloodTestResult.standardizedLabParameters[standardKey] {
                    let newItem = BloodTestItem(
                        name: standardParam.name,
                        value: selectedCandidate.value,
                        unit: selectedCandidate.unit ?? standardParam.unit,
                        referenceRange: selectedCandidate.referenceRange ?? standardParam.referenceRange,
                        isAbnormal: selectedCandidate.isAbnormal,
                        category: standardParam.category,
                        notes: "Original: \(selectedCandidate.originalTestName)"
                    )
                    updatedResults.append(newItem)
                    print("✅ DocumentsView: Added new item '\(standardParam.name)' = \(selectedCandidate.value)")
                }
            }
        }
        
        updatedBloodTest.results = updatedResults
        
        // Remove pending review flag
        var metadata = updatedBloodTest.metadata ?? [:]
        metadata.removeValue(forKey: "pending_review")
        metadata["duplicate_review_completed"] = "true"
        metadata["reviewed_groups_count"] = String(selectedGroups.count)
        updatedBloodTest.metadata = metadata
        
        // Save the updated blood test
        do {
            let healthDataManager = HealthDataManager.shared
            try await healthDataManager.addBloodTest(updatedBloodTest)
            print("✅ DocumentsView: Saved blood test after duplicate review with \(updatedResults.count) results")
            
            // Clear pending review
            await MainActor.run {
                documentProcessor.pendingDuplicateReview = nil
            }
        } catch {
            print("❌ DocumentsView: Failed to save blood test after review: \(error)")
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
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack {
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
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                Button("Filter") {
                    showingFilterView = true
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(hasActiveFilters ? Color.blue : Color(.systemGray6))
                .foregroundColor(hasActiveFilters ? .white : .blue)
                .cornerRadius(8)
            }
            
            // Active filters display
            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let status = documentManager.filterStatus {
                            ActiveFilterChip(title: status.displayName) {
                                documentManager.filterStatus = nil
                            }
                        }
                        
                        if let type = documentManager.filterType {
                            ActiveFilterChip(title: type.rawValue.capitalized) {
                                documentManager.filterType = nil
                            }
                        }
                        
                        if documentManager.sortOrder != .dateDescending {
                            ActiveFilterChip(title: documentManager.sortOrder.displayName) {
                                documentManager.sortOrder = .dateDescending
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Processing Progress Bar
    
    private var processingProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Processing documents...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(documentProcessor.processingProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: documentProcessor.processingProgress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Document Content
    
    @ViewBuilder
    private var documentContent: some View {
        switch viewMode {
        case .list:
            DocumentListView(
                documents: documentManager.filteredDocuments,
                selectedDocuments: $documentManager.selectedDocuments,
                onDocumentTap: { document in
                    selectedDocument = document
                }
            )
        case .grid:
            DocumentGridView(
                documents: documentManager.filteredDocuments,
                selectedDocuments: $documentManager.selectedDocuments,
                onDocumentTap: { document in
                    selectedDocument = document
                }
            )
        }
    }
    
    // MARK: - Backup Info Footer

    private var backupInfoFooter: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.horizontal)

            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "icloud")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(backupStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                if let totalSize = calculateTotalDocumentsSize(), totalSize > 0 {
                    HStack {
                        Text("Documents size:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if SettingsManager.shared.backupSettings.backupDocuments {
                            Text("Included in backup")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else {
                            Text("Not backed up")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Helper Properties

    private var hasActiveFilters: Bool {
        documentManager.filterStatus != nil ||
        documentManager.filterType != nil ||
        documentManager.sortOrder != .dateDescending ||
        !documentManager.searchText.isEmpty
    }

    private var backupStatusText: String {
        if !SettingsManager.shared.backupSettings.iCloudEnabled {
            return "iCloud backup is disabled"
        } else if SettingsManager.shared.backupSettings.backupDocuments {
            return "Documents will be backed up to iCloud"
        } else {
            return "Documents backup is disabled"
        }
    }

    private func calculateTotalDocumentsSize() -> Int64? {
        guard !documentManager.documents.isEmpty else { return nil }

        var totalSize: Int64 = 0
        for document in documentManager.documents {
            totalSize += document.fileSize
        }

        return totalSize > 0 ? totalSize : nil
    }
}

// MARK: - Supporting Types and Views

enum DocumentViewMode {
    case list
    case grid
}

struct ActiveFilterChip: View {
    let title: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}

// MARK: - Chat View
struct ChatView: View {
    @StateObject private var chatManager = AIChatManager(
        healthDataManager: HealthDataManager.shared,
        databaseManager: DatabaseManager.shared
    )
    @State private var showingContextSelector = false
    @State private var showingConversationList = false
    @State private var searchText = ""
    @State private var selectedConversationId: UUID?
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var shouldUseSplitView: Bool {
        isIPad && verticalSizeClass == .regular
    }
    
    var body: some View {
        Group {
            if shouldUseSplitView {
                iPadSplitView
            } else {
                iPhoneView
            }
        }
        .sheet(isPresented: $showingContextSelector) {
            UnifiedContextSelectorView(chatManager: chatManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await chatManager.loadConversations()
            // Skip automatic connection test on startup to avoid console noise
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)) { _ in
            // Handle keyboard appearance for iPad
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)) { _ in
            // Handle keyboard dismissal for iPad
        }
    }
    
    // MARK: - iPad Split View
    private var iPadSplitView: some View {
        NavigationSplitView {
            // Sidebar with conversations
            ConversationSidebarView(
                conversations: chatManager.conversations,
                selectedConversationId: $selectedConversationId,
                searchText: $searchText,
                onSelectConversation: { conversation in
                    chatManager.selectConversation(conversation)
                    selectedConversationId = conversation.id
                },
                onNewConversation: {
                    Task {
                        let conversation = try await chatManager.startNewConversation()
                        selectedConversationId = conversation.id
                    }
                },
                onDeleteConversation: { conversation in
                    Task {
                        try await chatManager.deleteConversation(conversation)
                        if selectedConversationId == conversation.id {
                            selectedConversationId = nil
                        }
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
        } detail: {
            // Main chat interface
            ChatDetailView(
                chatManager: chatManager,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    // MARK: - iPhone View
    private var iPhoneView: some View {
        NavigationStack {
            ChatDetailView(
                chatManager: chatManager,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button("Conversations") {
                            showingConversationList = true
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Chat") {
                            Task {
                                _ = try await chatManager.startNewConversation()
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingConversationList) {
                    ConversationListView(
                        conversations: chatManager.conversations,
                        onSelectConversation: { conversation in
                            chatManager.selectConversation(conversation)
                            showingConversationList = false
                        },
                        onDeleteConversation: { conversation in
                            Task {
                                try await chatManager.deleteConversation(conversation)
                                if chatManager.currentConversation?.id == conversation.id {
                                    chatManager.currentConversation = nil
                                }
                            }
                        }
                    )
                }
        }
    }
}


#Preview {
    ContentView()
        .environmentObject(AppState())
}
