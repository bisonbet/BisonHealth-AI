import SwiftUI
import UIKit
import VisionKit

enum PlatformCapabilities {
    /// The current app target is iOS/iPadOS, so an iOS app running in the Mac
    /// compatibility environment is the Mac runtime we can support today.
    static var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    static var isIPadAppOnMac: Bool {
        isRunningOnMac
    }

    /// Installed physical memory, not currently available/free memory.
    static let medGemmaMinimumMemoryBytes: UInt64 = 24 * 1024 * 1024 * 1024

    static var physicalMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    static var supportsMedGemma27BChat: Bool {
        supportsMedGemma27BChat(
            isMac: isRunningOnMac,
            physicalMemoryBytes: physicalMemoryBytes
        )
    }

    static func supportsMedGemma27BChat(
        isMac: Bool,
        physicalMemoryBytes: UInt64
    ) -> Bool {
        isMac && physicalMemoryBytes >= medGemmaMinimumMemoryBytes
    }

    // `UIDevice` and `VNDocumentCameraViewController` are main-actor isolated, so the
    // capabilities derived from them are too. Every caller is SwiftUI view code.
    @MainActor
    static var isIPadInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @MainActor
    static var supportsHardwareOptimizedInteractions: Bool {
        isIPadInterface || isIPadAppOnMac
    }

    @MainActor
    static var supportsDocumentScanning: Bool {
        !isIPadAppOnMac && VNDocumentCameraViewController.isSupported
    }

    @MainActor
    static func usesExpandedLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isIPadAppOnMac || horizontalSizeClass == .regular
    }
}
