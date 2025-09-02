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
    
    var body: some View {
        NavigationStack {
            List {
                PersonalInfoSection(
                    personalInfo: healthDataManager.personalInfo,
                    onEdit: { showingPersonalInfoEditor = true }
                )
                
                BloodTestsSection(
                    bloodTests: healthDataManager.bloodTests,
                    onAddNew: { showingBloodTestEntry = true }
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
        }
        .task {
            await healthDataManager.loadHealthData()
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
                        onScanDocument: { showingCamera = true },
                        onImportFile: { showingDocumentPicker = true },
                        onImportPhotos: { showingPhotosPicker = true }
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
            switch result {
            case .success(let urls):
                Task {
                    await documentManager.importDocuments(from: urls)
                }
            case .failure(let error):
                print("File import failed: \(error)")
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
    
    // MARK: - Helper Properties
    
    private var hasActiveFilters: Bool {
        documentManager.filterStatus != nil ||
        documentManager.filterType != nil ||
        documentManager.sortOrder != .dateDescending ||
        !documentManager.searchText.isEmpty
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
        ollamaClient: OllamaClient.shared,
        healthDataManager: HealthDataManager.shared,
        databaseManager: DatabaseManager.shared
    )
    @State private var messageText = ""
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
        }
        .task {
            await chatManager.loadConversations()
            await chatManager.checkConnection()
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
                messageText: $messageText,
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
                messageText: $messageText,
                showingContextSelector: $showingContextSelector,
                isIPad: isIPad
            )
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button("Conversations") {
                            showingConversationList = true
                        }
                        
                        if chatManager.currentConversation != nil {
                            Button("Context") {
                                showingContextSelector = true
                            }
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
                        }
                    )
                }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var ollamaHostname = "localhost"
    @State private var ollamaPort = "11434"
    @State private var doclingHostname = "localhost"
    @State private var doclingPort = "5001"
    @State private var iCloudBackupEnabled = false
    @State private var backupHealthData = true
    @State private var backupChatHistory = true
    @State private var backupDocuments = false
    @State private var showingConnectionTest = false
    @State private var connectionTestResult: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("AI Services") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ollama Server")
                            .font(.headline)
                        
                        HStack {
                            Text("Hostname:")
                            TextField("localhost", text: $ollamaHostname)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Text("Port:")
                            TextField("11434", text: $ollamaPort)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        Button("Test Connection") {
                            testOllamaConnection()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Docling Server")
                            .font(.headline)
                        
                        HStack {
                            Text("Hostname:")
                            TextField("localhost", text: $doclingHostname)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Text("Port:")
                            TextField("5001", text: $doclingPort)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        Button("Test Connection") {
                            testDoclingConnection()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("iCloud Backup") {
                    Toggle("Enable iCloud Backup", isOn: $iCloudBackupEnabled)
                    
                    if iCloudBackupEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Backup Options")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Toggle("Health Data", isOn: $backupHealthData)
                            Toggle("Chat History", isOn: $backupChatHistory)
                            Toggle("Documents", isOn: $backupDocuments)
                        }
                    }
                }
                
                Section("Data Management") {
                    NavigationLink("Export Health Data") {
                        DataExportView()
                    }
                    
                    NavigationLink("Storage Usage") {
                        StorageUsageView()
                    }
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .foregroundColor(.orange)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("Privacy Policy") {
                        PrivacyPolicyView()
                    }
                    
                    NavigationLink("Terms of Service") {
                        TermsOfServiceView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .alert("Connection Test", isPresented: $showingConnectionTest) {
            Button("OK") { }
        } message: {
            Text(connectionTestResult ?? "")
        }
    }
    
    private func testOllamaConnection() {
        Task {
            do {
                let client = OllamaClient(hostname: ollamaHostname, port: Int(ollamaPort) ?? 11434)
                let isConnected = try await client.testConnection()
                connectionTestResult = isConnected ? "Successfully connected to Ollama server" : "Failed to connect to Ollama server"
            } catch {
                connectionTestResult = "Connection failed: \(error.localizedDescription)"
            }
            showingConnectionTest = true
        }
    }
    
    private func testDoclingConnection() {
        Task {
            do {
                let client = DoclingClient(hostname: doclingHostname, port: Int(doclingPort) ?? 5001)
                let isConnected = try await client.testConnection()
                connectionTestResult = isConnected ? "Successfully connected to Docling server" : "Failed to connect to Docling server"
            } catch {
                connectionTestResult = "Connection failed: \(error.localizedDescription)"
            }
            showingConnectionTest = true
        }
    }
    
    private func clearCache() {
        // Implement cache clearing logic
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}