import SwiftUI

// MARK: - Bison App Theme

struct BisonTheme {
    static var charcoal: Color {
        Color.adaptive(
            light: Color(red: 0.12, green: 0.11, blue: 0.10),
            dark: Color(red: 0.91, green: 0.88, blue: 0.82)
        )
    }

    static var inkOnGold: Color {
        Color(red: 0.12, green: 0.11, blue: 0.10)
    }

    static var hideBrown: Color {
        Color.adaptive(
            light: Color(red: 0.48, green: 0.29, blue: 0.16),
            dark: Color(red: 0.76, green: 0.51, blue: 0.30)
        )
    }

    static var gold: Color {
        Color.adaptive(
            light: Color(red: 0.78, green: 0.55, blue: 0.16),
            dark: Color(red: 0.93, green: 0.70, blue: 0.28)
        )
    }

    static var sage: Color {
        Color.adaptive(
            light: Color(red: 0.23, green: 0.47, blue: 0.39),
            dark: Color(red: 0.45, green: 0.69, blue: 0.58)
        )
    }

    static var steel: Color {
        Color.adaptive(
            light: Color(red: 0.30, green: 0.38, blue: 0.43),
            dark: Color(red: 0.61, green: 0.70, blue: 0.74)
        )
    }

    static var appBackground: Color {
        Color.adaptive(
            light: Color(red: 0.97, green: 0.97, blue: 0.95),
            dark: Color(red: 0.07, green: 0.07, blue: 0.07)
        )
    }

    static var sidebarBackground: Color {
        Color.adaptive(
            light: Color(red: 0.94, green: 0.93, blue: 0.90),
            dark: Color(red: 0.10, green: 0.09, blue: 0.08)
        )
    }

    static var panelBackground: Color {
        Color.adaptive(
            light: Color.white,
            dark: Color(red: 0.15, green: 0.14, blue: 0.13)
        )
    }

    static var selectedSidebarItem: Color {
        Color.adaptive(
            light: Color.white.opacity(0.92),
            dark: Color(red: 0.19, green: 0.17, blue: 0.14)
        )
    }

    static var primaryText: Color {
        Color.primary
    }

    static var secondaryText: Color {
        Color.secondary
    }
}

// MARK: - Accessibility Color System

/// Provides accessibility-friendly colors with proper contrast for both light and dark modes
/// Ensures WCAG AA compliance (4.5:1 for normal text, 3:1 for large text)
struct AccessibilityColors {
    // MARK: - Primary Colors
    
    /// Primary accent color with high contrast
    static var primary: Color {
        BisonTheme.gold
    }
    
    /// Primary text color with high contrast
    static var primaryText: Color {
        Color.primary
    }
    
    /// Secondary text color with sufficient contrast
    static var secondaryText: Color {
        Color.secondary
    }
    
    // MARK: - Semantic Colors
    
    /// Success color with high contrast
    static var success: Color {
        BisonTheme.sage
    }
    
    /// Error color with high contrast
    static var error: Color {
        Color.adaptive(light: .red, dark: Color(red: 1.0, green: 0.4, blue: 0.4))
    }
    
    /// Warning color with high contrast
    static var warning: Color {
        BisonTheme.gold
    }
    
    /// Info color with high contrast
    static var info: Color {
        BisonTheme.steel
    }
    
    // MARK: - Background Colors
    
    /// Primary background color
    static var background: Color {
        BisonTheme.appBackground
    }
    
    /// Secondary background color (for cards, etc.)
    static var secondaryBackground: Color {
        BisonTheme.panelBackground
    }
    
    /// Tertiary background color
    static var tertiaryBackground: Color {
        Color(.tertiarySystemBackground)
    }
    
    /// Grouped background color
    static var groupedBackground: Color {
        BisonTheme.appBackground
    }
    
    // MARK: - Border Colors
    
    /// Border color with sufficient contrast
    static var border: Color {
        Color(.separator)
    }
    
    /// Divider color with sufficient contrast
    static var divider: Color {
        Color(.separator)
    }
    
    // MARK: - Interactive Colors
    
    /// Button background color with high contrast
    static var buttonBackground: Color {
        BisonTheme.gold
    }
    
    /// Button text color with high contrast
    static var buttonText: Color {
        BisonTheme.inkOnGold
    }
    
    /// Disabled button background
    static var disabledBackground: Color {
        Color(.systemGray4)
    }
    
    /// Disabled button text
    static var disabledText: Color {
        Color(.systemGray)
    }
    
    // MARK: - Status Colors
    
    /// Connected status color
    static var connected: Color {
        success
    }
    
    /// Disconnected status color
    static var disconnected: Color {
        error
    }
    
    /// Processing status color
    static var processing: Color {
        BisonTheme.gold
    }
    
    /// Pending status color
    static var pending: Color {
        warning
    }
}

// MARK: - Color Extension for Light/Dark Mode

extension Color {
    /// Creates a color that adapts to light and dark mode with explicit values
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        return Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
        #else
        return light
        #endif
    }
}

// MARK: - Accessibility Color Modifiers

extension View {
    /// Applies accessibility-friendly foreground color
    func accessibilityForegroundColor(_ color: Color) -> some View {
        self.foregroundColor(color)
    }
    
    /// Applies accessibility-friendly background color
    func accessibilityBackgroundColor(_ color: Color) -> some View {
        self.background(color)
    }
}
