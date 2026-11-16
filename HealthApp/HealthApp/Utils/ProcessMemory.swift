//
//  ProcessMemory.swift
//  HealthApp
//
//  Point-in-time memory and hardware facts for diagnostic logging.
//

import Foundation
import os

// MARK: - Process Memory

/// Memory and hardware facts for the diagnostic log.
///
/// On-device generation can end the process with nothing logged: a jetsam kill or an abort
/// inside MLX/Metal leaves the last line of the log as the last thing *before* the work
/// started. Recording the headroom iOS reports at each stage is what lets
/// an exported log tell those two apart without a separate crash report.
enum ProcessMemory {

    /// How much more this process may allocate before iOS terminates it, in bytes.
    static func availableBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    /// Hardware model identifier, e.g. "iPhone19,4". `UIDevice.model` only says "iPhone".
    static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }

    /// Headroom for log messages: "available=5120MB".
    static func summary() -> String {
        "available=\(megabytes(availableBytes()))MB"
    }

    static func megabytes(_ bytes: UInt64) -> UInt64 {
        bytes / (1024 * 1024)
    }
}
