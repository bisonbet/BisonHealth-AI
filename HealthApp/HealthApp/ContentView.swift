import SwiftUI
import VisionKit
import PhotosUI

// Import all view components
// Note: These should be automatically available in the same module, 
// but explicit imports help with build issues

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
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
                
                // Placeholder sections for future data types
                PlaceholderSection(
                    title: "Imaging Reports",
                    icon: "camera.metering.matrix",
                    description: "X-rays, MRIs, CT scans, and other imaging results"
                )
                
                PlaceholderSection(
                    title: "Health Checkups",
                    icon: "stethoscope",
                    description: "Annual physicals and routine health examinations"
                )
            }
            .navigationTitle("Health Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Personal Info") {
                            showingPersonalInfoEditor = true
                        }
                        Button("Blood Test") {
                            showingBloodTestEntry = true
                        }
                        Divider()
                        Button("Imaging Report") {
                            // Placeholder for future implementation
                        }
                        .disabled(true)
                        Button("Health Checkup") {
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
                            print("📁 ContentView: Triggering document picker - LaunchServices errors will appear now")
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
                        
                        Button("Filter") {
                            showingFilterView = true
                        }
                        .font(.caption)
                    }
                    
                    Menu {
                        Button("Scan Document", systemImage: "camera.viewfinder") {
                            showingCamera = true
                        }
                        Button("Import File", systemImage: "folder") {
                            print("📁 ContentView: Import File button tapped - triggering document picker")
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
                    await documentManager.importScannedDocument(scan)
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
                    await documentManager.importDocuments(from: urls)
                    print("✅ ContentView: Document import process completed")
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
                    print("❌ ContentView: LaunchServices database permission error detected in file importer!")
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
                    // Convert PhotosPickerItem to PHPickerResult equivalent
                    // This is a simplified implementation
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
                            FilterChip(title: status.displayName) {
                                documentManager.filterStatus = nil
                            }
                        }
                        
                        if let type = documentManager.filterType {
                            FilterChip(title: type.rawValue.capitalized) {
                                documentManager.filterType = nil
                            }
                        }
                        
                        if documentManager.sortOrder != .dateDescending {
                            FilterChip(title: documentManager.sortOrder.displayName) {
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

struct FilterChip: View {
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
            HealthDataContextSelector(
                selectedTypes: $chatManager.selectedHealthDataTypes,
                onSave: { types in
                    chatManager.selectHealthDataForContext(types)
                }
            )
            .presentationDetents([.medium, .large])
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
