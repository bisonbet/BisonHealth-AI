import XCTest
import SwiftUI
@testable import HealthApp

@MainActor
final class AccessibilityTests: XCTestCase {

    // MARK: - Dynamic Type Tests
    
    func testDynamicTypeHelper() {
        let font = DynamicTypeHelper.scaledFont(.body, isIPad: false)
        XCTAssertNotNil(font)
        
        let ipadFont = DynamicTypeHelper.scaledFont(.body, isIPad: true)
        XCTAssertNotNil(ipadFont)
        
        let customFont = DynamicTypeHelper.scaledFont(.headline, size: 18, isIPad: false)
        XCTAssertNotNil(customFont)
    }
    
    func testMinimumScaleFactor() {
        let scaleFactor = DynamicTypeHelper.minimumScaleFactor
        XCTAssertEqual(scaleFactor, 0.8, accuracy: 0.01)
    }
    
    // MARK: - Device Helper Tests
    
    func testDeviceAccessibilityHelper() {
        let isIPad = DeviceAccessibilityHelper.isIPad
        let isIPhone = DeviceAccessibilityHelper.isIPhone
        
        // One should be true, one should be false (depending on test environment)
        XCTAssertTrue(isIPad || isIPhone)
        XCTAssertFalse(isIPad && isIPhone)
    }
    
    func testMinimumTouchTarget() {
        let minTarget = DeviceAccessibilityHelper.minimumTouchTarget
        XCTAssertGreaterThanOrEqual(minTarget, 44.0) // Apple's minimum
    }
    
    func testRecommendedPadding() {
        let padding = DeviceAccessibilityHelper.recommendedPadding
        XCTAssertGreaterThanOrEqual(padding, 8.0)
    }
    
    // MARK: - Accessibility Colors Tests
    
    func testAccessibilityColorsExist() {
        // Test that all color properties exist and are accessible
        let _ = AccessibilityColors.primary
        let _ = AccessibilityColors.primaryText
        let _ = AccessibilityColors.secondaryText
        let _ = AccessibilityColors.success
        let _ = AccessibilityColors.error
        let _ = AccessibilityColors.warning
        let _ = AccessibilityColors.info
        let _ = AccessibilityColors.background
        let _ = AccessibilityColors.secondaryBackground
        let _ = AccessibilityColors.tertiaryBackground
        let _ = AccessibilityColors.groupedBackground
        let _ = AccessibilityColors.border
        let _ = AccessibilityColors.divider
        let _ = AccessibilityColors.buttonBackground
        let _ = AccessibilityColors.buttonText
        let _ = AccessibilityColors.disabledBackground
        let _ = AccessibilityColors.disabledText
        let _ = AccessibilityColors.connected
        let _ = AccessibilityColors.disconnected
        let _ = AccessibilityColors.processing
        let _ = AccessibilityColors.pending
    }
    
    // MARK: - Accessibility Traits Tests
    
    func testAccessibilityTraits() {
        var traits = HealthApp.AccessibilityTraits()
        XCTAssertTrue(traits.isEmpty)
        
        traits.insert(.button)
        XCTAssertTrue(traits.contains(.button))
        
        traits.insert(.header)
        XCTAssertTrue(traits.contains(.header))
        XCTAssertTrue(traits.contains(.button))
        
        let swiftUITraits = traits.swiftUITraits
        XCTAssertNotNil(swiftUITraits)
    }
}

// MARK: - Theme Contrast
//
// WS-10 measured white on BisonTheme.gold at 2.91:1 light and 1.89:1 dark — failing WCAG AA
// (4.5:1) and failing even the large-text threshold (3:1), on the surface where someone reads
// their own chat messages back. `inkOnGold` already existed and passes comfortably.
//
// These tests resolve the ACTUAL theme colours through UIColor rather than restating their
// literals. A first version hardcoded the numbers, and the negative check exposed that for
// what it was: darkening `gold` to near-black left every assertion green, so the tests could
// not have noticed a theme change at all — while their comments claimed they would.
@MainActor
final class ThemeContrastTests: XCTestCase {

    private struct RGB { let r: Double, g: Double, b: Double }

    private func resolve(_ color: Color, style: UIUserInterfaceStyle) throws -> RGB {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            throw XCTSkip("Colour could not be resolved to RGB in this environment")
        }
        return RGB(r: Double(r), g: Double(g), b: Double(b))
    }

    /// WCAG relative luminance, then the standard contrast ratio.
    private func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        func luminance(_ c: RGB) -> Double {
            0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private let aaNormal = 4.5
    private let aaLarge = 3.0

    func testInkOnGoldMeetsAAInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let gold = try resolve(BisonTheme.gold, style: style)
            let ink = try resolve(BisonTheme.inkOnGold, style: style)
            XCTAssertGreaterThan(
                contrastRatio(ink, gold), aaNormal,
                "inkOnGold must meet AA on gold in \(style == .light ? "light" : "dark") mode"
            )
        }
    }

    func testDarkTextBeatsWhiteOnGoldInBothAppearances() throws {
        // The actual reason for the swap, measured against the live theme. If `gold` is ever
        // changed enough that white becomes the better pairing, this fails and the decision
        // gets revisited deliberately instead of drifting.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let gold = try resolve(BisonTheme.gold, style: style)
            let ink = try resolve(BisonTheme.inkOnGold, style: style)
            let white = RGB(r: 1, g: 1, b: 1)
            XCTAssertGreaterThan(contrastRatio(ink, gold), contrastRatio(white, gold))
        }
    }

    func testWhiteOnGoldWouldFailWhichIsWhyItIsNotUsed() throws {
        // Guards the premise rather than the fix: white on the current gold is below even
        // the large-text threshold, which is what makes the swap necessary.
        let white = RGB(r: 1, g: 1, b: 1)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let gold = try resolve(BisonTheme.gold, style: style)
            XCTAssertLessThan(contrastRatio(white, gold), aaLarge)
        }
    }
}
