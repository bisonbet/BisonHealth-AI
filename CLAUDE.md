# BisonHealth AI - AI Coding Guide

**Privacy-first universal iOS app (iPhone + iPad) for personal health data management with AI assistance.**

## Quick Facts

- **Platform**: iOS 17.0+ (Universal - iPhone & iPad)
- **Language**: Swift 5.9+ with SwiftUI
- **Architecture**: MVVM with protocol-oriented design
- **Database**: SQLite with CryptoKit encryption (current version: 6)
- **AI Providers**: Ollama (local), AWS Bedrock (cloud), OpenAI-compatible
- **Document Processing**: Docling OCR service
- **Privacy**: Local-first, optional encrypted iCloud backup

---

## Project Structure

```
BisonHealth-AI/
├── HealthApp/                    # Main iOS application
│   ├── HealthApp/                # App source (113 Swift files)
│   │   ├── Models/               # 10 files - Data models
│   │   ├── Views/                # 54 files - SwiftUI views
│   │   ├── Managers/             # 10 files - Business logic (ViewModels)
│   │   ├── Services/             # 10 files - External integrations
│   │   ├── Database/             # 7 files - SQLite + encryption
│   │   ├── Networking/           # 3 files - Network layer
│   │   ├── Utils/                # 14 files - Utilities
│   │   └── ViewModels/           # 1 file
│   ├── HealthAppTests/           # 13 unit test files
│   ├── HealthAppUITests/         # 6 UI test files
│   └── HealthApp.xcodeproj/      # Xcode project
├── .github/workflows/            # CI/CD (Gemini & Claude agents)
├── .claude/                      # Claude AI configuration
└── *.md                          # 17+ documentation files
```

---

## Architecture (MVVM)

```
SwiftUI Views
    ↓ @StateObject / @ObservedObject
Managers (ViewModels)
    ↓ @Published properties
Services & Database
    ↓ Operates on
Models (HealthDataProtocol)
```

### Key Patterns

**Protocol-Oriented Design**
```swift
protocol HealthDataProtocol: Identifiable, Codable {
    var id: UUID { get }
    var dataType: HealthDataType { get }
    var lastModified: Date { get }
}

protocol AIProviderInterface {
    func sendMessage(_ message: String, context: String) async throws -> String
    func testConnection() async -> Bool
}
```

**Dependency Injection**
```swift
class HealthDataManager: ObservableObject {
    private let databaseManager: DatabaseManager
    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }
}
```

**Async/Await + MainActor**
```swift
@MainActor
class AIChatManager: ObservableObject {
    @Published var conversations: [ChatConversation] = []

    func loadConversations() async {
        conversations = try await databaseManager.loadConversations()
    }
}
```

---

## Critical Rules

### 1. Build Commands

⚠️ **NEVER run `xcodebuild` unless user explicitly requests it**

**DO NOT build**:
- After making code changes
- To verify changes
- Proactively
- To check for errors

**ONLY build when user says**: "build the project", "run a build", "compile"

```bash
# iPhone build (when requested)
cd HealthApp
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' clean build

# iPad build (when requested)
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' clean build
```

### 2. Database Migrations

⚠️ **CRITICAL**: Always increment version for schema changes to prevent data loss

**Current Database Version**: 6 (in `DatabaseManager.currentDatabaseVersion`)

**Safe changes (no migration)**:
- Adding optional fields with defaults
- Adding computed properties
- UI-only changes

**Requires migration**:
- Adding required fields
- Removing fields
- Changing field types
- Renaming fields

**Migration workflow**:
```swift
// 1. Increment version
private static let currentDatabaseVersion = 7  // Was 6

// 2. Add migration case
case 7:
    try db.run(table.addColumn(newColumn, defaultValue: ""))
    print("   ✓ Added newColumn to table")
```

**Always test**:
- Fresh install (new database)
- Upgrade (existing database migrates)
- Data integrity post-migration

### 3. iPad Compatibility

✅ **Required**: All features must work on iPhone AND iPad

- Use `NavigationStack` (never deprecated `NavigationView`)
- Test on both simulators
- Use adaptive layouts (`horizontalSizeClass`)
- Target: `TARGETED_DEVICE_FAMILY = "1,2"`

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass

var body: some View {
    if horizontalSizeClass == .regular {
        NavigationSplitView { /* iPad */ }
    } else {
        NavigationStack { /* iPhone */ }
    }
}
```

### 4. Accessibility

✅ **Required**: Every UI component needs accessibility support

```swift
Button("Add Blood Test") {
    showEditor = true
}
.accessibilityLabel("Add new blood test result")
.accessibilityHint("Opens form to enter blood test data")
.accessibilityIdentifier("addBloodTestButton")
```

---

## Coding Standards

### File Organization

```swift
import Foundation
import SwiftUI

// MARK: - Main Type
@MainActor
class HealthDataManager: ObservableObject {

    // MARK: - Published Properties
    @Published var healthData: [HealthDataProtocol] = []

    // MARK: - Private Properties
    private let databaseManager: DatabaseManager

    // MARK: - Initialization
    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    // MARK: - Public Methods
    func loadHealthData() async throws { }

    // MARK: - Private Methods
    private func validateData(_ data: HealthDataProtocol) -> Bool { }
}
```

### Naming Conventions

- **Files**: Match primary type (`DocumentProcessor.swift`)
- **Views**: End with `View` (`SettingsView.swift`)
- **Extensions**: Use `+` (`DatabaseManager+Chat.swift`)
- **Types**: PascalCase (`HealthDataManager`)
- **Variables/Functions**: lowerCamelCase (`healthDataManager`)
- **Enum cases**: camelCase with snake_case raw values

```swift
enum BloodTestCategory: String, Codable {
    case completeBloodCount = "complete_blood_count"
    case lipidPanel = "lipid_panel"
}
```

### DO ✅

- Use `NavigationStack` (not NavigationView)
- Use `@MainActor` for ObservableObject classes
- Use async/await for async operations
- Provide accessibility labels/hints
- Test on iPhone AND iPad
- Handle errors with recovery suggestions
- Use MARK comments
- Follow Apple's Swift API Design Guidelines

### DON'T ❌

- Force unwrap (`!`) - handle optionals safely
- Use deprecated APIs
- Skip accessibility
- Test only on iPhone
- Commit without incrementing database version for schema changes
- Hardcode sensitive data
- Build without explicit user request

---

## Key Components

### Core Managers (ViewModels)

| Manager | Purpose | Key Methods |
|---------|---------|-------------|
| `HealthDataManager` | Health data CRUD | `savePersonalInfo()`, `loadBloodTests()` |
| `AIChatManager` | Chat management | `sendMessage()`, `loadConversations()` |
| `DocumentManager` | Document processing | `importDocument()`, `processDocument()` |
| `SettingsManager` | App settings | `saveSettings()`, `loadSettings()` |
| `iCloudBackupManager` | Backup/restore | `createBackup()`, `restoreBackup()` |

### Services (External Integrations)

| Service | Purpose | Default Endpoint |
|---------|---------|------------------|
| `OllamaClient` | Local AI chat | `localhost:11434` |
| `BedrockClient` | AWS Bedrock AI | AWS region-based |
| `OpenAICompatibleClient` | OpenAI-compatible servers | User-configured |
| `DoclingClient` | Document OCR | `localhost:5001` |
| `MedicalDocumentExtractor` | Medical data extraction | N/A (local) |

### Database (SQLite + Encryption)

**Location**: `DatabaseManager.swift` + extensions

**Key Tables**:
- `health_data` - Encrypted health records
- `documents` - Document metadata
- `chat_conversations` - AI conversations
- `chat_messages` - Chat messages
- `database_version` - Schema version

**Extensions**:
- `DatabaseManager+HealthData.swift` - Health data queries
- `DatabaseManager+Documents.swift` - Document queries
- `DatabaseManager+Chat.swift` - Chat queries
- `DatabaseManager+MedicalDocuments.swift` - Medical doc queries
- `DatabaseManager+AppSettings.swift` - Settings queries

---

## Common Tasks

### Adding a New Health Data Type

```swift
// 1. Update enum (HealthDataProtocol.swift)
enum HealthDataType: String, Codable {
    case newDataType = "new_data_type"
}

// 2. Create model
struct NewDataType: HealthDataProtocol {
    let id: UUID
    let dataType: HealthDataType = .newDataType
    var lastModified: Date
    var customField: String
}

// 3. Increment database version & add migration
private static let currentDatabaseVersion = 7
case 7:
    try db.run(newDataTypeTable.create { t in
        t.column(id, primaryKey: true)
        t.column(customField)
    })

// 4. Add manager methods (HealthDataManager)
func saveNewDataType(_ data: NewDataType) async throws

// 5. Create UI views
struct NewDataTypeView: View { }

// 6. Add tests
func testSaveNewDataType_Success() async throws
```

### Adding a New AI Provider

```swift
// 1. Create client (Services/)
class NewAIClient: AIProviderInterface {
    func sendMessage(_ message: String, context: String) async throws -> String
    func testConnection() async -> Bool
}

// 2. Update enum
enum AIProvider: String {
    case newProvider
}

// 3. Update AIChatManager
private func getAIClient() -> AIProviderInterface {
    switch currentProvider {
    case .newProvider: return newAIClient
    }
}

// 4. Create settings view
struct NewAIProviderSettingsView: View { }
```

---

## External Services

### Ollama (Local AI)
- **Default**: `localhost:11434`
- **Models**: User-configurable (llama3.2, mistral, etc.)
- **Features**: Chat, streaming, model management
- **Integration**: `OllamaClient.swift`

### AWS Bedrock (Cloud AI)
- **Models**: Claude Sonnet 4, Llama 4 Maverick
- **Context**: 200k tokens (Claude)
- **Auth**: AWS credentials in Keychain
- **Integration**: `BedrockClient.swift`

### Docling (Document OCR)
- **Default**: `localhost:5001`
- **API Version**: v1
- **Formats**: PDF, DOCX, images
- **Key Endpoint**: `POST /v1/convert/file`
- **Integration**: `DoclingClient.swift`, `DocumentProcessor.swift`
- **Reference**: See `DOCLING_FORMATS_EXPLANATION.md`

---

## Testing

### Test Files (19 total)

**Unit Tests** (`HealthAppTests/` - 13 files):
- `ModelTests.swift` - Model validation
- `DatabaseTests.swift` - Database operations
- `HealthDataManagerTests.swift` - Manager logic
- `ServiceClientTests.swift` - Service integrations
- `ChatIntegrationTests.swift` - End-to-end tests

**UI Tests** (`HealthAppUITests/` - 6 files):
- `ChatInterfaceUITests.swift` - Chat interface
- `DocumentManagementUITests.swift` - Document management
- `AccessibilityUITests.swift` - Accessibility features

### Running Tests

```bash
# Unit tests
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# iPad tests
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'
```

---

## Privacy & Security

### Data Protection
- **Encryption**: CryptoKit for all health data
- **Storage**: SQLite with encrypted blobs
- **Secrets**: Keychain for credentials
- **Backup**: Optional encrypted iCloud
- **Network**: TLS 1.2+ only

### .gitignore Protection
```
*.sqlite                    # Database files
Documents/HealthApp/        # User documents
*.p12                       # Certificates
AuthKey_*.p8                # API keys
.env*                       # Environment variables
```

### HIPAA Awareness
⚠️ **NOT HIPAA COMPLIANT** - Personal use only, not for healthcare providers

---

## Troubleshooting

### Common Issues

**Build Errors**
- Check Swift package resolution
- Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Resolve packages: `xcodebuild -resolvePackageDependencies`

**Simulator Issues**
- Use iPhone 16 Pro or iPad Pro 11-inch (M4)
- Install iOS 18.6 runtime via Xcode > Settings > Platforms

**Database Migration Errors**
- Check console logs for migration errors
- Verify `currentDatabaseVersion` was incremented
- Restore from backup if needed: `health_data.sqlite.backup.[timestamp]`

**Document Picker Console Errors**
✅ **Safe to ignore** - These are iOS Simulator development environment issues:
```
Error acquiring assertion: <Error Domain=RBSAssertionErrorDomain...
LaunchServices: store (null) or url (null) was nil...
```
- Only appears in simulator, not production
- Does not affect functionality

### Debug Logging

Emoji prefixes for filtering:
- 📁 File system operations
- 📷 Camera/document scanning
- 🖼️ Image processing
- 💬 Chat operations
- 🗄️ Database operations
- 🔒 Encryption/security
- 📡 Network operations

---

## Dependencies

### Swift Packages (30+)

**External**:
- SQLite.swift (0.15.4) - Type-safe SQLite
- ollama-swift (main) - Ollama integration
- aws-sdk-swift (1.5.42) - AWS Bedrock
- swift-markdown-ui (main) - Markdown rendering
- grpc-swift (1.26.1) - gRPC communication
- swift-crypto (3.15.0) - Encryption
- swift-nio (2.86.0) - Network I/O

**Built-in Frameworks**:
- CryptoKit, VisionKit, PhotosUI, HealthKit, CloudKit, Combine, PDFKit

---

## Documentation Files

- `README.md` - Project overview
- `CLAUDE.md` - This file
- `CONTRIBUTING.md` - Contribution guidelines
- `AGENTS.md` - AI agent guidelines
- `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` - Document processing
- `DOCLING_FORMATS_EXPLANATION.md` - Docling API reference
- `OLLAMA_SWIFT_INTEGRATION.md` - Ollama integration guide

---

## Quick Reference

**Entry Point**: `HealthApp/HealthApp/HealthAppApp.swift`
**Root View**: `HealthApp/HealthApp/ContentView.swift`
**Database**: `HealthApp/HealthApp/Database/DatabaseManager.swift`
**Project**: `HealthApp/HealthApp.xcodeproj`

**Open Project**:
```bash
cd BisonHealth-AI
open HealthApp/HealthApp.xcodeproj
```

**Statistics**:
- 113 Swift files (Models: 10, Views: 54, Managers: 10, Services: 10, Database: 7, Utils: 14)
- 19 test files (13 unit, 6 UI)
- Database version: 6
- iOS 17.0+ deployment target

---

**Last Updated**: 2025-12-18
**License**: MIT
