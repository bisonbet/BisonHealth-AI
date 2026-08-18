# 🏥 BisonHealth AI

**AI-Powered Personal Health Data Management for iOS**

<div align="center">

![iOS](https://img.shields.io/badge/iOS-26.0+-blue?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=for-the-badge&logo=swift)
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

- 📱 **Universal iOS App** - Built with SwiftUI for iOS 26+, optimized for both iPhone and iPad
- 🔒 **Privacy-First Design** - All health data stored locally on-device, no cloud backup
- 🤖 **Multiple AI Providers** - Support for on-device MLX models, AWS Bedrock, and OpenAI-compatible servers
- 👨‍⚕️ **AI Doctor Personas** - Choose from specialized AI doctors (Primary Care, Orthopedic Specialist, Clinical Nutritionist, Exercise Specialist, Internal Medicine, Dentist, Orthodontist, Physical Therapist)
- 📄 **Smart Document Processing** - Automatic OCR and health-data extraction through the native PDFKit/Vision pipeline (`NativeDocumentExtractor` and `DocumentProcessor`)
- 🏥 **Medical Document Management** - Support for 11 document types including imaging reports, lab reports, prescriptions, discharge summaries, and more
- 🩺 **Comprehensive Health Data** - Personal info, blood tests, medical documents with structured extraction
- ⌚️ **Apple Health Sync** - Import vitals, sleep, and characteristics from HealthKit (`HealthKitManager`)
- 🗓️ **Appointment Prep** - AI-generated prep notes for upcoming doctor visits, pulling relevant health data and medications (`AppointmentPrepManager`)
- 💬 **AI Chat with Context** - Intelligent conversations with your health data as context, including current date/time awareness
- 📊 **Data Export** - Export your data in JSON or PDF formats
- 🌙 **Accessibility** - Full support for Dark Mode, VoiceOver, and Dynamic Type
- 🔄 **Offline Status** - View local data while offline; network-dependent provider operations report failure clearly and support explicit retry
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
│  └── Backup Management Shell (placeholder)                 │
├─────────────────────────────────────────────────────────────┤
│  External Service Layer                                     │
│  ├── AI Provider Interface (Protocol)                       │
│  │   ├── On-Device MLX Client                               │
│  │   ├── AWS Bedrock Client                                 │
│  │   └── OpenAI-Compatible Client                           │
│  ├── Native Document Extractor (PDFKit + Vision)             │
│  └── Medical Document Extractor (AI-Enhanced)             │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Getting Started

### Prerequisites

- Xcode 26.0 or later
- iOS 26.0+ deployment target
- Swift 6 language mode (strict concurrency checking is enabled project-wide)
- Optional AWS Bedrock or OpenAI-compatible endpoint for remote AI functionality

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
   - Dependencies are managed via Swift Package Manager (including `mlx-swift-lm` for on-device inference)
   - Xcode will automatically resolve packages on first build

4. **Configure External Services:**
   - Download an on-device model, or configure AWS Bedrock / an OpenAI-compatible endpoint for AI chat functionality
   - Import documents through the native on-device extraction path; configure a provider endpoint only when remote AI processing is needed
   - Configure providers and optional server endpoints in the app settings

### Building and Running

1. Select your target device or simulator
2. Build and run the project (⌘+R)
3. Configure server connections in Settings
4. Start importing your health data!

## 📋 Supported Health Data Types

### Currently Implemented
- **Personal Information** - Demographics, date of birth, medical history, medications, allergies, family history
- **Blood Test Results** - Comprehensive lab results with reference ranges, abnormal value detection
- **Apple Health Sync** - Import vitals (blood pressure, heart rate, temperature, oxygen saturation, respiratory rate, weight, height), sleep analysis, and characteristics (date of birth, biological sex, blood type) via `HealthKitManager`
- **Appointment Prep** - AI-generated prep documents for upcoming doctor visits, drawing on relevant health data and medications
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
- **Wearable Data Integration** - Direct fitness tracker integration beyond Apple Health

## 🔧 Configuration

### AI Provider Setup

BisonHealth AI supports multiple AI providers. Choose one based on your needs:

1. **On-Device LLM** (Default) - Local model execution for maximum privacy
   - Download a supported model from Settings
   - Runs directly on device after model download
   - No remote AI server required
   - **MedGemma 27B Chat** is text-only and is shown only when the iOS app is running on a Mac with at least 24 GB of installed physical memory (not available/free memory); the download is approximately 16.02 GB across three weight shards
   - MedGemma is an AI health-information model, not a substitute for clinical diagnosis or treatment, and its Hugging Face/Google terms should be reviewed before distribution

2. **AWS Bedrock** - Cloud AI service
   - Configure AWS credentials (access key, secret key, region)
   - Supports Claude Sonnet 4.5, Llama 4 Maverick, and Amazon Nova Premier models
   - Large context windows (200k tokens for Claude Sonnet 4.5)
   - Requires AWS account and Bedrock access

3. **OpenAI-Compatible Servers** - For LiteLLM, LocalAI, vLLM, etc.
   - Configure base URL and optional API key
   - Supports any OpenAI-compatible API endpoint
   - Flexible deployment options

### Document Processing Setup

**Native document extraction** - No Docling server is required
- `NativeDocumentExtractor` uses PDFKit for digital PDFs and Vision OCR for scans, photos, and image-based documents
- `DocumentProcessor` orchestrates the active extraction and processing path
- `MedicalDocumentExtractor` maps extracted text into structured medical data

### Privacy Settings

- **Local Storage** - All health data encrypted and stored locally
- **No Cloud Backup** - Health data never leaves the device (iCloud/CloudKit backup removed for HIPAA compliance)
- **Data Export** - Export your data anytime in JSON or PDF format
- **On-Device Extraction** - Native document text extraction does not require a remote server; configured remote AI providers do require network access

## 👨‍⚕️ AI Doctor Personas

BisonHealth AI includes multiple specialized AI doctor personas, each with unique expertise and communication styles:

- **Primary Care Physician** - General healthcare with clinical precision and professional communication
- **Orthopedic Specialist** - Focus on musculoskeletal conditions and joint issues
- **Clinical Nutritionist** - Evidence-based nutrition advice and meal planning
- **Exercise Specialist** - Exercise programs, rehabilitation, and injury prevention
- **Internal Medicine** - Complex medical conditions and adult diseases
- **Dentist** - General dental health and oral care guidance
- **Orthodontist** - Orthodontic treatment and alignment questions
- **Physical Therapist** - Rehabilitation, mobility, and injury recovery

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
│   │   ├── AppointmentPrep.swift
│   │   ├── ChatModels.swift
│   │   └── Doctor.swift
│   ├── Views/               # SwiftUI views and components
│   │   ├── ChatDetailView.swift
│   │   ├── MedicalDocumentDetailView.swift
│   │   ├── UnifiedContextSelectorView.swift
│   │   ├── AppointmentPrepView.swift
│   │   └── [50+ view files]
│   ├── Managers/            # MVVM view models/business logic
│   │   ├── HealthDataManager.swift
│   │   ├── DocumentManager.swift
│   │   ├── AIChatManager.swift
│   │   ├── AppointmentPrepManager.swift
│   │   ├── HealthKitManager.swift
│   │   └── SettingsManager.swift
│   ├── Services/            # External service clients
│   │   ├── BedrockClient.swift
│   │   ├── OpenAICompatibleClient.swift
│   │   ├── NativeDocumentExtractor.swift
│   │   └── MedicalDocumentExtractor.swift
│   ├── MLXOnDeviceLLM/      # On-device MLX inference
│   │   ├── MLXOnDeviceClient.swift
│   │   └── MLXModelDownloadManager.swift
│   ├── Database/            # SQLite database management
│   │   ├── DatabaseManager.swift
│   │   ├── DatabaseManager+HealthData.swift
│   │   ├── DatabaseManager+MedicalDocuments.swift
│   │   ├── DatabaseManager+AppointmentPrep.swift
│   │   └── DatabaseManager+Chat.swift
│   ├── Networking/          # Network management
│   │   ├── NetworkManager.swift
│   │   └── NetworkError.swift
│   └── Utils/               # Utility functions and extensions
├── HealthAppTests/          # Unit tests
├── HealthAppUITests/        # UI tests
└── [Documentation files]
```

### Key Technologies

- **SwiftUI** - Modern iOS UI framework with universal app support
- **SQLite.swift** - Type-safe SQLite wrapper for local data storage
- **CryptoKit** - Encryption for sensitive health data
- **VisionKit / Vision / PDFKit** - Document scanning and OCR
- **HealthKit** - Apple Health data sync
- **Combine** - Reactive programming framework for state management
- **mlx-swift-lm** - On-device LLM inference (MLX)
- **Textual** - Structured markdown rendering for AI chat responses
- **AWS SDK for Swift** - AWS Bedrock integration for cloud AI
- **Network Framework** - Network connectivity monitoring and status

### Testing

```bash
# Run unit tests
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run UI tests
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Note: The canonical simulator target is `iPhone 17 Pro`. If it is not installed locally, use another installed simulator temporarily.

## 📖 Documentation

Detailed documentation is available in the repository:

- **[Agent Guidelines](AGENTS.md)** - Development guidelines and coding standards
- **[Codebase Agent Instructions](AGENT_CODEBASE_INSTRUCTIONS.md)** - Detailed codebase map for AI coding agents
- **[Historical Docling Formats Note](DOCLING_FORMATS_EXPLANATION.md)** - Legacy format reference; not the current document-processing path

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on:

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
- **Documentation** - See the [Documentation](#-documentation) section above

## 🗺️ Roadmap

### ✅ Completed
- [x] **Phase 1** - Core health data management and AI chat
- [x] **Phase 2** - Advanced document processing and medical document management
- [x] **Phase 2.5** - Multiple AI provider support (on-device, AWS Bedrock, OpenAI-compatible)
- [x] **Phase 2.6** - AI doctor personas and specialized prompts
- [x] **Phase 2.7** - Medical document OCR and structured extraction
- [x] **Phase 2.8** - Context selection and priority management
- [x] **Phase 2.9** - Offline status and network handling
- [x] **Phase 2.10** - Streaming AI responses
- [x] **Phase 2.11** - Current date/time injection for temporal awareness
- [x] **Phase 2.12** - Apple Health (HealthKit) sync
- [x] **Phase 2.13** - AI-generated appointment prep

### 🚧 In Progress / Planned
- [ ] **Phase 3** - Direct wearable/fitness tracker integration beyond Apple Health
- [ ] **Phase 4** - Advanced AI features and health insights
- [ ] **Phase 5** - Multi-language support and accessibility enhancements

---

<div align="center">

**Built with ❤️ for health data privacy and user empowerment**

[Report Bug](https://github.com/bisonbet/BisonHealth-AI/issues) • [Request Feature](https://github.com/bisonbet/BisonHealth-AI/issues) • [Documentation](#-documentation)

</div>
