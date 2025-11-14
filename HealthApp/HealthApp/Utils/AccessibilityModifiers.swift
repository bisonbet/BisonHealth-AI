import SwiftUI

// MARK: - Dynamic Type Modifier

/// Modifier that applies Dynamic Type support with iPad optimization
struct DynamicTypeModifier: ViewModifier {
    let textStyle: Font.TextStyle
    let isIPad: Bool
    
    func body(content: Content) -> some View {
        content
            .font(DynamicTypeHelper.scaledFont(textStyle, isIPad: isIPad))
            .minimumScaleFactor(DynamicTypeHelper.minimumScaleFactor)
            .lineLimit(nil) // Allow text to wrap
    }
}

extension View {
    /// Applies Dynamic Type support with iPad optimization
    func dynamicType(_ textStyle: Font.TextStyle, isIPad: Bool = false) -> some View {
        modifier(DynamicTypeModifier(textStyle: textStyle, isIPad: isIPad))
    }
}

// MARK: - VoiceOver Label Modifier

/// Modifier that adds comprehensive VoiceOver support
struct VoiceOverLabelModifier: ViewModifier {
    let label: String
    let hint: String?
    let value: String?
    let traits: AccessibilityTraits
    
    init(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = []
    ) {
        self.label = label
        self.hint = hint
        self.value = value
        self.traits = traits
    }
    
    func body(content: Content) -> some View {
        var modified = content
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits.swiftUITraits)
        
        if let hint = hint, !hint.isEmpty {
            modified = modified.accessibilityHint(hint)
        }
        
        if let value = value, !value.isEmpty {
            modified = modified.accessibilityValue(value)
        }
        
        return modified
    }
}

extension View {
    /// Adds comprehensive VoiceOver support
    func voiceOverLabel(
        _ label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        modifier(VoiceOverLabelModifier(
            label: label,
            hint: hint,
            value: value,
            traits: traits
        ))
    }
}

// MARK: - Accessibility Traits

struct AccessibilityTraits: OptionSet {
    let rawValue: Int
    
    static let button = AccessibilityTraits(rawValue: 1 << 0)
    static let header = AccessibilityTraits(rawValue: 1 << 1)
    static let link = AccessibilityTraits(rawValue: 1 << 2)
    static let selected = AccessibilityTraits(rawValue: 1 << 3)
    static let image = AccessibilityTraits(rawValue: 1 << 4)
    static let searchField = AccessibilityTraits(rawValue: 1 << 5)
    static let summaryElement = AccessibilityTraits(rawValue: 1 << 6)
    static let notEnabled = AccessibilityTraits(rawValue: 1 << 7)
    static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 8)
    static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 9)
    static let adjustable = AccessibilityTraits(rawValue: 1 << 10)
    static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 11)
    static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 12)
    
    var swiftUITraits: SwiftUI.AccessibilityTraits {
        var result: SwiftUI.AccessibilityTraits = []
        
        if contains(.button) {
            _ = result.insert(.isButton)
        }
        if contains(.header) {
            _ = result.insert(.isHeader)
        }
        if contains(.link) {
            _ = result.insert(.isLink)
        }
        if contains(.selected) {
            _ = result.insert(.isSelected)
        }
        if contains(.image) {
            _ = result.insert(.isImage)
        }
        if contains(.searchField) {
            _ = result.insert(.isSearchField)
        }
        if contains(.summaryElement) {
            _ = result.insert(.isSummaryElement)
        }
        // Note: .notEnabled is handled via .disabled() modifier, not accessibility trait
        if contains(.updatesFrequently) {
            _ = result.insert(.updatesFrequently)
        }
        if contains(.startsMediaSession) {
            _ = result.insert(.startsMediaSession)
        }
        // Note: .adjustable is not available in SwiftUI AccessibilityTraits
        // Use .accessibilityAdjustableAction for adjustable elements instead
        if contains(.allowsDirectInteraction) {
            _ = result.insert(.allowsDirectInteraction)
        }
        if contains(.causesPageTurn) {
            _ = result.insert(.causesPageTurn)
        }
        
        return result
    }
}

// MARK: - Touch Target Modifier

/// Ensures minimum touch target size for accessibility
struct TouchTargetModifier: ViewModifier {
    let minSize: CGFloat
    
    init(minSize: CGFloat? = nil) {
        self.minSize = minSize ?? DeviceAccessibilityHelper.minimumTouchTarget
    }
    
    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Ensures minimum touch target size for accessibility
    func touchTarget(minSize: CGFloat? = nil) -> some View {
        modifier(TouchTargetModifier(minSize: minSize))
    }
}

// MARK: - iPad Keyboard Navigation Modifier

/// Adds keyboard navigation support for iPad
struct KeyboardNavigationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .focusable()
    }
}

extension View {
    /// Adds keyboard navigation support for iPad
    func keyboardNavigable() -> some View {
        modifier(KeyboardNavigationModifier())
    }
}

// MARK: - Accessibility Container Modifier

/// Groups related accessibility elements
struct AccessibilityContainerModifier: ViewModifier {
    let label: String
    let hint: String?
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
}

extension View {
    /// Groups related accessibility elements with a label
    func accessibilityContainer(label: String, hint: String? = nil) -> some View {
        modifier(AccessibilityContainerModifier(label: label, hint: hint))
    }
}

// MARK: - High Contrast Modifier

/// Ensures high contrast for accessibility
struct HighContrastModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contrast(1.2) // Slightly increase contrast
    }
}

extension View {
    /// Ensures high contrast for accessibility
    func highContrast() -> some View {
        modifier(HighContrastModifier())
    }
}

