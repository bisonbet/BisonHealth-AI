# WS-06 — SwiftUI state, lifecycle & memory

- **Agent / model**: Claude Sonnet 5.5 (`claude-sonnet-5-5`), single agent, read-only
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (working tree has uncommitted edits to `Documentation/Review/*` only; no Swift changes)
- **Scope actually covered**: `HealthAppApp.swift` (all), `ContentView.swift` (all 1,564 lines), `Managers/AIChatManager.swift`, `DocumentManager.swift`, `ErrorHandler.swift`, `AppSettingsManager.swift`, `AppointmentPrepManager.swift`, parts of `HealthDataManager.swift` / `SettingsManager.swift`; `ViewModels/MedicalDocumentDetailViewModel.swift`; Views: `ChatDetailView`, `HealthTabView`, `SettingsView` (mostly), `UnifiedContextSelectorView` (VM + header), `DocumentDetailView` (top, status, tag editor), `DocumentListView`, `DocumentGridView`, `ConversationSidebarView`, `AppointmentPrepView`/`Detail`/`Editor` (top), `VitalsListView`, `RecentVitalsSection` (index wiring), `PersonalInfoEditorView` (state/debounce), `Medication/Supplement/MedicalCondition` editors and their list/selector hosts, `BloodTestImportReviewView` (head), `AWSBedrockSettingsView` (state wiring); `Database/DatabaseManager.swift` init + migrations v11/v12; `Services/DocumentProcessor.swift` review queue; `Utils/AIResponseCleaner.swift`; `MLXOnDeviceClient.swift` streaming loop.
- **Scope not covered**: `GeneticTestsSection` (1,044 lines), `BloodTestsSection`, `PersonalInfoSection`, `StorageUsageView`, `OnDeviceLLMSettingsView`, `OpenAICompatibleSettingsView`, `DocumentDetailView` lines 520-850 (extracted-data rendering, QuickLook coordinator). Not read line-by-line; grepped for `.task`/`.onAppear`/observers/formatters/`sorted` only. **No runtime verification**: no build, no simulator (sibling agents were running); every runtime-dependent conclusion is marked code-trace. The micro-benchmarks below were compiled standalone with `swiftc -O` on the Mac host (not on device) from copies of the repo files in the scratchpad.
- **Verdict**: Not beta-ready in the document-import and chat flows. The architecture (MVVM, singletons plus `@StateObject` leaf owners) is sound and the memory hygiene is better than average (no leaks in observers/Combine), but several flows keep their *only* copy of in-flight state in views that a parent conditionally destroys, and two data-integrity flows (review sheet, Reset Database) depend on edge-triggered or absent UI synchronisation.
- **Counts**: P0=0 P1=3 P2=9 P3=3 (dropped: 2)

---

## State ownership graph

Single scene: no `UIApplicationSupportsMultipleScenes` in the generated Info.plist (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES`, no multi-scene key), so "per window" == "per process". iPad Split View / Slide Over / Stage Manager still resize **one** scene, which flips `horizontalSizeClass` (see WS-06-04).

### A. Process-lifetime singletons (all `@MainActor`)

| Object | Created | Wrapper at use sites | Lifetime | Main consumers |
|---|---|---|---|---|
| `DatabaseManager.shared` | `static let` closure, first touched by `AppStartupHealth.shared` / `AppState.init` (HealthAppApp.swift:10-12) | n/a (not observed) | process | everything |
| `AppStartupHealth.shared` | `@StateObject` in `HealthAppApp` (:12) | `@StateObject` | process | root `if blockingError` switch |
| `AppState` | `@StateObject` in `HealthAppApp` (:10); `.environmentObject` into `ContentView` (:70) | `@EnvironmentObject` (ContentView, SettingsView) | scene (= process) | colour scheme, scenePhase, crash alert |
| `AppSettingsManager.shared` | `@StateObject` (:11) + again in `FirstLaunchDisclaimerView:14` | `@StateObject` ×2 on a singleton | process | disclaimer gate; **swaps the whole shell** (WS-06-15) |
| `HealthDataManager.shared` | static; touched by `AppState` stored property | `@StateObject = .shared` in ContentView:279, SettingsView:29, VitalsListView:5 | process | Records tab, Settings, Vitals, DocumentProcessor |
| `SettingsManager.shared` | static | `@StateObject = .shared` (SettingsView:10), `@ObservedObject = .shared` (ChatDetailView:726) | process | settings, AI client factory |
| `AppointmentPrepManager.shared` | static | `@StateObject = .shared` (AppointmentPrepView:6) | process | Prep tab |
| `HealthKitManager.shared`, `MLXModelDownloadManager.shared`, `BloodTestDataManager.shared`, `NetworkManager.shared`, `AWSCredentialsManager.shared`, `ErrorHandler.shared`, `DocumentProcessor.shared` | static | mixed `@StateObject`/`@ObservedObject` with `= .shared` default | process | various |

`@StateObject … = X.shared` appears at ~16 sites. It is harmless here (the autoclosure just returns the singleton and `@StateObject` never owns anything), so it is not reported, but it is the wrong wrapper (`@ObservedObject`) and it hides which objects are actually view-owned.

### B. View-owned instances (the ones that can lose state)

| Object | Created where | Wrapper | Real lifetime | Destroyed when | Consumers |
|---|---|---|---|---|---|
| **`AIChatManager`** | `ChatView` (ContentView.swift:1383) | `@StateObject` | the `ChatView` identity | iPad sidebar section change (ContentView.swift:93); size-class flip (ContentView.swift:21-24); `appShell` swap (WS-06-15). **Survives** tab switches on iPhone (TabView retains) | `ChatDetailView` (`@ObservedObject`), `UnifiedContextSelectorView`, `ConversationSidebarView` (value copy of `conversations`) |
| **`DocumentManager`** | `DocumentsView` (ContentView.swift:521) | `@StateObject` | the `DocumentsView` identity | **Records⇄Documents segment toggle** (HealthTabView.swift:29); iPad section change; size-class flip | `DocumentList/GridView` (value copies), `DocumentDetailView` (`@ObservedObject`), `BatchProcessingView`, `DocumentFilterView` |
| `DocumentManager.shared` (second instance) | static, first touched by delete context menus / `MedicalDocumentDetailViewModel` | none | process | never | 5 delete call sites. Two live managers; kept consistent only through `.medicalDocumentDidDelete` |
| `UnifiedContextSelectorViewModel` | `UnifiedContextSelectorView.init` via `StateObject(wrappedValue:)` | `@StateObject` | the sheet presentation | sheet dismissal | context-selector sheet only |
| `MedicalDocumentDetailViewModel` | `MedicalDocumentDetailView.init(document:)` | `@StateObject` | one pushed detail screen | pop | holds a **snapshot** of the document (WS-06-08) |
| `ConversationExporter`, `DocumentExporter` | per-view property initialisers | `@StateObject` | per sheet / screen | dismissal | export UIs |
| `AppointmentPrepDetailView.prep` | `State(initialValue: prep)` | `@State` copy | one detail push | pop | snapshot, refreshed only via editor `onComplete` |

### C. Pass-through (`@ObservedObject` on a non-owner): `ChatDetailView.chatManager`, `DocumentDetailView.documentManager/documentProcessor`, `BatchProcessingView`, `DocumentFilterView`, `AppointmentPrep{Detail,Editor}View.manager`, `OpenAICompatibleSettingsView.settingsManager`. All are passed from a live owner; I found **no** `@ObservedObject` on a view that actually creates the object, and no `@StateObject` created inside a `NavigationLink` destination, `ForEach` row, or sheet closure other than the two sheet-scoped view models above (those are correct).

### D. In-flight state that lives only in a destroyable view (the real defects)

| State | Lives in | Lost when |
|---|---|---|
| `showingImportReview` / `showingGeneticTestReview` / `activeAutoImportSummary` (+ Undo) | `DocumentsView` `@State`, driven by edge-triggered `.onChange` | any destruction of `DocumentsView` |
| `pendingCategoryDocuments`, `pendingDocumentForCategory` | `DocumentsView` `@State` | same |
| Streaming placeholder message + `isSendingMessage` | `AIChatManager` (view-owned), only copy in memory | `ChatView` rebuilt, or `loadConversations()` re-run (WS-06-03) |
| `editedInfo` in `PersonalInfoEditorView`, `messageText`, `NavigationStack` pushes | sheets / views under `HealthDataView` / `ChatDetailView` | shell swap |

### E. Lifecycle hooks
`HealthAppApp` → `.onChange(of: scenePhase)` → `AppState.handleScenePhaseChange`: `.background` marks clean shutdown and suspends MLX; `.active` marks session active and resumes MLX. Nothing else reacts to scene phase: no flush of edit drafts, no `beginBackgroundTask` around a cloud stream. No `@SceneStorage`, `NavigationPath`, `onOpenURL`, or `NSUserActivity` anywhere, so there is no state restoration and **no stale-path hazard** (item 6 of the brief: negative result). No `didReceiveMemoryWarning` observer anywhere (item 10).

---

## Findings

### WS-06-01 — Review sheets are edge-triggered by a view that the Records⇄Documents toggle destroys: lab values needing review are never imported and the review queue jams
- **Severity**: P1 · **Confidence**: CONFIRMED (static trace) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Views/HealthTabView.swift:29-35`, `HealthApp/HealthApp/ContentView.swift:661-686`, `HealthApp/HealthApp/Services/DocumentProcessor.swift:51-57`
- **Scenario**: User imports a lab PDF; extraction takes tens of seconds (OCR + LLM). While it runs they tap **Records** in the segmented control to look at the results page. `HealthTabView.content` is a `switch`, so `DocumentsView` (and its `@StateObject DocumentManager` and all `@State`) is discarded. Extraction finishes with groups needing review, `DocumentProcessor.enqueueImportReview` sets `pendingImportReview`. Nobody is observing. The user taps **Documents** again; the new `DocumentsView` has `showingImportReview == false`, and `.onChange` does not fire for a value that was already set before the view existed. The review sheet never appears. Because `enqueueImportReview` only publishes when the slot is `nil`, every later document's review queues behind the stuck one for the rest of the session; the groups that needed review are never imported. The same applies to `pendingGeneticTestReview`, and the 12-second "Imported N values - Undo" banner is destroyed with the view (the summary stays set, so it never returns and Undo is gone). On iPad the same happens whenever the user picks another sidebar section (WS-06-04). The code comment at `ContentView.swift:1109-1110` ("a stuck slot jams every later document's review for the rest of the session") shows the authors know the cost. Workaround: relaunch (the pending review is memory-only, so the un-reviewed values are lost) and re-process the document.
- **Evidence**:
  ```swift
  // HealthTabView.swift:28
  switch segment {
  case .records:   HealthDataView(embedInNavigation: false)
  case .documents: DocumentsView(embedInNavigation: false)
  }
  // ContentView.swift:661  (no `initial: true`, no onAppear re-check)
  .onChange(of: documentProcessor.pendingImportReview) { oldValue, newValue in
      if newValue != nil { showingImportReview = true } else { showingImportReview = false }
  }
  // DocumentProcessor.swift:51
  func enqueueImportReview(_ review: PendingImportReview) {
      if pendingImportReview == nil { pendingImportReview = review } else { pendingReviewQueue.append(review) }
  }
  ```
- **Fix**: Make presentation level-triggered: derive `showingImportReview` from `documentProcessor.pendingImportReview != nil` (a computed binding, or `.onChange(..., initial: true)` plus the same in `.onAppear`). Better, hoist the review/banner presentation to `ContentView` (always alive) so it does not depend on which tab or segment is visible. Also stop switching the segment content out of the hierarchy (keep both children alive with `opacity`/`allowsHitTesting`, or lift `DocumentManager` to the tab).
- **Blast radius**: `ContentView.swift` (DocumentsView), `HealthTabView.swift`, `DocumentDetailView.swift:140-170` (duplicate presenter of the same review). Same file as tracker item 10 (`ContentView.swift`), so sequence after it.
- **Verification**: UI test: import a fixture lab PDF that needs review, toggle to Records and back before extraction completes, assert the review sheet is presented on return (or immediately). Unit-test `DocumentProcessor` queue: two enqueues, no observer, assert the second is promoted after the first is finished. Manual: confirm Undo banner survives a segment flip.

### WS-06-02 — "Reset Database" wipes SQLite but leaves every manager's in-memory copy; the UI keeps showing the deleted PHI and the next edit writes it back
- **Severity**: P1 · **Confidence**: CONFIRMED (static trace) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Views/SettingsView.swift:1011-1025`, `HealthApp/HealthApp/Database/DatabaseManager.swift:745-783`
- **Scenario**: The alert promises "permanently delete ALL your health data, documents, and chat history". `performDatabaseReset()` only calls `DatabaseManager.resetDatabase()`. `HealthDataManager.personalInfo/bloodTests/...`, `DocumentManager.documents`, `AIChatManager.conversations/currentConversation`, `AppointmentPrepManager.preps` and `AppSettingsManager.hasAcceptedDisclaimer` are all unchanged, and nothing posts a reset notification (grep: no observer for it). The success alert says everything was deleted while the Records, Documents and Chat screens still show it. If the user then opens **Personal Info** and taps Save (the editor is seeded from the stale `personalInfo`), `savePersonalInfo` writes the "deleted" record back into the fresh database; a chat reply to a stale conversation hits a foreign-key failure. This is distinct from WS-02-06 (backup never made, files left on disk): here the deletion is also *visibly and actually* undone by ordinary use. `AppStartupHealth.refresh()` is only called from the `DatabaseUnavailableView` path.
- **Evidence**:
  ```swift
  private func performDatabaseReset() {
      Task {
          do {
              try DatabaseManager.shared.resetDatabase()
              await MainActor.run {
                  successMessage = "Database has been reset successfully. All health data has been permanently deleted."
                  showingSuccessMessage = true
  ```
- **Fix**: Add a `DatabaseManager.didReset` notification (or an `async` `resetAll()` on a coordinator) that every manager observes and clears: `HealthDataManager`, `DocumentManager` (both instances), `AIChatManager`, `AppointmentPrepManager`, `DocumentProcessor` queues/pending reviews, `AppSettingsManager.refreshSettings()`. Call `AppStartupHealth.refresh()`.
- **Blast radius**: all managers; `SettingsView.swift`; overlaps WS-02-06 (`DatabaseManager.swift`) so one agent should own both.
- **Verification**: Test: seed personal info + a conversation, call the reset path, assert `healthDataManager.personalInfo == nil`, `chatManager.conversations.isEmpty`, `documentManager.documents.isEmpty`. UI: reset, open Records/Chat, expect empty states.

### WS-06-03 — `ChatView.task` re-loads all conversations from the database on every appearance, orphaning the streaming placeholder and silently discarding the reply
- **Severity**: P1 · **Confidence**: PLAUSIBLE (unverified link: that `.task` on a `TabView` page re-fires each time the tab is re-selected, which is standard `onAppear`/`task` behaviour for tab content but was not run) · **Effort**: S
- **Location**: `HealthApp/HealthApp/ContentView.swift:1415-1418`, `HealthApp/HealthApp/Managers/AIChatManager.swift:178-190,772-777`
- **Scenario**: On iPhone the user sends a question on a slow provider (on-device model, or a 300 s-timeout self-hosted server). While the reply streams they open the Health tab to check a value, then return to Chat. The `ChatView` `.task` runs again and replaces `conversations` with `fetchConversations()`. The placeholder assistant message is only persisted in `onComplete`, so the DB copy does not contain it. Subsequent `updateStreamingMessage` calls find no matching index and drop updates (UI freezes on the typing dots); `onComplete` then hits the guard "conversation cleared mid-stream" and returns **without saving**. The reply the provider produced (and, for Bedrock, billed for) is gone, with only an `AppLog` warning. `AIChatManager.init` also launches its own `loadConversations()` Task, so every `ChatView` creation does the full decrypt-everything fetch twice (see cost note below).
- **Evidence**:
  ```swift
  // ContentView.swift:1415
  .task { await chatManager.loadConversations() }
  // AIChatManager.swift:183
  conversations = try await databaseManager.fetchConversations()
  // AIChatManager.swift:772  (same guard in the OpenAI/Bedrock/MLX branches)
  guard let conversation = self.conversations.first(where: { $0.id == conversationId }),
        conversation.messages.contains(where: { $0.id == streamingMessageId }) else {
      AppLog.shared.ai("Discarding streamed reply: conversation cleared mid-stream", level: .warning)
      return
  ```
- **Fix**: Load once (guard with `if conversations.isEmpty && !didLoad`, or move to the manager's init only) and make `loadConversations()` merge instead of replace while `isSendingMessage` is true (keep the in-flight conversation's local copy). Persist the placeholder row up front, or make `onComplete` re-insert the message when the conversation still exists but the placeholder is missing.
- **Blast radius**: `AIChatManager.swift` (tracker hot spot: items 4, 10, 14), `ContentView.swift`. Cost note: `fetchConversations()` decrypts every message of every non-archived conversation on the main actor (O(total messages)); AES-GCM is not the cost (see brief), SQLite row iteration and per-conversation queries are.
- **Verification**: Unit test with a scripted streaming client: start a send, call `loadConversations()` mid-stream, finish the stream, assert the assistant message is in the DB and in `conversations`. Device: send on-device chat, switch tabs twice during generation.

### WS-06-04 — Size-class flips and iPad sidebar selection rebuild whole sections: `AIChatManager`, `DocumentManager`, editor sheets and navigation state are destroyed mid-use
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace; SwiftUI conditional-branch identity) · **Effort**: M
- **Location**: `HealthApp/HealthApp/ContentView.swift:18-24,90-94,142-152`
- **Scenario**: (a) iPad: the sidebar renders `selectedSection.destination`, a `@ViewBuilder switch`; selecting Settings destroys `ChatView` and its `@StateObject AIChatManager`. A reply still streaming keeps running (the view's `Task` retains the old manager), but returning to Chat creates a second manager that loads from the DB, shows no placeholder, reports `isSendingMessage == false` (so the user can send a second message while the first is still in flight), and never sees the first reply until it is reloaded. (b) Any iPad window resize that crosses the compact/regular boundary (Split View, Slide Over, Stage Manager) swaps `compactTabShell` for `expandedAppShell`; all four tabs lose their `@StateObject`s, open sheets (e.g. `PersonalInfoEditorView` with unsaved edits, `BloodTestEntryView`) are dismissed and chat drafts vanish. (c) `HealthTabView` also resets to Records.
- **Evidence**:
  ```swift
  // ContentView.swift:18
  Group { if isIPad { expandedAppShell } else { compactTabShell } }
  // ContentView.swift:90
  selectedSection.destination      // @ViewBuilder switch -> ChatView() / SettingsView() / ...
  // ContentView.swift:1383
  @StateObject private var chatManager = AIChatManager(healthDataManager: .shared, databaseManager: .shared)
  ```
- **Fix**: Own the long-lived managers above the shell (`ContentView` `@StateObject`, injected via `.environmentObject`), and keep all four sections in the hierarchy on iPad (ZStack with `opacity`/`allowsHitTesting`, or `TabView` with `.tabViewStyle(.sidebarAdaptable)` which preserves state). Do not branch on `horizontalSizeClass` above stateful views.
- **Blast radius**: `ContentView.swift`, `HealthTabView.swift`, every section root. Interacts with WS-06-01 and WS-06-03.
- **Verification**: iPad simulator: start a send, switch sidebar to Settings and back (expect the reply to complete in place); open Personal Info editor, enter Split View, expect the sheet to survive. UI test for `isSendingMessage` after a section round-trip.

### WS-06-05 — Frequency/end-date (and "diagnosed date") are committed in `onDisappear`, so "Add"/"Save" in the sheet hosts read the values before they exist
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/SupplementEditorView.swift:69-70,83-93`, `HealthApp/HealthApp/Views/SupplementSelectorView.swift:141-156`, `HealthApp/HealthApp/Views/PersonalMedicalHistoryView.swift:57-75`, `HealthApp/HealthApp/Views/MedicationEditorView.swift:79-80`
- **Scenario**: The editors keep frequency/end-date in `@State` copies and write them back to the `@Binding` only in `.onDisappear { saveChanges() }`. In `SupplementSelectorView` the custom-supplement sheet's **Add** button does `supplements.append(newCustomSupplement)` and dismisses; `onDisappear` fires afterwards and writes to `$newCustomSupplement`, a throwaway. A user who picks "Twice a day" saves the supplement as the default frequency. The same pattern in `PersonalMedicalHistoryView` (**Save** appends `newCondition` before `hasDiagnosedDate = false` is applied) keeps a diagnosed date the user turned off. The medication editor is reached by `NavigationLink` push, so Back commits first and is safe today, but it is one refactor from the same bug and a force-quit while the editor is on screen also loses the edit.
- **Evidence**:
  ```swift
  // SupplementSelectorView.swift:149
  Button("Add") {
      supplements.append(newCustomSupplement)      // frequency still the default
      showingCustomSupplementEditor = false
      dismiss()
  }
  // SupplementEditorView.swift:69
  .onAppear(perform: setupView)
  .onDisappear(perform: saveChanges)               // only place frequency reaches the binding
  ```
- **Fix**: Bind the picker through a `Binding<Frequency>` that writes `supplement.frequency` immediately (same for end date and diagnosed date); delete `setupView`/`saveChanges`.
- **Blast radius**: three editors plus their list/selector hosts; `PersonalInfoEditorView` Save path.
- **Verification**: UI test: add a custom supplement with "Twice a day", re-open it, expect "Twice a day"; unit-test the binding adapters.

### WS-06-06 — `DocumentDetailView` renders a frozen `let document`; status, tags, notes and extracted data never refresh while it is open
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/DocumentDetailView.swift:6,260-285,905-930`, `HealthApp/HealthApp/ContentView.swift:614-623,748-753`
- **Scenario**: `DocumentsView` stores the tapped row in `@State selectedDocument` and presents `DocumentDetailView(document: selectedDocument …)`. The detail view reads `document.processingStatus`, `document.tags`, `document.notes` and `document.extractedHealthData` from that immutable copy. After the user taps **Process Now**, the badge stays "Pending" and the button stays visible after processing finishes, so a second tap re-enqueues the same document (the pending/failed buttons are driven by the stale status). A tag added through `TagEditorSheet` is saved by id but never appears in the "Tags" section, and re-opening the tag editor diffs against the stale `document.tags`. The iPad split-view detail pane has the same staleness. The import flow also seeds `selectedDocument` with the just-imported (still `.pending`) document.
- **Evidence**:
  ```swift
  struct DocumentDetailView: View {
      let document: MedicalDocument                     // snapshot
      @ObservedObject var documentManager: DocumentManager
  // ContentView.swift:616
  .sheet(item: Binding(get: { usesSplitView ? nil : selectedDocument }, set: { selectedDocument = $0 }))
  ```
- **Fix**: Pass the `UUID` and resolve `documentManager.documents.first { $0.id == id } ?? fallback` in the view, or have `DocumentsView` mirror `documentManager.documents` into `selectedDocument` with `.onChange`.
- **Blast radius**: `DocumentDetailView.swift`, `ContentView.swift`; same `ContentView.swift` file as items 10/WS-06-01.
- **Verification**: UI test: open a pending document, process it, assert the detail badge becomes "Completed" without reopening; add a tag and assert it renders.

### WS-06-07 — Import flow presents the document-detail sheet and the category sheet in the same transaction (iPhone)
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified link: which sheet wins when two `.sheet` modifiers on one view flip together; SwiftUI presents one and defers or drops the other) · **Effort**: S
- **Location**: `HealthApp/HealthApp/ContentView.swift:954-962,1010-1016,614-623,711-730`
- **Scenario**: After a file or photo import both handlers do `selectedDocument = pendingCategoryDocuments.first` **and** `showingDocumentTypeSelector = true`. On iPhone `usesSplitView` is false, so the `.sheet(item:)` for `DocumentDetailView` also becomes active. Either the category sheet (non-dismissable) is deferred behind an unwanted detail sheet, or the detail sheet pops up after the user confirms a category (the confirm closure never clears `selectedDocument`, and re-sets it for the next queued file). The `selectedDocument` assignment only makes sense for the iPad detail pane.
- **Evidence**:
  ```swift
  pendingDocumentForCategory = pendingCategoryDocuments.first
  selectedDocument = pendingCategoryDocuments.first     // opens the detail sheet on iPhone
  ...
  showingDocumentTypeSelector = true
  ```
- **Fix**: Drive all three document sheets from a single `enum DocumentSheet: Identifiable` state (`.detail(id)`, `.category(id)`, `.filter`, `.batch`) so only one can be active; set `selectedDocument` only when `usesSplitView`.
- **Blast radius**: `DocumentsView` only.
- **Verification**: iPhone simulator: import two PDFs, expect exactly one category sheet at a time and no detail sheet before or after.

### WS-06-08 — Records tab lists for imaging reports and health checkups are refreshed only by pull-to-refresh; edits and imports do not propagate
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/HealthDataManager.swift:64-90,401-412`, `HealthApp/HealthApp/Services/DocumentProcessor.swift:228`, `HealthApp/HealthApp/ViewModels/MedicalDocumentDetailViewModel.swift:88-100`
- **Scenario**: `HealthDataManager` observes `.medicalDocumentDidChange` but its handler calls `refreshGeneticTestDocuments()` only; `imagingReports` and `healthCheckups` are filled in `loadHealthDataInternal` at launch and never again. The notification itself is posted from exactly one place (`saveGeneticTestResult`). So a newly processed imaging report or doctor's note does not appear under Records until the user pulls to refresh or relaunches, and edits made in `MedicalDocumentDetailView` (date, category, provider, tags) are written to the DB by the view model but never reflected in the section list that links to it (a document recategorised away from Imaging stays listed). The detail view model also writes a full-row `updateMedicalDocument` from its init-time snapshot, which overwrites any newer processor output on the same row.
- **Evidence**:
  ```swift
  // HealthDataManager.swift:64
  ... forName: .medicalDocumentDidChange ... { _ in
      Task { @MainActor [weak self] in await self?.refreshGeneticTestDocuments() }
  // DocumentProcessor.swift:228  (the only post)
  NotificationCenter.default.post(name: .medicalDocumentDidChange, object: document)
  ```
- **Fix**: Post `.medicalDocumentDidChange` from `DocumentProcessor` on completion and from `MedicalDocumentDetailViewModel.saveDocument`, and have `HealthDataManager` refresh all three document-derived lists in the handler (one `fetchMedicalDocuments` per category; they are small). Make the VM write a patch or re-read before write.
- **Blast radius**: `HealthDataManager.swift`, `DocumentProcessor.swift` (tracker hot spot: items 5, 13), the VM.
- **Verification**: Import an imaging-report fixture, expect it under Records without refresh; change a document's category in the detail screen and expect the section to update.

### WS-06-09 — Settings controls bound to state nothing reads: Bedrock model/temperature/max-tokens, "Enable AWS Bedrock", and the conversation "Streaming Responses" toggle
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace; overlaps WS-04 scope) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/AWSBedrockSettingsView.swift:12-15,288-295,362-387`, `HealthApp/HealthApp/Managers/SettingsManager.swift:494-510`, `HealthApp/HealthApp/Views/ChatDetailView.swift:727`
- **Scenario**: The Bedrock settings screen stores its model, temperature, token limit and enable flag in `@AppStorage` keys (`awsBedrockModel`, …). The chat client is built by `SettingsManager.getBedrockClient()` from `modelPreferences.bedrockModel` (assigned nowhere except its default and the decoder) with hard-coded `temperature: 0.1` and `maxTokens: 4096`. A user who selects Amazon Nova Premier, sees "Test connection: Model Nova Premier is ready" (the test builds its config from the view's own state), and then chats, is served Claude Sonnet 4.5 at fixed parameters. Likewise `ConversationSettingsView.useStreaming` is a private `@State` that is never consulted (`sendMessage(…, useStreaming: !AppTestRuntime.isUITesting)`). Two sources of truth, one of them dead.
- **Evidence**:
  ```swift
  // AWSBedrockSettingsView.swift:12
  @AppStorage("awsBedrockModel") private var selectedModel: String = AWSBedrockModel.claudeSonnet45.rawValue
  // SettingsManager.swift:505
  model: AWSBedrockModel(rawValue: modelPreferences.bedrockModel) ?? .claudeSonnet45,
  temperature: 0.1,
  maxTokens: 4096,
  ```
  `grep -rn "bedrockModel\s*=" HealthApp` returns only the decoder line; `grep -rn awsBedrockModel` returns only the declaration.
- **Fix**: Bind the picker to `settingsManager.modelPreferences.bedrockModel` (+ temperature/maxTokens fields in `ModelPreferences`) and delete the `@AppStorage` copies; remove or implement the streaming toggle.
- **Blast radius**: `SettingsManager.swift` (Codable `ModelPreferences`; adding fields needs decoder defaults, no DB migration), `AWSBedrockSettingsView`, `ChatDetailView`.
- **Verification**: Select a non-default model, send a chat, assert the request's `modelId` (`ServiceClientTests` with a recorded request); relaunch and assert persistence.

### WS-06-10 — A stream that dies midway leaves a truncated assistant message that looks complete, is never persisted, and is replayed to the model as history
- **Severity**: P2 · **Confidence**: CONFIRMED (static trace) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:455-480,690-700,826-835`
- **Scenario**: Partial text is written into the in-memory assistant message by `updateStreamingMessage`; persistence happens only in `onComplete`. If the provider call throws part-way (network drop, server timeout, iOS suspending the socket when the app is backgrounded; there is no `beginBackgroundTask` and no scene-phase hook in the chat manager), the `catch` in `sendMessage` marks the *user* message failed and removes only assistant messages whose content is **empty**. The non-empty partial reply stays in `conversations` with no error styling and no "incomplete" marker, disappears at next launch (never saved), and is included in `conversationHistory` (`filter { !$0.content.isEmpty }`) for the retry and every later turn, so the model is told it already answered with half a sentence.
- **Evidence**:
  ```swift
  // AIChatManager.swift:475
  conversations[index].messages.removeAll { $0.role == .assistant && $0.content.isEmpty }
  // AIChatManager.swift:700 (history for next turn)
  messagesWithoutCurrent.filter { !$0.content.isEmpty }
  ```
- **Fix**: In the `catch`, remove the streaming placeholder by its id (`streamingMessageId`), whether or not it has content, or mark it `.failed` and exclude failed/incomplete messages from history. Persist or discard consistently.
- **Blast radius**: `AIChatManager.swift` (items 4, 10, 14 hot spot); WS-04 may touch the same error path.
- **Verification**: Scripted client that emits two chunks then throws; assert no assistant message with partial text remains in `conversations` and that `retryFailedMessage` sends history without it.

### WS-06-11 — Streaming cost grows with reply length: whole-message cleaning runs in `body` every tick and again per update on the main actor
- **Severity**: P2 · **Confidence**: CONFIRMED for the algorithm and the host-side timings; PLAUSIBLE for device impact (benchmark ran on the Mac, not on an iPhone; Textual parse/layout cost not measured) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/ChatDetailView.swift:506-515`, `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:372-380`, `HealthApp/HealthApp/Utils/AIResponseCleaner.swift:99-151`
- **Scenario**: **Containers are fine** (see "Streaming verdict" below). The remaining per-tick cost is O(length): `EnhancedMessageBubbleView.buildMarkdownView()` runs `AIResponseCleaner.clean(message.content)` (NFC normalise, ~N special-token `replacingOccurrences`, per-line regex whitespace pass) on every body evaluation of the streaming bubble, i.e. at the 15 fps throttle, and on every bubble that is materialised by scrolling. The MLX client already cleaned the same text with `cleanConversational` (20 Hz, main actor), so the view-side clean is redundant. Measured with `swiftc -O` against a copy of the repo file: `clean()` = 1.15 ms at 2 KB, 2.68 ms at 6 KB, 8.36 ms at 20 KB; `cleanConversational` = 1.14 / 2.76 / 9.31 ms. Per second of streaming, on the main thread: 6 KB reply ≈ 15×2.7 + 20×2.8 ≈ 96 ms (10%); 20 KB reply ≈ 15×8.4 + 20×9.3 ≈ 312 ms (31%), before Textual's own parse and layout, which also re-run over the whole text each tick. Device timings will be higher.
- **Evidence**:
  ```swift
  // ChatDetailView.swift:508
  let cleanedContent = AIResponseCleaner.clean(message.content)
  return StructuredText(markdown: cleanedContent)
  // MLXOnDeviceClient.swift:375  (loop runs on the main actor, per its own comment)
  if Date().timeIntervalSince(lastProgressEmit) >= 0.05 {
      onUpdate(AIResponseCleaner.cleanConversational(accumulatedContent, detectRunawayRepetition: false))
  ```
- **Fix**: Clean once where the text is produced (clients already do) and drop the view-side `clean()`; for legacy stored messages clean on load. If kept, memoise on `(message.id, content.count)`. Consider appending only the delta to an `AttributedString` rather than re-parsing the whole message.
- **Blast radius**: `ChatDetailView.swift` (tracker hot spot), `AIResponseCleaner` call sites (Bedrock/OpenAI paths already clean in the client).
- **Verification**: Instruments Time Profiler on device with a 20 KB scripted stream; assert `body` of the streaming bubble < 4 ms. Unit test that `clean(cleanConversational(x)) == cleanConversational(x)` before removing the view-side call.

### WS-06-12 — Database open and v11/v12 migrations run synchronously on the main thread before the first SwiftUI frame
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified link: wall-clock cost on a real library; mechanism is certain) · **Effort**: M
- **Location**: `HealthApp/HealthApp/HealthAppApp.swift:10-12`, `HealthApp/HealthApp/Database/DatabaseManager.swift:11-19,125-270,562-577,587-640`
- **Scenario**: `@StateObject AppState()` / `AppStartupHealth.shared` pull `DatabaseManager.shared`, whose initialiser reads the Keychain, opens SQLite, creates tables and runs `performDatabaseMigration` on the main thread inside the first `body` evaluation. For a fresh install this is a few tens of ms (a version-0 database just records the version). For a beta tester upgrading from a build below v12 it also (1) copies the whole database file (`createBackupBeforeMigration`), (2) loads **every document row's** text/sections/extracted-data into memory and re-encrypts it (v11 `encryptDocumentPHIColumns`), and (3) runs `ALTER TABLE documents DROP COLUMN raw_docling_output` (v12), which rewrites every row, including legacy multi-MB Docling payloads. Time scales with library size; a library of a few hundred documents is plausibly seconds, during which the user sees only the static launch screen (the SwiftUI `SplashScreenView` has not rendered yet), and a very large one approaches the launch watchdog. This is code-trace only; no migration timing was run.
- **Evidence**:
  ```swift
  // HealthAppApp.swift:10
  @StateObject private var appState = AppState()          // touches HealthDataManager.shared / SettingsManager.shared
  @StateObject private var startupHealth = AppStartupHealth.shared   // -> DatabaseManager.shared
  // DatabaseManager.swift:574
  case 12: try db.run("ALTER TABLE documents DROP COLUMN raw_docling_output")
  ```
- **Fix**: Keep first-frame work to "open connection + read version". If `currentVersion < target`, show a "Updating your data…" view and run migrations in a detached task (the connection is not `Sendable`; do it before publishing `DatabaseManager` to the UI, behind a `LaunchGate` state). At minimum, batch the v11 re-encryption and measure on a 300-document fixture.
- **Blast radius**: `DatabaseManager.swift` (tracker hot spot: items 2, 3, 12), `HealthAppApp.swift`, `AppStartupHealth`.
- **Verification**: Build a v11 fixture DB with 300 documents (100 KB text each), launch, record time-to-first-frame with `os_signpost`; expected target < 1 s or a visible progress UI.

### WS-06-13 — `ErrorHandler` history retains retry closures that strongly capture `AIChatManager`; failed sends also raise two alerts
- **Severity**: P3 · **Confidence**: CONFIRMED (retention) / PLAUSIBLE (alert suppression under sheets) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:483-490`, `HealthApp/HealthApp/Managers/ErrorHandler.swift:98-99,252-260`, `HealthApp/HealthApp/Views/ChatDetailView.swift:205-214`
- **Scenario**: `sendMessage` calls `errorHandler.handle(..., retryAction: { Task { await self.retryFailedMessage(...) } })`. `HandledError` keeps `retryAction`, and `ErrorHandler.shared.errorHistory` keeps the last 50 `HandledError`s, so a manager whose send ever failed is pinned (with all its conversations, its `NWPathMonitor` and Combine subscription, whose `deinit` never runs) for up to 50 subsequent errors. **Leak rate**: at most one `AIChatManager` per *failed send on a manager that has since been replaced*. On iPhone there is a single `ChatView` for the process lifetime, so the effective leak is ~0; on iPad it grows with shell rebuilds (WS-06-04), bounded at 50 closures. A "Retry" tapped from the global alert then runs on that orphaned manager, whose reply the visible chat never shows. Separately, the same failure raises the global alert (root-level `withErrorHandling`) and `ChatDetailView`'s own "Failed to send message" alert, so the user dismisses two alerts; an alert attached at the root cannot present while a descendant sheet is up, so errors raised from sheets wait until the sheet closes (platform behaviour, unverified at runtime).
- **Evidence**:
  ```swift
  errorHandler.handle(error, context: "Send Message",
      retryAction: { Task { await self.retryFailedMessage(userMessage, conversationId: conversation.id) } })
  // ErrorHandler.swift:254
  errorHistory.append(handledError)       // keeps retryAction alive
  ```
- **Fix**: Capture `[weak self]` in retry closures; store only `context/message/timestamp` in `errorHistory` (drop closures once the alert is dismissed); show a failed send in one place.
- **Blast radius**: `ErrorHandler.swift`, `AIChatManager.swift:485`, `HealthDataManager.swift:123` (same pattern; harmless there since that manager is a singleton).
- **Verification**: Test: create a manager in an autorelease scope, trigger a handled error with a retry action, release it, assert `weak` reference is nil.

### WS-06-14 — Vital editing uses a fresh `UUID` item identity per body pass and array indices that can go stale
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified link: `sheet(item:)` re-presents on id change) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/VitalsListView.swift:40-43,58-62`, `HealthApp/HealthApp/ContentView.swift:497-500`, `HealthApp/HealthApp/Views/RecentVitalsSection.swift:28-32`
- **Scenario**: The edit sheet's item is built inside the `Binding` getter as `EditingVitalWrapper(type:index:)` whose `id = UUID()`, so every `VitalsListView` body pass yields an item with a different identity. If `HealthDataManager` publishes while the sheet is open (HealthKit sync completion, another save), SwiftUI sees a new item id and can tear down and re-present the sheet, discarding the in-progress entry in `VitalEntryView`. Independently, edit and delete close over the row's *array index*; `deleteVitalReading` re-reads `personalInfo` after the tap, so a HealthKit merge that inserts or reorders readings between render and tap deletes the wrong reading.
- **Evidence**:
  ```swift
  .sheet(item: Binding(
      get: { editingVital.map { EditingVitalWrapper(type: $0.type, index: $0.index) } },   // new UUID each call
      set: { editingVital = $0.map { ($0.type, $0.index) } }
  ))
  struct EditingVitalWrapper: Identifiable { let id = UUID() ... }
  ```
- **Fix**: Make the item `Identifiable` with a stable id (the reading's `id`, or `"\(type)-\(index)"`), and edit/delete by `VitalReading.id`.
- **Blast radius**: `VitalsListView`, `RecentVitalsSection`, dead copies in `HealthDataView` (`ContentView.swift:283-284,424-446,455-496`, never triggered).
- **Verification**: UI test: open the edit sheet, publish a `HealthDataManager` change, assert the sheet stays; unit-test delete-by-id after an insert at index 0.

### WS-06-15 — Launch pins a 5 s splash that hides nothing; "Reset Disclaimer" swaps the root view immediately
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/HealthAppApp.swift:38-55,61-67`, `HealthApp/HealthApp/Views/SettingsView.swift:995-997`
- **Scenario**: (a) `SplashScreenView` is shown for a fixed 5.0 s (+0.8 s fade) from `onAppear`, on every cold launch. By then the database is open (WS-06-12) and `ContentView` is already built underneath, so the splash gates nothing; users on any device wait 5 s to reach a ready app. (b) Settings → Reset Disclaimer Acceptance calls `AppSettingsManager.resetDisclaimerAcceptance()`, which flips `shouldShowDisclaimer`; `appShell` immediately replaces `ContentView` with `FirstLaunchDisclaimerView` (destroying every tab's state, WS-06-04) while the success alert, shown from the view being torn down, says it applies "on next app launch".
- **Evidence**:
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { withAnimation(.easeInOut(duration: 0.8)) { showSplashScreen = false } }
  // SettingsView.swift:997
  successMessage = "... You will need to accept the disclaimer again on next app launch."
  ```
- **Fix**: Shorten the splash to the real readiness signal (or ~1 s minimum) and make it skippable; for (b) either change the copy or defer the flag until next launch.
- **Blast radius**: `HealthAppApp.swift`, `AppSettingsManager.swift`.
- **Verification**: Measure cold-launch-to-interactive; tap Reset Disclaimer and assert the behaviour matches the message.

---

## Streaming verdict (brief item 5)

For a 500-message conversation there is **no container-level frame-rate cliff** in the current code: `EnhancedMessageListView` uses `ScrollView { LazyVStack { ForEach(visibleMessages) } }` with stable `UUID` ids, `EnhancedMessageBubbleView` is `Equatable` and wrapped in `.equatable()` (only the streaming bubble re-renders), and `AIChatManager.updateStreamingMessage` throttles to ~15 fps (67 ms). Copy-on-write of the shared `messages` array per tick is O(n) pointer copies (sub-0.1 ms at n=500). What remains is the O(reply length) work per tick in WS-06-11, which is quadratic over a reply. Two smaller observations that I measured and **did not** report because they are cheap: `localizedCaseInsensitiveContains` over 5,000 × ~1 KB messages (sidebar search per keystroke) = 18 ms; `RelativeDateTimeFormatter()` allocation per sidebar row ×15 = 0.08 ms; `String.count` on 100 KB = 0.1 ms (the token-estimate "cache" in `UnifiedContextSelectorViewModel` hashes `text.count` anyway, still ~5 ms for 50 documents).

## Leak verdict (brief item 4)

No per-message, per-document or per-launch leak found. Verified clean: both `NotificationCenter` block observers (`DocumentManager`, `HealthDataManager`) are removed by `NotificationObserverBag.deinit`; `assign(to: &$published)` ties subscriptions to the owner; the `.sink` closures use `[weak self]`; `NWPathMonitor` is cancelled in `deinit`; `streamingUpdateTask` is weak-capturing and cancelled; the unstructured `Task { await … }` blocks in views hold their manager only for the duration of the call (stream ≤ 300 s). The one retention is WS-06-13 (≤ 50 closures, one orphaned `AIChatManager` per failed send on a replaced manager). No image or thumbnail cache exists (thumbnails are 200×200 JPEGs read in `body`: ~12 visible rows, negligible), and nothing listens for memory warnings.

## Structural risks (max 5 bullets)
- Long-lived workflow state (import review queue, category queue, streaming placeholder, banners) is owned by views whose parents conditionally rebuild them; the fix pattern is one always-alive owner (`ContentView` or a coordinator) rather than per-finding patches.
- Two `DocumentManager` instances and two review presenters (`DocumentsView` and `DocumentDetailView`) for the same `pendingImportReview` mean every change to that flow must be made in three places.
- Notification-based synchronisation (`medicalDocumentDidChange` posted from one site, `medicalDocumentDidDelete` from one) is the only cross-manager consistency mechanism; most "stale list" bugs here are missing posts.
- `HealthDataView` carries dead code (`showingVitalEntry`, `editingVital`, `deleteVitalReading`, `calculateTotalDocumentsSize`, `findStandardKey` in `ContentView.swift`) that the Definition of Done says to remove; it also hides that `ContentView.swift` mixes five unrelated views.
- Every list reload decrypts and decodes full document and message payloads on the main actor (`fetchDocuments`, `fetchConversations`); it is fine at beta scale and will not be at several hundred documents.

## Dropped (2)
- `DocumentManager.fetchDocuments()`/`HealthDataManager` copies carry full `extractedText`/sections for every document (memory ≈ copies × library size; unmeasured).
- Dead `@State` and helper code in `HealthDataView` (covered under structural risks).

## Out-of-scope observations (not counted, for the triage agent)
- `HealthDataManager.mergeVitalReadings` (`HealthDataManager.swift:~690-720`) claims manual entries are "sacrosanct - never discard" but truncates the merged list to `limit: 7` newest, so manual readings older than the seven newest are dropped on every sync. WS-02 territory.

## Machine-readable summary
```json
[
  {"id":"WS-06-01","title":"Review sheets edge-triggered by a view the segment toggle destroys; import review lost and queue jams","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/HealthTabView.swift:29","HealthApp/HealthApp/ContentView.swift:661","HealthApp/HealthApp/Services/DocumentProcessor.swift:51"],"effort":"M","area":"swiftui-state"},
  {"id":"WS-06-02","title":"Reset Database leaves manager in-memory state; deleted PHI shown and re-saved","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/SettingsView.swift:1011","HealthApp/HealthApp/Database/DatabaseManager.swift:745"],"effort":"M","area":"swiftui-state"},
  {"id":"WS-06-03","title":"ChatView.task reloads conversations on every appearance, orphaning the streaming placeholder and discarding the reply","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/ContentView.swift:1415","HealthApp/HealthApp/Managers/AIChatManager.swift:183","HealthApp/HealthApp/Managers/AIChatManager.swift:772"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-04","title":"Size-class flips and iPad sidebar selection rebuild sections, destroying managers, sheets and drafts","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:18","HealthApp/HealthApp/ContentView.swift:90","HealthApp/HealthApp/ContentView.swift:1383"],"effort":"M","area":"swiftui-state"},
  {"id":"WS-06-05","title":"Frequency/end-date committed in onDisappear; custom supplement and condition saved with default values","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/SupplementEditorView.swift:69","HealthApp/HealthApp/Views/SupplementSelectorView.swift:150","HealthApp/HealthApp/Views/PersonalMedicalHistoryView.swift:70"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-06","title":"DocumentDetailView renders a frozen document snapshot; status, tags, extracted data stale","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentDetailView.swift:6","HealthApp/HealthApp/ContentView.swift:616"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-07","title":"Import flow triggers detail sheet and category sheet in the same transaction on iPhone","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/ContentView.swift:960","HealthApp/HealthApp/ContentView.swift:1014","HealthApp/HealthApp/ContentView.swift:616"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-08","title":"Imaging/checkup Records lists refresh only on pull-to-refresh; detail edits and imports do not propagate","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthDataManager.swift:64","HealthApp/HealthApp/Services/DocumentProcessor.swift:228","HealthApp/HealthApp/ViewModels/MedicalDocumentDetailViewModel.swift:88"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-09","title":"Bedrock model/temperature/max-tokens/enable and streaming toggle bound to state nothing reads","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/AWSBedrockSettingsView.swift:12","HealthApp/HealthApp/Managers/SettingsManager.swift:505","HealthApp/HealthApp/Views/ChatDetailView.swift:727"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-10","title":"Mid-stream failure leaves a truncated assistant message that is unpersisted and replayed as history","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:475","HealthApp/HealthApp/Managers/AIChatManager.swift:700"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-11","title":"Whole-message cleaning in body and on the main actor makes streaming cost grow with reply length (1.1/2.7/8.4 ms at 2/6/20 KB)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:508","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:375","HealthApp/HealthApp/Utils/AIResponseCleaner.swift:99"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-12","title":"Database open and v11/v12 migrations run synchronously on the main thread before the first frame","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:10","HealthApp/HealthApp/Database/DatabaseManager.swift:574","HealthApp/HealthApp/Database/DatabaseManager.swift:587"],"effort":"M","area":"swiftui-state"},
  {"id":"WS-06-13","title":"ErrorHandler history retains retry closures that capture AIChatManager; failed send raises two alerts","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:485","HealthApp/HealthApp/Managers/ErrorHandler.swift:254","HealthApp/HealthApp/Views/ChatDetailView.swift:205"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-14","title":"Vital edit sheet item gets a fresh UUID each body pass; edit/delete use stale array indices","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/VitalsListView.swift:40","HealthApp/HealthApp/ContentView.swift:499","HealthApp/HealthApp/Views/RecentVitalsSection.swift:28"],"effort":"S","area":"swiftui-state"},
  {"id":"WS-06-15","title":"Fixed 5 s splash hides nothing; Reset Disclaimer swaps root immediately contrary to its message","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/HealthAppApp.swift:47","HealthApp/HealthApp/Views/SettingsView.swift:997"],"effort":"S","area":"swiftui-state"}
]
```
