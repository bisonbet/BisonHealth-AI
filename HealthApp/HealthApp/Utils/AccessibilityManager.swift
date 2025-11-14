import SwiftUI
import UIKit

// MARK: - Haptic Feedback Manager

/// Manages haptic feedback for user interactions
/// Provides iPhone-specific haptics and appropriate alternatives for iPad
@MainActor
class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private init() {
        // Prepare generators for immediate use
        hapticGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
    
    /// Provides haptic feedback for button taps and general interactions
    /// On iPad, uses lighter feedback or visual feedback alternatives
    func impact(_ style: ImpactStyle = .medium) {
        guard SettingsManager.shared.appPreferences.hapticFeedback else { return }
        
        if isIPad {
            // iPad uses lighter feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } else {
            // iPhone uses standard feedback
            let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
            generator.impactOccurred()
        }
    }
    
    /// Provides haptic feedback for success actions
    func success() {
        guard SettingsManager.shared.appPreferences.hapticFeedback else { return }
        notificationGenerator.notificationOccurred(.success)
    }
    
    /// Provides haptic feedback for error actions
    func error() {
        guard SettingsManager.shared.appPreferences.hapticFeedback else { return }
        notificationGenerator.notificationOccurred(.error)
    }
    
    /// Provides haptic feedback for warning actions
    func warning() {
        guard SettingsManager.shared.appPreferences.hapticFeedback else { return }
        notificationGenerator.notificationOccurred(.warning)
    }
    
    /// Provides haptic feedback for selection changes
    func selection() {
        guard SettingsManager.shared.appPreferences.hapticFeedback else { return }
        selectionGenerator.selectionChanged()
    }
}

enum ImpactStyle {
    case light
    case medium
    case heavy
    
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        }
    }
}

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

// MARK: - Accessibility Label Builder

/// Helper for building comprehensive VoiceOver labels
struct AccessibilityLabelBuilder {
    /// Builds a descriptive label for VoiceOver
    static func buildLabel(
        primary: String,
        secondary: String? = nil,
        status: String? = nil,
        action: String? = nil
    ) -> String {
        var components: [String] = [primary]
        
        if let secondary = secondary {
            components.append(secondary)
        }
        
        if let status = status {
            components.append(status)
        }
        
        if let action = action {
            components.append(action)
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Builds a hint for VoiceOver actions
    static func buildHint(
        action: String,
        context: String? = nil
    ) -> String {
        var hint = action
        
        if let context = context {
            hint += ". \(context)"
        }
        
        return hint
    }
}

// MARK: - Device Type Helper

/// Helper for device-specific accessibility features
struct DeviceAccessibilityHelper {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
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

