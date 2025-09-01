# Contributing to BisonHealth AI

Thank you for your interest in contributing to BisonHealth AI! This document provides guidelines and information for contributors.

## 🤝 How to Contribute

### Reporting Issues

1. **Check existing issues** first to avoid duplicates
2. **Use the issue templates** when available
3. **Provide detailed information** including:
   - iOS version and device model
   - Steps to reproduce the issue
   - Expected vs actual behavior
   - Screenshots or logs if applicable

### Suggesting Features

1. **Check the roadmap** in README.md to see if it's already planned
2. **Open a feature request** with detailed description
3. **Explain the use case** and why it would be valuable
4. **Consider privacy implications** for health data features

### Code Contributions

1. **Fork the repository** and create a feature branch
2. **Follow the coding standards** outlined below
3. **Write tests** for new functionality
4. **Update documentation** as needed
5. **Submit a pull request** with clear description

## 📋 Development Setup

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ deployment target
- Swift 5.9+
- Git

### Local Development

1. **Clone your fork:**
   ```bash
   git clone git@github.com:yourusername/BisonHealth-AI.git
   cd BisonHealth-AI
   ```

2. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Open in Xcode:**
   ```bash
   open BisonHealthAI.xcodeproj
   ```

4. **Make your changes** following the guidelines below

5. **Test your changes:**
   ```bash
   # Run unit tests
   xcodebuild test -scheme BisonHealthAI -destination 'platform=iOS Simulator,name=iPhone 15'
   
   # Run UI tests
   xcodebuild test -scheme BisonHealthAIUITests -destination 'platform=iOS Simulator,name=iPhone 15'
   ```

## 🎯 Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with these additions:

#### Naming Conventions
```swift
// Use descriptive names
func processHealthDocument(_ document: HealthDocument) -> ProcessingResult

// Use clear parameter labels
func saveBloodTest(_ result: BloodTestResult, to database: DatabaseManager)

// Use meaningful variable names
let encryptedHealthData = encrypt(personalInfo)
```

#### Code Organization
```swift
// MARK: - Properties
private let databaseManager: DatabaseManager
@Published var healthData: [HealthDataProtocol] = []

// MARK: - Initialization
init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
}

// MARK: - Public Methods
func loadHealthData() async throws {
    // Implementation
}

// MARK: - Private Methods
private func validateHealthData(_ data: HealthDataProtocol) -> Bool {
    // Implementation
}
```

#### Error Handling
```swift
// Use specific error types
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
}

// Handle errors appropriately
do {
    try await saveHealthData(personalInfo)
} catch let error as HealthDataError {
    logger.error("Health data error: \(error.localizedDescription)")
    throw error
} catch {
    logger.error("Unexpected error: \(error)")
    throw HealthDataError.databaseUnavailable
}
```

### SwiftUI Guidelines

#### View Structure
```swift
struct HealthDataView: View {
    // MARK: - Properties
    @StateObject private var viewModel: HealthDataViewModel
    @State private var showingEditor = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            content
                .navigationTitle("Health Data")
                .toolbar { toolbarContent }
        }
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
}
```

#### Accessibility
```swift
// Always include accessibility labels
Button("Add Blood Test") {
    showingBloodTestEntry = true
}
.accessibilityLabel("Add new blood test result")
.accessibilityHint("Opens form to enter blood test data")

// Support Dynamic Type
Text("Health Summary")
    .font(.title2)
    .dynamicTypeSize(.large...accessibility5)
```

### Privacy & Security Guidelines

#### Data Handling
```swift
// Always encrypt sensitive health data
func savePersonalInfo(_ info: PersonalHealthInfo) async throws {
    let encryptedData = try encrypt(info, using: encryptionKey)
    try await databaseManager.save(encryptedData)
}

// Use secure file operations
func saveDocument(_ document: Data, to path: URL) throws {
    var attributes = [FileAttributeKey: Any]()
    attributes[.protectionKey] = FileProtectionType.complete
    try document.write(to: path, options: .atomic)
    try FileManager.default.setAttributes(attributes, ofItemAtPath: path.path)
}
```

#### Network Security
```swift
// Use secure connections only
let configuration = URLSessionConfiguration.default
configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
let session = URLSession(configuration: configuration)

// Validate server certificates
func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    // Implement certificate pinning if needed
    return (.performDefaultHandling, nil)
}
```

## 🧪 Testing Guidelines

### Unit Tests
```swift
class HealthDataManagerTests: XCTestCase {
    var healthDataManager: HealthDataManager!
    var mockDatabase: MockDatabaseManager!
    
    override func setUp() {
        super.setUp()
        mockDatabase = MockDatabaseManager()
        healthDataManager = HealthDataManager(databaseManager: mockDatabase)
    }
    
    func testSavePersonalInfo() async throws {
        // Given
        let personalInfo = PersonalHealthInfo(name: "Test User")
        
        // When
        try await healthDataManager.savePersonalInfo(personalInfo)
        
        // Then
        XCTAssertTrue(mockDatabase.saveCalled)
        XCTAssertEqual(mockDatabase.savedData?.name, "Test User")
    }
}
```

### UI Tests
```swift
class HealthDataUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }
    
    func testAddPersonalInfo() {
        // Navigate to health data tab
        app.tabBars.buttons["Health Data"].tap()
        
        // Tap add button
        app.navigationBars.buttons["Add"].tap()
        
        // Select personal info
        app.buttons["Personal Info"].tap()
        
        // Fill form
        let nameField = app.textFields["Name"]
        nameField.tap()
        nameField.typeText("John Doe")
        
        // Save
        app.buttons["Save"].tap()
        
        // Verify
        XCTAssertTrue(app.staticTexts["John Doe"].exists)
    }
}
```

## 📝 Documentation

### Code Documentation
```swift
/// Manages health data storage and retrieval with encryption
///
/// This class provides a secure interface for storing personal health information
/// locally on the device. All data is encrypted before storage and decrypted
/// when retrieved.
///
/// - Important: This class handles sensitive health data and must maintain
///   strict privacy and security standards.
class HealthDataManager: ObservableObject {
    
    /// Saves personal health information to encrypted local storage
    ///
    /// - Parameter info: The personal health information to save
    /// - Throws: `HealthDataError.encryptionFailed` if encryption fails
    /// - Throws: `HealthDataError.databaseUnavailable` if database is unavailable
    func savePersonalInfo(_ info: PersonalHealthInfo) async throws {
        // Implementation
    }
}
```

### README Updates
When adding new features, update the README.md to include:
- Feature description in the overview
- Any new setup requirements
- Updated roadmap if applicable

## 🔄 Pull Request Process

### Before Submitting
1. **Ensure all tests pass** locally
2. **Run the linter** and fix any issues
3. **Update documentation** for any API changes
4. **Add tests** for new functionality
5. **Check accessibility** with VoiceOver

### PR Description Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] UI tests added/updated
- [ ] Manual testing completed
- [ ] Accessibility testing completed

## Privacy Impact
- [ ] No sensitive data handling changes
- [ ] New sensitive data handling (describe below)
- [ ] Changes to encryption/security (describe below)

## Screenshots
(If applicable)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] No breaking changes (or documented)
```

### Review Process
1. **Automated checks** must pass (tests, linting)
2. **Code review** by at least one maintainer
3. **Privacy review** for any health data changes
4. **Accessibility review** for UI changes
5. **Final approval** and merge

## 🚀 Release Process

### Version Numbering
We use semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist
- [ ] All tests passing
- [ ] Documentation updated
- [ ] Privacy policy reviewed
- [ ] App Store metadata updated
- [ ] TestFlight testing completed
- [ ] Release notes prepared

## 🛡️ Security

### Reporting Security Issues
**Do not open public issues for security vulnerabilities.**

Instead, email security concerns to: [security@bisonhealth.ai]

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Security Guidelines
- Never commit sensitive data (keys, passwords, health data)
- Use encryption for all health data storage
- Validate all user inputs
- Follow iOS security best practices
- Regular security audits of dependencies

## 📞 Getting Help

### Community Support
- **GitHub Discussions**: For general questions and community help
- **GitHub Issues**: For bug reports and feature requests
- **Documentation**: Check the `/Docs/` directory first

### Maintainer Contact
For urgent issues or questions about contributing:
- Open a GitHub issue with the `question` label
- Tag maintainers in discussions

## 📄 License

By contributing to BisonHealth AI, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to BisonHealth AI! Your help makes this project better for everyone who values health data privacy and control. 🙏