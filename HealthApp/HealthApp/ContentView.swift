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
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
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
                    DocumentListView(
                        documents: documentManager.filteredDocuments,
                        selectedDocuments: $documentManager.selectedDocuments,
                        onDocumentTap: { document in
                            // Navigate to document detail view
                        }
                    )
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if !documentManager.documents.isEmpty {
                        EditButton()
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !documentManager.selectedDocuments.isEmpty {
                        Button("Process") {
                            Task {
                                await documentManager.processSelectedDocuments()
                            }
                        }
                    }
                    
                    Menu {
                        Button("Scan Document") {
                            showingCamera = true
                        }
                        Button("Import File") {
                            showingDocumentPicker = true
                        }
                        Button("Import Photos") {
                            showingPhotosPicker = true
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
        .onChange(of: selectedPhotos) { photos in
            if !photos.isEmpty {
                Task {
                    // Convert PhotosPickerItem to PHPickerResult equivalent
                    // This is a simplified implementation
                    selectedPhotos = []
                }
            }
        }
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
    
    var body: some View {
        NavigationStack {
            VStack {
                if let conversation = chatManager.currentConversation {
                    // Connection status indicator
                    if !chatManager.isConnected {
                        ConnectionStatusBanner(
                            isOffline: chatManager.isOffline,
                            onRetry: {
                                Task {
                                    await chatManager.checkConnection()
                                }
                            }
                        )
                    }
                    
                    // Messages list
                    MessageListView(
                        messages: conversation.messages,
                        isLoading: chatManager.isLoading
                    )
                    
                    // Message input
                    MessageInputView(
                        text: $messageText,
                        isEnabled: chatManager.isConnected && !chatManager.isOffline,
                        onSend: {
                            Task {
                                try await chatManager.sendMessage(messageText)
                                messageText = ""
                            }
                        }
                    )
                } else {
                    ChatEmptyStateView(
                        onStartNewChat: {
                            Task {
                                _ = try await chatManager.startNewConversation()
                            }
                        }
                    )
                }
            }
            .navigationTitle("Bison Health")
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
        }
        .sheet(isPresented: $showingContextSelector) {
            HealthDataContextSelector(
                selectedTypes: $chatManager.selectedHealthDataTypes,
                onSave: { types in
                    chatManager.selectHealthDataForContext(types)
                }
            )
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
        .task {
            await chatManager.loadConversations()
            await chatManager.checkConnection()
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var ollamaHostname = "localhost"
    @State private var ollamaPort = "11434"
    @State private var doclingHostname = "localhost"
    @State private var doclingPort = "8080"
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
                            TextField("8080", text: $doclingPort)
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
                let client = DoclingClient(hostname: doclingHostname, port: Int(doclingPort) ?? 8080)
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