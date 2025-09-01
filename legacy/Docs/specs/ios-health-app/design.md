# Design Document

## Overview

The iOS Health Data Management App is a SwiftUI-based application that provides secure, local storage and AI-powered analysis of personal health information. The app follows a privacy-first approach, storing all sensitive data locally on the device with optional iCloud backup. It integrates with external AI services (Ollama for LLM, Docling for document processing) while maintaining data sovereignty.

The architecture emphasizes modularity, testability, and extensibility to support future enhancements including additional AI providers and health data types. The design follows Apple's Human Interface Guidelines and supports comprehensive accessibility features.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS Health App                           │
├─────────────────────────────────────────────────────────────┤
│  SwiftUI Views & ViewModels (MVVM Pattern)                 │
├─────────────────────────────────────────────────────────────┤
│  Business Logic Layer                                       │
│  ├── Health Data Manager                                    │
│  ├── Document Processor                                     │
│  ├── AI Chat Manager                                        │
│  └── Export Manager                                         │
├─────────────────────────────────────────────────────────────┤
│  Data Access Layer                                          │
│  ├── SQLite Database Manager                                │
│  ├── File System Manager                                    │
│  └── iCloud Backup Manager                                  │
├─────────────────────────────────────────────────────────────┤
│  External Service Layer                                     │
│  ├── Ollama Client                                          │
│  ├── Docling Client                                         │
│  └── Future AI Provider Interface                           │
├─────────────────────────────────────────────────────────────┤
│  Device Integration Layer                                   │
│  ├── Camera & Document Scanner                              │
│  ├── Files App Integration                                  │
│  └── iOS System Services                                    │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

- **UI Framework**: SwiftUI (iOS 17+)
- **Architecture Pattern**: MVVM (Model-View-ViewModel)
- **Database**: SQLite with SQLite.swift wrapper
- **Document Scanning**: VisionKit + Custom document processing
- **Networking**: URLSession with async/await
- **Encryption**: CryptoKit for local data encryption
- **File Management**: FileManager with iCloud integration
- **Dependency Injection**: Custom lightweight DI container

## Components and Interfaces

### Core Data Models

#### Health Data Models
```swift
// Base health data protocol
protocol HealthDataProtocol {
    var id: UUID { get }
    var type: HealthDataType { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var metadata: [String: Any]? { get }
}

// Personal information model
struct PersonalHealthInfo: HealthDataProtocol {
    let id: UUID
    let type: HealthDataType = .personalInfo
    var name: String?
    var dateOfBirth: Date?
    var gender: Gender?
    var height: Measurement<UnitLength>?
    var weight: Measurement<UnitMass>?
    var bloodType: BloodType?
    var allergies: [String]
    var medications: [Medication]
    var medicalHistory: [MedicalCondition]
    var emergencyContacts: [EmergencyContact]
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: Any]?
}

// Blood test results model
struct BloodTestResult: HealthDataProtocol {
    let id: UUID
    let type: HealthDataType = .bloodTest
    var testDate: Date
    var laboratoryName: String?
    var results: [BloodTestItem]
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: Any]?
}

// Individual blood test item
struct BloodTestItem {
    let name: String
    let value: String
    let unit: String?
    let referenceRange: String?
    let isAbnormal: Bool
}

// Future placeholder models
struct ImagingReport: HealthDataProtocol {
    // Placeholder for future implementation
    let id: UUID
    let type: HealthDataType = .imagingReport
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: Any]?
}

struct HealthCheckup: HealthDataProtocol {
    // Placeholder for future implementation
    let id: UUID
    let type: HealthDataType = .healthCheckup
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: Any]?
}
```

#### Document and Chat Models
```swift
// Document model for imported files
struct HealthDocument {
    let id: UUID
    let fileName: String
    let fileType: DocumentType
    let filePath: URL
    let thumbnailPath: URL?
    var processingStatus: ProcessingStatus
    var extractedData: [HealthDataProtocol]
    let importedAt: Date
    var processedAt: Date?
    var fileSize: Int64
}

// Chat conversation model
struct ChatConversation {
    let id: UUID
    let title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var includedHealthDataTypes: Set<HealthDataType>
}

struct ChatMessage {
    let id: UUID
    let content: String
    let role: MessageRole
    let timestamp: Date
    var metadata: [String: Any]?
}

enum MessageRole {
    case user
    case assistant
}
```

### Database Layer

#### SQLite Database Manager
```swift
class DatabaseManager: ObservableObject {
    private let db: Connection
    private let encryptionKey: SymmetricKey
    
    // Table definitions
    private let healthDataTable = Table("health_data")
    private let documentsTable = Table("documents")
    private let chatConversationsTable = Table("chat_conversations")
    private let chatMessagesTable = Table("chat_messages")
    
    init() throws {
        // Initialize SQLite connection with encryption
        // Create tables if they don't exist
        // Set up database schema
    }
    
    // CRUD operations for health data
    func save<T: HealthDataProtocol>(_ data: T) async throws
    func fetch<T: HealthDataProtocol>(_ type: T.Type) async throws -> [T]
    func update<T: HealthDataProtocol>(_ data: T) async throws
    func delete<T: HealthDataProtocol>(_ data: T) async throws
    
    // Document operations
    func saveDocument(_ document: HealthDocument) async throws
    func fetchDocuments() async throws -> [HealthDocument]
    func updateDocumentStatus(_ documentId: UUID, status: ProcessingStatus) async throws
    
    // Chat operations
    func saveConversation(_ conversation: ChatConversation) async throws
    func fetchConversations() async throws -> [ChatConversation]
    func addMessage(to conversationId: UUID, message: ChatMessage) async throws
}
```

### Business Logic Layer

#### Health Data Manager
```swift
@MainActor
class HealthDataManager: ObservableObject {
    @Published var personalInfo: PersonalHealthInfo?
    @Published var bloodTests: [BloodTestResult] = []
    @Published var documents: [HealthDocument] = []
    
    private let databaseManager: DatabaseManager
    private let fileManager: FileSystemManager
    
    init(databaseManager: DatabaseManager, fileManager: FileSystemManager) {
        self.databaseManager = databaseManager
        self.fileManager = fileManager
    }
    
    // Health data operations
    func loadHealthData() async throws
    func savePersonalInfo(_ info: PersonalHealthInfo) async throws
    func addBloodTest(_ result: BloodTestResult) async throws
    func updateHealthData<T: HealthDataProtocol>(_ data: T) async throws
    func deleteHealthData<T: HealthDataProtocol>(_ data: T) async throws
    
    // Document operations
    func importDocument(from url: URL) async throws -> HealthDocument
    func importFromCamera(_ image: UIImage) async throws -> HealthDocument
    func processDocument(_ document: HealthDocument, immediately: Bool = false) async throws
}
```

#### AI Chat Manager
```swift
@MainActor
class AIChatManager: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var currentConversation: ChatConversation?
    @Published var isConnected: Bool = false
    
    private let ollamaClient: OllamaClient
    private let healthDataManager: HealthDataManager
    private let databaseManager: DatabaseManager
    
    init(ollamaClient: OllamaClient, healthDataManager: HealthDataManager, databaseManager: DatabaseManager) {
        self.ollamaClient = ollamaClient
        self.healthDataManager = healthDataManager
        self.databaseManager = databaseManager
    }
    
    func startNewConversation(title: String) async throws -> ChatConversation
    func sendMessage(_ content: String, to conversation: ChatConversation) async throws
    func loadConversations() async throws
    func selectHealthDataForContext(_ types: Set<HealthDataType>) async
    private func buildHealthDataContext() -> String
}
```

### External Service Layer

#### Ollama Client
```swift
class OllamaClient {
    private let baseURL: URL
    private let session: URLSession
    // TODO: Add authentication properties when needed
    
    init(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")!
        self.session = URLSession.shared
    }
    
    func testConnection() async throws -> Bool
    func sendChatMessage(_ message: String, context: String) async throws -> String
    func getAvailableModels() async throws -> [String]
    
    // Placeholder for future authentication
    // func authenticate(credentials: AuthCredentials) async throws
}
```

#### Docling Client
```swift
class DoclingClient {
    private let baseURL: URL
    private let session: URLSession
    // TODO: Add authentication properties when needed
    
    init(hostname: String, port: Int) {
        self.baseURL = URL(string: "http://\(hostname):\(port)")!
        self.session = URLSession.shared
    }
    
    func testConnection() async throws -> Bool
    func processDocument(_ document: Data, type: DocumentType) async throws -> ProcessedDocumentResult
    func getProcessingStatus(_ jobId: String) async throws -> ProcessingStatus
    
    // Placeholder for future authentication
    // func authenticate(credentials: AuthCredentials) async throws
}

struct ProcessedDocumentResult {
    let extractedText: String
    let structuredData: [String: Any]
    let confidence: Double
    let processingTime: TimeInterval
}
```

### User Interface Layer

#### Main App Structure
```swift
@main
struct HealthApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}

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
    }
}
```

#### Key View Components
```swift
// Health data entry and display
struct HealthDataView: View {
    @StateObject private var healthDataManager: HealthDataManager
    @State private var showingPersonalInfoEditor = false
    @State private var showingBloodTestEntry = false
    
    var body: some View {
        NavigationView {
            List {
                PersonalInfoSection(personalInfo: healthDataManager.personalInfo)
                BloodTestsSection(bloodTests: healthDataManager.bloodTests)
                // Placeholder sections for future data types
                PlaceholderSection(title: "Imaging Reports", icon: "xray")
                PlaceholderSection(title: "Health Checkups", icon: "stethoscope")
            }
            .navigationTitle("Health Data")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Personal Info") { showingPersonalInfoEditor = true }
                        Button("Blood Test") { showingBloodTestEntry = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// Document import and management
struct DocumentsView: View {
    @StateObject private var healthDataManager: HealthDataManager
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    
    var body: some View {
        NavigationView {
            List(healthDataManager.documents) { document in
                DocumentRowView(document: document)
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Scan Document") { showingCamera = true }
                        Button("Import File") { showingDocumentPicker = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// AI chat interface
struct ChatView: View {
    @StateObject private var chatManager: AIChatManager
    @State private var messageText = ""
    @State private var showingContextSelector = false
    
    var body: some View {
        NavigationView {
            VStack {
                if let conversation = chatManager.currentConversation {
                    MessageListView(messages: conversation.messages)
                    MessageInputView(text: $messageText, onSend: sendMessage)
                } else {
                    EmptyStateView(title: "No Conversation", 
                                 subtitle: "Start a new conversation with your AI health assistant")
                }
            }
            .navigationTitle("AI Assistant")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Context") { showingContextSelector = true }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New Chat") { startNewConversation() }
                }
            }
        }
    }
}
```

## Data Models

### Database Schema

#### Health Data Table
```sql
CREATE TABLE health_data (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    encrypted_data BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    metadata TEXT
);

CREATE INDEX idx_health_data_type ON health_data(type);
CREATE INDEX idx_health_data_created ON health_data(created_at);
```

#### Documents Table
```sql
CREATE TABLE documents (
    id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    thumbnail_path TEXT,
    processing_status TEXT NOT NULL,
    imported_at INTEGER NOT NULL,
    processed_at INTEGER,
    file_size INTEGER NOT NULL
);

CREATE INDEX idx_documents_status ON documents(processing_status);
CREATE INDEX idx_documents_imported ON documents(imported_at);
```

#### Chat Tables
```sql
CREATE TABLE chat_conversations (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    included_health_data_types TEXT
);

CREATE TABLE chat_messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    content TEXT NOT NULL,
    role TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    metadata TEXT,
    FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_messages_conversation ON chat_messages(conversation_id);
CREATE INDEX idx_messages_timestamp ON chat_messages(timestamp);
```

### File System Structure
```
Documents/
├── HealthApp/
│   ├── Database/
│   │   └── health_data.sqlite
│   ├── Documents/
│   │   ├── Imported/
│   │   │   ├── {document_id}.pdf
│   │   │   └── {document_id}.jpg
│   │   └── Thumbnails/
│   │       ├── {document_id}_thumb.jpg
│   │       └── {document_id}_thumb.jpg
│   ├── Exports/
│   │   ├── health_data_export.json
│   │   └── health_report.pdf
│   └── Logs/
│       └── app.log
```

## Error Handling

### Error Types and Handling Strategy

```swift
enum HealthAppError: LocalizedError {
    case databaseError(String)
    case networkError(String)
    case fileSystemError(String)
    case encryptionError(String)
    case documentProcessingError(String)
    case aiServiceError(String)
    case validationError(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseError(let message):
            return "Database Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .fileSystemError(let message):
            return "File System Error: \(message)"
        case .encryptionError(let message):
            return "Encryption Error: \(message)"
        case .documentProcessingError(let message):
            return "Document Processing Error: \(message)"
        case .aiServiceError(let message):
            return "AI Service Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        }
    }
}

// Global error handling
class ErrorHandler: ObservableObject {
    @Published var currentError: HealthAppError?
    @Published var showingError = false
    
    func handle(_ error: Error) {
        DispatchQueue.main.async {
            if let healthError = error as? HealthAppError {
                self.currentError = healthError
            } else {
                self.currentError = .databaseError(error.localizedDescription)
            }
            self.showingError = true
        }
    }
}
```

### Network Error Handling
- Automatic retry logic for transient failures
- Graceful degradation when services are unavailable
- Clear user messaging for different error scenarios
- Offline mode detection and appropriate UI updates

### Data Validation
- Input validation for all health data entries
- File type and size validation for document imports
- Server configuration validation with connection testing
- Data integrity checks during database operations

## Testing Strategy

### Unit Testing
- **Data Models**: Test all health data model validation and serialization
- **Database Operations**: Test CRUD operations, encryption, and data integrity
- **Business Logic**: Test health data management, document processing, and AI chat logic
- **Network Clients**: Test API communication with mock servers
- **File Operations**: Test document import, export, and file system management

### Integration Testing
- **Database Integration**: Test complete data flow from UI to database
- **External Services**: Test integration with Ollama and Docling services
- **File System Integration**: Test document import from various sources
- **iCloud Backup**: Test backup and restore functionality

### UI Testing
- **Navigation Flow**: Test complete user journeys through the app
- **Accessibility**: Test VoiceOver, Dynamic Type, and other accessibility features
- **Dark/Light Mode**: Test UI appearance in both themes
- **Error Scenarios**: Test error handling and user feedback

### Performance Testing
- **Database Performance**: Test query performance with large datasets
- **Memory Usage**: Test memory efficiency during document processing
- **Battery Usage**: Test power consumption during AI operations
- **Storage Efficiency**: Test data compression and storage optimization

### Security Testing
- **Data Encryption**: Verify all sensitive data is properly encrypted
- **Network Security**: Test secure communication with external services
- **File System Security**: Verify proper file permissions and access controls
- **iCloud Security**: Test encrypted backup and restore processes

## Key Design Decisions

### Privacy-First Architecture
The app is designed with privacy as the primary concern. All health data is encrypted and stored locally, with no cloud dependencies for core functionality. External services are used only for processing, not storage.

### Modular Service Architecture
The external service layer is designed to be easily extensible. New AI providers can be added by implementing the common interface, allowing for future expansion beyond Ollama.

### Offline-First Design
The app is fully functional offline for data viewing and editing. Network-dependent features gracefully degrade with clear user feedback about availability.

### Accessibility and Usability
Following Apple's Human Interface Guidelines ensures the app is accessible to all users and provides a familiar, intuitive experience consistent with iOS design patterns.

### Scalable Data Model
The health data model is designed to accommodate future expansion. Placeholder structures and extensible schemas allow for adding new health data types without major architectural changes.

### Secure File Handling
Document storage and processing follow iOS security best practices, with proper sandboxing and encryption for sensitive medical documents.