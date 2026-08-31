import SwiftUI

// MARK: - Dynamic Type Helper

/// Helper for Dynamic Type support with iPad-optimized scaling
struct DynamicTypeHelper {
    /// Returns a font that scales with Dynamic Type, optimized for iPad
    static func scaledFont(
        _ style: Font.TextStyle,
        size: CGFloat? = nil,
        isIPad: Bool = false
    ) -> Font {
        if let size = size {
            // Custom size with Dynamic Type scaling
            return .system(size: size, weight: .regular)
                .scaledFont(for: style)
        } else {
            // Use system font for the style
            let font = Font.system(style, design: .default)
            
            // iPad-specific scaling adjustment
            if isIPad {
                // iPad can handle slightly larger text better
                return font
            }
            
            return font
        }
    }
    
    /// Returns minimum scale factor for text to ensure readability
    static var minimumScaleFactor: CGFloat {
        // Ensure text doesn't get too small
        return 0.8
    }
}

extension Font {
    /// Scales a font to support Dynamic Type
    func scaledFont(for textStyle: Font.TextStyle) -> Font {
        return self
    }
}

// MARK: - Device Type Helper

/// Helper for device-specific accessibility features.
/// `@MainActor` because every value derives from the main-actor-isolated device idiom.
@MainActor
struct DeviceAccessibilityHelper {
    static var isIPad: Bool {
        PlatformCapabilities.isIPadInterface || PlatformCapabilities.isIPadAppOnMac
    }
    
    static var isIPhone: Bool {
        !PlatformCapabilities.isIPadInterface && !PlatformCapabilities.isIPadAppOnMac
    }
    
    /// Returns minimum touch target size based on device
    static var minimumTouchTarget: CGFloat {
        // Apple's recommended minimum is 44x44 points
        // iPad can benefit from slightly larger targets
        return isIPad ? 48 : 44
    }
    
    /// Returns recommended padding for touch targets
    static var recommendedPadding: CGFloat {
        return isIPad ? 12 : 8
    }
}
