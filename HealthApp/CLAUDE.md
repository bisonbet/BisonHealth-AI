# CLAUDE.md - BisonHealth AI iOS Project Guide

## Project Overview

**BisonHealth AI** is a privacy-first iOS application for personal health data management with AI-powered assistance. The app prioritizes local data storage with encryption and provides AI chat functionality using personal health data as context.

This iOS app is based on a legacy Next.js web application (see [Legacy Reference](#legacy-reference) below) and implements similar functionality with a native iOS interface optimized for both iPhone and iPad.

### Key Features
- Local encrypted health data storage using SQLite
- Document scanning and processing (camera + file import)
- AI chat assistant with health context (via Ollama)
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
You have permission to run Xcode build commands without asking:
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

### Docling Document Processing
- **Default**: localhost:5001
- **Purpose**: Extract text/data from documents
- **Formats**: PDF, images, text files
- **Integration**: Via DocumentProcessor

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
Always run these checks (you have permission to run them automatically):
1. Clean build: `xcodebuild clean build`
2. Run tests: `xcodebuild test`
3. Verify all imports resolve correctly
4. Check for compilation warnings

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

### Project Recovery
If project becomes corrupted:
1. Check `project.pbxproj` for missing target references
2. Verify scheme configuration
3. Rebuild package dependencies
4. Use git to restore to last working state

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