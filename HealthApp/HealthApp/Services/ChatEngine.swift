import Foundation

// MARK: - Chat Engine (Deprecated)

/// DEPRECATED: This class has been superseded by the direct generation loop in MLXClient.swift
/// utilizing the standard MLXLMCommon library.
///
/// This file is kept to prevent build errors if referenced by the Xcode project,
/// but it should not be used for new development.
@MainActor
class ChatEngine {
    init() {
        print("⚠️ Warning: ChatEngine is deprecated. Use MLXClient directly.")
    }
}