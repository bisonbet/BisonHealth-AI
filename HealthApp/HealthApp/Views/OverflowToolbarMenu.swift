import SwiftUI

// MARK: - Overflow Toolbar Menu
/// Secondary actions for a screen's toolbar.
///
/// On iOS 27 they go into the system overflow menu. Apple's iPhone Duo guidance asks apps
/// to move their own "More" menus there, so every overflowed action — the app's and the
/// system's, when side bars run out of room — is in one place. Earlier systems keep the
/// app's own titled "More" menu.
///
/// The iOS 27 calls in this file sit behind `#if compiler(>=6.4)` as well as `#available`:
/// `#available` only decides at run time, and CI builds with Xcode 26, whose SDK does not
/// declare them at all. Swift 6.4 is the Xcode 27 toolchain this app ships with.
struct OverflowToolbarMenu<Content: View>: ToolbarContent {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            ToolbarOverflowMenu {
                content
            }
        } else {
            moreMenu
        }
        #else
        moreMenu
        #endif
    }

    private var moreMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                content
            } label: {
                Label("More", systemImage: "ellipsis.circle")
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
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
