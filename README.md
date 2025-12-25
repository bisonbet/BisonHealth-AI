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

- 📱 **Universal iOS App** - Built with SwiftUI for iOS 17+, optimized for both iPhone and iPad
- 🔒 **Privacy-First Design** - All health data stored locally with optional iCloud backup
- 🤖 **Multiple AI Providers** - Support for Ollama, AWS Bedrock, and OpenAI-compatible servers
- 👨‍⚕️ **AI Doctor Personas** - Choose from specialized AI doctors (Root Cause Analysis, Primary Care, Chronic Health AI, and more)
- 📄 **Smart Document Processing** - Automatic OCR and extraction of health data from documents using Docling
- 🏥 **Medical Document Management** - Support for 11 document types including imaging reports, lab reports, prescriptions, discharge summaries, and more
- 🩺 **Comprehensive Health Data** - Personal info, blood tests, medical documents with structured extraction
- 💬 **AI Chat with Context** - Intelligent conversations with your health data as context, including current date/time awareness
- 📊 **Data Export** - Export your data in JSON or PDF formats
- 🌙 **Accessibility** - Full support for Dark Mode, VoiceOver, and Dynamic Type
- ☁️ **Optional iCloud Backup** - Secure, encrypted backup with granular control
- 🔄 **Offline Support** - Queue operations when offline, automatic retry when connection restored
- 📡 **Streaming Responses** - Real-time AI responses for better user experience
- 🎯 **Context Selection** - Choose which health data and documents to include in AI conversations

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
│  ├── AI Provider Interface (Protocol)                       │
│  │   ├── Ollama Client                                      │
│  │   ├── AWS Bedrock Client                                 │
│  │   └── OpenAI-Compatible Client                           │
│  ├── Docling Client (Document Processing)                   │
│  └── Medical Document Extractor (AI-Enhanced)             │
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
   open HealthApp/HealthApp.xcodeproj
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
- **Personal Information** - Demographics, date of birth, medical history, medications, allergies, family history
- **Blood Test Results** - Comprehensive lab results with reference ranges, abnormal value detection
- **Medical Documents** - Full support for 11 document categories:
  - Doctor's Notes
  - Imaging Reports (X-rays, MRIs, CT scans, ultrasounds)
  - Lab Reports
  - Prescriptions
  - Discharge Summaries
  - Operative Reports
  - Pathology Reports
  - Consultations
  - Vaccine Records
  - Referrals
  - Other medical documents

### Document Features
- **OCR & Text Extraction** - Automatic text extraction from PDFs and images
- **Structured Data Extraction** - AI-powered extraction of dates, providers, document categories, and sections
- **Section Detection** - Automatic identification of Findings, Impressions, Recommendations, etc.
- **AI Context Integration** - Select documents to include in AI doctor conversations
- **Priority Management** - Set priority levels (1-5) for document inclusion in AI context
- **Search & Filter** - Full-text search across document content, filter by category, provider, date range

### Planned Features
- **Health Checkups** - Regular health assessments and vital signs
- **Wearable Data Integration** - Apple Health, fitness trackers

## 🔧 Configuration

### AI Provider Setup

BisonHealth AI supports multiple AI providers. Choose one based on your needs:

1. **Ollama** (Default) - Local AI server for maximum privacy
   - Install and run Ollama on your local network or remote server
   - Configure hostname and port in app settings
   - Supports any Ollama-compatible models (llama3.2, mistral, etc.)
   - Supports streaming responses for real-time chat

2. **AWS Bedrock** - Cloud AI service
   - Configure AWS credentials (access key, secret key, region)
   - Supports Claude Sonnet 4 and Llama 4 Maverick models
   - Large context windows (200k tokens for Claude Sonnet 4)
   - Requires AWS account and Bedrock access

3. **OpenAI-Compatible Servers** - For LiteLLM, LocalAI, vLLM, etc.
   - Configure base URL and optional API key
   - Supports any OpenAI-compatible API endpoint
   - Flexible deployment options

### Document Processing Setup

**Docling Server** - Required for document processing
- Set up Docling server for document parsing and OCR
- Configure hostname and port in app settings
- Processes PDFs, images, and other document formats
- Extracts structured data and text from medical documents

### Privacy Settings

- **Local Storage** - All health data encrypted and stored locally
- **iCloud Backup** - Optional, user-controlled backup to iCloud
- **Data Export** - Export your data anytime in JSON or PDF format
- **No Cloud Dependencies** - Core functionality works completely offline

## 👨‍⚕️ AI Doctor Personas

BisonHealth AI includes multiple specialized AI doctor personas, each with unique expertise and communication styles:

- **Root Cause Analysis & Long Term Health** - Systematic approach to identifying root causes with structured analysis
- **Primary Care Physician** - General healthcare with clinical precision and professional communication
- **Chronic Health AI** - Specialized in managing chronic conditions with comprehensive symptom tracking
- **Orthopedic Specialist** - Focus on musculoskeletal conditions and joint issues
- **Clinical Nutritionist** - Evidence-based nutrition advice and meal planning
- **Exercise Specialist** - Exercise programs, rehabilitation, and injury prevention
- **Internal Medicine** - Complex medical conditions and adult diseases

Each doctor persona has a customized system prompt that guides their responses and ensures they only use the health data explicitly provided in context. The AI is aware of the current date and time, allowing it to calculate patient age, assess document recency, and provide time-aware medical guidance.

## 🛠️ Development

### Project Structure

```
HealthApp/
├── HealthApp/
│   ├── Models/              # Data models and protocols
│   │   ├── PersonalHealthInfo.swift
│   │   ├── BloodTestResult.swift
│   │   ├── MedicalDocument.swift
│   │   ├── ChatModels.swift
│   │   └── Doctor.swift
│   ├── Views/               # SwiftUI views and components
│   │   ├── ChatDetailView.swift
│   │   ├── MedicalDocumentDetailView.swift
│   │   ├── UnifiedContextSelectorView.swift
│   │   └── [40+ view files]
│   ├── Managers/            # MVVM view models/business logic
│   │   ├── HealthDataManager.swift
│   │   ├── DocumentManager.swift
│   │   ├── AIChatManager.swift
│   │   └── SettingsManager.swift
│   ├── Services/            # External service clients
│   │   ├── OllamaClient.swift
│   │   ├── BedrockClient.swift
│   │   ├── OpenAICompatibleClient.swift
│   │   ├── DoclingClient.swift
│   │   └── MedicalDocumentExtractor.swift
│   ├── Database/            # SQLite database management
│   │   ├── DatabaseManager.swift
│   │   ├── DatabaseManager+HealthData.swift
│   │   ├── DatabaseManager+MedicalDocuments.swift
│   │   └── DatabaseManager+Chat.swift
│   ├── Networking/          # Network management
│   │   ├── NetworkManager.swift
│   │   └── PendingOperationsManager.swift
│   └── Utils/               # Utility functions and extensions
├── HealthAppTests/          # Unit tests
├── HealthAppUITests/        # UI tests
└── [Documentation files]
```

### Key Technologies

- **SwiftUI** - Modern iOS UI framework with universal app support
- **SQLite.swift** - Type-safe SQLite wrapper for local data storage
- **CryptoKit** - Encryption for sensitive health data
- **VisionKit** - Document scanning capabilities
- **Combine** - Reactive programming framework for state management
- **MarkdownUI** - Rich text rendering for AI responses
- **AWS SDK** - AWS Bedrock integration for cloud AI
- **Network Framework** - Network monitoring and offline support

### Testing

```bash
# Run unit tests
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run UI tests
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Note: Default simulator target is `iPhone 16 Pro`. If not available, use another device like `iPhone 15`.

## 📖 Documentation

Detailed documentation is available in the repository:

- **[Medical Documents Implementation](MEDICAL_DOCUMENTS_IMPLEMENTATION.md)** - Comprehensive guide to medical document processing
- **[Ollama Integration Guide](HealthApp/OLLAMA_SWIFT_INTEGRATION.md)** - Setup and usage of Ollama AI provider
- **[Docling Formats Explanation](DOCLING_FORMATS_EXPLANATION.md)** - Understanding Docling output formats
- **[Agent Guidelines](AGENTS.md)** - Development guidelines and coding standards
- **[Requirements](.kiro/specs/ios-health-app/requirements.md)** - Detailed user stories and acceptance criteria
- **[Design](.kiro/specs/ios-health-app/design.md)** - Architecture and technical design
- **[Tasks](.kiro/specs/ios-health-app/tasks.md)** - Implementation roadmap and task breakdown

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

### ✅ Completed
- [x] **Phase 1** - Core health data management and AI chat
- [x] **Phase 2** - Advanced document processing and medical document management
- [x] **Phase 2.5** - Multiple AI provider support (Ollama, AWS Bedrock, OpenAI-compatible)
- [x] **Phase 2.6** - AI doctor personas and specialized prompts
- [x] **Phase 2.7** - Medical document OCR and structured extraction
- [x] **Phase 2.8** - Context selection and priority management
- [x] **Phase 2.9** - Offline functionality and network handling
- [x] **Phase 2.10** - Streaming AI responses
- [x] **Phase 2.11** - Current date/time injection for temporal awareness

### 🚧 In Progress / Planned
- [ ] **Phase 3** - Wearable device integration and Apple Health sync
- [ ] **Phase 4** - Advanced AI features and health insights
- [ ] **Phase 5** - Multi-language support and accessibility enhancements

---

<div align="center">

**Built with ❤️ for health data privacy and user empowerment**

[Report Bug](https://github.com/bisonbet/BisonHealth-AI/issues) • [Request Feature](https://github.com/bisonbet/BisonHealth-AI/issues) • [Documentation](Docs/)

</div>