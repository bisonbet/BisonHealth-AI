# 🏥 BisonHealth AI

**AI-Powered Personal Health Data Management for iOS**

<div align="center">

![iOS](https://img.shields.io/badge/iOS-17.0+-blue?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange?style=for-the-badge&logo=swift)
![SwiftUI](https://img.shields.io/badge/SwiftUI-blue?style=for-the-badge&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

</div>

---

## 🌟 Overview

BisonHealth AI is a privacy-first iOS application that empowers users to take complete control of their personal health data. By leveraging AI and personal health information, BisonHealth AI provides a private assistant that helps users better understand and manage their health - all while keeping sensitive data securely stored locally on their device.

> **⚠️ IMPORTANT: Personal Use Only**
> 
> BisonHealth AI is designed exclusively for individual, personal health tracking and management. This application is **NOT** intended for use by HIPAA Covered Entities, Business Associates, or any professional, clinical, or enterprise environments. We do not provide Business Associate Agreements (BAAs) or HIPAA-compliant guarantees. Users assume full responsibility for their own data choices and usage decisions.

### ✨ Key Features

- 📱 **Native iOS App** - Built with SwiftUI for iOS 17+
- 🔒 **Privacy-First Design** - All health data stored locally with optional iCloud backup
- 🤖 **AI-Powered Insights** - Integration with Ollama for intelligent health conversations
- 📄 **Smart Document Processing** - Automatic extraction of health data from documents using Docling
- 🩺 **Comprehensive Health Data** - Support for personal info, blood tests, imaging reports, and more
- 📊 **Data Export** - Export your data in JSON or PDF formats
- 🌙 **Accessibility** - Full support for Dark Mode, VoiceOver, and Dynamic Type
- ☁️ **Optional iCloud Backup** - Secure, encrypted backup with granular control

## 🚫 Personal Use Only - Not HIPAA Compliant

**BisonHealth AI is designed exclusively for individual, personal health management and is NOT suitable for professional, clinical, or enterprise use.**

### What This Means:
- ✅ **Personal Health Records**: Perfect for individuals managing their own health data
- ✅ **Consumer Privacy**: Built with consumer-grade privacy protections
- ✅ **Individual Control**: You maintain complete control over your personal data
- ❌ **No HIPAA Compliance**: We do not provide Business Associate Agreements (BAAs)
- ❌ **No Professional Use**: Not intended for healthcare providers, clinics, or organizations
- ❌ **No Regulated Hosting**: We do not offer HIPAA-compliant hosting or guarantees

### Your Responsibility:
As a user, you are responsible for ensuring that your use of BisonHealth AI complies with all applicable laws and regulations. If you are a healthcare provider or work in a regulated environment, you must not use this application for managing patient data or any professional healthcare activities.

## 🏗️ Architecture

BisonHealth AI follows a modular, privacy-focused architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    BisonHealth AI                           │
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
│  ├── SQLite Database Manager (Encrypted)                   │
│  ├── File System Manager                                    │
│  └── iCloud Backup Manager                                  │
├─────────────────────────────────────────────────────────────┤
│  External Service Layer                                     │
│  ├── Ollama Client (AI Chat)                               │
│  ├── Docling Client (Document Processing)                  │
│  └── Extensible AI Provider Interface                       │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Getting Started

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ deployment target
- Swift 5.9+
- Access to Ollama server for AI functionality
- Access to Docling server for document processing

### Installation

1. **Clone the repository:**
   ```bash
   git clone git@github.com:bisonbet/BisonHealth-AI.git
   cd BisonHealth-AI
   ```

2. **Open in Xcode:**
   ```bash
   open BisonHealthAI.xcodeproj
   ```

3. **Install Dependencies:**
   - Dependencies are managed via Swift Package Manager
   - Xcode will automatically resolve packages on first build

4. **Configure External Services:**
   - Set up your Ollama server for AI chat functionality
   - Set up your Docling server for document processing
   - Configure server endpoints in the app settings

### Building and Running

1. Select your target device or simulator
2. Build and run the project (⌘+R)
3. Configure server connections in Settings
4. Start importing your health data!

## 📋 Supported Health Data Types

### Currently Implemented
- **Personal Information** - Demographics, medical history, medications, allergies
- **Blood Test Results** - Comprehensive lab results with reference ranges

### Planned Features
- **Imaging Reports** - X-rays, MRIs, CT scans, ultrasounds
- **Health Checkups** - Regular health assessments and vital signs
- **Wearable Data Integration** - Apple Health, fitness trackers
- **Medication Tracking** - Prescription management and reminders

## 🔧 Configuration

### Server Setup

BisonHealth AI requires two external services:

1. **Ollama Server** - For AI chat functionality
   - Install and run Ollama on your local network or remote server
   - Configure hostname and port in app settings
   - Supports any Ollama-compatible models

2. **Docling Server** - For document processing
   - Set up Docling server for document parsing
   - Configure hostname and port in app settings
   - Processes PDFs, images, and other document formats

### Privacy Settings

- **Local Storage** - All health data encrypted and stored locally
- **iCloud Backup** - Optional, user-controlled backup to iCloud
- **Data Export** - Export your data anytime in JSON or PDF format
- **No Cloud Dependencies** - Core functionality works completely offline

## 🛠️ Development

### Project Structure

```
BisonHealthAI/
├── BisonHealthAI/
│   ├── Models/              # Data models and protocols
│   ├── Views/               # SwiftUI views and components
│   ├── ViewModels/          # MVVM view models
│   ├── Services/            # Business logic and external services
│   ├── Database/            # SQLite database management
│   ├── Utils/               # Utility functions and extensions
│   └── Resources/           # Assets, localizations, etc.
├── BisonHealthAITests/      # Unit tests
├── BisonHealthAIUITests/    # UI tests
└── Docs/                    # Documentation and specs
    └── specs/               # Detailed specification documents
```

### Key Technologies

- **SwiftUI** - Modern iOS UI framework
- **SQLite.swift** - Type-safe SQLite wrapper
- **CryptoKit** - Encryption for sensitive data
- **VisionKit** - Document scanning capabilities
- **Combine** - Reactive programming framework

### Testing

```bash
# Run unit tests
xcodebuild test -scheme BisonHealthAI -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild test -scheme BisonHealthAIUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 📖 Documentation

Detailed documentation is available in the `/Docs/specs/` directory:

- **[Requirements](Docs/specs/ios-health-app/requirements.md)** - Detailed user stories and acceptance criteria
- **[Design](Docs/specs/ios-health-app/design.md)** - Architecture and technical design
- **[Tasks](Docs/specs/ios-health-app/tasks.md)** - Implementation roadmap and task breakdown

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines for details on:

- Code style and conventions
- Testing requirements
- Pull request process
- Issue reporting

## 🔒 Privacy & Security

BisonHealth AI is built with privacy as the foundation for personal health data management:

- **Local-First** - All sensitive data stays on your device
- **Encryption** - Health data encrypted using CryptoKit
- **No Tracking** - No analytics, tracking, or data collection
- **Open Source** - Transparent, auditable codebase
- **User Control** - You decide what data to backup or export
- **Personal Use Only** - Designed for individual health management, not professional healthcare
- **Consumer-Grade Protection** - Privacy safeguards appropriate for personal use, not HIPAA compliance

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues** - Report bugs or request features via GitHub Issues
- **Discussions** - Join community discussions in GitHub Discussions
- **Documentation** - Check the `/Docs/` directory for detailed guides

## 🗺️ Roadmap

- [ ] **Phase 1** - Core health data management and AI chat
- [ ] **Phase 2** - Advanced document processing and imaging reports
- [ ] **Phase 3** - Wearable device integration and Apple Health sync
- [ ] **Phase 4** - Advanced AI features and health insights
- [ ] **Phase 5** - Multi-language support and accessibility enhancements

---

<div align="center">

**Built with ❤️ for health data privacy and user empowerment**

[Report Bug](https://github.com/bisonbet/BisonHealth-AI/issues) • [Request Feature](https://github.com/bisonbet/BisonHealth-AI/issues) • [Documentation](Docs/)

</div>