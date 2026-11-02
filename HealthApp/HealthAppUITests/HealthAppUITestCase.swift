import XCTest

/// Base for every UI test: launches the app in its UI-test mode and knows how to reach each
/// section on iPhone (tab bar) and iPad (sidebar).
///
/// The launch arguments matter. Without `--ui-testing` the app opens its real container, so a
/// test run would read and write the data of whoever last used that simulator.
class HealthAppUITestCase: XCTestCase {
    /// Set for every test in `setUpWithError`. Not a default value: `XCUIApplication` is
    /// main-actor isolated and XCTest's lifecycle methods are not, so this is the one place an
    /// implicitly unwrapped optional is the honest type.
    var app: XCUIApplication! // swiftlint:disable:this implicitly_unwrapped_optional

    /// Overridden by suites that need a seeded document or another variation.
    var launchArguments: [String] {
        [
            "--ui-testing",
            "--reset-test-data",
            "--skip-disclaimer",
            "--scripted-ai-provider",
            "--disable-healthkit-sync",
            "--disable-mlx-preload"
        ]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()
    }

    // MARK: - Navigation

    /// A top-level section's button: a tab-bar button where there is a bottom tab bar, and
    /// otherwise a plain button — a sidebar row on iPad, or the side strip on iPhone Duo,
    /// which XCUITest does not report as a tab bar.
    func sectionButton(_ section: String) -> XCUIElement {
        let tab = app.tabBars.buttons[section]
        return tab.exists ? tab : app.buttons[section]
    }

    /// The Back button that returns to `title`. On iPhone Duo bars sit in the side strip and
    /// are not reported as navigation bars, so this does not look inside `navigationBars`.
    func backButton(to title: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == 'BackButton'", title)
        ).firstMatch
    }

    /// Opens a top-level section: a tab on iPhone, a sidebar row on iPad.
    func navigate(to section: String) {
        let tab = app.tabBars.buttons[section]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
            return
        }
        let sidebarButton = app.buttons[section]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5), "\(section) navigation should be visible")
        sidebarButton.tap()
    }

    func navigateToHealth() {
        navigate(to: "Health")
    }

    /// Health → the Documents segment.
    func navigateToDocuments() {
        navigateToHealth()
        let documentsSegment = app.buttons["Documents"]
        XCTAssertTrue(documentsSegment.waitForExistence(timeout: 5), "Documents segment should be visible in the Health tab")
        documentsSegment.tap()
    }

    func navigateToChat() {
        navigate(to: "AI Chat")
    }

    func navigateToSettings() {
        navigate(to: "Settings")
    }

    /// Health → the "Add Health Data" menu → `item` (its VoiceOver label, e.g.
    /// "Add Lab Results").
    func openAddHealthDataMenuItem(_ item: String) {
        navigateToHealth()
        let records = app.buttons["Records"]
        if records.waitForExistence(timeout: 2) {
            records.tap()
        }
        let menu = app.buttons["Add Health Data"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The Add Health Data menu should be visible")
        menu.tap()
        let entry = app.buttons[item]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(item) should be in the Add Health Data menu")
        entry.tap()
    }
}
