# WS-18 — iPhone Duo readiness plan

- **Date**: 2026-11-01
- **Scope**: what Apple's iPhone Duo guidance asks of an app, how BisonHealth AI measures up today, and the work to make Duo a first-class device for the first TestFlight round.
- **Sources read**: Apple's [Get ready for iPhone Duo](https://developer.apple.com/iphone-duo/) hub; the HIG page [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) (new 2026-09-09); [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo); [Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/); and Xcode 27.2's own `app-resizability` and `swiftui-whats-new-27` agent skills (`xcrun agent skills export`). The six tech-talk videos were not watched; everything below is from the written pages.

## Why this is urgent: the next build already gets Duo behaviour

Apple's SDK table decides what a Duo owner sees:

| Built with | On iPhone Duo |
|---|---|
| iOS 26 SDK | Runs letterboxed: centred on the inner display with empty space around it |
| iOS 27 SDK | Fills most of the inner display |
| **iOS 27.1 SDK or later** | **Fills both displays, and toolbars and tab bars move to the side of the screen** |

This Mac has **Xcode 27.2 (iOS 27.2 SDK)**, so `Scripts/archive.sh` produces a 27.1-or-later build. Apple's warning for exactly this case: *"Before shipping an app build with the iOS 27.1 SDK, make sure your app's content adapts to the bars becoming vertical."* There is no opting out short of building with an old SDK, and that only buys the letterboxed experience. So the Duo work is not a later polish item; it decides how the very first TestFlight build looks on Duo.

**CI does not see any of this.** `.github/workflows/ci.yml` pins `DEVELOPER_DIR` to Xcode 26.2, so CI compiles against the iOS 26 SDK. A green CI run says nothing about Duo layout. See item D-12.

## How Duo works (the parts that matter for this app)

- **Two displays.** The outer display (closed) is a *compact-width* phone screen that is wider and shorter than other iPhones. The inner display (open) is *regular width*, and Apple wants it to feel like "a natural extension of its iPad layout".
- **Folding or unfolding resizes the app mid-session.** The app moves between displays and changes size class while running. Apple: *keep functionality and the state of elements the same between displays.*
- **Side-mounted bars.** On the outer display, and on the inner display in landscape, the navigation bar, toolbar and tab bar move to a vertical strip on one side. Inner display in portrait keeps horizontal bars. In a split view, the sidebar keeps horizontal bars and the detail column goes vertical.
  - A toolbar item is presented vertically **only if it has an icon**. A title-only item, or a custom view, stays in a horizontal bar.
  - The top of the vertical strip is for Back/Close, then the prominent action (Done).
- **The fold.** When the device is partially folded, a *reserved region* splits the inner display. System sheets, alerts, menus, popovers and split views move clear of it on their own. Custom layouts must use `ReservedRegion` or an `ArrangementView`. Grids should prefer an even number of columns.
- **Poses.** Book-style, flat, standing on an edge. Apple: don't design per pose; let size classes and the existing layout expand.

## Audit: where the app stands

Checked by reading code, plus the Duo simulator once the build finished (screenshots in the section after the plan).

**Already good**
- Apple's three prerequisites pass: the launch screen is generated (`INFOPLIST_KEY_UILaunchScreen_Generation`), iPad lists all four orientations, and `UIRequiresFullScreen` is absent.
- No `UIScreen.main`, no `UIDevice.current.orientation` / `interfaceOrientation`, and no hard-coded screen sizes anywhere in `HealthApp/`.
- SwiftUI `App` lifecycle, so there is no app-delegate-to-scene migration.
- Layout choices already key off size class (`PlatformCapabilities.usesExpandedLayout(horizontalSizeClass:)`), not idiom. That is what Apple asks for.
- `DocumentGridView` already uses one `.adaptive` column (WS-09 / W-H), not fixed widths.
- All presentation is through system `.sheet`, which Apple says moves clear of the fold automatically.

**Problems, by impact**

| # | Finding | Where | Why it matters on Duo |
|---|---|---|---|
| D-1 | **The root view swaps between two different view trees** depending on size class: `compactTabShell` (a `TabView`) or `expandedAppShell` (a hand-built `HStack` sidebar). | `ContentView.swift` `body`, `compactTabShell`, `expandedAppShell` | Every fold and unfold changes size class, so the whole app is torn down and rebuilt. The selected section survives (`$selectedSection`), but **every `NavigationStack` path, scroll position, in-progress form and open chat is lost**. That breaks Apple's first rule for Duo, and it happens every time the user opens the phone. |
| D-2 | The wide layout's sidebar is a custom `AppSidebar` at a fixed `.frame(width: 280)`, with a hand-drawn divider. | `ContentView.swift` `expandedAppShell` | The system knows nothing about this split, so it can't adjust it for the fold. On a partially folded inner display the fold lands inside the content column, and no vertical bars appear for it. |
| D-3 | **Chat swaps `NavigationSplitView` for a `NavigationStack`** on size class (`iPadSplitView` / `iPhoneView`). | `ContentView.swift` `ChatView` | Same teardown as D-1: unfolding mid-conversation drops the open conversation and any typed draft. A single `NavigationSplitView` collapses to a stack on compact width by itself, so the swap isn't needed. |
| D-4 | **48 toolbar buttons are title-only** (`Button("Cancel")`, `"Save"`, `"Done"`, `"Close"`, `"New Chat"`, `"Conversations"` …), almost all using the positional `.navigationBarLeading` / `.navigationBarTrailing` placements, which are now soft-deprecated. Only one `.cancellationAction` and one `.confirmationAction` exist. | 28 files | Apple: title-only items are not presented vertically. On the outer display these bars either stay horizontal and eat vertical space, or break up the vertical strip. Positional placements also stop the system from putting Close/Back at the top and Done next. |
| D-5 | The Health tab's Records/Documents switcher is a **custom view in `.principal`**. | `HealthTabView.swift` `segmentSwitcher` | Custom-view toolbar items are never presented vertically, so on the outer display the main navigation control of the busiest tab sits in a stray horizontal bar, or gets squeezed. |
| D-6 | **iPhone is portrait-only** (`INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`). | `project.pbxproj` | Apple's skill calls a portrait-only *iPhone* normal, but the Duo inner display is usually held book-style in landscape, and Apple asks apps to fill every pose. **Behaviour on the inner display has to be checked on the simulator**: whether iOS letterboxes or rotates a portrait-only app there decides whether this is a one-line fix or a broader one. |
| D-7 | Global `UINavigationBar.appearance()` and `UITabBar.appearance()` styling, plus `.toolbarBackground(... .visible ...)` on the tab shell. | `HealthAppApp.swift`, `ContentView.swift` | These were written for horizontal bars. They may paint a solid strip down the side of the outer display, clash with Liquid Glass vertical bars, or simply not apply. Needs a visual check. |
| D-8 | `DeviceAccessibilityHelper.isIPad` / `isIPhone` choose touch-target sizes by **idiom**. | `Utils/AccessibilityManager.swift` | On the Duo's iPad-like inner display the idiom is still `.phone`, so the iPad sizing never applies. Apple: base layout on size class or available space, not idiom. Low impact. |
| D-9 | `.scaledToFill()` hero on the splash; `.aspectRatio(contentMode: .fill)` on document thumbnails. | `SplashScreenView.swift`, `DocumentGridView`, `DocumentListView`, `DocumentDetailView`, `BatchProcessingView` | Apple flags fill-mode media for wide displays, since important content gets cropped. The splash also sits under the side bar's camera region. Thumbnails are probably fine (they are crops by design); the splash needs a look. |
| D-10 | Nothing is fold-aware: no `ReservedRegion`, no `ArrangementView`, no even-column rule. | — | Matters only for custom layouts: the documents grid, the chat composer, prep detail. System containers handle themselves. |
| D-11 | The inner display shows the same one-level hierarchy as a phone for Documents: a document opens in a sheet, as it does on iPad. | `DocumentsView` | Apple *suggests* an extra level of hierarchy on the inner display (list and detail side by side, like Mail). The owner decided on 2026-11-01 to keep the iPad design as is, so this is listed as a choice, not a defect. |
| D-12 | CI builds with Xcode 26.2, the iOS 26 SDK. | `.github/workflows/ci.yml` | No CI signal for Duo. Moving CI to Xcode 27.1+ depends on what the hosted runner image offers; on 2026-10-26 the newest Xcode with a matching simulator runtime there was 26.2. |
| D-13 | The test plans have no Duo destination, and the UI smoke test runs on iPhone 17 Pro only. | `TestPlans/`, `RegressionSmokeUITests` | A fold/unfold state-loss regression (D-1/D-3) would never be caught. |

## Observed on the simulator (2026-11-01)

- **The current code builds and launches on the iPhone Duo simulator** (Xcode 27.2, `DTSDKName = iphonesimulator27.2`), so nothing blocks the device outright.
- On the outer display, the status bar and camera sit on the **right edge**, as Apple describes. The HealthKit permission sheet and the notification alert lay out cleanly around them.
- **What could not be checked from here:** `simctl` has no command to open, close or partly fold the device. Its `screenConfig power` only switches a display panel off, and the inner panel showed black while closed. Poses are changed in Xcode's Device Hub, by hand. The simulator's permission dialogs also did not respond reliably to scripted taps. So the app's own screens on each pose, and therefore D-1, D-5, D-6 and D-7, are **confirmed by reading the code, not yet on screen**. The first job in phase 1 is a 15-minute Device Hub pass: closed, open portrait, open landscape, partly folded.

## Phase 1 status (2026-11-01, uncommitted)

| Item | State |
|---|---|
| 1 One root container | **Done.** `ContentView.appShell` is a single `TabView(.sidebarAdaptable)` with `.defaultAdaptableTabBarPlacement(.sidebar)`. The custom `AppSidebar` / `AppSidebarItem`, `AppSection.accent` and `BisonTheme.selectedSidebarItem` are deleted; the branding header and "Private by design" footer moved to `.tabViewSidebarHeader` / `.tabViewSidebarFooter`. |
| 2 Chat split view | **Done.** `ChatView` is one `NavigationSplitView(preferredCompactColumn:)` that opens on the chat on phones. The phone-only "Conversations" sheet and `ConversationListView.swift` are deleted. New Chat is an icon item (`chat.newConversation`). |
| 3 Toolbar items | **Done.** 41 Cancel/Close/Save/Done buttons now use `.cancellationAction` / `.confirmationAction` with xmark/checkmark icons. Image-only and HStack items became titled items with icons; the "More" and "Reset" menus have titles. No `.navigationBarLeading`/`Trailing` remain. Deliberately text-only: "Import N of M" (the count is the point), "Skip", and keyboard Done buttons. |
| 4 Records/Documents switch | **Done** as the safe default: pinned above the content with `safeAreaInset(edge: .top)`. |
| 5 Orientation | **Done:** iPhone now allows portrait and both landscapes (not upside down), because the open Duo is held book-style. No code locks orientation. Checked on the Duo's outer display: landscape moves the bar strip to the left, beside the camera, and the selected tab and content survive the rotation. **This also changes ordinary iPhones**, which can now rotate. |

## Simulator test pass (2026-11-01, "BisonHealth Duo Test", iOS 27.1)

Duo devices exist only on the iOS 27.1 simulator runtime; `simctl create` refuses 27.2.
- **Chat:** Back, New Chat and the system "…" overflow stack in the side strip in that order, as the HIG asks. The composer and the AI disclaimer stay clear of the bar.
- **Draft across rotation:** a message typed in the composer survived a rotation to landscape and back. The tab and the open conversation survived too.
- **Conversation list:** "Conversations" was showing twice, once as the new navigation title and once as the sidebar's own header. Fixed: the header text is gone, and the + is now a toolbar item (`chat.sidebar.newConversation`) that the Duo places in its side strip. The duplicate ⌘N shortcut went with it.
- **Device Hub pass (the owner drove the poses, 2026-11-01):**
  - Closing the phone kept the open chat and the typed draft on the outer display.
  - Reopening restored the list and chat side by side.
  - Inner display, open in landscape: the app fills the display. The chat is a split view, with the list's bar horizontal and the chat's actions in the side strip.
  - **Half-folded, two bugs found and fixed:**
    1. The chat split view's column was capped at 400 pt, which kept the system from moving the column edge to the fold. The crease ran through the chat. The cap is removed and the columns now meet at the crease.
    2. The centred Records/Documents switch sat on the crease. It now moves to the leading half while a fold divides the screen, using `PlatformCapabilities.isDividedByFold`, now shared with the documents grid. It returns to the centre when the phone is fully open.
  - The fold detection itself is confirmed working on the simulator. The grid's even-column count could not be eyeballed because the seed data has a single document; it is covered by its unit test.
- **Earlier limitation, now resolved:** I could not change poses myself. Device Hub's pose controls are reachable only through its window, and scripting that needs macOS Accessibility permission.

## Phase 2–3 status (2026-11-01, uncommitted)

| Item | State |
|---|---|
| 6 Bar styling | **No change needed.** The UIKit appearance proxies and `.toolbarBackground` render correctly on Duo's vertical bars. The splash's fill-mode hero is decorative and keeps its branding inside the safe area, so it was left alone. |
| 7 Toolbar priorities | **Done.** The app's own "More" menus on chat, document detail, medical document detail and genetic tests go through `OverflowToolbarMenu`. On iOS 27 that puts them in the system `ToolbarOverflowMenu`; on iOS 26 it keeps the titled "More" menu. The main action on each screen gets `keptVisibleLongest()` (`visibilityPriority(.high)` on iOS 27): New Chat, Add Health Data, Add Document, New Appointment Prep. Prep's report menu stays a visible menu, because Share/Copy/Print are that screen's main actions. |
| 8 Fold-aware layouts | **Documents grid done:** an even fixed column count while a fold divides it (`ReservedRegion` `.division`, iOS 27.1), and the adaptive column otherwise. Unit-tested. Chat and prep need nothing: chat is a system split view, which adapts to the fold itself, and sheets move clear of the fold automatically. `presentationPlacement` was not set; the automatic placement is right for every sheet here. |
| 9 Touch targets | **Done.** `DeviceAccessibilityHelper.minimumTouchTarget(for:)` uses horizontal size class (48 pt regular, 44 pt compact), so the Duo's inner display gets the larger targets. Removed the now-unused idiom helpers (`isIPadInterface`, `supportsHardwareOptimizedInteractions`, `isIPad`/`isIPhone`, `recommendedPadding`). |
| 10 Fill-mode media | **No change.** Thumbnails are crops by design, and the splash is covered under item 6. |
| 11 Documents split view | Not done; this is still the owner's call. |
| 13 Fold regression test | **Not possible yet:** XCUITest in Xcode 27.2 has no API to change the device's pose (checked `XCUIDevice` and the XCUIAutomation headers). It stays a manual Device Hub check. |
| 12 / 14 / 15 | Manual or owner items: the Device Hub matrix, the CI Xcode pin (it depends on the runner image), and Duo screenshots in App Store Connect. |

**Verified:**
- `ModelTests` and `AccessibilityTests` pass on the iPhone Duo simulator: 45/45.
- Duo and iPad builds succeed on the iOS 27.2 SDK.
- swiftlint introduces no new violations.

**Still unseen:** the inner display and the fold. They need Xcode's Device Hub, because `simctl` cannot open the device and powering off the outer panel does not open it.

**Seen on the simulators:**
- **Duo, outer display:** the tab bar is a vertical strip on the right under the camera and status bar. The Add Health Data "+" joined that strip, and the Records/Documents switch is pinned above the list.
- **iPad landscape:** the system sidebar sits beside the content with the app's header and footer.
- **iPad portrait — a visible change:** the system sidebar opens *over* the content until dismissed. The old custom sidebar always sat beside it.

Both builds succeed against the iOS 27.2 SDK. The inner display and fold poses still need Device Hub.

## The plan

The order matters: phase 1 changes the app's skeleton, and later work sits on top of it.

### Phase 1: must land before the TestFlight build (structural)

1. **One root container that adapts by itself (fixes D-1, D-2).** Replace the `compactTabShell` / `expandedAppShell` swap with **one `TabView` using `.tabViewStyle(.sidebarAdaptable)`**:
   - On compact width (outer display, ordinary iPhones) it is a tab bar, which the system moves to the side on Duo.
   - On regular width (inner display, iPad, Mac) it becomes a system sidebar that the fold logic knows about.
   - The view tree is the same in both states, so folding no longer resets navigation.

   `AppSidebar`'s header and branding move into the sidebar via `TabSection` / `.tabViewSidebarHeader`. The custom theming will need re-checking on iPad and Mac too. This is a visible change on iPad (the sidebar becomes the system one). It doesn't revisit the "keep iPad as is" decision in substance, but it does mean the iPad sidebar looks system-standard, not hand-drawn. **This needs the owner's OK.**
2. **Chat: one `NavigationSplitView`, always (fixes D-3).** Drop the `iPhoneView` branch, keep the conversation selection in the split view's selection binding, and let compact width collapse it to a stack. Move the iPhone-only "Conversations" button's job to the split view's own sidebar button. Afterwards, an open conversation and a typed draft survive a fold.
3. **Toolbar items the system can place (fixes D-4).** Across the 28 files:
   - `Cancel` / `Close` → `ToolbarItem(placement: .cancellationAction)`.
   - `Save` / `Done` → `.confirmationAction`.
   - Everything else → a `Label(title, systemImage:)` with `.topBarLeading` / `.topBarTrailing` or a semantic placement.

   Mechanical, but it touches nearly every editor. Gate any iOS 27-only API (`visibilityPriority`, `ToolbarOverflowMenu`, `.topBarPinnedTrailing`) behind `if #available(iOS 27, *)`, because the deployment target is 26.0.
4. **Move the Records/Documents switch out of the toolbar (fixes D-5).** Put it at the top of the content, pinned above the list (Apple: *locate controls near the content they affect*), or make Records and Documents separate entries in the `sidebarAdaptable` sidebar on regular width. The second is cleaner on the inner display, but it changes the tab structure, so it's the owner's call. The first is a safe default.
5. **Orientation (D-6).** Depends on the simulator result:
   - If the portrait lock letterboxes the inner display, enable all orientations on iPhone. That then needs a landscape pass over every iPhone screen, which also changes behaviour on ordinary iPhones.
   - If iOS already ignores the lock on Duo, leave the setting alone and test the landscape layouts on Duo only.

### Phase 2: first-class polish (same TestFlight if time allows; otherwise the round after)

6. **Bar styling (D-7).** Retest the appearance proxies and `.toolbarBackground` on vertical bars, and remove whatever fights Liquid Glass. Use `backgroundExtensionEffect()` (iOS 27) on the splash, so the art runs under the vertical bar.
7. **Toolbar priorities.** Add `visibilityPriority(.high)` to the actions people need most: New Chat, Send-related controls, the context selector (it carries privacy state, so keep it visible), Import. Put rarely used actions in `ToolbarOverflowMenu`. Chat is navigation-focused, so keep the default compression. The editors are task-focused, so minimise the tab bar there (`toolbarVerticalCompressionBehavior`).
8. **Fold-aware custom layouts (D-10).**
   - Documents grid: prefer an even column count when a fold division is active.
   - Chat composer and prep detail: read `ReservedRegion`s and keep the text field and Send clear of the fold.
   - Sheets on the inner display: set `presentationPlacement` so the import-review sheet, a long data-entry form, sits on one half when the device is partially folded.
9. **Idiom to size class (D-8):** `DeviceAccessibilityHelper` sizes touch targets from the trait environment, not from the idiom.
10. **Fill-mode media (D-9):** check the splash on both displays, and fit or anchor it if it crops.
11. **Optional, the owner's call (D-11):** on the inner display, show the documents list and the selected document side by side using a `NavigationSplitView` or a split `ArrangementView`. It would make Duo genuinely first-class, but it is the same design question already deferred for iPad.

### Phase 3: verification and store presence

12. **Test matrix on the iPhone Duo simulator (Xcode 27.2):** closed; open portrait; open landscape; partially folded (book); Split View with another app on the inner display, where bars sit on the outer edge; Dynamic Type at the largest size on the outer display. Repeat on iPhone 17 Pro and an iPad simulator, because Phase 1 changes both.
13. **Regression test for state across a fold (D-13):** add a Duo destination to the `PreRelease` plan, and a UI test that opens a conversation, types a draft, changes display, and checks that both survive.
14. **CI (D-12):** check whether the hosted runner image now has Xcode 27.1+ with its simulator runtime, and move the `DEVELOPER_DIR` pin when it does. Until then, the Duo matrix is a local, pre-upload gate.
15. **App Store:** iPhone Duo screenshots in App Store Connect show an "optimized for iPhone Duo" badge on the product page. That matters for the App Store release, not for internal TestFlight.

### What stays the owner's decision

- Phase 1 item 1 changes the iPad and Mac sidebar from custom to system-standard.
- Phase 1 item 4: a pinned in-content switch, or separate sidebar entries.
- Item 11: a Documents split view on the inner display (and so, by extension, on iPad).
- Whether phase 2 ships in the first TestFlight build or the next one. Phase 1 should not slip, because the 27.2 SDK build turns vertical bars on regardless.
