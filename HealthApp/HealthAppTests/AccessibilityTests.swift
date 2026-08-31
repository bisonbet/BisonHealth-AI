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
