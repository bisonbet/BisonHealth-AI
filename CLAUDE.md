# CLAUDE.md - BisonHealth AI Repository Guide for AI Assistants

## Table of Contents
1. [Project Overview](#project-overview)
2. [Repository Structure](#repository-structure)
3. [Development Environment](#development-environment)
4. [Architecture & Design Patterns](#architecture--design-patterns)
5. [Coding Standards & Conventions](#coding-standards--conventions)
6. [Data Safety & Migrations](#data-safety--migrations)
7. [Testing Guidelines](#testing-guidelines)
8. [Build & Deployment](#build--deployment)
9. [AI Assistant Workflows](#ai-assistant-workflows)
10. [External Services](#external-services)
11. [Privacy & Security](#privacy--security)
12. [Common Tasks](#common-tasks)
13. [Troubleshooting](#troubleshooting)

---

## Project Overview

**BisonHealth AI** is a privacy-first iOS application that empowers users to take complete control of their personal health data. The app provides AI-powered assistance for health data management while keeping all sensitive information securely stored locally on the device.

### Key Characteristics
- **Platform**: Universal iOS app (iPhone + iPad) with iOS 17.0+ deployment target
- **Language**: Swift 5.9+ with SwiftUI
- **Architecture**: MVVM pattern with protocol-oriented design
- **Privacy**: Local-first with optional encrypted iCloud backup
- **AI Integration**: Multiple providers (Ollama, AWS Bedrock, OpenAI-compatible)
- **Document Processing**: AI-powered OCR via Docling service
- **Status**: Personal use only - NOT HIPAA compliant

### Core Features
- 📱 Universal iOS app optimized for iPhone and iPad
- 🔒 Local encrypted SQLite database for health data
- 🤖 AI doctor personas with health context awareness
- 📄 Smart document processing with OCR and extraction
- 🏥 11 medical document types supported
- 💬 AI chat with conversation management
- 📊 Data export (JSON/PDF)
- ☁️ Optional iCloud encrypted backup
- 🌙 Full accessibility support (VoiceOver, Dynamic Type, Dark Mode)

---

## Repository Structure

### Root Directory Layout
```
BisonHealth-AI/
├── HealthApp/                      # Main iOS application
│   ├── HealthApp/                  # App source code
│   ├── HealthAppTests/             # Unit tests
│   ├── HealthAppUITests/           # UI tests
│   └── HealthApp.xcodeproj/        # Xcode project
├── legacy/                         # Legacy Next.js web app (READ-ONLY REFERENCE)
├── .claude/                        # Claude AI configuration
├── .github/workflows/              # CI/CD workflows (Gemini, Claude agents)
├── .gitignore                      # Git ignore rules (includes PHI protection)
├── README.md                       # Project overview and features
├── CONTRIBUTING.md                 # Contribution guidelines
├── AGENTS.md                       # AI agent development guidelines
├── MEDICAL_DOCUMENTS_IMPLEMENTATION.md
├── DOCLING_FORMATS_EXPLANATION.md
├── GEMINI.md
├── LICENSE
└── CLAUDE.md                       # This file
```

### iOS App Structure (HealthApp/)
```
HealthApp/HealthApp/
├── HealthAppApp.swift              # App entry point
├── ContentView.swift               # Root TabView (4 tabs)
├── Models/                         # Data models (10 files)
│   ├── HealthDataProtocol.swift    # Base protocol for health data
│   ├── PersonalHealthInfo.swift    # Personal medical info
│   ├── BloodTestResult.swift       # Lab results
│   ├── MedicalDocument.swift       # Medical document with extraction
│   ├── HealthDocument.swift        # Base document model
│   ├── ChatModels.swift            # Chat conversations
│   ├── Doctor.swift                # AI doctor personas
│   └── ...
├── Views/                          # SwiftUI views (52 files)
│   ├── ChatDetailView.swift
│   ├── MedicalDocumentDetailView.swift
│   ├── UnifiedContextSelectorView.swift
│   └── ...
├── Managers/                       # Business logic/ViewModels (9 files)
│   ├── HealthDataManager.swift     # Health data CRUD
│   ├── AIChatManager.swift         # Chat management
│   ├── DocumentManager.swift       # Document processing
│   ├── SettingsManager.swift       # App settings
│   ├── iCloudBackupManager.swift   # Backup/restore
│   └── ...
├── Services/                       # External integrations (10 files)
│   ├── AIProviderInterface.swift   # AI provider protocol
│   ├── OllamaClient.swift          # Ollama integration
│   ├── BedrockClient.swift         # AWS Bedrock integration
│   ├── OpenAICompatibleClient.swift
│   ├── DoclingClient.swift         # Document OCR service
│   ├── MedicalDocumentExtractor.swift
│   └── ...
├── Database/                       # Data persistence (7 files)
│   ├── DatabaseManager.swift       # Core SQLite + encryption
│   ├── DatabaseManager+HealthData.swift
│   ├── DatabaseManager+MedicalDocuments.swift
│   ├── DatabaseManager+Chat.swift
│   ├── DatabaseManager+AppSettings.swift
│   └── Keychain.swift
├── Networking/                     # Network layer (3 files)
│   ├── NetworkManager.swift
│   ├── NetworkError.swift
│   └── PendingOperationsManager.swift
├── Utils/                          # Utilities (13 files)
│   ├── FileSystemManager.swift
│   ├── DocumentImporter.swift
│   ├── DocumentExporter.swift
│   ├── AccessibilityManager.swift
│   └── ...
└── Assets.xcassets/                # App assets and icons
```

**Statistics:**
- Total Swift files: 107
- Views: 52
- Models: 10
- Managers: 9
- Services: 10
- Database extensions: 7
- Utils: 13
- Unit tests: 13
- UI tests: 6

### Legacy Reference (READ-ONLY)
The `legacy/` directory contains a Next.js web application used as reference for:
- Database schema design (Prisma)
- UI/UX patterns and workflows
- API structure and endpoints
- Data models and relationships

**IMPORTANT**: Never modify files in `legacy/`. Use only as reference when implementing new features.

---

## Development Environment

### Prerequisites
- **Xcode**: 15.0 or later
- **iOS Deployment Target**: 17.0+
- **Swift**: 5.9+
- **macOS**: Compatible with Xcode 15+
- **Simulators**: iPhone 16 Pro, iPad Pro 11-inch (M4)

### Swift Package Dependencies
The app uses 30+ packages managed via Swift Package Manager. Key dependencies:

| Package | Purpose | Version |
|---------|---------|---------|
| **SQLite.swift** | Type-safe SQLite wrapper | 0.15.4 |
| **ollama-swift** | Ollama AI integration | main branch |
| **aws-sdk-swift** | AWS Bedrock integration | 1.5.42 |
| **swift-markdown-ui** | Markdown rendering | main branch |
| **grpc-swift** | gRPC communication | 1.26.1 |
| **swift-crypto** | Encryption utilities | 3.15.0 |
| **swift-nio** | Network I/O | 2.86.0 |

**Built-in Frameworks:**
- CryptoKit (encryption)
- VisionKit (document scanning)
- PhotosUI (photo selection)
- Combine (reactive programming)
- CloudKit (iCloud backup)

### Xcode Project Configuration
- **Project**: `HealthApp.xcodeproj`
- **Scheme**: `HealthApp`
- **Bundle ID**: `com.bisonhealth.app`
- **Target Devices**: Universal (`TARGETED_DEVICE_FAMILY = "1,2"`)
- **Simulators**:
  - Primary: iPhone 16 Pro (iOS 18.6)
  - Secondary: iPad Pro 11-inch (M4) (iOS 18.6)

### Opening the Project
```bash
cd BisonHealth-AI
open HealthApp/HealthApp.xcodeproj
```

---

## Architecture & Design Patterns

### MVVM Pattern
The app strictly follows Model-View-ViewModel architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                       │
│          (ContentView, ChatDetailView, etc.)                │
└────────────────────┬────────────────────────────────────────┘
                     │ @StateObject / @ObservedObject
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Managers (ViewModels)                    │
│   (HealthDataManager, AIChatManager, DocumentManager)       │
│                    @Published properties                    │
└────────────────────┬────────────────────────────────────────┘
                     │ Uses
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Services & Database                      │
│     (OllamaClient, DatabaseManager, DoclingClient)          │
└────────────────────┬────────────────────────────────────────┘
                     │ Operates on
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                          Models                             │
│   (PersonalHealthInfo, BloodTestResult, MedicalDocument)    │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Patterns

#### 1. Protocol-Oriented Design
```swift
// Base protocol for all health data
protocol HealthDataProtocol: Identifiable, Codable {
    var id: UUID { get }
    var dataType: HealthDataType { get }
    var lastModified: Date { get }
}

// AI provider abstraction
protocol AIProviderInterface {
    func sendMessage(_ message: String, context: String) async throws -> String
    func testConnection() async -> Bool
}
```

#### 2. Dependency Injection
```swift
class HealthDataManager: ObservableObject {
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager

    init(databaseManager: DatabaseManager = .shared,
         fileSystemManager: FileSystemManager = .shared) {
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager
    }
}
```

#### 3. Async/Await Everywhere
```swift
// All async operations use modern concurrency
func loadConversations() async {
    do {
        conversations = try await databaseManager.loadConversations()
    } catch {
        errorHandler.handle(error)
    }
}
```

#### 4. @MainActor for UI
```swift
@MainActor
class AIChatManager: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var isLoading = false
}
```

#### 5. Singleton Pattern (Used Sparingly)
```swift
// Only for shared resources
class DatabaseManager {
    static let shared = DatabaseManager()
    private init() { }
}
```

### Data Flow Architecture

```
User Interaction (SwiftUI View)
    ↓
View calls ViewModel method
    ↓
ViewModel updates @Published properties
    ↓
ViewModel calls Service/Database
    ↓
Service makes API call / Database query
    ↓
Results flow back through ViewModel
    ↓
SwiftUI View automatically updates
```

---

## Coding Standards & Conventions

### Naming Conventions

#### Files
- Match primary type: `DocumentProcessor.swift` contains `DocumentProcessor`
- Views end with `View`: `SettingsView.swift`
- Tests end with `Tests`: `ModelTests.swift`
- Extensions use `+`: `DatabaseManager+Chat.swift`
- Group related functionality in folders

#### Types (Classes, Structs, Enums, Protocols)
- **PascalCase**: `HealthDataManager`, `BloodTestResult`
- **Protocols**: Describe capability or end with `Protocol`
  - `HealthDataProtocol`, `AIProviderInterface`, `Codable`
- **Enums**: `HealthDataType`, `DocumentCategory`, `AIProvider`

#### Variables & Functions
- **lowerCamelCase**: `healthDataManager`, `isLoading`, `sendMessage()`
- **Published properties**: `@Published var conversations: [ChatConversation]`
- **Private properties**: Use underscore prefix sparingly
- **Constants**: `static let currentDatabaseVersion = 5`

#### Enum Cases & Raw Values
```swift
enum BloodTestCategory: String, Codable {
    case completeBloodCount = "complete_blood_count"
    case lipidPanel = "lipid_panel"
    case liverFunction = "liver_function"
    case fattyAcid = "fatty_acid"  // Note: singular, not plural
}
```

### Code Organization

#### File Structure Template
```swift
import Foundation
import SwiftUI

// MARK: - Main Type
@MainActor
class HealthDataManager: ObservableObject {

    // MARK: - Published Properties
    @Published var healthData: [HealthDataProtocol] = []
    @Published var isLoading = false

    // MARK: - Private Properties
    private let databaseManager: DatabaseManager
    private let fileSystemManager: FileSystemManager

    // MARK: - Initialization
    init(databaseManager: DatabaseManager = .shared,
         fileSystemManager: FileSystemManager = .shared) {
        self.databaseManager = databaseManager
        self.fileSystemManager = fileSystemManager
    }

    // MARK: - Public Methods
    func loadHealthData() async throws {
        // Implementation
    }

    // MARK: - Private Methods
    private func validateData(_ data: HealthDataProtocol) -> Bool {
        // Implementation
    }
}

// MARK: - Supporting Types
enum HealthDataError: LocalizedError {
    case invalidData
    case databaseError(Error)

    var errorDescription: String? {
        // Implementation
    }
}
```

#### SwiftUI View Structure
```swift
struct HealthDataView: View {
    // MARK: - Properties
    @StateObject private var healthDataManager = HealthDataManager()
    @State private var showingEditor = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Body
    var body: some View {
        NavigationStack {  // Always NavigationStack, never NavigationView
            content
                .navigationTitle("Health Data")
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingEditor) { EditorView() }
    }

    // MARK: - View Components
    @ViewBuilder
    private var content: some View {
        List {
            personalInfoSection
            bloodTestsSection
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            addButton
        }
    }

    // MARK: - Private Views
    private var personalInfoSection: some View {
        Section("Personal Info") {
            // Implementation
        }
    }
}
```

### Swift Style Guidelines

#### Error Handling
```swift
// Define specific error types with recovery suggestions
enum HealthDataError: LocalizedError {
    case invalidFormat(String)
    case encryptionFailed
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let details):
            return "Invalid health data format: \(details)"
        case .encryptionFailed:
            return "Failed to encrypt health data"
        case .databaseUnavailable:
            return "Database is currently unavailable"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidFormat:
            return "Please check your data and try again"
        case .encryptionFailed:
            return "Check your device security settings"
        case .databaseUnavailable:
            return "Restart the app or check storage"
        }
    }
}

// Handle errors appropriately
do {
    try await saveHealthData(personalInfo)
} catch let error as HealthDataError {
    logger.error("Health data error: \(error.localizedDescription)")
    await errorHandler.handle(error)
} catch {
    logger.error("Unexpected error: \(error)")
    await errorHandler.handle(HealthDataError.databaseUnavailable)
}
```

#### Accessibility (REQUIRED for all UI)
```swift
Button("Add Blood Test") {
    showingEditor = true
}
.accessibilityLabel("Add new blood test result")
.accessibilityHint("Opens form to enter blood test data")
.accessibilityIdentifier("addBloodTestButton")

Text("Health Summary")
    .font(.title2)
    .dynamicTypeSize(.large...accessibility5)
```

#### iPad Compatibility (REQUIRED)
```swift
// Check device type
private var isIPad: Bool {
    horizontalSizeClass == .regular
}

// Adaptive layouts
var body: some View {
    if isIPad {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    } else {
        NavigationStack {
            content
        }
    }
}
```

### Best Practices

#### DO ✅
- Use `NavigationStack` (never deprecated `NavigationView`)
- Use `@MainActor` for all ObservableObject classes
- Use async/await for all async operations
- Provide accessibility labels, hints, and identifiers
- Test on both iPhone AND iPad simulators
- Use MARK comments to organize code
- Follow Apple's Swift API Design Guidelines
- Use meaningful, descriptive names
- Prefer composition over inheritance
- Use protocols for abstraction

#### DON'T ❌
- Use force unwrapping (`!`) - always handle optionals safely
- Use deprecated APIs (NavigationView, UIViewRepresentable when SwiftUI exists)
- Hardcode values - use constants or configuration
- Ignore accessibility requirements
- Skip error handling
- Commit secrets, API keys, or PHI
- Modify files in `legacy/` directory
- Mix UI code with business logic

---

## Data Safety & Migrations

### Critical Data Protection Rules

⚠️ **CRITICAL**: User health data is extremely sensitive. Follow these rules religiously to prevent data loss:

### Database Version Management

#### Current State
- **Database Version**: 5 (see `DatabaseManager.currentDatabaseVersion`)
- **Version Tracking**: Stored in `database_version` table
- **Automatic Backups**: Created before every migration
- **Backup Location**: `health_data.sqlite.backup.[timestamp]`

### When Making Model Changes

#### Step 1: ALWAYS Increment Version for Breaking Changes
```swift
// In DatabaseManager.swift
private static let currentDatabaseVersion = 6  // Increment by 1
```

#### Step 2: Determine If Migration Is Required

**Safe Changes (No Migration):**
- Adding optional fields with default values
- Adding computed properties
- Adding methods to types
- UI-only changes
- Adding new tables (non-breaking)

**Requires Migration:**
- Adding required fields to existing models
- Removing fields from models
- Changing field types
- Renaming fields/columns
- Restructuring relationships
- Changing table schemas

#### Step 3: Implement Migration
```swift
// In DatabaseManager.swift performMigration(db:toVersion:)
case 6:
    // Migration for version 6: Add new required field to PersonalHealthInfo
    try db.run(personalHealthInfoTable.addColumn(newColumn, defaultValue: ""))
    print("   ✓ Added newColumn to personal_health_info")
```

### Migration Best Practices

#### Safe Examples ✅
```swift
// Adding optional field
struct PersonalHealthInfo {
    var newOptionalField: String? = nil  // Safe - has default
}

// Adding computed property
extension PersonalHealthInfo {
    var displayName: String {
        return "\(firstName) \(lastName)"  // Safe - not stored
    }
}

// Adding new table
try db.run(newTable.create(ifNotExists: true) { t in
    t.column(id, primaryKey: true)
    t.column(data)
})
```

#### Dangerous Examples ❌
```swift
// Adding required field WITHOUT migration
struct PersonalHealthInfo {
    var newRequiredField: String  // BREAKS existing data!
}

// Removing field WITHOUT migration
struct PersonalHealthInfo {
    // var existingField: String  // DELETED - BREAKS!
}

// Changing type WITHOUT migration
struct PersonalHealthInfo {
    var age: String  // Was Int before - BREAKS!
}
```

### Migration Testing Checklist

Before committing model changes:
- [ ] Database version incremented for breaking changes
- [ ] Migration logic implemented in `performMigration`
- [ ] Fresh install tested (new database)
- [ ] Upgrade tested (existing database migrates)
- [ ] Data integrity verified post-migration
- [ ] Console shows correct migration messages
- [ ] All existing functionality works
- [ ] New features work correctly
- [ ] No compilation errors
- [ ] Backup created successfully

### Emergency Recovery

#### If Data Loss Occurs:
1. Check if `currentDatabaseVersion` was incremented
2. Verify migration logic exists for the version
3. Check console logs for migration errors
4. Locate backup: `health_data.sqlite.backup.[timestamp]`
5. Consider manual backup restoration:
   ```swift
   // Emergency restore from backup
   // 1. Stop app
   // 2. Replace current .sqlite with backup
   // 3. Restart app
   ```

#### Prevention Strategy:
- **ALWAYS** increment version for schema changes
- **ALWAYS** test with existing populated database
- **ALWAYS** verify backups are created
- **NEVER** skip migration for "small" changes
- **NEVER** assume data is compatible

### Database Reset (Development Only)

Available in advanced settings for development:
```swift
// WARNING: Deletes ALL user data
try DatabaseManager.shared.resetDatabase()
```

---

## Testing Guidelines

### Testing Framework
- **Framework**: XCTest (Apple's standard)
- **Unit Tests**: `HealthAppTests/` (13 test files)
- **UI Tests**: `HealthAppUITests/` (6 test files)
- **Coverage**: Mirrors app structure

### Unit Test Structure

#### Test File Organization
```swift
import XCTest
@testable import HealthApp

class HealthDataManagerTests: XCTestCase {
    // MARK: - Properties
    var sut: HealthDataManager!
    var mockDatabase: MockDatabaseManager!
    var mockFileSystem: MockFileSystemManager!

    // MARK: - Setup & Teardown
    override func setUp() {
        super.setUp()
        mockDatabase = MockDatabaseManager()
        mockFileSystem = MockFileSystemManager()
        sut = HealthDataManager(
            databaseManager: mockDatabase,
            fileSystemManager: mockFileSystem
        )
    }

    override func tearDown() {
        sut = nil
        mockDatabase = nil
        mockFileSystem = nil
        super.tearDown()
    }

    // MARK: - Tests
    func testSavePersonalInfo_Success() async throws {
        // Given
        let personalInfo = PersonalHealthInfo(name: "Test User")

        // When
        try await sut.savePersonalInfo(personalInfo)

        // Then
        XCTAssertTrue(mockDatabase.saveCalled)
        XCTAssertEqual(mockDatabase.savedData?.name, "Test User")
    }

    func testLoadBloodTests_ReturnsEmptyArray_WhenNoneExist() async throws {
        // Given
        mockDatabase.bloodTests = []

        // When
        let results = try await sut.loadBloodTests()

        // Then
        XCTAssertTrue(results.isEmpty)
    }
}
```

#### Test Naming Convention
- Files: `*Tests.swift`
- Methods: `test[Function]_[Expected]_[Condition]()`
- Examples:
  - `testSavePersonalInfo_Success()`
  - `testLoadBloodTests_ThrowsError_WhenDatabaseUnavailable()`
  - `testDeleteDocument_RemovesFile_WhenFileExists()`

### UI Test Structure

```swift
import XCTest

class ChatInterfaceUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testSendMessage_DisplaysInConversation() {
        // Navigate to Chat tab
        app.tabBars.buttons["Chat"].tap()

        // Tap new conversation button
        app.navigationBars.buttons["New Chat"].tap()

        // Enter message
        let messageField = app.textFields["Message"]
        messageField.tap()
        messageField.typeText("Hello, doctor!")

        // Send message
        app.buttons["Send"].tap()

        // Verify message appears
        XCTAssertTrue(app.staticTexts["Hello, doctor!"].exists)
    }
}
```

### Test Coverage Requirements

#### Required Test Files
| Category | Test File | Coverage |
|----------|-----------|----------|
| Models | ModelTests.swift | Codable, validation, protocols |
| Database | DatabaseTests.swift | CRUD, encryption, migrations |
| Managers | HealthDataManagerTests.swift | Business logic, data flow |
| Chat | AIChatManagerTests.swift | Conversation management |
| Services | ServiceClientTests.swift | API calls, error handling |
| Files | FileSystemTests.swift | File operations, storage |
| Network | NetworkingTests.swift | Connectivity, retry logic |
| Backup | iCloudBackupTests.swift | Backup/restore flows |
| Integration | ChatIntegrationTests.swift | End-to-end workflows |
| Integration | DocumentProcessingIntegrationTests.swift | Document pipeline |
| Accessibility | AccessibilityTests.swift | VoiceOver, Dynamic Type |
| Validation | ValidationHelperTests.swift | Input validation |
| Settings | SettingsManagerTests.swift | Settings persistence |

### Running Tests

#### Command Line
```bash
# Unit tests (iPhone)
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HealthAppTests

# UI tests (iPhone)
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:HealthAppUITests

# iPad tests
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'

# All tests
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

#### Xcode IDE
- **Run Single Test**: Click diamond next to test method
- **Run Test Class**: Click diamond next to class name
- **Run All Tests**: ⌘+U
- **View Coverage**: Editor → Code Coverage

### Testing Best Practices

#### DO ✅
- Use Given-When-Then structure
- Test both success and failure cases
- Use descriptive test names
- Mock external dependencies
- Test edge cases and boundary conditions
- Test accessibility features
- Clean up after tests (tearDown)
- Use XCTestExpectation for async operations

#### DON'T ❌
- Test implementation details
- Make tests dependent on each other
- Use hardcoded delays (use expectations)
- Skip tearDown cleanup
- Test private methods directly (test public interface)
- Ignore flaky tests (fix them)

---

## Build & Deployment

### Build Commands

⚠️ **CRITICAL RULE**: **NEVER** run build commands unless explicitly requested by the user.

**ONLY build when user says**: "build the project", "run a build", "compile", "test the build"

**DO NOT build**:
- After making code changes
- To verify changes
- Proactively
- To check for errors
- Without explicit permission

#### Available Commands (Use Only When Requested)

```bash
# Navigate to project directory
cd HealthApp

# iPhone build
xcodebuild -project HealthApp.xcodeproj \
  -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  clean build

# iPad build
xcodebuild -project HealthApp.xcodeproj \
  -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' \
  clean build

# Run tests
xcodebuild test -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Clean build folder
xcodebuild clean -scheme HealthApp
```

### Pre-Commit Checklist

**Only when explicitly requested:**
- [ ] Clean build succeeds
- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Accessibility tested with VoiceOver
- [ ] Tested on iPhone simulator
- [ ] Tested on iPad simulator
- [ ] No force unwraps added
- [ ] Database version incremented (if schema changed)
- [ ] Migration implemented (if schema changed)

### CI/CD Workflows

Located in `.github/workflows/`:
- `claude.yml` - Claude AI agent workflow
- `claude-code-review.yml` - Automated code reviews
- `gemini-*.yml` - Gemini AI agent workflows
- `gemini-triage.yml` - Issue triage automation
- `gemini-scheduled-triage.yml` - Scheduled triage

---

## AI Assistant Workflows

### Guidelines for AI Assistants (Claude, Gemini, etc.)

#### General Principles
1. **Privacy First**: Never suggest cloud solutions when local alternatives exist
2. **Data Safety**: Always increment database version for schema changes
3. **Accessibility**: Every UI component needs accessibility labels
4. **Universal Design**: All features must work on iPhone AND iPad
5. **Test Coverage**: Add tests for new functionality
6. **Documentation**: Update docs when adding features

#### Before Making Changes
1. **Read existing code** to understand patterns
2. **Follow established conventions** (naming, structure, error handling)
3. **Check for similar implementations** to maintain consistency
4. **Review data model changes** for migration requirements
5. **Consider accessibility** implications

#### When Adding Features

**Step 1: Plan**
- Review existing architecture
- Identify affected components (Models → Services → Managers → Views)
- Check if database migration needed
- Plan test coverage

**Step 2: Implement**
- Follow MVVM pattern
- Use dependency injection
- Add proper error handling
- Include accessibility features
- Add MARK comments

**Step 3: Test**
- Add unit tests
- Add UI tests if needed
- Test on iPhone simulator
- Test on iPad simulator
- Test with VoiceOver enabled

**Step 4: Document**
- Update inline documentation
- Update README if user-facing
- Update this CLAUDE.md if architectural

#### Common Mistakes to Avoid

❌ **Don't:**
- Run `xcodebuild` without explicit user request
- Modify `legacy/` directory
- Add required fields without migration
- Use deprecated APIs (NavigationView)
- Skip accessibility labels
- Test only on iPhone (must test iPad too)
- Commit without incrementing database version for schema changes
- Use force unwrapping
- Hardcode sensitive data

✅ **Do:**
- Use `NavigationStack` (not NavigationView)
- Add `@MainActor` to ObservableObject classes
- Use async/await for async operations
- Provide recovery suggestions in errors
- Test both iPhone and iPad
- Follow existing naming conventions
- Use MARK comments
- Add comprehensive error handling

#### File Creation Guidelines

When creating new Swift files, they MUST be added to Xcode project:

1. Add `PBXBuildFile` entry
2. Add `PBXFileReference` entry
3. Add to appropriate group (Utils, Models, Views, etc.)
4. Add to Sources build phase for correct target

**Recommended**: Use Xcode's "New File" feature or provide script to update `project.pbxproj`

---

## External Services

### Ollama AI Server (Local AI)

**Default**: `localhost:11434`

**Purpose**: Local AI chat with health context

**Configuration**:
```swift
// In OllamaClient.swift
let baseURL = "http://\(hostname):\(port)"
```

**Features**:
- Chat completion
- Streaming responses
- Model management
- Offline operation

**Models**: User-configurable (llama3.2, mistral, etc.)

**Integration**: Via `OllamaClient.swift` implementing `AIProviderInterface`

### AWS Bedrock (Cloud AI)

**Purpose**: Cloud AI service with large context windows

**Configuration**:
- AWS Access Key
- AWS Secret Key
- AWS Region
- Model selection (Claude Sonnet 4, Llama 4 Maverick)

**Features**:
- 200k token context (Claude Sonnet 4)
- Streaming responses
- Multiple models
- Managed credentials (Keychain)

**Integration**: Via `BedrockClient.swift` implementing `AIProviderInterface`

### OpenAI-Compatible Servers

**Purpose**: Support for LiteLLM, LocalAI, vLLM, etc.

**Configuration**:
- Base URL
- Optional API key
- Model name

**Integration**: Via `OpenAICompatibleClient.swift`

### Docling Document Processing Server

**Default**: `localhost:5001`

**Purpose**: AI-powered OCR and document extraction

**API Version**: v1 (migrated from v1alpha)

**Key Endpoints**:
```
POST /v1/convert/file          - Sync file conversion
POST /v1/convert/source        - Sync URL conversion
POST /v1/convert/file/async    - Async file conversion
GET  /v1/status/poll/{task_id} - Check async status
```

**Supported Formats**:
- PDF documents
- Images (PNG, JPEG)
- DOCX files

**Features**:
- OCR with multiple engines (easyocr, etc.)
- Structured data extraction
- Section detection
- Medical document parsing

**Integration**:
- `DoclingClient.swift` - API client
- `DocumentProcessor.swift` - Processing pipeline
- `MedicalDocumentExtractor.swift` - Medical data extraction

**Configuration Example**:
```swift
let doclingClient = DoclingClient(
    hostname: "localhost",
    port: 5001,
    apiKey: nil  // Optional
)
```

**Authentication**: Optional `X-Api-Key` header

**Health Check**: Use `GET /v1/convert/file` (returns 200 when available)

**Reference**: See `DOCLING_FORMATS_EXPLANATION.md` for detailed API documentation

---

## Privacy & Security

### Data Protection Principles

1. **Local-First Architecture**
   - All health data stored locally
   - SQLite database with encryption
   - No cloud dependencies for core features
   - Optional encrypted iCloud backup

2. **Encryption at Rest**
   ```swift
   // Using CryptoKit for encryption
   let encryptedData = try encrypt(healthData, using: encryptionKey)
   ```

3. **Keychain for Secrets**
   ```swift
   // Store encryption keys in Keychain
   try Keychain.shared.save(key: encryptionKey, forAccount: "healthData")
   ```

4. **File System Protection**
   ```swift
   // Set file protection attributes
   var attributes = [FileAttributeKey: Any]()
   attributes[.protectionKey] = FileProtectionType.complete
   try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
   ```

### Network Security

```swift
// TLS 1.2+ only
let config = URLSessionConfiguration.default
config.tlsMinimumSupportedProtocolVersion = .TLSv12

// Validate server certificates
func urlSession(_ session: URLSession,
                didReceive challenge: URLAuthenticationChallenge)
    -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    // Implement certificate validation
    return (.performDefaultHandling, nil)
}
```

### Privacy Guidelines for AI Assistants

#### DO ✅
- Use local storage first
- Encrypt sensitive data
- Store credentials in Keychain
- Validate all inputs
- Log security events
- Use secure file attributes
- Provide user control over backups

#### DON'T ❌
- Commit PHI (Protected Health Information)
- Commit API keys or secrets
- Send health data to cloud without explicit consent
- Log sensitive data
- Use insecure network connections
- Store passwords in plain text
- Make cloud services required

### .gitignore Protection

The `.gitignore` file protects:
```
# Health data
*.sqlite
*.sqlite-wal
*.sqlite-shm
Documents/HealthApp/
LocalDocuments/

# Secrets
Config/Production.plist
Config/Secrets.plist
.env
.env.local
.env.production

# Certificates
*.p12
*.mobileprovision
AuthKey_*.p8

# Internal docs with PHI
HIPAA_Compliance_Remediation_Plan.md
```

### HIPAA Awareness

**IMPORTANT**: BisonHealth AI is for **personal use only** and is **NOT HIPAA compliant**.

- ❌ Not for healthcare providers
- ❌ Not for clinical use
- ❌ No Business Associate Agreements (BAAs)
- ✅ For individual personal health tracking
- ✅ Consumer-grade privacy protections

**Disclaimers**: See `FirstLaunchDisclaimerView.swift` for required user acceptance.

---

## Common Tasks

### Adding a New Health Data Type

#### Step 1: Update Enum
```swift
// In HealthDataProtocol.swift
enum HealthDataType: String, Codable {
    case personalInfo = "personal_info"
    case bloodTest = "blood_test"
    case newDataType = "new_data_type"  // Add here
}
```

#### Step 2: Create Model
```swift
// Create NewDataType.swift in Models/
struct NewDataType: HealthDataProtocol {
    let id: UUID
    let dataType: HealthDataType = .newDataType
    var lastModified: Date

    // Custom fields
    var customField: String
}
```

#### Step 3: Update Database
```swift
// Increment version in DatabaseManager.swift
private static let currentDatabaseVersion = 6

// Add migration
case 6:
    // Create new table
    try db.run(newDataTypeTable.create { t in
        t.column(id, primaryKey: true)
        t.column(customField)
        t.column(lastModified)
    })
```

#### Step 4: Add Manager Methods
```swift
// In HealthDataManager.swift
func saveNewDataType(_ data: NewDataType) async throws {
    try await databaseManager.saveNewDataType(data)
    await loadNewDataTypes()
}

func loadNewDataTypes() async throws -> [NewDataType] {
    return try await databaseManager.loadNewDataTypes()
}
```

#### Step 5: Create UI
```swift
// Create NewDataTypeView.swift
struct NewDataTypeView: View {
    @StateObject private var healthDataManager = HealthDataManager()

    var body: some View {
        // Implementation
    }
}
```

#### Step 6: Add Tests
```swift
// In HealthDataManagerTests.swift
func testSaveNewDataType_Success() async throws {
    // Given
    let data = NewDataType(...)

    // When
    try await sut.saveNewDataType(data)

    // Then
    XCTAssertTrue(mockDatabase.saveCalled)
}
```

### Adding a New AI Provider

#### Step 1: Create Client
```swift
// Create NewAIClient.swift in Services/
class NewAIClient: AIProviderInterface {
    func sendMessage(_ message: String, context: String) async throws -> String {
        // Implementation
    }

    func testConnection() async -> Bool {
        // Implementation
    }
}
```

#### Step 2: Update Settings
```swift
// Add to AIProvider enum
enum AIProvider: String {
    case ollama
    case bedrock
    case newProvider  // Add here
}
```

#### Step 3: Update AIChatManager
```swift
// In AIChatManager.swift
private func getAIClient() -> AIProviderInterface {
    switch currentProvider {
    case .ollama: return ollamaClient
    case .bedrock: return bedrockClient
    case .newProvider: return newAIClient
    }
}
```

#### Step 4: Create Settings View
```swift
// Create NewAIProviderSettingsView.swift
struct NewAIProviderSettingsView: View {
    // Configuration UI
}
```

### Adding a New Document Type

#### Step 1: Update Enum
```swift
// In MedicalDocument.swift
enum DocumentCategory: String, Codable {
    case doctorNotes = "doctor_notes"
    // ...
    case newDocType = "new_doc_type"  // Add here
}
```

#### Step 2: Update Extraction Logic
```swift
// In MedicalDocumentExtractor.swift
// Add extraction rules for new document type
```

#### Step 3: Update UI
```swift
// Add to DocumentTypeSelectorView.swift
// Add icon and label for new type
```

### Implementing a New View

#### Template
```swift
import SwiftUI

struct NewFeatureView: View {
    // MARK: - Properties
    @StateObject private var manager = FeatureManager()
    @State private var showingSheet = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Body
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feature Title")
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingSheet) { DetailView() }
    }

    // MARK: - View Components
    @ViewBuilder
    private var content: some View {
        List {
            // Content
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Add") { showingSheet = true }
                .accessibilityLabel("Add new item")
        }
    }
}

// MARK: - Preview
struct NewFeatureView_Previews: PreviewProvider {
    static var previews: some View {
        NewFeatureView()
    }
}
```

---

## Troubleshooting

### Common Issues

#### 1. Scheme Not Found
**Error**: `xcodebuild: error: The project named "HealthApp" does not contain a scheme named "HealthApp"`

**Solution**: Check that `HealthApp.xcscheme` exists in `HealthApp.xcodeproj/xcshareddata/xcschemes/`

#### 2. Simulator Not Available
**Error**: `Unable to find destination matching 'platform=iOS Simulator,name=iPhone 16 Pro'`

**Solutions**:
- Install iOS 18.6 runtime via Xcode > Settings > Platforms
- Use alternative simulator: `iPhone 15`, `iPhone 16`, etc.
- List available simulators: `xcrun simctl list devices`

#### 3. Package Resolution Failures
**Error**: SPM fails to resolve dependencies

**Solutions**:
```bash
# Reset package caches
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData

# Resolve packages
xcodebuild -resolvePackageDependencies -scheme HealthApp
```

#### 4. Database Migration Errors
**Error**: App crashes on launch after update

**Solutions**:
- Check console logs for migration errors
- Verify `currentDatabaseVersion` was incremented
- Check migration logic in `performMigration`
- Restore from backup if needed

#### 5. Document Picker Console Errors (Safe to Ignore)
**Errors**:
```
Error acquiring assertion: <Error Domain=RBSAssertionErrorDomain...
LaunchServices: store (null) or url (null) was nil...
```

**Status**: ✅ Safe to ignore - iOS Simulator development environment issue
- Occurs only in development/simulator
- Does not affect functionality
- Will not appear in production

### Development Environment Issues

#### Keychain Access Warnings
**Safe to ignore in simulator** - Expected behavior in development environment

#### SQLite Warnings During Migrations
**Safe to ignore** - Normal during schema updates

#### Network Timeouts
**Expected when external services unavailable** (Ollama, Docling, Bedrock)

### Project Recovery

If project becomes corrupted:

1. **Check project.pbxproj**:
   ```bash
   git diff HealthApp/HealthApp.xcodeproj/project.pbxproj
   ```

2. **Restore from git**:
   ```bash
   git checkout HEAD -- HealthApp/HealthApp.xcodeproj/project.pbxproj
   ```

3. **Clean build folder**:
   ```bash
   xcodebuild clean -scheme HealthApp
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

4. **Resolve packages**:
   ```bash
   xcodebuild -resolvePackageDependencies
   ```

### Debug Logging

The app uses emoji-prefixed logs for easy filtering:

```
📁 - File system operations
📷 - Camera/document scanning
🖼️ - Image processing
💬 - Chat operations
🗄️ - Database operations
🔒 - Encryption/security
📡 - Network operations
```

Filter logs in Xcode Console using these prefixes.

---

## Quick Reference

### Project Stats
- **Language**: Swift 5.9+
- **Platform**: iOS 17.0+
- **Architecture**: MVVM
- **Total Files**: 107 Swift files
- **Tests**: 19 test files
- **External Packages**: 30+

### Key Files
- **Entry Point**: `HealthApp/HealthApp/HealthAppApp.swift`
- **Root View**: `HealthApp/HealthApp/ContentView.swift`
- **Database**: `HealthApp/HealthApp/Database/DatabaseManager.swift`
- **Project**: `HealthApp/HealthApp.xcodeproj`

### Essential Commands
```bash
# Open project
open HealthApp/HealthApp.xcodeproj

# Build (when requested)
xcodebuild -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Test (when requested)
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Documentation Files
- `README.md` - Project overview
- `CONTRIBUTING.md` - Contribution guidelines
- `AGENTS.md` - AI agent guidelines
- `HealthApp/CLAUDE.md` - iOS app specific guide
- `HealthApp/OLLAMA_SWIFT_INTEGRATION.md` - Ollama integration
- `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` - Document processing
- `DOCLING_FORMATS_EXPLANATION.md` - Docling API reference

### Support
- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Security**: Email security concerns (do not open public issues)

---

## Version History

- **v5.0** - Current database version
- **v4.0** - Medical document management
- **v3.0** - Multiple AI providers
- **v2.0** - Document processing
- **v1.0** - Initial release

---

**Last Updated**: 2025-11-18

**Maintained By**: BisonHealth AI Team

**License**: MIT
