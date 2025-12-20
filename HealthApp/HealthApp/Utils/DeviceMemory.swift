import Foundation
import os

// MARK: - Device Memory Utility

/// Utility for detecting device memory and calculating appropriate MLX cache limits
enum DeviceMemory {

    /// Get total physical memory in bytes
    static func getTotalMemory() -> UInt64 {
        return ProcessInfo.processInfo.physicalMemory
    }

    /// Get total memory in gigabytes
    static func getTotalMemoryGB() -> Double {
        return Double(getTotalMemory()) / 1_073_741_824.0 // 1024^3
    }

    /// Get recommended GPU cache limit based on device memory
    /// - Returns: Cache limit in bytes
    static func getRecommendedGPUCacheLimit() -> Int {
        let totalMemoryGB = getTotalMemoryGB()

        // Conservative allocation strategy:
        // - Lower memory devices (< 4GB): 128MB cache
        // - Mid-range devices (4-6GB): 256MB cache
        // - Higher memory devices (6-8GB): 384MB cache
        // - High-end devices (> 8GB): 512MB cache

        let cacheMB: Int
        if totalMemoryGB < 4.0 {
            cacheMB = 128
        } else if totalMemoryGB < 6.0 {
            cacheMB = 256
        } else if totalMemoryGB < 8.0 {
            cacheMB = 384
        } else {
            cacheMB = 512
        }

        os_log(.info, "📊 Device memory: %.2f GB, setting GPU cache to %d MB", totalMemoryGB, cacheMB)

        return cacheMB * 1024 * 1024  // Convert to bytes
    }

    /// Check if device has sufficient memory for MLX inference
    /// - Parameter minimumGB: Minimum memory required in GB (default: 3.0)
    /// - Returns: True if device has sufficient memory
    static func hasSufficientMemory(minimumGB: Double = 3.0) -> Bool {
        let totalMemoryGB = getTotalMemoryGB()
        return totalMemoryGB >= minimumGB
    }

    /// Get available memory warning threshold
    /// - Returns: Memory threshold in bytes for triggering warnings
    static func getLowMemoryThreshold() -> UInt64 {
        return 500 * 1024 * 1024  // 500MB
    }
}
