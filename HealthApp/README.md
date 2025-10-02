# BisonHealth AI iOS App

A privacy-first iOS application for personal health data management with AI-powered assistance.

> **⚠️ IMPORTANT: Personal Use Only**
> 
> This application is designed exclusively for individual, personal health tracking and management. It is **NOT** intended for use by HIPAA Covered Entities, Business Associates, or any professional, clinical, or enterprise environments. We do not provide Business Associate Agreements (BAAs) or HIPAA-compliant guarantees.

## Features

- **Local Data Storage**: All health data is stored locally on your device with encryption
- **Document Scanning**: Import health documents using camera or file system
- **AI Assistant**: Chat with BisonHealth AI using your personal health data as context
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

## Privacy & Personal Use

This app prioritizes your privacy for personal health management:
- All health data is encrypted and stored locally
- External services are used only for processing, not storage
- iCloud backup is optional and encrypted
- No analytics or tracking
- **Personal Use Only**: Designed for individual health tracking, not professional healthcare
- **Not HIPAA Compliant**: We do not provide BAAs or regulated hosting guarantees

## License

Private project - All rights reserved