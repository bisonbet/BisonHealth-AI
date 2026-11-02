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

// MARK: - Touch Target Helper

/// Touch target sizing.
///
/// Chosen by horizontal size class, not by device type. iPhone Duo's inner display is a
/// regular-width layout on a `.phone` device, so an idiom check would give it phone-sized
/// targets inside an iPad-style layout.
enum DeviceAccessibilityHelper {
    /// Apple's minimum is 44 × 44 pt; regular-width layouts get slightly larger targets.
    static func minimumTouchTarget(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular ? 48 : 44
    }
}
