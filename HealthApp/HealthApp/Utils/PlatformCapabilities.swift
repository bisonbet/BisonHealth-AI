import SwiftUI
import UIKit
import VisionKit

enum PlatformCapabilities {
    static var isIPadAppOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
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
