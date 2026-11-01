import SwiftUI

// MARK: - Overflow Toolbar Menu
/// Secondary actions for a screen's toolbar.
///
/// On iOS 27 they go into the system overflow menu. Apple's iPhone Duo guidance asks apps
/// to move their own "More" menus there, so every overflowed action — the app's and the
/// system's, when side bars run out of room — is in one place. Earlier systems keep the
/// app's own titled "More" menu.
struct OverflowToolbarMenu<Content: View>: ToolbarContent {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some ToolbarContent {
        if #available(iOS 27.0, *) {
            ToolbarOverflowMenu {
                content
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    content
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

// MARK: - Visibility Priority
extension ToolbarContent {
    /// Keeps this item in the bar the longest when there is not room for everything, as on
    /// iPhone Duo's side bars. For a screen's main action: Add, New Chat, Import.
    @ToolbarContentBuilder
    func keptVisibleLongest() -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            visibilityPriority(.high)
        } else {
            self
        }
    }
}
