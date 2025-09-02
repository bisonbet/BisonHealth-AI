# 💎 GEMINI Project Overview: BisonHealth AI

This document provides a comprehensive overview of the BisonHealth AI project for Gemini.

## 🌟 Project Overview

BisonHealth AI is a privacy-first iOS application that empowers users to take complete control of their health data. By leveraging AI and personal health information, BisonHealth AI provides a private assistant that helps users better understand and manage their health - all while keeping sensitive data securely stored locally on their device.

The project is composed of two main parts:

1.  **`HealthApp/`**: The primary iOS application written in Swift using SwiftUI. This is the focus of current development.
2.  **`legacy/`**: A Next.js web application that served as the original prototype for the project. It is no longer in active development but is kept for reference.

### Key Technologies

- **iOS App**: Swift, SwiftUI, SQLite.swift, CryptoKit, VisionKit
- **AI/ML**: Ollama for local AI models
- **Document Processing**: Docling for OCR and data extraction
- **Legacy Web App**: Next.js, React, TypeScript, Prisma

## 🚀 Building and Running the iOS App

The main application is the iOS app. Here's how to get it running:

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ deployment target
- Swift 5.9+
- Access to an Ollama server for AI functionality
- Access to a Docling server for document processing

### Installation and Execution

1.  **Clone the repository:**
    ```bash
    git clone git@github.com:bisonbet/BisonHealth-AI.git
    cd BisonHealth-AI
    ```

2.  **Open in Xcode:**
    ```bash
    open HealthApp/HealthApp.xcodeproj
    ```

3.  **Install Dependencies:**
    Dependencies are managed via Swift Package Manager. Xcode will automatically resolve packages on first build.

4.  **Configure External Services:**
    - Set up your Ollama server for AI chat functionality.
    - Set up your Docling server for document processing.
    - Configure the server endpoints in the app's settings.

5.  **Build and Run:**
    - Select your target device or simulator in Xcode.
    - Build and run the project using the `⌘+R` shortcut.

### Testing

To run the test suites, use the following commands:

```bash
# Run unit tests
xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild test -scheme HealthAppUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 🛠️ Development Conventions

- **Architecture**: The iOS app follows the Model-View-ViewModel (MVVM) pattern.
- **Code Style**: Adhere to the Swift API Design Guidelines.
- **Testing**: Unit tests are located in `HealthApp/HealthAppTests` and UI tests are in `HealthApp/HealthAppUITests`. All new features should be accompanied by tests.
- **Dependencies**: iOS dependencies are managed using the Swift Package Manager.
- **Privacy**: All sensitive data is stored locally and encrypted. No personal data should be committed to the repository.

##  legacy/ Web Application

The `legacy/` directory contains the original Next.js web application. This is no longer in active development but serves as a reference for the iOS app's features and data models. For more information, see the `legacy/README.md` file.
