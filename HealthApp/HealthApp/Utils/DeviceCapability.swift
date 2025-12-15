//
//  DeviceCapability.swift
//  HealthApp
//
//  Created by Claude Code
//  Copyright © 2025 BisonHealth. All rights reserved.
//

import Foundation
import UIKit

/// Utility for detecting device capabilities, particularly for on-device LLM support
struct DeviceCapability {

    // MARK: - Constants

    /// Minimum RAM required for on-device LLM (6GB)
    private static let minimumRAMForLLM: Double = 6.0

    /// Recommended RAM for optimal performance (8GB)
    private static let recommendedRAMForLLM: Double = 8.0

    // MARK: - Memory Detection

    /// Get total physical memory in GB
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
    }

    /// Get total physical memory in bytes
    static var physicalMemoryBytes: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// Check if device meets minimum RAM requirement for on-device LLM
    static var meetsMinimumRAMRequirement: Bool {
        physicalMemoryGB >= minimumRAMForLLM
    }

    /// Check if device has recommended RAM for optimal performance
    static var hasRecommendedRAM: Bool {
        physicalMemoryGB >= recommendedRAMForLLM
    }

    // MARK: - Model Support

    /// Check if device can support on-device LLM with given model size
    /// - Parameter modelSizeBytes: Size of the model file in bytes
    /// - Returns: True if device has sufficient memory
    static func canSupportModel(sizeBytes: Int64) -> Bool {
        guard meetsMinimumRAMRequirement else {
            return false
        }

        let modelSizeGB = Double(sizeBytes) / 1_000_000_000

        // Q4_K_M models need ~1.5x their file size in RAM (file + runtime overhead)
        let requiredMemoryGB = modelSizeGB * 1.5

        // Need headroom for iOS system and app
        let availableForModel = physicalMemoryGB - 2.0

        return availableForModel >= requiredMemoryGB
    }

    /// Get recommended model based on device capabilities
    /// - Returns: Model ID that's best suited for this device, or nil if insufficient RAM
    static func recommendedModelID() -> String? {
        guard meetsMinimumRAMRequirement else {
            return nil
        }

        // 8GB+: Can handle MedGemma 4B
        if physicalMemoryGB >= 8.0 {
            return "medgemma-4b"
        }

        // 6-8GB: Recommend Meditron3-Gemma2-2B (smaller, better fit)
        return "meditron3-gemma2-2b"
    }

    // MARK: - Device Information

    /// Get user-friendly RAM description
    static var ramDescription: String {
        String(format: "%.1f GB RAM", physicalMemoryGB)
    }

    /// Get device capability status message
    static var capabilityStatusMessage: String {
        if !meetsMinimumRAMRequirement {
            return "Your device has \(ramDescription). On-device LLM requires at least 6GB RAM. Consider using a newer device for this feature."
        } else if hasRecommendedRAM {
            return "Your device has \(ramDescription) and supports on-device LLM with optimal performance."
        } else {
            return "Your device has \(ramDescription). On-device LLM is supported, but a smaller model is recommended for best performance."
        }
    }
}
