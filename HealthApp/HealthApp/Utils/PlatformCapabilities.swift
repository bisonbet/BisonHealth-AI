import SwiftUI
import UIKit
import VisionKit

enum PlatformCapabilities {
    static var isIPadAppOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    static var isIPadInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var supportsHardwareOptimizedInteractions: Bool {
        isIPadInterface || isIPadAppOnMac
    }

    static var supportsDocumentScanning: Bool {
        !isIPadAppOnMac && VNDocumentCameraViewController.isSupported
    }

    static func usesExpandedLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isIPadAppOnMac || horizontalSizeClass == .regular
    }
}
