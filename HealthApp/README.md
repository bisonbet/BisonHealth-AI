# Bison Health AI iOS App

A privacy-first iOS application for personal health data management with AI-powered assistance.

## Features

- **Local Data Storage**: All health data is stored locally on your device with encryption
- **Document Scanning**: Import health documents using camera or file system
- **AI Assistant**: Chat with Bison Health AI using your personal health data as context
- **Data Export**: Export your health data in JSON or PDF formats
- **iCloud Backup**: Optional encrypted backup to iCloud
- **Privacy First**: No cloud dependencies for core functionality

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Architecture

The app follows a modular MVVM architecture with the following layers:

- **Views**: SwiftUI views and user interface components
- **ViewModels**: Business logic and state management
- **Models**: Data models and protocols
- **Services**: External service clients (Ollama, Docling)
- **Database**: SQLite database management with encryption
- **Utils**: Utility classes and extensions

## Dependencies

- **SQLite.swift**: Local database management
- **CryptoKit**: Data encryption (built-in)
- **VisionKit**: Document scanning (built-in)

## Getting Started

1. Open `HealthApp.xcodeproj` in Xcode
2. Build and run the project
3. Configure server connections in Settings
4. Start importing your health documents

## Privacy

This app prioritizes your privacy:
- All health data is encrypted and stored locally
- External services are used only for processing, not storage
- iCloud backup is optional and encrypted
- No analytics or tracking

## License

Private project - All rights reserved