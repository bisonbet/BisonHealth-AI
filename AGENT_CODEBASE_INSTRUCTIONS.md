# BisonHealth-AI Codebase Agent Instructions

## Codebase Overview

### Project Structure
```
BisonHealth-AI/
├── HealthApp/
│   ├── HealthApp/                  # Main iOS application
│   │   ├── Assets.xcassets/        # App assets (icons, colors)
│   │   ├── Database/               # Database management and models
│   │   ├── Managers/               # Core application managers
│   │   ├── Models/                 # Data models and structures
│   │   ├── Networking/             # Network operations and clients
│   │   ├── Services/               # AI and external service integrations
│   │   ├── Utils/                  # Utility classes and helpers
│   │   ├── ViewModels/             # View model layer
│   │   ├── Views/                  # SwiftUI views
│   │   ├── ContentView.swift       # Main content view
│   │   └── HealthAppApp.swift      # App entry point
│   ├── HealthAppTests/            # Unit tests
│   ├── HealthAppUITests/          # UI tests
│   └── HealthApp.xcodeproj/       # Xcode project
├── Documentation/                 # Project documentation
├── Legacy/                       # Legacy reference code (read-only)
└── Configuration files            # Various config files
```

### Key Components

#### 1. AI Integration Architecture
- **AIChatManager.swift**: Central chat management
- **AIProviderInterface.swift**: Protocol for AI providers
- **OllamaClient.swift**: Local Ollama integration
- **BedrockClient.swift**: AWS Bedrock integration
- **OpenAICompatibleClient.swift**: OpenAI-compatible API integration

#### 2. Data Management
- **DatabaseManager.swift**: Core database operations
- **HealthDataManager.swift**: Health data processing

#### 3. Core Managers
- **SettingsManager.swift**: Application settings and preferences
- **ErrorHandler.swift**: Centralized error handling
- **Logger.swift**: Logging system
- **NetworkManager.swift**: Network connectivity monitoring

#### 4. Models
- **ChatModels.swift**: Chat conversation models
- **HealthDataProtocol.swift**: Health data structures

#### 5. Services
- **DocumentProcessor.swift**: Document processing
- **MedicalDocumentExtractor.swift**: Medical document parsing
- **BloodTestMappingService.swift**: Blood test data handling

## Agent Instructions

### General Rules

1. **NO FILE CREATION WITHOUT EXPLICIT REQUEST**
   - Never create new files unless explicitly requested by user
   - Always ask for confirmation before creating files
   - Prefer modifying existing files over creating new ones

2. **CODE QUALITY STANDARDS**
   - Follow existing code style and patterns
   - Use Swift API Design Guidelines
   - 4-space indentation, no force-unwraps
   - Add proper documentation and MARK comments
   - Maintain consistent naming conventions

3. **XCODE PROJECT INTEGRATION**
   - When creating new Swift files, they MUST be added to Xcode project
   - Required: PBXBuildFile, PBXFileReference, group membership, build phase
   - Use Xcode's "Add Files" or proper script integration

4. **TESTING REQUIREMENTS**
   - Add tests for new functionality in appropriate test files
   - Follow existing test patterns and naming conventions
   - Ensure tests are added to test targets in Xcode project

### Workflow Guidelines

#### Issue Analysis
1. **Reproduce the Problem**: Understand exact steps to reproduce
2. **Review Debug Logs**: Check existing logging for clues
3. **Code Tracing**: Follow execution path through relevant files
4. **Root Cause Identification**: Find the actual cause, not just symptoms

#### Implementation
1. **Minimal Changes**: Make smallest possible changes to fix issues
2. **Backward Compatibility**: Ensure changes don't break existing functionality
3. **Error Handling**: Add proper error handling and user feedback
4. **Logging**: Add appropriate debug/logging for troubleshooting
5. **Documentation**: Update relevant documentation

#### Testing
1. **Unit Tests**: Add or update unit tests
2. **Integration Tests**: Verify component interactions
3. **Manual Testing**: Provide clear testing instructions
4. **Edge Cases**: Consider and test edge cases

### Specific Component Guidelines

#### AI Integration
- **Ollama**: Network-based local AI
- **Bedrock**: AWS cloud AI with authentication
- **OpenAI**: Compatible API endpoints

#### Database Operations
- **Thread Safety**: All database operations must be thread-safe
- **Error Handling**: Proper error handling for database failures
- **Migration**: Consider data migration for schema changes

### Debugging Best Practices

1. **Add Temporary Debug Logging**: Use `print()` or `logger.debug()`
2. **Remove Debug Code**: Clean up temporary debug code after fixing
3. **Use Existing Patterns**: Follow existing debug logging patterns
4. **Log Key Decisions**: Log important branching decisions
5. **Include Context**: Log relevant variable values and states

### File Modification Rules

#### When to Modify Files
- Fixing bugs in existing functionality
- Adding new features to existing components
- Improving existing code quality
- Adding documentation to existing files

#### When NOT to Modify Files
- Legacy reference code (read-only)
- Generated files (e.g., Xcode project files)
- Configuration files without explicit instruction
- Files outside the main HealthApp directory

### Common Patterns to Follow

#### Error Handling
```swift
do {
    try someOperation()
} catch {
    logger.error("Operation failed", error: error)
    errorHandler.handle(error, context: "OperationContext")
    // Provide user feedback
}
```

#### Logging
```swift
// Debug logging
logger.debug("Processing started with \(input.count) items")

// Info logging
logger.info("✅ Operation completed successfully")

// Error logging
logger.error("❌ Operation failed", error: error)
```

#### Async Operations
```swift
Task {
    do {
        let result = try await asyncOperation()
        await MainActor.run {
            // Update UI or state
        }
    } catch {
        handleError(error)
    }
}
```

### Documentation Requirements

1. **Code Comments**: Add MARK comments for sections
2. **Function Documentation**: Document parameters and returns
3. **Complex Logic**: Explain non-obvious logic
4. **TODO Comments**: Mark incomplete work with TODO:
5. **FIXME Comments**: Mark known issues with FIXME:

### Testing Requirements

1. **Unit Tests**: Test individual components in isolation
2. **Integration Tests**: Test component interactions
3. **UI Tests**: Test user interface flows
4. **Performance Tests**: Test with large datasets
5. **Error Condition Tests**: Test failure scenarios

### Git Workflow

1. **Small Commits**: Make small, focused commits
2. **Descriptive Messages**: Use conventional commit format
3. **Commit Message Format**: `type(scope): description`
4. **Examples**:
   - `fix(chat): correct turn detection logic`
   - `docs: update AI integration guide`
   - `refactor(manager): improve error handling`

### Security Considerations

1. **No Hardcoded Secrets**: Never commit API keys or credentials
2. **Data Protection**: Use appropriate protection for sensitive data
3. **Network Security**: Use HTTPS and proper certificate validation
4. **Input Validation**: Validate all external inputs
5. **Error Messages**: Don't expose sensitive information in errors

## Common Issues and Solutions

### Database Issues
- **Migration Problems**: Check schema versions and migration paths
- **Threading Issues**: Ensure all operations are on correct queues
- **Performance Issues**: Review query efficiency and indexing

### Network Issues
- **Connection Problems**: Check network monitoring and retry logic
- **Authentication Issues**: Verify credential handling
- **Timeout Issues**: Review timeout settings and retry policies

## Emergency Procedures

1. **Critical Bugs**: Focus on minimal fix to restore functionality
2. **Data Corruption**: Implement recovery procedures first
3. **Crashes**: Add crash protection before fixing root cause
4. **Security Issues**: Prioritize security fixes immediately

## Code Review Checklist

1. **Functionality**: Does it solve the problem?
2. **Error Handling**: Are all error cases handled?
3. **Performance**: Are there performance implications?
4. **Memory**: Are there memory management issues?
5. **Thread Safety**: Is the code thread-safe?
6. **Testing**: Are there adequate tests?
7. **Documentation**: Is the code well documented?
8. **Consistency**: Does it follow existing patterns?
9. **Security**: Are there security implications?
10. **User Experience**: Does it provide good user feedback?

## Remember: NO FILE CREATION WITHOUT EXPLICIT REQUEST!

Always ask for confirmation before creating any new files. Prefer modifying existing files whenever possible.
