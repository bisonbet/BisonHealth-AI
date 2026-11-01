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

    /// Off for the first TestFlight round: the 27B Mac path is the least-tested model
    /// (about 16 GB to download, and no beta tester's Mac has run it yet). Turning this
    /// off hides the model from the catalog and the settings screen; the memory gate
    /// below is unchanged and still applies once this is turned back on.
    static let isMedGemma27BEnabled = false

    static var supportsMedGemma27BChat: Bool {
        isMedGemma27BEnabled && supportsMedGemma27BChat(
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

    // `VNDocumentCameraViewController` is main-actor isolated, so the capability derived
    // from it is too. Every caller is SwiftUI view code. Layout decisions use size class, not
    // device type: iPhone Duo's inner display is regular width on a phone.
    @MainActor
    static var supportsDocumentScanning: Bool {
        !isIPadAppOnMac && VNDocumentCameraViewController.isSupported
    }

    @MainActor
    static func usesExpandedLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isIPadAppOnMac || horizontalSizeClass == .regular
    }
}
