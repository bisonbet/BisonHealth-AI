# CLAUDE.md - BisonHealth AI iOS Project Guide

## Project Overview

**BisonHealth AI** is a privacy-first iOS application for personal health data management with AI-powered assistance. The app prioritizes local data storage with encryption and provides AI chat functionality using personal health data as context.

This iOS app is based on a legacy Next.js web application (see [Legacy Reference](#legacy-reference) below) and implements similar functionality with a native iOS interface optimized for both iPhone and iPad.

### Key Features
- Local encrypted health data storage using SQLite
- Document scanning and processing (camera + file import)
- AI chat assistant with health context (via Ollama or on-device LLM)
- **On-device LLM**: Run medical AI models locally for complete privacy (requires 6GB+ RAM)
- Document processing via Docling server
- Optional iCloud encrypted backup
- Health data export (JSON/PDF)
- **Universal iOS App**: Optimized for iPhone and iPad with adaptive layouts

## Architecture

### MVVM Pattern with SwiftUI
- **Models**: Core data structures and protocols (`Models/`)
- **Views**: SwiftUI UI components (`Views/` + ContentView.swift)
- **ViewModels**: Business logic managers (`Managers/`)
- **Services**: External service clients (`Services/`)
- **Database**: SQLite management with encryption (`Database/`)
- **Utils**: Utility classes and extensions (`Utils/`)

### Core Components

#### 1. Data Layer
- **DatabaseManager**: SQLite database with encryption
- **FileSystemManager**: Local file storage management
- **Models**: HealthDataProtocol conforming structs
- **Health Data Types**: PersonalInfo, BloodTest, ImagingReport, HealthCheckup

#### 2. Service Layer
- **OllamaClient**: AI chat service (local Ollama server)
- **DoclingClient**: Document processing service
- **AIProviderInterface**: Protocol for AI service abstraction

#### 3. Manager Layer (ViewModels)
- **HealthDataManager**: Health data CRUD operations
- **DocumentManager**: Document import, processing, management
- **AIChatManager**: Chat conversations with health context

#### 4. UI Layer
- **TabView Structure**: HealthData, Documents, Chat, Settings
- **SwiftUI Components**: Forms, lists, sheets, navigation

## Development Guidelines

### Build Configuration
- **Primary iOS Simulator**: iPhone 16 (iOS 18.6)
- **iPad Testing Simulator**: iPad Pro 11-inch (M4) (iOS 18.6)
- **Target Devices**: iPhone and iPad (Universal app - `TARGETED_DEVICE_FAMILY = "1,2"`)
- **Minimum iOS Version**: 17.0+
- **Xcode Version**: 15.0+
- **Swift Version**: 5.9+

### Dependencies
- **SQLite.swift**: Database management
- **CryptoKit**: Built-in encryption
- **VisionKit**: Built-in document scanning
- **PhotosUI**: Built-in photo selection

### Build Commands

⚠️ **CRITICAL RULE**: **NEVER** run `xcodebuild` or any build commands unless the user **EXPRESSLY** asks you to build the project.

❌ **DO NOT**:
- Run builds after making changes
- Run builds to "verify" or "test" code
- Run builds proactively
- Run builds to check for errors
- Run any `xcodebuild` commands without explicit user request

✅ **ONLY build when user explicitly says**:
- "build the project"
- "run a build"
- "compile the app"
- "test the build"

Available build commands (use only when explicitly requested):
```bash
# iPhone build command
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' clean build

# iPad build command
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' clean build

# Test command (both iPhone and iPad)
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' test
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' test
```

## Code Standards

### Swift Coding Style
- Use SwiftUI for all UI components
- **NavigationStack**: Use `NavigationStack` instead of deprecated `NavigationView` for iPad compatibility
- Follow Apple's Swift API Design Guidelines
- Use `@MainActor` for UI-related ObservableObject classes
- Prefer composition over inheritance
- Use meaningful, descriptive names
- Group code with `// MARK: -` comments

### iPad Compatibility Guidelines
- **Universal App**: All features must work on both iPhone and iPad
- **Adaptive Layouts**: Use size classes and adaptive layouts where appropriate
- **Navigation**: Always use `NavigationStack` for proper iPad split-view support
- **Testing**: Test on both iPhone and iPad simulators before deployment
- **Target Settings**: Ensure `TARGETED_DEVICE_FAMILY = "1,2"` for all targets

### Architecture Patterns
- **MVVM**: ViewModels as ObservableObject managers
- **Dependency Injection**: Shared instances passed to managers
- **Protocol-Oriented**: Use protocols for service abstraction
- **Async/Await**: For all async operations
- **Error Handling**: Comprehensive error types with recovery suggestions

### Data Management
- All health data must be encrypted at rest
- Use SQLite for structured data storage
- FileSystem for document/image storage
- Optional iCloud encrypted backup
- No cloud dependencies for core functionality

## Data Safety & Migration Guidelines

⚠️ **CRITICAL**: Always follow these guidelines when modifying data models to prevent user data loss:

### Database Version Management
- **Current Database Version**: 2 (see `DatabaseManager.currentDatabaseVersion`)
- **Version Tracking**: Database versions are tracked in the `database_version` table
- **Automatic Backups**: System creates backups before any migration

### When Making Model Changes

#### 1. **BEFORE Making Changes**
```bash
# Always increment database version when modifying data models
DatabaseManager.currentDatabaseVersion = 3  // Increment by 1
```

#### 2. **Safe Changes (No Migration Required)**
- Adding optional fields with default values
- Adding new computed properties
- Adding new methods to existing types
- Modifying UI-only components

#### 3. **Changes Requiring Migration**
- Adding required fields to existing models
- Removing fields from models
- Changing field types
- Renaming fields
- Restructuring data relationships

#### 4. **Migration Implementation**
When making breaking changes, add a migration case in `performMigration(db:toVersion:)`:

```swift
case 3: // Your new version number
    // Migration for version 3: Describe what changed
    // Add specific migration logic here
    print("   ✓ Description of migration")
```

### Migration Best Practices

#### Safe Migration Examples:
```swift
// ✅ SAFE: Adding optional field with default
struct PersonalHealthInfo {
    var newOptionalField: String? = nil  // Safe - has default
}

// ✅ SAFE: Adding computed property
extension PersonalHealthInfo {
    var computedProperty: String { return "value" }  // Safe - not stored
}
```

#### Dangerous Changes:
```swift
// ❌ DANGEROUS: Adding required field without migration
struct PersonalHealthInfo {
    var newRequiredField: String  // Will break existing data!
}

// ❌ DANGEROUS: Removing existing field without migration
struct PersonalHealthInfo {
    // var existingField: String  // Removed - will break!
}

// ❌ DANGEROUS: Changing field type without migration
struct PersonalHealthInfo {
    var existingField: Int  // Was String before - will break!
}
```

### Testing Data Changes

#### Before Committing:
1. **Test with existing data**: Use app with existing database
2. **Test fresh install**: Verify new installations work
3. **Test migration**: Delete app, reinstall, verify data loads
4. **Test version detection**: Verify console shows correct migration messages

#### Migration Testing Checklist:
- [ ] Fresh database starts at current version
- [ ] Existing database migrates without data loss
- [ ] Migration backup is created
- [ ] Console shows migration progress
- [ ] All existing functionality works post-migration
- [ ] New features work correctly

### Database Reset Functionality

#### For Development:
- Database reset available in advanced settings
- Creates warning dialog before deletion
- Completely removes database and recreates from scratch
- **Use only when necessary** - production users will lose all data

#### Implementation:
```swift
// Available in DatabaseManager
try DatabaseManager.shared.resetDatabase()
```

### Recovery Options

#### Automatic Backups:
- Created before each migration as `health_data.sqlite.backup.[timestamp]`
- Located in app's Database directory
- Can be manually restored by developer if needed

#### Manual Recovery:
```swift
// To restore from backup (emergency use only):
// 1. Locate backup file in app's Database directory
// 2. Replace current database with backup
// 3. Restart app
```

### Developer Guidelines

#### When Adding New Health Data Types:
1. Add to `HealthDataType` enum
2. Create conforming model with `HealthDataProtocol`
3. Increment database version if changing existing types
4. Add migration logic if needed
5. Test thoroughly with existing data

#### When Modifying Existing Types:
1. **ALWAYS** increment `currentDatabaseVersion`
2. Add migration case in `performMigration`
3. Test migration with populated database
4. Document changes in migration comments

#### Warning Signs - Check These:
- Compilation errors about missing fields
- App crashes on startup with existing data
- Data not loading in UI
- Console errors about deserialization
- Missing health information that was previously entered

### Emergency Procedures

#### If Users Report Data Loss:
1. Check if database version was incremented
2. Verify migration logic is present
3. Check console logs for migration errors
4. Consider providing manual data export/import tool

#### Prevention Checklist:
- [ ] Database version incremented for breaking changes
- [ ] Migration logic implemented and tested
- [ ] Backup functionality verified
- [ ] Changes tested with existing data
- [ ] No compilation errors related to data models

## Key Files and Structure

```
HealthApp/
├── HealthAppApp.swift           # App entry point + AppState
├── ContentView.swift            # Main TabView interface
├── Models/                      # Data models
│   ├── HealthDataProtocol.swift # Base protocol + enums
│   ├── PersonalHealthInfo.swift # Personal info model
│   ├── BloodTestResult.swift    # Blood test model
│   ├── HealthDocument.swift     # Document model
│   ├── ChatModels.swift         # Chat conversation models
│   └── PlaceholderModels.swift  # Future data type placeholders
├── Views/                       # SwiftUI views
│   └── HealthDataContextSelector.swift
├── ViewModels/                  # (Currently empty - using Managers)
├── Managers/                    # Business logic (ViewModels)
│   ├── HealthDataManager.swift  # Health data operations
│   ├── DocumentManager.swift    # Document operations
│   └── AIChatManager.swift      # Chat operations
├── Services/                    # External service clients
│   ├── AIProviderInterface.swift # AI service protocol
│   ├── OllamaClient.swift       # Ollama AI client
│   ├── DoclingClient.swift      # Document processing client
│   └── DocumentProcessor.swift  # Document processing logic
├── Database/                    # SQLite management
│   ├── DatabaseManager.swift    # Core database operations
│   ├── DatabaseManager+HealthData.swift
│   ├── DatabaseManager+Documents.swift
│   ├── DatabaseManager+Chat.swift
│   └── Keychain.swift           # Keychain utilities
└── Utils/                       # Utilities
    ├── FileSystemManager.swift  # File operations
    ├── DocumentImporter.swift   # Document import
    ├── DocumentExporter.swift   # Document export
    └── Keychain.swift           # Keychain wrapper
```

## Testing Structure

```
HealthAppTests/
├── ModelTests.swift             # Model validation tests
├── DatabaseTests.swift          # Database operation tests
├── FileSystemTests.swift        # File system tests
├── ServiceClientTests.swift     # Service client tests
├── HealthDataManagerTests.swift # Manager tests
├── AIChatManagerTests.swift     # Chat functionality tests
├── ChatIntegrationTests.swift   # Integration tests
└── DocumentProcessingIntegrationTests.swift
```

## External Services

### Ollama AI Server
- **Default**: localhost:11434
- **Purpose**: Local AI chat with health context
- **Models**: Configurable (default: llama2)
- **Features**: Chat completion, model management
- **Status**: Connection testing implemented

### Docling Document Processing Server
- **Default**: localhost:5001
- **Purpose**: Extract text/data from documents using AI-powered OCR
- **Formats**: PDF, DOCX, images (JPEG, PNG, etc.)
- **Integration**: Via DocumentProcessor and DoclingClient

#### Docling API v1 Reference
**Base URL**: `http://hostname:port`

**Key Endpoints**:
- `POST /v1/convert/file` - Synchronous document conversion (upload files)
- `POST /v1/convert/source` - Synchronous document conversion (from URLs)  
- `POST /v1/convert/file/async` - Asynchronous file conversion
- `POST /v1/convert/source/async` - Asynchronous source conversion
- `GET /v1/status/poll/{task_id}` - Check async task progress
- `/v1/status/ws/{task_id}` - WebSocket for async task updates

**Authentication**:
- Optional `X-Api-Key` header when authentication is enabled
- Configured via `DOCLING_SERVE_API_KEY` environment variable

**Health Check**:
- **No dedicated health endpoint exists**
- Use HEAD or GET request to `/v1/convert/file` to test service availability
- Service returns 405 (Method Not Allowed) for HEAD requests when running
- Service returns 200 for GET requests with proper parameters

**API Migration Notes**:
- API changed from `/v1alpha/` to `/v1/` endpoints
- Unified `sources` array replaces separate `file_sources`/`http_sources`
- New `target` specification replaces `options.return_as_file`
- Legacy v0.x API no longer supported in v1.x versions

**Common Parameters**:
- `from_formats`: Input document types (pdf, docx, image)
- `to_formats`: Output formats (md, json, etc.)
- `do_ocr`: Enable/disable OCR processing
- `ocr_engine`: OCR engine selection (easyocr, etc.)
- `sources`: Array of input sources with `kind` field

**Example v1 Sources Format**:
```json
{
  "sources": [
    {
      "kind": "file",
      "base64_string": "abc123...",
      "filename": "document.pdf"
    },
    {
      "kind": "http", 
      "url": "https://example.com/document.pdf"
    }
  ]
}
```

**Reference Documentation**:
- [Docling Serve Usage](https://github.com/docling-project/docling-serve/blob/main/docs/usage.md)
- [v1 Migration Guide](https://github.com/docling-project/docling-serve/blob/main/docs/v1_migration.md)

## On-Device LLM

### Overview
The app supports running local Large Language Models (LLMs) directly on the device for complete privacy. All AI processing happens on-device with no data sent to external servers.

**Status**: Currently using LocalLLMClient framework with MLX backend for on-device inference.

### Device Requirements

**Critical**: On-device LLM requires specific hardware capabilities:

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| **RAM** | 6GB | 8GB+ |
| **iOS Version** | 17.0+ | 18.0+ |
| **Devices** | iPhone 14 Pro or newer | iPhone 15 Pro or newer |
|  | iPad Pro (M1/M2/M4) | iPad Pro with 8GB+ RAM |

**Compatibility Check**:
- The app automatically detects device RAM using `DeviceCapability.swift`
- Users with insufficient RAM receive an alert when attempting to enable on-device LLM
- Download is blocked for incompatible devices

### Supported Models

**Current Models** (all use Q4_K_M quantization):

1. **Meditron3-Gemma2-2B** (Recommended for 6-8GB RAM)
   - Size: ~1.5GB
   - Parameters: 2B
   - Context: 8K tokens
   - Best for: Devices with exactly 6GB RAM
   - Source: `mradermacher/Meditron3-Gemma2-2B-GGUF`

2. **MedGemma-4B** (Recommended for 8GB+ RAM)
   - Size: ~2.5GB
   - Parameters: 4B
   - Context: 8K tokens
   - Best for: iPhone 15/16 Pro, iPad Pro
   - Source: `unsloth/medgemma-4b-it-GGUF`

**Quantization**:
- Only Q4_K_M is supported (optimal balance for iOS)
- Q5_K_M and Q8_0 are NOT supported (excessive memory requirements)

### Memory Management

**Without Entitlements**:
- App operates within standard iOS memory limits (~3-4GB on 8GB devices)
- No special Apple entitlements required for App Store submission
- Aggressive memory monitoring and graceful degradation

**Memory Safety**:
- Models are unloaded on memory warnings
- Device capability checks prevent downloads on incompatible devices
- File size validation before and after download

### Architecture

**Key Files**:
```
HealthApp/
├── OnDeviceLLM/
│   ├── OnDeviceLLMService.swift       # Core LLM operations
│   ├── OnDeviceLLMModels.swift        # Model definitions & config
│   ├── OnDeviceLLMSettingsView.swift  # Settings UI with RAM checks
│   └── ModelDownloadManager.swift     # Download & storage management
├── Services/
│   └── LocalLLMProvider.swift         # AIProviderInterface implementation
└── Utils/
    └── DeviceCapability.swift         # RAM detection & compatibility
```

**Storage**:
- Models stored in Application Support directory
- Downloaded model tracking via UserDefaults (not SQLite)
- No database migration required for on-device LLM

### Development Guidelines

**When Adding Models**:
1. Only add Q4_K_M quantized models
2. Verify model size is appropriate for iOS (≤2.5GB preferred)
3. Test on actual devices with 6GB and 8GB RAM
4. Update `DeviceCapability.recommendedModelID()` if needed

**When Modifying Memory Requirements**:
1. Update `DeviceCapability.minimumRAMForLLM` constant
2. Update device compatibility table in this documentation
3. Test on minimum spec device (iPhone 14 Pro with 6GB RAM)
4. Update user-facing messages in `OnDeviceLLMSettingsView`

**Testing Checklist**:
- [ ] Test RAM detection on simulators with different configurations
- [ ] Verify alert shows on devices with <6GB RAM
- [ ] Test model download on WiFi and cellular (if allowed)
- [ ] Verify model loads and generates responses
- [ ] Test memory warning handling (unload model)
- [ ] Verify storage space checks work correctly

### Security Considerations

**Entitlements**:
- `com.apple.developer.kernel.increased-memory-limit` is **NOT used**
- Standard iOS memory limits apply
- App Store submission does not require special approval

**Privacy Benefits**:
- All inference happens on-device
- No data sent to external servers
- Models downloaded once, used offline
- Complete privacy for sensitive health data

### Known Limitations

1. **Model Size**: Limited to Q4_K_M quantization only
2. **Device Support**: Requires 6GB+ RAM (excludes older devices)
3. **Performance**: Slower than cloud-based inference
4. **Vision Models**: Not currently supported (planned for future)
5. **Streaming**: Not implemented (returns full response)

### Future Enhancements

- [ ] Streaming response support
- [ ] Vision model integration for image analysis
- [ ] Model update mechanism
- [ ] Performance optimizations for lower-end devices
- [ ] Additional medical domain specialized models

## Privacy & Security

### Data Protection
- All health data encrypted using CryptoKit
- SQLite database encryption
- Keychain for sensitive configuration
- No cloud dependencies for core functionality
- Optional encrypted iCloud backup

### Permissions
- Camera: Document scanning
- Photos: Document import from photos
- No network permissions required for core functionality

## Development Workflow

### When Making Changes
1. **Read existing code** to understand patterns and architecture
2. **Follow established patterns** in similar files
3. **Use existing managers** and services where possible
4. **Test builds** using the approved iPhone 16 simulator
5. **Maintain privacy-first** approach

### Common Tasks

#### Adding New Health Data Type
1. Add enum case to `HealthDataType` in `HealthDataProtocol.swift`
2. Create new model conforming to `HealthDataProtocol`
3. Add database methods in `DatabaseManager+HealthData.swift`
4. Update `HealthDataManager` for CRUD operations
5. Add UI components to `HealthDataView`

#### Adding New Service
1. Define protocol in `Services/` directory
2. Implement client class with connection management
3. Add error handling with recovery suggestions
4. Create manager class for business logic
5. Integrate with UI via ObservableObject pattern

#### UI Development
1. Use SwiftUI exclusively
2. Follow TabView -> NavigationView -> Content pattern
3. Use sheets for modal presentations
4. Implement pull-to-refresh with `.refreshable`
5. Use proper loading and error states

## Build & Test Guidelines

### Before Committing
⚠️ **CRITICAL**: **NEVER** run build commands unless the user **EXPLICITLY** requests it with words like "build", "compile", or "test the build".

Pre-commit checklist (when explicitly requested by user):
1. Clean build: `xcodebuild clean build`
2. Run tests: `xcodebuild test`
3. Verify all imports resolve correctly
4. Check for compilation warnings

**Default behavior**: Make code changes and commit without building. Let the user decide when to build.

### Simulator Configuration
- **Primary Target**: iPhone 16, iOS 18.6
- **Secondary Target**: iPad Pro 11-inch (M4), iOS 18.6
- **Universal Design**: iPad-optimized layouts with iPhone fallbacks

## Future Enhancements

### Planned Features (Placeholder Implementation)
- Imaging reports processing
- Health checkup records
- Advanced AI model selection
- Authentication for AI services
- Streaming chat responses
- Export to additional formats

### Technical Debt
- Authentication system for AI services (TODOs in OllamaClient)
- Streaming responses implementation
- Enhanced error handling in DocumentManager
- Performance optimization for large datasets

## Troubleshooting

### Common Issues
1. **Scheme not found**: Ensure `HealthApp.xcscheme` exists in xcshareddata
2. **Build errors**: Check SQLite.swift package resolution
3. **Simulator issues**: Use iPhone 16 or any available iOS simulator
4. **Connection failures**: Verify Ollama/Docling server status

### Development Environment Issues

#### Document Picker Console Errors (Safe to Ignore)
When using "Import File" functionality, you may see these console errors:
```
📁 ContentView: Triggering document picker - LaunchServices errors will appear now
Error acquiring assertion: <Error Domain=RBSAssertionErrorDomain Code=2...
Plugin query method called
(501) Invalidation handler invoked, clearing connection
LaunchServices: store (null) or url (null) was nil...
Attempt to map database failed: permission was denied...
Failed to initialize client context with error...
```

**Status**: ✅ **SAFE TO IGNORE** - These are known iOS Simulator/development environment issues
- **Cause**: LaunchServices database access limitations in development environment
- **Impact**: None - document picker functionality works correctly
- **Occurrence**: Only in development/simulator, not in production builds
- **Solution**: These errors don't affect app functionality and will not appear in production

#### Other Development Console Messages
- **SQLite warnings**: Normal during database migrations
- **Keychain access warnings**: Expected in simulator environment
- **Network connection timeouts**: Normal when external services (Ollama/Docling) are unavailable

### Project Recovery
If project becomes corrupted:
1. Check `project.pbxproj` for missing target references
2. Verify scheme configuration
3. Rebuild package dependencies
4. Use git to restore to last working state

### Development Best Practices

#### Console Log Management
- Use descriptive log messages for debugging
- Prefix logs with emoji/component identifiers (📁, 📷, 🖼️)
- Include context about expected system errors
- Filter out known safe development warnings

#### Testing Document Import
1. **Test File Types**: PDF, images (PNG, JPEG), text files
2. **Test Multiple Selection**: Verify batch import works
3. **Test Error Handling**: Try importing unsupported files
4. **Verify Processing**: Check document processing pipeline works

#### Performance Testing
- Test with large files (>10MB)
- Test with many files (10+ documents)
- Monitor memory usage during processing
- Verify background processing doesn't block UI

---

## Legacy Reference

The iOS BisonHealth AI app is based on a legacy Next.js web application located in `/legacy/web-app/`. This web application serves as a reference for:

### Web Application Structure (`/legacy/web-app/`)
- **Framework**: Next.js 14+ with TypeScript
- **Database**: PostgreSQL with Prisma ORM
- **Frontend**: React components with Tailwind CSS
- **Authentication**: NextAuth.js with OAuth2
- **AI Integration**: Similar Ollama integration patterns
- **Document Processing**: PDF parsing and text extraction

### Key Reference Files
- **Database Schema**: `/legacy/web-app/prisma/schema.prisma`
  - User management and authentication models
  - Health data structures and relationships
  - Chat conversation and message models
  - Document storage and processing tracking

- **API Routes**: `/legacy/web-app/src/app/api/`
  - Health data CRUD operations
  - Authentication endpoints
  - Document processing pipelines
  - Chat conversation management

- **UI Components**: `/legacy/web-app/src/`
  - Health data forms and displays
  - Chat interfaces and conversation lists
  - Document upload and management
  - Settings and configuration screens

### Other Legacy Resources
- **Deployment**: `/legacy/deployment/` - Docker configurations
- **Development**: `/legacy/dev-config/` - IDE settings and configurations
- **Documentation**: `/legacy/Docs/` - Original project documentation

### Reference Usage
When adding new features or understanding data models:
1. Check the corresponding web app implementation
2. Review the Prisma schema for data relationships
3. Reference UI patterns and user flows
4. Adapt web concepts to native iOS patterns

**Note**: The legacy web application demonstrates the intended functionality but should be adapted to iOS patterns, not directly ported.

---

## Quick Reference

**Current Status**: Universal iOS app with local AI chat and document processing capabilities, optimized for iPhone and iPad.

**Next Development**: Focus on enhancing AI integration, adding more health data types, and improving document processing workflows.

**Architecture Philosophy**: Privacy-first, local-storage-centric, with optional cloud backup. No dependencies on external cloud services for core functionality. Universal app design for iPhone and iPad.