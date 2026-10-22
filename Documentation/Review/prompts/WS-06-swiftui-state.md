# WS-06 — SwiftUI state, lifecycle & memory

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-06-swiftui-state.md`**

54 views, a 1,560-line `ContentView`, and ten `@MainActor` managers. The failure modes
here are not crashes — they are views that don't update, work that restarts on every
redraw, state that resets when a sheet closes, and memory that never comes back.

## Scope

- `HealthApp/HealthApp/ContentView.swift` (~1,565 LOC)
- `HealthApp/HealthApp/HealthAppApp.swift`
- `HealthApp/HealthApp/Managers/` (10 files, ~6,170 LOC)
- `HealthApp/HealthApp/ViewModels/`
- `HealthApp/HealthApp/Views/` — all 54, but prioritise `ChatDetailView` (~1,060),
  `SettingsView` (~1,150), `UnifiedContextSelectorView` (~1,130), `GeneticTestsSection`
  (~1,045), `DocumentDetailView` (~990), and the tab/split containers.

## What to examine

1. **Ownership graph.** Who creates each manager, and with what property wrapper? Find
   managers created with `@StateObject` inside a view that is re-created (a `NavigationLink`
   destination, a `ForEach` row, a `sheet` content closure) — those get rebuilt and lose
   state. Conversely find `@ObservedObject` on a view that owns the object — that gets
   deallocated. Draw the graph; most state bugs in a codebase this size are visible from it.

2. **Work in `body`.** Anything expensive evaluated during view construction: database
   reads, decryption, date formatting in a loop, `sorted()` over large arrays, JSON
   encoding. `body` can run many times per frame.

3. **`.task` / `.onAppear` discipline.** Does `.task(id:)` carry the right id? Is work
   restarted on every appearance (tab switches, scroll reuse) when it should run once?
   Is work *not* restarted when the id genuinely changed? Is `.onAppear` loading data that
   `.task` already loads (double fetch)?

4. **Retain cycles and leaks.** `Task { }` closures capturing `self` strongly on a view
   model that outlives the view; Combine subscriptions never cancelled; notification
   observers never removed; delegate properties that are `strong` instead of `weak`.
   Quantify what leaks and how often (per chat message? per document? per app launch?).

5. **List performance.** Large collections in `List`/`ForEach`: stable `id`s, `LazyVStack`
   vs `VStack`, whether a chat with 500 messages or a document set of 200 re-diffs the
   whole collection on each append. Check the streaming-message append path specifically
   — appending to a `@Published` array per token with a non-lazy container is a known
   frame-rate cliff.

6. **Navigation state.** `NavigationStack` path arrays: can a stale path value reference a
   deleted record and push an empty/crashing detail view? Deep-link or state-restoration
   paths that resolve IDs that no longer exist.

7. **Sheet / alert / confirmation state.** Multiple `.sheet` modifiers on one view (only
   one wins), `item:`-based sheets with non-`Identifiable`-stable items, alerts whose
   state is reset before the action closure runs.

8. **Scene lifecycle.** Backgrounding mid-stream or mid-import; `scenePhase` handling;
   what is saved and when. On iPad, multiple windows of the same app sharing `@StateObject`
   singletons — check nothing assumes a single window.

9. **Launch path.** `HealthAppApp` → splash → first-launch disclaimer → content. Is
   database init blocking the main thread? What does the user see if init fails
   (`DatabaseUnavailableView`)? Is the splash hiding a slow path that will look like a
   hang on an older device?

10. **Memory.** The MLX path can hold multi-GB models while SwiftUI holds image thumbnails
    and decoded PDFs. Look for unbounded caches, `UIImage` arrays held by views, and
    whether anything responds to memory pressure. Report the worst-case resident set you
    can estimate from the code.

## Output

Plan §1.6 contract, plus the **state ownership graph** as an indented list or table
(manager → created where → wrapper → lifetime → consumers), before the findings.
