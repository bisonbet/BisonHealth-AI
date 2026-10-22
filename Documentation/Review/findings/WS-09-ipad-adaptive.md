# WS-09 — iPad & adaptive layout

> **Screenshots are deliberately not in this repository.** This file cites 29 screenshots
> by filename as evidence. They were kept out of git at the owner's request — a health
> app's UI captures do not belong in version history, and `.gitignore` now excludes
> `Documentation/Review/findings/**/*.png`. The originals are in this session's scratchpad
> at `WS-09-screenshots/`. Re-running WS-09 regenerates them; treat the filenames below as
> labels for what was observed, not as repo paths.

- **Agent / model**: Claude Sonnet 5.5 (WS-09 subagent), simulator-driven
- **Date**: 2026-10-22
- **Commit reviewed**: af05db1 (built from that tree; derived data in the review scratchpad, nothing written to the repo except this file and the screenshots)
- **Scope actually covered**: Built and ran the app on `iPad Pro 11-inch (M5)` (iOS 26.5) and walked: first launch, disclaimer, Health (Records + Documents), document import from Files (single and multi-select), type picker, import-review sheet, doc detail, AI Chat (portrait/landscape, conversation overlay, software keyboard), Settings (+ OpenAI-compatible sub-route), Appointment Prep (+ editor with keyboard), Lab Results entry sheet (+ inline test-result row, decimal pad). Rotated portrait<->landscape with a keyboard and a draft open. Parity re-check of Health, Chat and Lab entry on `iPhone 17 Pro`. Static audit via the brief's greps (size classes, NavigationView = 0 hits, `UIScreen` = 0 hits, ~60 fixed-frame hits triaged), plus a read of ContentView, HealthTabView, DocumentGridView, DocumentsView, ChatView and the sheet call sites. Screenshots: `Documentation/Review/findings/WS-09-screenshots/`.
- **Scope not covered**: **Split View 1/2 and 1/3, Slide Over and Stage Manager were NOT run** (the simulator tools give no way to drag a second app or resize a window); findings 06 is therefore static-only. Hardware-keyboard Tab traversal / Esc / pointer hover were not exercised (no tool to send Esc/Tab; no pointer) — finding 12 is from grep. Drag-and-drop was not tried (no `onDrop` exists, see 12). Landscape disclaimer, Vitals list, Genetics, Imaging, Storage Usage, Export, Privacy/Terms screens, and the iPad MLX download flow were not opened. The app was driven with a mock OpenAI-compatible server on `localhost:4000` (scratchpad `mock.py`, returns `{}` for chat) and, after the first relaunch, with launch args `--ui-testing --disable-healthkit-sync --skip-disclaimer` (see finding 05 for why). That means after the relaunch the DB was the test DB, not the one from the first session. Multi-window: confirmed not supported — no `UIApplicationSupportsMultipleScenes` in `project.pbxproj` (only `UIApplicationSupportsIndirectInputEvents = YES`, line 1103); iPad orientations are all four (line 1106), iPhone portrait only (line 1105). Nothing further to check there.
- **Verdict**: The app is usable on iPad — every primary screen renders, rotates, takes keyboard input and keeps drafts across rotation — but it is a stretched phone layout with real defects (a portrait document-grid overflow, an unreachable iPad master-detail, cramped form sheets) and, on a fresh install, document import cannot succeed and fails silently (finding 01), which an App Store reviewer on iPad will hit first. No P0.
- **Counts**: P0=0 P1=1 P2=7 P3=7 (dropped: 0)

## Backlog item 1 — tracker item 9 live repro (HealthTabView destroys DocumentsView)

**CONFIRMED live, and it is trivial to hit.** Sequence on iPad portrait, unmodified code: import `lab-report.pdf` → Process (extraction provider pointed at the mock server) → *while it was processing* I tapped Settings in the sidebar. Log at that moment: `DocumentProcessor.swift:1023 "6 groups need review (4 auto-accepted) — showing review sheet"`. Returning to Health > Documents showed the document **Completed**, **no review sheet**, and Health > Records showed **no Lab Results** (screenshot `09-ipad-portrait-records-after-cancel-empty.png` shows the same empty Records state). Switching Records<->Documents or Health<->Settings re-creates the view; `.onChange(of: documentProcessor.pendingImportReview)` (`ContentView.swift:661`) never fires because the value was already non-nil when the new `DocumentsView` appeared. Nothing in the UI says a review is waiting.

Second import jamming behind it: **CONFIRMED in the same session.** With review #1 stranded as `pendingImportReview`, importing and processing `lab-report-2.pdf` logged a second `6 groups need review` and called `enqueueImportReview` (`DocumentProcessor.swift:52-58`), which appends to `pendingReviewQueue` because `pendingImportReview != nil` — no value change, no `onChange`, no sheet. Both documents showed **Completed** with zero values imported. The only recovery found was Reprocess Document from the detail sheet (the stored blood test still sits under "Extracted Health Data → Data 1 / Lab Results" in the detail view but that row is not tappable), after which a sheet did appear. A tester would conclude "the import did nothing".

A second, unfiled way to lose the sheet without leaving the tab: a review created while the document-detail sheet is open is queued behind it. Once, the sheet appeared on closing the detail; another time (reprocess at 19:37:46) the sheet had not appeared by 19:39 and only surfaced after more taps. PLAUSIBLE; link not isolated (nested-sheet presentation order of `showingImportReview` vs `selectedDocument`).

## Backlog item 2 — WS-05-06 / tracker item 6

- **Cancel discards the extracted values with nothing to re-open them: CONFIRMED live.** In the review sheet (10 results, 4 "Auto-imported", 6 groups needing review, several defaulted to "Will Ignore", e.g. Total Cholesterol 205 mg/dL, screenshot `08-ipad-portrait-import-review-sheet.png`) I tapped Cancel (`ContentView.swift:640-643` → `discardPendingImportReview`). Result: document stays **Completed**, Records stays empty (`09-…`), the 4 auto-accepted values are gone too, and no "needs review" marker appears in the Documents list. The only re-entry is Reprocess Document (re-runs the whole extraction).
- **Relaunch discards: CONFIRMED mechanically, not separately re-run.** `pendingImportReview` and `pendingReviewQueue` are plain in-memory properties on `DocumentProcessor` (`DocumentProcessor.swift:27,52-68`). I relaunched the app twice during the session, but the relaunch also switched to the `--ui-testing` store, so I do not claim a clean live test of "pending review lost across relaunch". The in-memory-only reading is unambiguous from source.
- **Promoted sheet reusing stale state: PLAUSIBLE, not live-demonstrated.** I could not get two reviews to promote in sequence (see item 1 — the second one never presents). Source reading: `BloodTestImportReviewView` seeds `@State autoAcceptedGroups` with `State(initialValue:)` (`BloodTestImportReviewView.swift:16,27,43`), which SwiftUI honours only on first creation, and the sheet content in `ContentView.swift:625-648` has no `.id(review.documentId)`. If review B is promoted while the sheet is still mounted, A's auto-accepted audit list, plus any `selectedIds`/`ignoredGroupIds`/`demotedGroups`, would carry over. Additionally `handleImportReviewComplete` completes, promotes B (onChange sets `showingImportReview = true`) and then the `Task` at `ContentView.swift:636` sets `showingImportReview = false` after its `await`, which would dismiss B immediately and strand it as in item 1. Fix: `.id(review.documentId)` on the sheet content, and set the flag from the promoted value rather than unconditionally false.

## Screen adaptivity table

| Screen | iPad layout verdict | Evidence |
|---|---|---|
| App shell (`ContentView`) | **Adaptive by size class**, but hand-rolled: fixed 280 pt `HStack` sidebar when regular, `TabView` when compact; sidebar cannot collapse; compact flip rebuilds state (WS-06-04) | `ContentView.swift:17-23,84-98`; `02-…health-home.png`, `22-…landscape-health-records.png`; Split View not run (finding 06) |
| Splash | Phone-style, scales to window | `SplashScreenView.swift:19` (GeometryReader), first-launch screenshot not saved |
| First-launch disclaimer | **Phone-only layout**: full-width cards, ~140-char lines on an 834 pt portrait iPad | `01b-ipad-portrait-disclaimer-clean.png` (finding 09) |
| Health > Records | **Phone layout stretched** (single column of full-width cards; empty-state content off-centre) | `02-…`, `22-…`; findings 09, 10 |
| Health > Documents list | **Phone layout in a wide window**; iPad split view exists in code but is unreachable | `23-ipad-landscape-documents-list.png`; finding 03 |
| Health > Documents grid | **Broken in portrait** (fixed 200 pt tiles in 4 flexible columns overlap/clip); acceptable in landscape | `25-ipad-portrait-documents-grid.png`, `24-…landscape-documents-grid.png`; finding 02 |
| Document detail | Presented as a small form sheet, not a detail pane | `ContentView.swift:559,616`; finding 03 |
| Document-type picker | `.medium` detent sheet: 3 of ~6 rows visible | `05-ipad-portrait-document-type-sheet.png`; finding 04 |
| Import review sheet | Default form sheet (~430x480 pt on 834x1210) for a 10-group review | `08-ipad-portrait-import-review-sheet.png`; finding 04 |
| AI Chat | **Adaptive** (`NavigationSplitView` inside the app shell): conversation list is an overlay in portrait, a third column in landscape | `10-…`, `11-…`, `12-…`, `13-ipad-landscape-chat-typed-text.png`; finding 08 |
| Chat input + keyboard | Adaptive: stays above the software keyboard; draft survives rotation | `13-…`, `15-ipad-rotate-with-keyboard-and-draft.png` |
| Settings | Single full-width form; works, no readable-width cap | `06-…`, `14-ipad-landscape-settings.png`; finding 09 |
| OpenAI-compatible settings | Same, pushed over the whole detail pane | `07-…openai-settings.png` |
| Appointment Prep | Adaptive empty state; editor is a small form sheet that follows the keyboard correctly | `16-…`, `17-…`, `18-ipad-portrait-prep-editor-keyboard.png` |
| Lab Results entry | Small form sheet, inline row expand, decimal-pad popover | `19-…`, `20-…`, `21-…` |
| Offline banner | **Untested**; code puts it under the status bar | finding 07 |
| Vitals list, Genetic/Imaging/Medical Visit sections, Storage Usage, Export, Privacy/Terms, DatabaseUnavailable | **Untested** (DatabaseUnavailable caps at 560 pt: `DatabaseUnavailableView.swift:79`, the only view that caps width) | static only |
| iPhone parity (Health, Chat, Lab entry) | No regression: tab bar shell, large-title chat, full-screen sheet | `30-…`, `31-…`, `32-…` |

## Findings

### WS-09-01 — On a fresh install document import retries forever, silently, and can never succeed
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:618-630` (retry), `:139-143` (fresh item per add), `:1544-1555` (`validateConfiguredExtractionProvider`), `Managers/SettingsManager.swift:103` (default `.onDeviceLLM`)
- **Scenario**: Fresh install on iPad (an App Review device has no downloaded model). Health > Documents > Import File > pick a PDF > Process Now. `extractionProvider` defaults to `.onDeviceLLM`, no vision model is downloaded, so `validateConfiguredExtractionProvider` throws `MLXOnDeviceError.visionModelNotDownloaded`. The failure branch re-queues via `addToQueue`, which builds a **new** `ProcessingQueueItem` with `retryCount = 0`, so `retryCount < maxRetryAttempts` is always true. Observed in the log: `Retrying in 2.0 seconds (attempt 2/3)` repeated roughly every 4 s for the 50+ s I watched, across 13+ cycles; the document row stayed **Pending** and the detail sheet showed "Pending" with no message. No alert, banner or Failed status was ever shown. The loop ended only when I changed the extraction provider (the next retry then succeeded).
- **Evidence**:
  ```swift
  currentItem.retryCount += 1
  if currentItem.retryCount < maxRetryAttempts { ... retryTasks[id] = Task { sleep; await self.addToQueue(currentItem.document, ...) } }
  // addToQueue: let queueItem = ProcessingQueueItem(document: document, priority: priority, addedAt: Date())  // retryCount = 0
  ```
- **Fix**: Carry `retryCount` through the re-queue (pass the item or keep a `[UUID: Int]` map), and classify errors: configuration errors (`visionModelNotDownloaded`) should go straight to `.failed` with a user-visible reason and a "Choose a provider" action, never retry.
- **Blast radius**: `DocumentProcessor` retry path (shared with WS-05-04/-06, tracker items 2, 6, 11, 12); `DocumentDetailView.swift:278-292` status display; Settings "Data Extraction" card.
- **Verification**: Fresh install, no model, import a PDF: expect Failed within ~1 s with an actionable message, exactly one log line `Processing failed`, no re-queue. Unit test: processor with a throwing client increments `retryCount` to the cap and stops.

### WS-09-02 — Document grid overflows and overlaps in iPad portrait
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/DocumentGridView.swift:12-14` (4 flexible columns), `:48-51` (`itemSize` 200), `:89,117` (`.frame(width: itemSize)`)
- **Scenario**: iPad in portrait, Health > Documents > grid toggle. Content width is ~554 pt (834 minus the 280 pt sidebar), 4 columns leave ~118 pt each, but every tile is a fixed 200 pt wide, so tiles overlap their neighbours and the first tile is clipped at the leading edge. `usesExpandedLayout` is true for any regular-width iPad, so the portrait case gets the landscape column count. Screenshot `25-ipad-portrait-documents-grid.png` (landscape is fine: `24-…`).
- **Evidence**:
  ```swift
  let columnCount = isCompact ? 2 : 4
  ...
  private var itemSize: CGFloat { PlatformCapabilities.usesExpandedLayout(...) ? 200 : 160 }
  .frame(width: itemSize, height: itemSize * 0.75)
  ```
- **Fix**: Use `GridItem(.adaptive(minimum: 160, maximum: 220))` and size tiles with `.frame(maxWidth: .infinity)` plus `aspectRatio`, not a fixed width.
- **Blast radius**: `DocumentGridView` only (iPhone uses the same view at 160 pt/2 cols).
- **Verification**: Import 6 docs; portrait and landscape; no tile overlaps or clips at 834 and 1194 pt width; also at 1/3 split.

### WS-09-03 — iPad master-detail for Documents is dead code; detail opens as a small sheet
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/ContentView.swift:559-561,616,744-765`; `HealthApp/HealthApp/Views/HealthTabView.swift:31-33`
- **Scenario**: `DocumentsView` only takes the `NavigationSplitView` path when `embedInNavigation` is true, but its sole call site passes `embedInNavigation: false` (`HealthTabView.swift:33`; grep shows no other `DocumentsView(`/`HealthDataView(` call). The Health-tab merge therefore left `documentsSplitView`, `ContentUnavailableView("Select a Document")`, the `navigationSplitViewColumnWidth(min: 340…)` and the `usesSplitView ? nil : selectedDocument` branch unreachable. On a 1194 pt landscape iPad the user gets a full-width list (`23-ipad-landscape-documents-list.png`) and tapping a row opens a ~430 pt form sheet (`ContentView.swift:616-624`), as in the doc-detail screenshots. The plan's iPad requirement ("must work well on iPad") is met functionally, but the iPad-specific work no longer ships.
- **Evidence**:
  ```swift
  private var usesSplitView: Bool { isIPad && embedInNavigation }   // embedInNavigation is always false
  DocumentsView(embedInNavigation: false)                            // HealthTabView.swift:33
  ```
- **Fix**: Either give the Health tab a real two-column layout on regular width (list + `DocumentDetailView` as the detail column, Records/Documents switch in the list column) or delete the dead branch so it stops drifting. Fix: unknown — needs design.
- **Blast radius**: `HealthTabView`, `DocumentsView`, `DocumentDetailView(showsCloseButton:)`; interacts with WS-06-01/-04 (selection/state loss) so sequence after tracker item 9.
- **Verification**: Landscape iPad: selecting a document shows detail beside the list; portrait: detail presented adaptively; no dead `usesSplitView` branch remains.

### WS-09-04 — Every modal editor/review is a default iPad form sheet (~430x480 pt); the type picker is a clipped medium detent
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `ContentView.swift:625-648` (import review), `Views/DocumentTypeSelectorView.swift:80` (`.presentationDetents([.medium, .large])`), `Views/AppointmentPrepEditorView.swift`, `Views/SectionEditorView.swift:84`, 38 `.sheet(` sites in total, none sets a size
- **Scenario**: On an 834x1210 iPad the import review for a 10-value lab report (the core "review before saving clinical data" step) shows one value card at a time in a 430x480 pt window (`08-ipad-portrait-import-review-sheet.png`); the document-type picker shows 3 of ~6 rows with "Lab Report" cut at the edge and the rest behind a scroll (`05-ipad-portrait-document-type-sheet.png`); the Lab Results and Prep editors fit ~2 fields above the keyboard (`18-…`, `21-…`). All of it works (keyboard avoidance and rotation were fine, `15-…`), but the review sheet is `interactiveDismissDisabled(true)` and long, so the user is scrolling a postage-stamp. Apple does call this out on iPad.
- **Evidence**:
  ```swift
  .presentationDetents([.medium, .large])   // DocumentTypeSelectorView.swift:80
  .interactiveDismissDisabled(true)         // BloodTestImportReviewView.swift:110
  ```
- **Fix**: Add `.presentationSizing(.page)` (iOS 18+, target is 26) or `.presentationDetents([.large])` for the review, lab-entry and Prep editors on regular width; give the type picker `.fitted`/`.large` sizing. Verify with `PresentationSizing` that iPhone presentation is unchanged.
- **Blast radius**: All sheet call sites; iPhone presents sheets full-height already, so no change expected there.
- **Verification**: iPad portrait/landscape, open each sheet; review sheet shows several groups without scrolling; iPhone screenshots unchanged.

### WS-09-05 — Health permission is requested at launch over the splash/disclaimer, and in the simulator the sheet became an unrenderable blocker across relaunches
- **Severity**: P2 · **Confidence**: PLAUSIBLE (sheet-over-disclaimer CONFIRMED; the "re-prompts and blocks on every launch" link is unverified on a real device) · **Effort**: S
- **Location**: `HealthApp/HealthApp/HealthAppApp.swift:275-307` (`syncHealthKitOnLaunch`), `Managers/HealthKitManager.swift:139-151`
- **Scenario**: First launch on iPad: the system "Health Access" sheet appears over the splash before the user has seen the disclaimer (`01-ipad-portrait-disclaimer.png` shows the follow-up "iCloud Health Data Sync is Off" sheet stacked on the disclaimer). I tapped Don't Allow. On every later launch (incl. after a simulator reboot) a blank, untappable white form sheet (screenshot taken, not kept) covered the app; tap and swipe did nothing, so the app was unusable until relaunched with `--disable-healthkit-sync`. The log line each launch is `HealthKit sync failed … Authorization not determined`: the 4-hour throttle (`:283-289`) only records success, so a denied or undetermined state re-requests forever. This may be a simulator HealthKit-UI quirk; I could not confirm on a device. An App Review tester on iPad who dismisses the first sheet may see the same.
- **Evidence**:
  ```swift
  guard !AppTestRuntime.shouldDisableHealthKitSync else { return }
  ... try await healthDataManager.syncFromAppleHealth()   // requests authorization every launch until it succeeds
  ```
- **Fix**: Do not call HealthKit from launch. Trigger `requestAuthorization` only from an explicit "Connect Apple Health" action in Settings (the app already has Sync Now), after the disclaimer, and persist "asked/declined" so it is not retried.
- **Blast radius**: `HealthDataManager.syncFromAppleHealth`, `HealthKitManager`, WS-13 (permission strings, `toShare: []`) and tracker item 22.
- **Verification**: Fresh install: no Health sheet before the disclaimer is accepted, none on relaunch after Don't Allow; Settings > Sync Now still prompts.

### WS-09-06 — The app shell is a hand-rolled fixed-280 pt HStack; Split View / Slide Over / Stage Manager width changes fall back to the iPhone tab layout (not run)
- **Severity**: P2 · **Confidence**: PLAUSIBLE (static only; the size-class flip itself is WS-06-04) · **Effort**: M
- **Location**: `HealthApp/HealthApp/ContentView.swift:17-23,84-98`; `Utils/PlatformCapabilities.swift:55-57`
- **Scenario**: `usesExpandedLayout` is `isIPadAppOnMac || horizontalSizeClass == .regular`. In Split View at 1/2 or 1/3 width (and any Stage Manager window narrower than ~678 pt) the class is compact, so the whole app switches to `compactTabShell`; in 2/3 and full width it is a 280 pt sidebar that never collapses, leaving 554 pt for content in portrait and nested `NavigationSplitView` columns inside Chat. Because of WS-06-04 every crossing of that boundary rebuilds the sections (open sheets and drafts are lost). Not executed: no Split View / window-resize control was available. The 11" portrait result (`02-…`) and the landscape Chat result (`13-…`) show the sidebar is already ~1/3 of portrait width.
- **Evidence**:
  ```swift
  AppSidebar(selectedSection: $selectedSection).frame(width: 280)
  ```
- **Fix**: Use `NavigationSplitView` (or `TabView` with `.tabViewStyle(.sidebarAdaptable)`, iOS 18+) at the root so the system handles collapse, Split View and Stage Manager; keep one `selectedSection` state at the root.
- **Blast radius**: `ContentView` shell, `AppSection.destination`; tracker item 9 (same file, `HealthTabView`).
- **Verification**: Run in Split View 1/2, 1/3, 2/3 and a resized Stage Manager window: no content clipped, sidebar collapses, an open editor sheet survives a width change.

### WS-09-07 — The offline banner is positioned under the status bar and over the navigation bar
- **Severity**: P2 · **Confidence**: PLAUSIBLE (static; offline state not forced) · **Effort**: S
- **Location**: `HealthApp/HealthApp/ContentView.swift:27-36`; `HealthApp/HealthApp/Views/OfflineIndicatorView.swift:11-38`
- **Scenario**: The banner VStack has `.ignoresSafeArea(edges: .top)` and no top inset, so its 12 pt-padded text starts at y≈12, inside the status-bar/Dynamic-Island region (24 pt on iPad, 54+ on iPhone 17 Pro), and it overlays the top nav bar, including the sidebar header and trailing toolbar buttons, with a tappable full-width button. Seen only by reading; offline was not simulated.
- **Evidence**:
  ```swift
  VStack { OfflineIndicatorView(); Spacer() }
      .ignoresSafeArea(edges: .top)
  ```
- **Fix**: Drop `ignoresSafeArea` and use `.safeAreaInset(edge: .top)` on the shell so the banner pushes content down; on iPad scope it to the detail column.
- **Blast radius**: Every screen when offline (iPhone too).
- **Verification**: Toggle Wi-Fi off in the Simulator (or Network Link Conditioner): banner sits below the status bar, nav-bar buttons stay tappable.

### WS-09-08 — "Process Now" in the document detail sheet gives no feedback and the next sheet is hidden behind it
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/DocumentDetailView.swift:278-292`; `ContentView.swift:616-624`
- **Scenario**: Import a PDF (the detail sheet opens automatically) and tap Process Now. For 20+ s the sheet still shows the orange "Pending" badge and the same two buttons (the view holds a `let document` snapshot, so it never reflects the queue). The "Document Type" sheet that the flow wants is queued behind this sheet and only appears when the user closes the detail; the review sheet can be deferred the same way. Seen three times on iPad. A tester will conclude the button did nothing and tap it again.
- **Evidence**:
  ```swift
  Button("Process Now") { Task { await documentProcessor.addToQueue(document, priority: .urgent) } }
  ```
- **Fix**: Observe the live document/queue item in the detail view (status, progress), dismiss or collapse the detail when processing starts, and present the type picker before the detail sheet.
- **Blast radius**: `DocumentDetailView`, `DocumentsView` sheet ordering; related to tracker items 4, 9.
- **Verification**: Tap Process Now: badge changes to Processing within a second and a progress indication appears; the type picker is visible without closing the detail.

### WS-09-09 — Content is never width-limited: disclaimer, Records and Settings stretch edge-to-edge on iPad
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/FirstLaunchDisclaimerView.swift:93`, `Views/SettingsView.swift` (list), `ContentView.swift` HealthDataView content; `DatabaseUnavailableView.swift:79` is the only `maxWidth` cap in the app
- **Scenario**: Portrait disclaimer lines run ~140 characters (`01b-ipad-portrait-disclaimer-clean.png`); landscape Settings puts "AI Provider" at the far left and its value ~900 pt away (`14-ipad-landscape-settings.png`); Records cards are 880 pt wide with a 40 pt icon in them (`22-ipad-landscape-health-records.png`).
- **Fix**: Wrap scroll content in `.frame(maxWidth: 720)` + centre, or use `.contentMargins`/`readableContentGuide` equivalents.
- **Blast radius**: Visual only; iPhone unaffected.
- **Verification**: iPad landscape: text columns ≤ ~720 pt, cards centred.

### WS-09-10 — Empty-state cards are not centred on their content
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: Records section empty states (`ContentView.swift` HealthDataView, `Views/*Section.swift`)
- **Scenario**: Icon and caption sit at ~40% of the card width instead of its centre on iPad (`02-ipad-portrait-health-home.png`, `22-…`) and on iPhone (`30-iphone-health-records.png`); looks like a `VStack` without `.frame(maxWidth: .infinity)`.
- **Fix**: `.frame(maxWidth: .infinity)` on the empty-state VStack.
- **Blast radius**: All Records empty states. **Verification**: icon centred in the card at 834, 1194 and iPhone widths.

### WS-09-11 — Document thumbnails render as a thin band of tiny text on white, with no tile border
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/DocumentGridView.swift:86-92`, `Views/DocumentListView.swift:150`
- **Scenario**: A text-only PDF's page-1 thumbnail fills the tile white-on-white, so the grid shows floating strips of text (`24-ipad-landscape-documents-grid.png`, `25-…`) and the list row shows a 50x50 smear (`23-…`).
- **Fix**: Give thumbnails a hairline border/shadow and `.scaledToFit` with a placeholder aspect ratio.
- **Blast radius**: Visual. **Verification**: grid/list show a visibly bounded page thumbnail.

### WS-09-12 — Hardware keyboard and pointer support is thin
- **Severity**: P3 · **Confidence**: CONFIRMED (grep; not exercised with Tab/Esc) · **Effort**: M
- **Location**: whole app (`grep keyboardShortcut` = 9 hits; `cancelAction`/`defaultAction`/`onKeyPress`/`onExitCommand`/`onDrop`/`dropDestination` = 0; `hoverEffect` = 5 views)
- **Scenario**: Cancel/Save in every sheet lack `.keyboardShortcut(.cancelAction/.defaultAction)`, so Esc does not dismiss them. The only shortcuts live inside `Menu`s (`ContentView.swift:849,859`, `Views/ChatDetailView.swift:269-281`) so they are not discoverable from the iPad shortcut overlay unless the menu is open. There is no sidebar shortcut (⌘1-4) for the four sections, no drag-and-drop import (the UI does not claim one, so no rejection risk). `UIApplicationSupportsIndirectInputEvents` is on, but only conversation and document rows have hover effects.
- **Fix**: `.keyboardShortcut(.cancelAction)` / `.defaultAction` on sheet buttons; `.commands`/menu-bar items for ⌘1-4 and import.
- **Blast radius**: All sheets. **Verification**: Esc closes a sheet; ⌘1-4 switch sections; shortcut overlay lists them.

### WS-09-13 — Cancelling the Appointment Prep editor discards typed text without a prompt
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/AppointmentPrepEditorView.swift:58-62`
- **Scenario**: Typed "Occasional chest tightness…" into Symptoms (`18-ipad-portrait-prep-editor-keyboard.png`), tapped Cancel: sheet closed, draft gone, no confirmation. On iPad the Cancel sits next to the full-size keyboard area where mis-taps are easy; iPhone behaves the same.
- **Fix**: Confirmation dialog when fields are non-empty, or persist the draft.
- **Blast radius**: This editor only. **Verification**: Type, Cancel → prompt.

### WS-09-14 — Relative timestamps read "in 0 seconds" for brand-new items
- **Severity**: P3 · **Confidence**: PLAUSIBLE (seen live in the Documents list and conversation sidebar; cause inferred) · **Effort**: S
- **Location**: `Views/DocumentListView.swift:78`, `Views/ConversationSidebarView.swift:148`, `Views/ConversationListView.swift:97`
- **Scenario**: `RelativeDateTimeFormatter().localizedString(for: importedAt, relativeTo: Date())` renders "in 0 seconds" when `importedAt` is a few ms ahead of `Date()` (creation date stamped before render). Cosmetic, both iPad and iPhone.
- **Fix**: Clamp: `min(date, Date())`. **Blast radius**: three views. **Verification**: new item shows "now"/"0 seconds ago".

### WS-09-15 — Chat in landscape nests a conversation split view inside the app shell, leaving ~560 pt for the transcript
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `ContentView.swift:1429-1460` (`NavigationSplitView`, column width 300-400), plus the 280 pt shell sidebar `:84-87`
- **Scenario**: 1194 pt landscape: 280 pt app sidebar + ~350 pt conversation column + ~560 pt chat (`13-ipad-landscape-chat-typed-text.png`); with the software keyboard up the transcript is ~130 pt tall. In portrait the conversation list is a floating overlay that stays open after "Start New Conversation" until tapped away. Functional, but the three-column result is the symptom of finding 06.
- **Fix**: Fold into the root `NavigationSplitView` rework (06). **Blast radius**: `ChatView`. **Verification**: landscape chat gets at least ~700 pt for the transcript, or the app sidebar collapses.

## Structural risks (max 5 bullets)

- `ContentView.swift` is ~1,700 lines and holds the app shell, Records, Documents, Chat container and Vitals; the iPad branch in each is a parallel implementation that drifts (finding 03 is the result).
- `isIPad` is used as a name for "regular width" throughout (`usesExpandedLayout`), so portrait iPad gets landscape metrics (findings 02, 06).
- There is no adaptive-layout test coverage: 113 UI test functions are orphaned from the target and there is no snapshot test at 834/1194/417 pt.
- All section/editor state lives in views destroyed by the shell's `switch` (WS-06-04); layout fixes that change the shell must land together with that fix.
- Launch-time side effects (HealthKit request, notification prompt on first Documents visit) run before the user has accepted anything; this interacts with every first-run screenshot Apple will take.

## Machine-readable summary
```json
[
  {"id":"WS-09-01","title":"Fresh install: document import retries forever, silently, and cannot succeed","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:618","HealthApp/HealthApp/Services/DocumentProcessor.swift:139","HealthApp/HealthApp/Services/DocumentProcessor.swift:1544"],"effort":"M","area":"ipad-adaptive"},
  {"id":"WS-09-02","title":"Document grid overflows and overlaps in iPad portrait","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentGridView.swift:12","HealthApp/HealthApp/Views/DocumentGridView.swift:89"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-03","title":"iPad Documents master-detail is dead code; detail opens as a small sheet","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:559","HealthApp/HealthApp/Views/HealthTabView.swift:33"],"effort":"M","area":"ipad-adaptive"},
  {"id":"WS-09-04","title":"All modal editors/reviews are default iPad form sheets; type picker clipped medium detent","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:625","HealthApp/HealthApp/Views/DocumentTypeSelectorView.swift:80"],"effort":"M","area":"ipad-adaptive"},
  {"id":"WS-09-05","title":"HealthKit permission requested at launch over splash/disclaimer; blank blocking sheet on relaunch in simulator","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:275"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-06","title":"Hand-rolled fixed 280pt shell; Split View/Stage Manager fall back to phone tab layout (not run)","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/ContentView.swift:17","HealthApp/HealthApp/ContentView.swift:84"],"effort":"M","area":"ipad-adaptive"},
  {"id":"WS-09-07","title":"Offline banner sits under the status bar and over the nav bar","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/ContentView.swift:27","HealthApp/HealthApp/Views/OfflineIndicatorView.swift:11"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-08","title":"Process Now gives no feedback; next sheet hidden behind detail sheet","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentDetailView.swift:278"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-09","title":"No readable-width cap: disclaimer, Records, Settings stretch edge to edge","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/FirstLaunchDisclaimerView.swift:93"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-10","title":"Empty-state cards not centred on content","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:278"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-11","title":"Document thumbnails render as a thin text band on white, no tile border","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentGridView.swift:86","HealthApp/HealthApp/Views/DocumentListView.swift:150"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-12","title":"Hardware keyboard and pointer support thin (no Esc/cancelAction, shortcuts only in menus)","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:849","HealthApp/HealthApp/Views/ChatDetailView.swift:269"],"effort":"M","area":"ipad-adaptive"},
  {"id":"WS-09-13","title":"Prep editor Cancel discards typed text without confirmation","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/AppointmentPrepEditorView.swift:60"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-14","title":"Relative timestamps show 'in 0 seconds' for new items","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/DocumentListView.swift:78","HealthApp/HealthApp/Views/ConversationSidebarView.swift:148"],"effort":"S","area":"ipad-adaptive"},
  {"id":"WS-09-15","title":"Landscape chat nests conversation split view in app shell leaving ~560pt","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:1429"],"effort":"M","area":"ipad-adaptive"}
]
```
