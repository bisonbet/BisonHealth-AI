# WS-08 — Error handling & failure UX

- **Agent / model**: Claude (Sonnet 5.5), code-trace only
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (working tree has uncommitted doc changes only; no Swift diffs)
- **Scope actually covered**: every error type in the app (20 `LocalizedError`/`Error` declarations); all ~217 `catch` sites and ~177 `try?` sites triaged, the ~110 that matter for user-visible behaviour read in context; `ErrorHandler.swift` and its 4 call sites; `ContentView.swift` (health, documents, chat tabs); `HealthAppApp.swift` startup path; `DatabaseUnavailableView`; `DocumentManager`, `DocumentImporter`, `DocumentProcessor` (failure paths only); `AIChatManager` (send, retry, context, connection state); `ChatDetailView`, `ConnectionStatusBanner`, `OfflineIndicatorView`; OpenAI-compatible, Bedrock and MLX client failure paths; `SettingsView` (reset, sync, test-connection alerts), `OpenAICompatibleSettingsView`, `AWSBedrockSettingsView`, `OnDeviceLLMSettingsView`, `StorageUsageView`; `HealthKitManager` + sync path; `DocumentExporter`, `DataExportView`, `LogExporter`; `AppointmentPrepManager` + prep views; every delete/clear/reset affordance.
- **Scope not covered**: nothing was run. Per the batch instruction this agent did **not** build, launch the simulator or touch Xcode. Every conclusion below is **code-trace only**; the findings whose last link needs a runtime (SwiftUI alert presentation, `NWPathMonitor` timing, HealthKit authorization semantics) say so and are marked PLAUSIBLE. Not read: `GeneticTestsSection` internals, `BloodTestImportReviewView` layout, `AWSCredentialsManager` bodies (its `lastError` is rendered in `AWSBedrockSettingsView.swift:252-262`, so it was treated as handled), accessibility of error UI (WS-10), iPad layout of alerts (WS-09).
- **Verdict**: Not beta-ready for failure UX. The app's startup-failure screen, appointment-prep failures, settings validation and document-detail delete are well done, but the two flagship flows — **importing a document** and **chatting** — turn almost every failure into either nothing or a misleading banner, and a failed *load* of documents/prep/health data is indistinguishable from "you have no data".
- **Counts**: P0=0 P1=5 P2=9 P3=1 (dropped: 4, listed at the end)

**Relationship to already-filed items.** Not re-reported: tracker 10 (14 `Task { try await }` sites), 13 (`validationFailed` in `DocumentProcessor`, unreadable-fields write-back), 12 (Reset Database backup promise), 14 (no Stop button), 7 (no cloud indicator), 5/1 (stuck `.processing`, delete resurrection), WS-07-08 (dead export toggles), WS-01-03 (failure notification shows file names), WS-02-08 (one bad chat message hides the list). Where a finding below touches one of them it says "related" and describes a different site or a different user-visible consequence.

**Answer to the P1-4 follow-up** (does Retry re-run the failed operation on every path that offers it). Four contexts feed the global alert:

| Context | Has `retryAction` | Retry button shown | Verified behaviour |
|---|---|---|---|
| "Load Health Data" `HealthDataManager.swift:120-127` | yes, `loadHealthData()` | yes | Re-runs. But see WS-08-06(b): a fast re-failure is deduplicated and the tap does nothing visible. |
| "Send Message" `AIChatManager.swift:482-491` | yes, `retryFailedMessage` | yes | Re-runs (re-resolves the failed message, so the stale-snapshot concern is handled). |
| "Retry Message" `AIChatManager.swift:577` | **no** | only when `error.isRetryable` (URLError) | If it ever displays, Retry is a no-op (P1-4 shape). Latent: URLError is `.warning`, which is queued, not shown (WS-08-06(a)); a drained stale warning would show it. |
| "Load Conversations" `AIChatManager.swift:187` | **no** | no (DB errors are not retryable) | Dismiss only. |

So the original P1-4 fix holds for the two paths that pass an action; the no-action contexts are protected only by accident of severity routing.

---

## Findings

### WS-08-01 — Every document-import failure is invisible: `lastError` is write-only
- **Severity**: P1 · **Confidence**: CONFIRMED (code trace) · **Effort**: M
- **Location**: `ContentView.swift:966-981`, `ContentView.swift:991-999`, `Managers/DocumentManager.swift:185-188` (and :211, :235, :279), `Utils/DocumentImporter.swift:332-336`, `Views/DocumentCameraView.swift:43-46`
- **Scenario**: A tester imports a 60 MB scan (limit is 50 MB, `DocumentImporter.swift:353-356`), an empty PDF, a file in an iCloud folder that has not downloaded, or a photo that fails to encode; or the disk is full. `DocumentImporter` throws a well-written `DocumentImportError` ("File is too large. Maximum file size is 50MB." + recovery text). `DocumentManager` stores it in `lastError` and returns `[]`. **No view in the app reads `DocumentManager.lastError`, `DocumentImporter.lastError`, `DocumentExporter.lastError` or `ConversationExporter.lastError`** (`grep -rn "\.lastError" Views ContentView.swift` finds only chat/AWS/storage state). The picker closure checks `if !importedDocs.isEmpty` and otherwise does nothing: no alert, no toast, the sheet just closes. In a multi-file pick, `importMultipleDocuments` deliberately continues past a failing file, so 4 of 5 PDFs appear and the fifth silently never does. If the system file picker itself reports `.failure` (`handleFileImportResult`), the only action is logging, and the log even says "This error doesn't affect document import functionality". Scanner failure (`didFailWithError`) just dismisses the camera. Net: "Import" is the app's first action and "nothing happened" is the main failure mode.
- **Evidence**:
  ```swift
  // ContentView.swift:966-981
  case .failure(let error):
      AppLog.shared.ui("File import failed with error: \(error)", level: .error)
      ...
      if error.localizedDescription.contains("OSStatusErrorDomain Code=-54") || ... .contains("permission") {
          AppLog.shared.ui("This error doesn't affect document import functionality")
      } else { AppLog.shared.ui("Unexpected file import error that may need attention", level: .error) }
  // DocumentManager.swift:185-187
  } catch { lastError = error; return [] }
  // DocumentImporter.swift:332-335
  } catch { /* Continue with other files even if one fails */ lastError = error }
  ```
- **Fix**: Give `DocumentsView` one `@State importFailure: (title, message)?` fed by (a) `.failure` from the picker, (b) the thrown error from `importDocuments`/`importScannedDocument`/photo paths, and (c) a per-batch summary ("3 of 5 imported. `x.pdf`: File is too large (max 50 MB)."). Render `error.localizedDescription` + `recoverySuggestion` (they already exist). Make `importMultipleDocuments` return `(imported, failures)`.
- **Blast radius**: `DocumentManager` (13 `lastError` writers), `DocumentsView`, `DocumentImporter`. Shares `ContentView.swift` with tracker item 10 — sequence after it.
- **Verification**: UI/unit test importing (i) a 0-byte PDF, (ii) a 51 MB file, (iii) three files with one bad; assert an alert/banner is presented naming the bad file and reason, and that 2 documents still import.

### WS-08-02 — A failed document shows a red "Failed" badge and nothing else; the reason and the recovery advice are never rendered
- **Severity**: P1 · **Confidence**: CONFIRMED (code trace) · **Effort**: S–M
- **Location**: `Services/DocumentProcessor.swift:632-654, 1646-1659`; `Views/DocumentDetailView.swift:270-277`; `Views/DocumentListView.swift:157-190`; `Views/BatchProcessingView.swift:191-194`
- **Scenario**: A scan with no readable text is imported. After 3 attempts `NativeDocumentExtractor` throws `allPagesEmpty` ("No text could be extracted from any page", recovery: "…Re-scan with better lighting and focus, or import a higher-quality copy"). `processDocument` records a `ProcessingError` in `processingErrors` — whose only reader is `BatchProcessingView`, which shows just the **count** ("Recent errors: 1"). The document row and the detail screen show a red `Failed` badge and a `Retry Processing` button. The only place the text is surfaced is a local notification, which iOS does **not** display while the app is in the foreground (no `UNUserNotificationCenterDelegate` exists: `grep -rn willPresent` is empty) and which asks for notification permission at launch (`DocumentProcessor.swift:1624`). The user retries, hits the same failure, and files a beta report that says only "it failed". The retry loop also burns ~14 s of backoff (2+4+8 s) first, during which the row says "Retrying" with no reason.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:643-649  (reason captured, never displayed)
  let processingError = ProcessingError(documentId: ..., documentName: ..., error: error, timestamp: Date())
  processingErrors.append(processingError)
  // DocumentDetailView.swift:270-277
  if document.processingStatus == .failed {
      Button("Retry Processing") { Task { await documentProcessor.addToQueue(document, priority: .high) } }
  ```
- **Fix**: In `DocumentDetailView` (and as a one-line subtitle in the list row), show the last failure's `localizedDescription` + `recoverySuggestion` from `processingErrors` keyed by `documentId`; persist a short, filename-free reason string with the `.failed` status so it survives relaunch. Keep the notification body generic (WS-01-03).
- **Blast radius**: `DocumentProcessor` (shared with tracker items 5, 13), `DocumentDetailView`, `DocumentListView`/`GridView`. Related: tracker 5 (documents stuck in `.processing`) is about the status never leaving; this is about the status that does arrive carrying no reason.
- **Verification**: process a blank-page PDF; assert the detail view contains "No text could be extracted" and the re-scan advice without opening Console or Notification Center; kill and relaunch, assert it persists.

### WS-08-03 — Chat composer is disabled by a stale connection flag, the banner says "Reconnecting to AI server…", and on-device chat is declared unavailable offline
- **Severity**: P1 · **Confidence**: PLAUSIBLE (the "never recomputed" link is traced; the one runtime link is whether a later `NWPath` update lands after conversations load — it does not on a normal launch) · **Effort**: S–M
- **Location**: `Managers/AIChatManager.swift:13, 102-121, 147-175, 401`; `Views/ChatDetailView.swift:106-114, 198-203`; `Views/ConnectionStatusBanner.swift:13-18`; `Views/OfflineIndicatorView.swift:22-30, 72-82`
- **Scenario**: (a) *First open.* `isConnected` is `@Published … = false`. `checkConnection()` is called from exactly two places: the network-status sink, only when `!conversations.isEmpty` (and `NetworkManager.statusPublisher` is a `PassthroughSubject`, so it never replays the launch-time path), and the banner's own Retry. A new tester taps *Start New Conversation*; the composer is disabled and an orange banner reads "Connection Issue — Reconnecting to AI server…" even with a valid provider. Nothing is reconnecting. (b) *No provider configured / model not downloaded.* Same banner; Retry recomputes the same `false`; nothing says "choose a provider in Settings". (c) *Provider changed in Settings.* `AIChatManager` has no observer of `settingsManager` (`grep "settingsManager.\$"` is empty), so a tester who finishes downloading the on-device model and returns to Chat is still locked out until they find Retry. (d) *Airplane mode with the on-device model.* `checkConnection` and `sendMessage` both `guard !isOffline` **before** switching on provider, and `OfflineIndicatorView` tells the user "Not available offline: Send chat messages / Process documents" — both false for on-device (document processing is documented on-device in `DocumentManager.swift:286`). The product's headline privacy mode reads as broken whenever Wi-Fi is off.
- **Evidence**:
  ```swift
  // AIChatManager.swift:13   @Published var isConnected: Bool = false
  // AIChatManager.swift:112-114
  if !self.conversations.isEmpty { await self.checkConnection() }
  // AIChatManager.swift:156-159   offline check precedes the provider switch
  guard !isOffline else { isConnected = false; return }
  // ConnectionStatusBanner.swift:18
  Text(isOffline ? "AI assistant unavailable" : "Reconnecting to AI server...")
  ```
- **Fix**: Compute `isConnected` synchronously from provider config on init and on `settingsManager.$modelPreferences`/key changes; skip the `isOffline` gate for `.onDeviceLLM`; give the banner three honest states ("No AI provider set up — Open Settings", "On-device model not downloaded — Open Settings", "Offline — this provider needs a network"). Fix the capability list in `OfflineIndicatorView` to reflect the active provider.
- **Blast radius**: `AIChatManager` (shared with tracker items 4, 10, 14), `ChatDetailView` (items 6, 7, 10, 14), `OfflineIndicatorView`. Related to tracker 7 (provider indicator) — the same banner slot would carry it.
- **Verification**: unit test that a fresh `AIChatManager` with a configured provider reports `isConnected == true` without `checkConnection()`; test that with `.onDeviceLLM` and `isOffline = true` the composer is enabled; UI check of the three banner strings.

### WS-08-04 — A failed *load* renders as "you have no data" on Documents, Appointment Prep, Health records and Chat — the worst "looks like data loss" case is the Documents tab
- **Severity**: P1 · **Confidence**: CONFIRMED that no failure signal reaches these screens; PLAUSIBLE on how often the trigger fires · **Effort**: M
- **Location**: `ContentView.swift:766-776`; `Managers/DocumentManager.swift:107-113`; `Managers/AppointmentPrepManager.swift:72-78` + `Views/AppointmentPrepView.swift:19-26`; `Managers/HealthDataManager.swift:96-136`; `Views/ChatDetailView.swift:19-23`; `Managers/AIChatManager.swift:15, 179-189`
- **Scenario**: Any thrown error from `fetchDocuments()` (e.g. a `SQLITE_BUSY`, a decryption error remapped to `.decryptionFailed`, see WS-08-12) leaves `documentManager.documents == []`. `documentsPrimaryContent` then renders `DocumentsEmptyStateView` — "import your first document" with Scan/Import buttons — over a database that is full of records. `lastError` is unread (WS-08-01). Appointment Prep is identical: `loadPreps` writes `errorMessage`, the list only reads `preps.isEmpty` and shows the friendly "Prep for Your Appointment" onboarding card. Health records: `HealthDataManager.errorMessage` is unread; sections fall back to their "no data" rows, and the only signal is a one-time global alert titled "Load Health Data" that disappears on Dismiss (and, per WS-08-06(d), may never appear). Chat: `isLoadingConversations` is set but never read (so the welcome screen also flashes during every load), and on launch `currentConversation` is `nil`, so a returning user with 30 conversations lands on "Start New Conversation" every time; if the load failed, that screen is the entire evidence. A beta tester sees an empty app after an update and reports "all my data is gone". Related (not duplicated): WS-02-08 and the generic `fetch<T>` skip-and-return-`[]` are the *database-side* causes; this is the missing *UI-side* disclosure.
- **Evidence**:
  ```swift
  // DocumentManager.swift:107-113
  func loadDocuments() async {
      do { documents = try await databaseManager.fetchDocuments() }
      catch { lastError = error; AppLog.shared.documents("Failed to load documents: \(error)", level: .error) }
  }
  // ContentView.swift:768-769
  if documentManager.documents.isEmpty { DocumentsEmptyStateView(...)
  // AppointmentPrepManager.swift:75-77
  } catch { errorMessage = error.localizedDescription ...  // AppointmentPrepView only reads manager.preps.isEmpty
  ```
- **Fix**: Add a tri-state (`loading / loaded / failed(Error)`) per list manager; when `failed`, render a `ContentUnavailableView` "Couldn't load your documents — your data has not been deleted. [Try Again] [Share diagnostic logs]" instead of the onboarding empty state. Gate `ChatEmptyStateView` on `!isLoadingConversations && conversations.isEmpty`, and auto-select the most recent conversation (or show the list) when `conversations` is non-empty.
- **Blast radius**: `DocumentManager`, `AppointmentPrepManager`, `HealthDataManager`, `AIChatManager`; `ContentView.swift`, `AppointmentPrepView`, `ChatDetailView`.
- **Verification**: unit test with a throwing `DatabaseManager` double → assert managers expose `.failed`; snapshot/UI test that the failed state shows "not been deleted" and not the onboarding card; assert a returning user with existing conversations never sees `ChatEmptyStateView`.

### WS-08-05 — Lab values the user has just reviewed or typed are dropped without a word when `addBloodTest` refuses them
- **Severity**: P1 · **Confidence**: CONFIRMED (code trace) · **Effort**: S
- **Location**: `ContentView.swift:1097-1107` and `Views/DocumentDetailView.swift:560-569` (review sheet); `ContentView.swift:409-415`, `Views/BloodTestEntryView.swift:167-168`, `Managers/HealthDataManager.swift:229-252` (manual entry)
- **Scenario**: (1) *Import review.* The user opens the review sheet, picks candidates (or deselects every group), taps Complete. `handleImportReviewComplete` calls `addBloodTest`; if it throws `validationFailed` (empty selection → "Blood test data is incomplete or invalid"; or "A very similar blood test already exists for this date"), the `catch HealthDataError.validationFailed` logs and moves on, with a comment asserting these are "idempotent re-imports". Any other error is logged too. The sheet closes, `finishPendingImportReview()` advances the queue, the document still reads Completed — and none of the reviewed values exist. (2) *Manual entry.* `BloodTestEntryView` calls `onSave` then `dismiss()` synchronously; the parent runs `Task { try await addBloodTest }`. Entering a second panel on the same day with ≥80 % overlapping test names trips the duplicate rule at `HealthDataManager.swift:246-251`, the sheet closes as if saved, and nothing is stored. This one is deterministic, not a rare DB fault. Related: tracker 10 (discarded `Task` error) and 13 (the automatic-path `validationFailed`); these are the user-confirmed variants, which are worse because the user was explicitly shown a confirm step.
- **Evidence**:
  ```swift
  // ContentView.swift:1101-1107
  } catch HealthDataError.validationFailed(let reason) {
      // Same-document/similar-date duplicates are idempotent re-imports ...
      AppLog.shared.ui("Blood test after review skipped: \(reason)", level: .warning)
  } catch {
      AppLog.shared.ui("Failed to save blood test after review: \(error)", level: .error)
  }
  // ContentView.swift:411-413
  Task { try await healthDataManager.addBloodTest(bloodTest) }
  ```
- **Fix**: Make `onSave` async-throwing and keep the sheet open on failure with an inline message ("A similar lab result for this date already exists — open it or change the date"); for the review path, distinguish "nothing selected" (keep the sheet, explain) from true duplicates (tell the user "already imported" and link to the existing record) and surface everything else.
- **Blast radius**: `ContentView.swift` (tracker 10 sites), `DocumentDetailView`, `BloodTestEntryView`, `HealthDataManager.addBloodTest`.
- **Verification**: tests: (i) review with zero selected groups → sheet remains with message; (ii) add a lab on a day that already has a ≥80 %-similar panel → inline error, sheet stays; (iii) induce a DB throw → error visible.

### WS-08-06 — The global error layer can lose, replace, delay and misdirect errors
- **Severity**: P2 · **Confidence**: CONFIRMED for (a)(b)(c) by code trace; PLAUSIBLE for (d)(e) (SwiftUI presentation behaviour not run) · **Effort**: M
- **Location**: `Managers/ErrorHandler.swift:74-79, 122-125, 134-144, 171-186, 189-205, 287-312`; `ContentView.swift:28`; `Managers/AIChatManager.swift:482-491` vs `Views/ChatDetailView.swift:238-246`; `Managers/AppointmentPrepManager.swift:228`
- **Scenario**: There is exactly one presenter (`ContentView.swift:28`) and four producers. Observed defects:
  (a) **Warnings are never shown.** `.warning` goes to `queueError` and the queue is only drained inside `dismissCurrentError()`. Every `URLError` classifies as `.warning` (`ErrorHandler.swift:234-235`), so a chat send that fails with "Could not connect to the server" produces no global alert at all; it sits in `errorQueue` and pops up later, out of context, the next time *any* unrelated error alert is dismissed (and a queued "Retry Message" entry then offers a Retry that does nothing — the P1-4 shape).
  (b) **Retry can be swallowed.** `isSimilar` suppresses any error with the same context+message created within 5 s of the previous one. Tap Retry on "Load Health Data" within 5 s and it fails fast (non-retryable DB error) → logged "Deduplicated" and no alert: the tap appears to do nothing.
  (c) **A second error replaces the first.** `showError` only queues when the current error is `.critical`; otherwise `currentError` is overwritten in place and the first error's message and `retryAction` vanish (two failing loads at launch).
  (d) **Alert can sit behind a sheet.** The `.alert` hangs off the root `Group`; if an error is raised while any descendant sheet is up, UIKit cannot present the alert over it. `AppointmentPrepManager.buildHealthContext` calls `loadHealthData()` from inside the Prep editor sheet. `showErrorAlert` can then stay `true`, making later `= true` assignments no-ops.
  (e) **One chat failure = two alerts.** `sendMessage` calls `errorHandler.handle(...)` *and* rethrows; `ChatDetailView` also raises its own "Error / Failed to send message" alert. Two `.alert` presenters fire for one failure.
  Dismissal itself is consistent (state is cleared and the queue advances); the loss is on the way in.
- **Evidence**:
  ```swift
  // ErrorHandler.swift:138-140
  case .warning:
      // Queue for display
      queueError(handledError)          // drained only in dismissCurrentError()
  // ErrorHandler.swift:171-180
  if let current = currentError, current.severity == .critical && handledError.severity != .critical { queueError(...); return }
  currentError = handledError           // overwrites an unacknowledged error
  // ErrorHandler.swift:75-78
  return self.context == other.context && self.message == other.message && abs(timestamp delta) < 5.0
  ```
- **Fix**: Show warnings immediately as a non-modal banner (or drop the severity split); queue *every* error while one is on screen; scope dedupe to errors that were never presented, or reset it when the user taps Retry; present from the topmost view (or attach `.withErrorHandling()` where sheets are presented); pick one presenter per failure (global **or** local).
- **Blast radius**: `ErrorHandler`, `AIChatManager`, `HealthDataManager`, `ChatDetailView`.
- **Verification**: unit tests on `ErrorHandler` with a clock: warning with empty queue becomes visible; two `.error`s both reach the user in order; Retry-then-fail-within-1 s still shows an alert. UI test: trigger a load failure with the Prep editor sheet open.

### WS-08-07 — The AI is asked with less data than the user selected, and a reply that fails to save is lost, with no word either way
- **Severity**: P2 · **Confidence**: CONFIRMED (code trace) · **Effort**: S–M
- **Location**: `Managers/AIChatManager.swift:789-791, 863-865, 935-937` (reply save), `:1076-1083` (document context), `:1133-1155` (truncation), `:1263-1270` (`contextTooLarge` never thrown); `Managers/AppointmentPrepManager.swift:247-252`
- **Scenario**: (1) The user ticks Documents in the context selector. `fetchDocumentsForAIContext` throws → `medicalDocuments = []`, a log line, and the request goes out with only labs/personal info. The AI then answers "I don't see any of your imaging reports". Same in Appointment Prep. (2) Large selections are cut at `contextTokenLimit × 4` characters mid-JSON with a notice only the model sees; `AIChatError.contextTooLarge` (with a good message) is never thrown anywhere. The UI never says "only part of your data fit". (3) After a successful stream, `addMessage` for the reply can fail; the `catch` sets `AIChatManager.errorMessage`, which **no view reads**. `finalizeStreamingMessage` is skipped, so the reply stays on screen as an unfinalised bubble and is gone after relaunch.
- **Evidence**:
  ```swift
  // AIChatManager.swift:1080-1083
  } catch { AppLog.shared.ai("[Context] Failed to fetch medical documents: ...", level: .warning); medicalDocuments = [] }
  // AIChatManager.swift:789-791
  } catch { self.errorMessage = "Failed to save message: \(error.localizedDescription)" }
  ```
- **Fix**: Surface a one-line inline notice above the composer ("Couldn't include 3 documents" / "Only part of your selected data fit this model's limit — N items omitted") built from the context builder's own counts; show the reply-save failure as a retryable banner on the bubble.
- **Blast radius**: `AIChatManager` (tracker 4/10/14 hot spot), `ChatContext`, `AppointmentPrepManager`.
- **Verification**: inject a throwing document fetch and assert the notice; over-limit selection test asserts the omission count is shown; stub `addMessage` throw → bubble shows "Not saved".

### WS-08-08 — A mid-stream drop can leave a truncated answer stored (or shown) as if it were complete
- **Severity**: P2 · **Confidence**: PLAUSIBLE (needs a server/proxy that closes cleanly without `[DONE]`, or an on-device stream error after first tokens; neither run) · **Effort**: S
- **Location**: `Services/OpenAICompatibleClient.swift:701-757`; `MLXOnDeviceLLM/MLXOnDeviceClient.swift:388-399`; `Managers/AIChatManager.swift:473-476`
- **Scenario**: Three variants. (a) OpenAI-compatible: the `for try await` loop ends when the connection closes; a missing `[DONE]` and a missing `finish_reason` are not errors; any non-empty text goes to `onComplete` and is persisted as the full answer ("…recommended dose is"). (b) On-device: an error after the first tokens is logged and the partial text is returned as success. (c) A thrown `URLError` after partial output: the catch only removes *empty* assistant placeholders, so the partial text stays on screen next to a red "failed" user message, unsaved, and a Retry then appends a second assistant message. In a health context a half sentence that looks final is worse than an error.
- **Evidence**:
  ```swift
  // MLXOnDeviceClient.swift:394-398
  // If streaming fails partway, still return what we have
  if accumulatedContent.isEmpty { throw MLXOnDeviceError.generationFailed(error.localizedDescription) }
  AppLog.shared.mlx("... Streaming ended with error but got partial content ...", level: .warning)
  // AIChatManager.swift:475
  conversations[index].messages.removeAll { $0.role == .assistant && $0.content.isEmpty }
  ```
- **Fix**: Track whether a terminal marker/`finish_reason` arrived; if not, mark the message `isIncomplete` and render "Response was cut off — Retry"; remove or label non-empty partials in the error path.
- **Blast radius**: both clients, `AIChatManager`, `ChatMessage` model. Overlaps WS-04 on provider streaming correctness; this item is only the disclosure.
- **Verification**: stub a stream that closes after 20 tokens without `[DONE]` → assert the stored message carries an "incomplete" flag and the bubble says so.

### WS-08-09 — Several destructive actions are one tap with no confirmation, and the confirmations that exist don't say what is destroyed
- **Severity**: P2 · **Confidence**: CONFIRMED (code trace) · **Effort**: S
- **Location**: `Views/DocumentListView.swift:121-125`, `Views/DocumentGridView.swift:146-150`; `Views/AppointmentPrepView.swift:92-98`, `Views/AppointmentPrepDetailView.swift:70-75`; `Views/BloodTestsSection.swift:184-188`; `Views/ConversationSidebarView.swift:95-99`; `Views/SettingsView.swift:48-53, 1005-1006`
- **Scenario / assessment**:

| Action | Confirmation | Reversible | Text states what is destroyed? |
|---|---|---|---|
| Delete document — context menu (list/grid) | **none** | no | n/a. Deletes the encrypted file, thumbnail and extracted data; result `Bool` ignored (failure invisible). |
| Delete document — detail view | yes `DocumentDetailView.swift:172-185` | no | "cannot be undone"; **does not say** extracted lab values/ records already imported from it remain (no cascade: `DatabaseManager+Documents.swift:228-237`). |
| Delete appointment prep — swipe | **none**; `swipeActions` default allows full-swipe; `try?` hides failure | no | n/a. Prep holds typed symptoms + hours of generated content. |
| Delete appointment prep — detail | yes, `try?` hides failure, view closes anyway | no | generic. |
| Delete lab result — "Lab Results" list swipe | **none** (the detail screen has one); list row is removed optimistically (`bloodTests.remove(atOffsets:)`) before the async delete, whose error is discarded (tracker 10) → deleted result **reappears after relaunch** | no | n/a |
| Delete conversation — iPad sidebar swipe | **none** (context menu has one, list sheet has one) | no | n/a |
| Clear conversation messages | yes, `ChatDetailView.swift:72-78` | no | accurate |
| Reset Server / All Settings | yes | no | "reset server configurations to defaults" — **doesn't mention it deletes the saved API key** (`SettingsManager.swift:786`) |
| Reset Database | yes | no | filed (tracker 12). Extra defect: `performReset` sets `showingSuccessMessage = true` for **every** case (`SettingsView.swift:1006`), so a blank or stale "Success" alert appears before the wipe finishes, and a failure then raises a second "Validation Error" alert. |
| Erase and Start Over (launch screen) | yes, accurate ("no backup to restore from") | no | good |

- **Fix**: add `confirmationDialog` to the five unguarded paths; set `allowsFullSwipe: false`; make `BloodTestListView` delete only after success; state "Imported lab values stay in Health Data" in the document-delete text and "removes your saved API key" in the settings-reset text; show the reset success alert only from inside the success branch.
- **Blast radius**: view-only except `BloodTestListView`/`HealthDataView` (tracker 10 sites).
- **Verification**: UI tests that each destructive affordance presents a dialog; delete failure keeps the row.

### WS-08-10 — "Share Diagnostic Logs" silently sends an email with no logs when Mail isn't set up, while the body says they're attached
- **Severity**: P2 · **Confidence**: CONFIRMED (code trace) · **Effort**: S
- **Location**: `Utils/LogExporter.swift:22-40, 62-74`; callers `Views/SettingsView.swift:1028-1033`, `HealthAppApp.swift:76-80`, `Views/DatabaseUnavailableView.swift:242-247`
- **Scenario**: This is the only support channel the app offers every other error screen ("share the diagnostic logs"). On a device without a configured Mail account `MFMailComposeViewController.canSendMail()` is false, so `openMailApp` builds a `mailto:` URL whose body is `emailBody(...)` — which says "Diagnostic logs are attached" — and **no attachment** (a `mailto:` cannot carry one). The tester sends it believing the logs went. If writing the temp file fails, or no window/root view controller exists, the function returns with no message; `UIApplication.shared.open` failure (no mail app) is not observed.
- **Evidence**:
  ```swift
  // LogExporter.swift:22-27
  do { try content.write(to: tempURL, ...) } catch { AppLog.shared.error(...); return }
  // :63-73  mailto: fallback reuses emailBody(for:) ("Diagnostic logs are attached ...") with no file
  ```
- **Fix**: Fall back to a `UIActivityViewController` with the log file URL (works for AirDrop/Files/any mail app); change the mailto body when no attachment is possible; show an alert on write failure.
- **Blast radius**: `LogExporter` + 3 callers.
- **Verification**: simulator without a Mail account: tapping Share Logs must present a share sheet containing `BisonHealth-Logs-*.txt`.

### WS-08-11 — Apple Health: denied, revoked and "no data" are indistinguishable, every outcome reads "Successfully synced", and the first prompt fires before the disclaimer
- **Severity**: P2 · **Confidence**: PLAUSIBLE (HealthKit read-authorization semantics unverified on device; the code paths are traced) · **Effort**: S–M
- **Location**: `HealthAppApp.swift:10, 269, 277-307`; `Managers/HealthKitManager.swift:118-133, 181-213, 282-310`; `Views/SettingsView.swift:602-611, 1060-1081`
- **Scenario**: `AppState()` is a `@StateObject` created at app start and calls `syncHealthKitOnLaunch()`, whose `requestAuthorization()` raises the system Health sheet over the splash/disclaimer — before the user has accepted anything or knows why. If they decline, HealthKit never throws for denied *reads*; it returns empty arrays, so `syncFromAppleHealth` completes and Settings shows "Successfully synced data from Apple Health" with 0 readings. The date-of-birth/sex/blood-type readers use `try?` (denied == nil == not set), and per-characteristic failures go to `SyncStatistics.failedDataTypes`, which no view reads. `checkAuthorizationStatus` maps `authorizationStatus(for:)` — which describes *write* sharing, and the app requests none (`toShare: []`) — to `isAuthorized`, so the row can read "Not Authorized" for a user who granted read access but has no samples. There is no instruction anywhere on how to re-enable (Settings › Health › Data Access & Devices), and `requestAuthorization` will not prompt a second time.
- **Evidence**:
  ```swift
  // SettingsView.swift:1065-1070
  try await healthDataManager.syncFromAppleHealth()
  ... successMessage = "Successfully synced data from Apple Health"
  // HealthKitManager.swift:282-283
  guard let dateOfBirth = try? healthStore.dateOfBirthComponents() else { return nil }
  ```
- **Fix**: Defer the launch sync until after disclaimer acceptance; after a sync report what arrived ("0 readings — Health access may be off. Settings › Health › Data Access & Devices › BisonHealth AI"); drive the status label from sync results rather than write-authorization status.
- **Blast radius**: `HealthKitManager`, `HealthDataManager.syncFromAppleHealth`, `SettingsView`, `AppState`.
- **Verification**: simulator: deny all Health types → Sync Now shows the 0-readings guidance; first launch shows the disclaimer before any Health prompt.

### WS-08-12 — Failures are labelled with the wrong cause: Bedrock errors become "Network error", database write failures become "Failed to encrypt data", HTTP failures lose their reason
- **Severity**: P2 · **Confidence**: CONFIRMED for the mapping; PLAUSIBLE for the exact SDK strings · **Effort**: M
- **Location**: `Services/BedrockClient.swift:474-477, 594-596` (and `:1063-1100`); `Database/DatabaseManager+HealthData.swift:63-67`, `Database/DatabaseManager+AppointmentPrep.swift:49-51`, `Database/DatabaseManager+Documents.swift:222-226`; `Services/OpenAICompatibleClient.swift:1228-1241`; `Networking/NetworkError.swift` (never constructed)
- **Scenario**: (1) *Bad Bedrock credentials / model not enabled in the region / throttling:* every SDK error is wrapped as `BedrockError.networkError(error)` → "Network error: <opaque Swift error text>", recovery "Check your internet connection and try again". `invalidCredentials`, `insufficientPermissions`, `rateLimitExceeded` and `modelNotSupported` exist with good copy and are **never produced**. (2) *Disk full / database locked while saving a vital or a prep:* the catch-all maps every SQLite failure to `.encryptionFailed` ("Failed to encrypt data"), and several reads to `.decryptionFailed`; to a tester that reads as key corruption. (3) *OpenAI-compatible 400/404/429:* the response body is deliberately never read (`:693`), so a wrong model name (404), an exceeded context (400) and a rate limit (429) all render "OpenAI-compatible request failed (HTTP 40x) [request ID: …]" with the generic "Check your request and try again". (4) `NetworkError` has excellent copy and recovery for 18 cases, but nothing constructs it, so the user gets raw `URLError` text; and when it is a LAN/Ollama server that went away, `AIChatError.notConnected` / the offline banner say "Check your internet connection".
- **Evidence**:
  ```swift
  // BedrockClient.swift:474-476
  } catch { lastError = error; throw BedrockError.networkError(error) }
  // DatabaseManager+HealthData.swift:65-67
  } catch { AppLog.shared.error("Failed to save health data: ..."); throw DatabaseError.encryptionFailed }
  ```
- **Fix**: classify AWS SDK errors (access denied / throttling / validation / resource-not-found) into the existing `BedrockError` cases; map SQLite `SQLITE_FULL/BUSY` to a storage-specific case; map 400/404/429 to dedicated `OpenAICompatibleError` cases with fixed text ("The server doesn't have the model '…'"; "The conversation is longer than the server's context window"); actually use `NetworkError.from(error:)` at the client boundary.
- **Blast radius**: provider clients (WS-04 overlap), `DatabaseManager+*`, `DatabaseUnavailableView` (uses `.decryptionFailed` to pick its advice).
- **Verification**: unit tests per mapping with a fake `AccessDeniedException`, a `SQLITE_FULL`, and 400/404/429 responses.

### WS-08-13 — Pages that fail extraction are skipped silently and the import is reported as a success
- **Severity**: P2 · **Confidence**: CONFIRMED (code trace) · **Effort**: M
- **Location**: `Services/DocumentProcessor.swift:945-947, 1099-1107, 1130-1133`; `MLXOnDeviceLLM/MLXOnDeviceClient.swift:833-835`; summary banner `ContentView.swift:1138-1148`
- **Scenario**: A 6-page lab report is extracted page by page by the vision model. Pages 3 and 4 fail (cloud timeout, on-device memory pressure): each `catch` logs "continuing", the merged result contains pages 1, 2, 5, 6, and the document completes. The only user-visible output is "Imported 18 lab values" (a count) with an Undo button. Nothing says "2 of 6 pages couldn't be read". A tester concludes the report only had 18 values. In a lab context, the missing page may hold the abnormal result. Related to, but different from, tracker 13 (which concerns `validationFailed` yielding zero data).
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:1130-1133
  } catch {
      AppLog.shared.error("Vision extraction failed for page \(pageImage.pageNumber) — continuing", ...)
      return CloudVisionLabExtraction.Result(candidates: [], ...)
  ```
- **Fix**: count failed pages in the merge result; if > 0 mark the document "Partially processed — pages 3, 4 couldn't be read [Retry these pages]" in the detail view and add it to the import banner.
- **Blast radius**: `DocumentProcessor` (tracker 5/13 hot spot), `MLXOnDeviceClient`, `AutoImportSummary`.
- **Verification**: stub a vision client that fails page 2 of 3; assert summary and badge mention the failed page.

### WS-08-14 — Buttons that do nothing: the document "Share" menu item, and scan/preview failures that just close the screen
- **Severity**: P2 · **Confidence**: CONFIRMED (code trace) · **Effort**: S
- **Location**: `Views/DocumentListView.swift:107-109`, `Views/DocumentGridView.swift:132-134`; `Views/DocumentCameraView.swift:43-46`; `Views/DocumentDetailView.swift:814-816`; `Managers/AppSettingsManager.swift:55-65`
- **Scenario**: (1) Long-press a document → **Share**: the closure body is a comment ("Share functionality would be handled by parent"); the menu closes and nothing happens. (The detail screen's Share works.) (2) Scan Document: if `VNDocumentCameraViewController` reports `didFailWithError` (e.g. camera permission denied), the cover is dismissed with only a log line. (3) Quick Look on a document that fails to decrypt shows an empty preview; the catch only logs. (4) `acceptDisclaimer()` swallows a database write failure, so "I Understand and Accept" does nothing and the user is stuck on the first screen with no message (rare; consequence is an unusable first launch).
- **Evidence**:
  ```swift
  // DocumentListView.swift:107-109
  Button("Share", systemImage: "square.and.arrow.up") {
      // Share functionality would be handled by parent
  }
  ```
- **Fix**: remove the dead menu item or wire it to the same decrypt-to-temp share used in `DocumentDetailView`; add "Camera access is off — enable it in Settings" for scanner failures; show an inline "Couldn't open this file" in Quick Look; alert on disclaimer persistence failure.
- **Blast radius**: four small views plus `AppSettingsManager`.
- **Verification**: UI test that Share from the context menu presents a share sheet; deny camera permission and assert the explanatory alert.

### WS-08-15 — Error-type inventory residue: unreachable error cases, developer-facing copy, and a few misleading titles
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: see inventory below; notably `Views/SettingsView.swift:1111` (title "Validation Error" used for sync, cache, reset and credential failures), `Services/BedrockClient.swift:1100`, `Services/DocumentProcessor.swift:1926-1946`, `Utils/Keychain.swift:171-178`, `Services/NativeDocumentExtractor.swift:123-128`, `Managers/AppSettingsManager.swift:80-82` + `Views/SettingsView.swift:996-997`
- **Scenario / assessment**: Dead cases (never constructed, so their carefully written copy never reaches a user): all of `NetworkError`; `AIChatError.contextTooLarge/.processingFailed/.networkError`; `BedrockError.rateLimitExceeded/.insufficientPermissions/.modelNotSupported/.documentFormatNotSupported`; `HealthKitError.notAuthorized/.readFailed`; `OpenAICompatibleError.authenticationFailed`. Developer-facing text a tester can see: Bedrock recovery "Configure AWS credentials using setCredentials method"; `processingTimeout` recovery "check server performance" (there is no server any more); `launchServicesError` "iOS LaunchServices database error"; Keychain "Failed to store item in keychain: -25300" (raw `OSStatus`). Alerts that carry the wrong title: Apple Health sync failure, Clear Cache failure and Reset Database failure all appear under **"Validation Error"**; "Reset Disclaimer Acceptance" reports success even if the write threw. Filename/path in error text: `NativeExtractionError.fileNotFound(path)`, `.pdfLoadFailed(name)`, `DocumentProcessingError.documentNotFound(fileName)` (reaches the lock screen via the filed WS-01-03; would reach the screen if WS-08-01/02 are fixed by rendering `localizedDescription`, so render a filename-free form). No other PHI was found in any error string that a user can currently see or screenshot; `hostUnreachable(URL)` and `HealthKitError.readFailed(details)` would be the next candidates but are never constructed.
- **Fix**: delete or wire the dead cases; rewrite the five developer-facing strings; rename the alert titles ("Couldn't Sync", "Couldn't Clear Cache"); report disclaimer-reset success only on success.
- **Blast radius**: copy-only.
- **Verification**: grep that every `case` of each `LocalizedError` has at least one constructor site (add a small test using `CaseIterable` shims).

---

## Error-type inventory

Legend: **Msg** = user-facing message present; **Plain** = readable by a non-engineer; **Rec** = `recoverySuggestion`; **Leak** = PHI/internal identifier in text; **Reaches user?** = how the text can actually be seen today. Note: `recoverySuggestion` is only rendered by the global `ErrorHandler` alert (4 call sites) and `DatabaseUnavailableView`; every local alert in Chat, Settings, Export and Document views prints `localizedDescription` only, so most recovery copy is never shown.

| Type (file:line) | Msg | Plain | Rec | Leak | Reaches user? |
|---|---|---|---|---|---|
| `DatabaseError` (`Database/DatabaseManager.swift:1035`) | yes | partly ("Database constraint violation", "Invalid data format") | launch-only (`launchRecoverySuggestion`), none at runtime | `.migrationFailed/.incompatibleVersion(String)` embed raw text incl. SQL identifiers (Details panel) | "Load Health Data" alert; launch screen. Causes are mislabelled (WS-08-12). |
| `FileSystemError` (`Utils/FileSystemManager.swift:653`) | yes | terse | launch-only | `.initializationFailed` embeds underlying error text | launch screen; export alerts |
| `KeychainError` (`Utils/Keychain.swift:166`) | yes | no (`OSStatus` number) | no | none | mostly masked by `SettingsManager`/AWS wrappers |
| `AWSCredentialsError` (`Services/AWSCredentialsHelper.swift:163`) | yes | yes | yes | none | `AWSBedrockSettingsView.swift:252-262` — good |
| `NetworkError` (`Networking/NetworkError.swift:5`) | yes, best in app | yes | yes, every case | `.hostUnreachable(url)` would print the URL | **never constructed** — dead |
| `OpenAICompatibleEndpointValidationError` (`OpenAICompatibleClient.swift:6`) | yes | yes | in text | none | inline in settings — good |
| `OpenAICompatibleError` (`:1162`) | yes | yes; HTTP failures lack cause | generic | server request ID appended (harmless) | chat alert (no rec), settings test; `.authenticationFailed` never thrown |
| `BedrockError` (`Services/BedrockClient.swift:1063`) | yes | yes | one is developer text ("setCredentials method") | `.modelNotSupported(model)` | 4 of 9 cases never constructed; all real failures arrive as `.networkError` |
| `AIChatError` (`Managers/AIChatManager.swift:1263`) | yes | yes | yes | none | 3 of 7 cases never constructed; `.notConnected` says "internet" |
| `MLXOnDeviceError` (`MLXOnDeviceLLM/MLXOnDeviceResponse.swift:43`) | yes | yes, actionable ("Go to Settings > On-Device AI…") | yes | `.modelLoadFailed/.generationFailed(reason)` embed raw MLX text | chat alert; download manager |
| `MLXDownloadTransferError` (`MLXModelDownloadManager.swift:49`) | yes | engineer-ish ("HTTP 404 for model-00001-of-00003.safetensors", byte counts) | no | HF file names | "Download Error" section (`OnDeviceLLMSettingsView.swift:241-251`) |
| `HealthKitError` (`Managers/HealthKitManager.swift:718`) | yes | yes | none | `.readFailed(details)` | `.notAuthorized/.readFailed` never constructed |
| `HealthDataError` (`Managers/HealthDataManager.swift:801`) | yes | prefix style ("Validation failed: …") | none | free-text string | **discarded** at nearly every call site (WS-08-05, tracker 10) |
| `DocumentImportError` (`Utils/DocumentImporter.swift:556`) | yes | yes | yes, every case | none | **never displayed** (WS-08-01); `.networkError` says "internet" for a local import |
| `DocumentProcessingError` (`Services/DocumentProcessor.swift:1911`) | yes | partly (LaunchServices, "server performance") | yes | `.documentNotFound(fileName)` | **never displayed in-app** (WS-08-02); filename appears on lock screen (WS-01-03) |
| `NativeExtractionError` (`Services/NativeDocumentExtractor.swift:112`) | yes | yes | yes, good | `fileNotFound(path)`, `pdfLoadFailed(name)` | wrapped into `nativeExtractionFailed(String)`; not displayed |
| `DocumentExportError` (`Utils/DocumentExporter.swift:353`) / `ConversationExportError` (`ConversationExporter.swift:684`) | yes | yes | none | none | export alerts — fine |
| `UnifiedContextSelectorView.ValidationError` (`:1108`) | yes | yes | in text | none | alert — fine |
| `HandledError` wrapper (`ErrorHandler.swift:29`) | title = internal `context` string ("Load Health Data", "Send Message") | action-style titles, acceptable | shown | n/a | global alert |
| Raw `URLError`/Cocoa/SQLite/AWS errors | system text | mostly | none | URL in some | chat local alert, settings "Error: …" |

---

## Flow × failure matrix (all cells code-trace only; nothing was run)

| Flow | Failure | What the user sees | Evidence | Rating |
|---|---|---|---|---|
| **First launch** | Database fails to open | Full-screen "Your Health Data Didn't Open" + recovery card + selectable details + Share Logs / Copy / Erase (erase only where sensible). The static card "Your data is intact" is shown even for `.decryptionFailed`, contradicting the recovery text that says the records "cannot be read". | `HealthAppApp.swift:33-34`; `DatabaseUnavailableView.swift:57-102, 156-181` | Good (P3 wording nit) |
| | Secure file storage fails | Same screen, "Secure File Storage Didn't Open" | `DatabaseUnavailableView.swift:23-29` | Good |
| | Migration fails | Same screen with `launchRecoverySuggestion` ("…along with a copy taken before the upgrade started…"); erase confirmation says "no backup to restore from". Contradiction and unrestorable backup are filed (WS-02-07). | `DatabaseManager.swift:1081`; `DatabaseUnavailableView.swift:86-93` | Good UX, filed data issue |
| | Disclaimer "declined" | There is no decline control; only "I Understand and Accept". If persisting acceptance throws, tapping does nothing | `FirstLaunchDisclaimerView.swift:85-99`; `AppSettingsManager.swift:63-65` | Silent (WS-08-14) |
| | Health permission sheet | Fires at app start from `AppState.init`, before/behind the disclaimer | `HealthAppApp.swift:10, 269, 277-296` | Poor (WS-08-11) |
| **Add blood test by hand** | Required field empty | Inline red text; Save disabled | `BloodTestEntryView.swift:206-236, 170` | Good |
| | Implausible value | Not checked: any text ≤ 20 characters is accepted ("abc", "-5") | `BloodTestEntryView.swift:431-442` | Gap (P3, not filed) |
| | Future date / > 10 y old | Inline error | `BloodTestEntryView.swift:191-204` | Good |
| | Duplicate date / ≥ 80 % similar panel | Sheet closes as if saved; nothing stored; no message | `BloodTestEntryView.swift:167-168`; `ContentView.swift:411-413`; `HealthDataManager.swift:246-251` | Silent (WS-08-05) |
| | DB write fails | Same silent drop | tracker 10 | Silent (filed) |
| **Import a document** | Unsupported type | Picker allows only PDF + images, so mostly prevented; if the importer rejects, nothing shown | `ContentView.swift:588-594`; `DocumentImporter.swift:75-78` | Silent (WS-08-01) |
| | Unreadable / access denied file | Picker `.failure` logged only; importer error stored in unread `lastError` | `ContentView.swift:966-981` | Silent (WS-08-01) |
| | Too large / empty file | `DocumentImportError` created, never shown; in a batch the file is skipped | `DocumentImporter.swift:332-336, 353-360` | Silent (WS-08-01) |
| | Out of disk | `DocumentImportError.storageError` set in `lastError`; nothing shown | `DocumentImporter.swift:119` | Silent (WS-08-01) |
| | Extraction finds nothing | Document ends **Failed** (3 retries, ~14 s): red badge + Retry only, no reason | `DocumentProcessor.swift:735-738, 632-654`; `DocumentDetailView.swift:270-277` | Poor (WS-08-02) |
| | Some pages fail | Imports the rest; banner shows value count only | `DocumentProcessor.swift:1099-1107, 1130-1133` | Silent (WS-08-13) |
| | Scan cancelled / camera fails | Cover closes; failure only logged | `DocumentCameraView.swift:39-46` | Silent (WS-08-14) |
| **Chat** | No provider configured | Composer disabled; orange banner "Connection Issue / Reconnecting to AI server…" | `ChatDetailView.swift:106-114, 198-203`; `ConnectionStatusBanner.swift:13-18` | Misleading (WS-08-03) |
| | Bad credentials | OpenAI-compat 401: local alert "Error — Failed to send message: OpenAI-compatible request failed (HTTP 401) [request ID …]" (recovery text only appears in the global alert path). Bedrock: "Network error: …", "Check your internet connection" | `ChatDetailView.swift:243-244`; `BedrockClient.swift:474-476` | Poor (WS-08-12) |
| | Endpoint unreachable | URLError → global handler classifies `.warning` → queued, never shown; local alert shows the raw OS text ("Could not connect to the server.") and the user message is marked failed with a Retry chip | `ErrorHandler.swift:234-235, 138-140`; `ChatDetailView.swift:559-563` | Acceptable, with a stale queued alert (WS-08-06) |
| | Model not downloaded | Composer disabled, same "Reconnecting…" banner; if forced, `MLXOnDeviceError.modelNotDownloaded` is clear | `AIChatManager.swift:173`; `MLXOnDeviceResponse.swift:58` | Misleading banner (WS-08-03) |
| | Context too large | Silently truncated for the model; HTTP 400 from a server shows only "HTTP 400" | `AIChatManager.swift:1133-1155`; `OpenAICompatibleClient.swift:693` | Silent (WS-08-07/12) |
| | Mid-stream drop | Partial text stays or is saved as complete; alert says "Failed to send message" | `OpenAICompatibleClient.swift:701-757`; `AIChatManager.swift:473-476` | Poor (WS-08-08) |
| | Offline with on-device model | Composer disabled; global banner claims chat/doc processing unavailable | `AIChatManager.swift:156-159, 401`; `OfflineIndicatorView.swift:72-82` | Wrong (WS-08-03) |
| **On-device model** | Insufficient memory | No pre-flight check anywhere (only the 27B model is gated, by installed RAM, in `MLXModelInfo`); a load that exhausts memory ends in a jetsam kill, not an error | `MLXModelDownloadManager.swift:140-148` | Gap (WS-12 owns) |
| | Insufficient disk | No free-space pre-check (grep for `availableCapacity` finds nothing); failure after GBs surfaces as the raw Cocoa string in "Download Error" | `MLXModelDownloadManager.swift:297`; `OnDeviceLLMSettingsView.swift:241-251` | Poor |
| | Download interrupted | Auto-retries, then "Download stalled. Check your network connection and tap Download to retry." | `MLXModelDownloadManager.swift:851` | Good |
| | Corrupt/incomplete download | `modelDownloadIncomplete`: "…did not finish all required files. Please try the download again."; partial files cleaned up | `MLXOnDeviceResponse.swift:58-60`; `MLXModelDownloadManager.swift:287-288` | Good |
| **HealthKit** | Permission denied / revoked | Reads return empty; "Successfully synced"; row may read "Not Authorized"; no re-enable instructions | `SettingsView.swift:1065-1070, 602-611` | Misleading (WS-08-11) |
| | No data available | Same "Successfully synced" | `HealthKitManager.swift:262-266` | Misleading (WS-08-11) |
| **Export / share** | No data to export | PDF: alert "No data available to export" (no recovery). JSON: succeeds with empty arrays | `DocumentExporter.swift:160` (PDF only; the JSON path has no guard) | Acceptable |
| | Write fails | Alert "Export Error — Failed to create export file" | `DataExportView.swift:122-127` | Acceptable |
| | User cancels share sheet | Nothing; file stays in Documents (filed WS-07-07) | `DataExportView.swift:118-121` | Neutral |
| | Document share from list/grid | Menu item does nothing | `DocumentListView.swift:107-109` | Dead (WS-08-14) |
| **Appointment prep** | No health data yet | Generates from an empty context; no warning that the AI has nothing | `AppointmentPrepManager.swift:221-262` | Gap (P3) |
| | Generation fails mid-way | Inline red "xmark.octagon" message in the editor — good; but partial output is saved as `.complete` (missing the medical-disclaimer suffix that step 3 adds) | `AppointmentPrepView`-editor `:176-181`; `AppointmentPrepManager.swift:195-209` | Mostly good (dropped item) |
| | List fails to load | Onboarding empty state | `AppointmentPrepView.swift:19-26` | Looks like data loss (WS-08-04) |
| **Settings** | Invalid endpoint URL | Inline message + failed badge | `OpenAICompatibleSettingsView.swift:279-287` | Good |
| | Credential test fails | OpenAI: "Error: <text>"; Bedrock: "❌ Connection failed: <SDK text>" | `OpenAICompatibleSettingsView.swift:335-341`; `AWSBedrockSettingsView.swift:491-495` | Acceptable |
| | Switch provider mid-stream | No guard; old stream finishes on the old client; connection flag stale (WS-08-03) | `AIChatManager.swift` (no settings observer) | Gap |
| | Sync/cache/reset failures | Shown under the title "Validation Error" | `SettingsView.swift:1111` | Misleading title (WS-08-15) |

---

## Silent-catch inventory (excluding filed items)

User action → site → what the user sees. "Detail" cites the finding that treats it; entries marked (log) are log-only.

| # | User action | Site | Effect |
|---|---|---|---|
| SC-01 | Import File (picker error) | `ContentView.swift:966-981` | nothing (WS-08-01) |
| SC-02 | Import Photos | `ContentView.swift:991-999` (`try?` + catch) | failed photos vanish (01) |
| SC-03 | Import several files | `DocumentImporter.swift:332-336` | bad files skipped (01) |
| SC-04 | Import / scan / photo-library import | `DocumentManager.swift:186, 211, 235, 279` | `lastError` unread (01) |
| SC-05 | Scan Document | `Views/DocumentCameraView.swift:43-46` | cover closes (14) |
| SC-06 | Open Documents tab | `DocumentManager.swift:107-113` | empty state (04) |
| SC-07 | Choose category after import | `DocumentManager.swift:255` | document never queued, stays Pending, no message |
| SC-08 | Edit tags/notes on a document | `DocumentManager.swift:333` | edit not saved, no message |
| SC-09 | Delete document from list/grid menu | `DocumentListView.swift:121-125`, `DocumentGridView.swift:146-150` (result `Bool` ignored; `DocumentManager.swift:400`) | row stays or reappears, no message (09) |
| SC-10 | Process a multi-page document | `DocumentProcessor.swift:1099-1107, 1130-1133`; `MLXOnDeviceClient.swift:833-835` | partial import (13) |
| SC-11 | Process a lab report | `DocumentProcessor.swift:819-822, 945-947, 1245-1250` | falls back to lower-quality extraction silently |
| SC-12 | Process any document | `DocumentProcessor.swift:525-527` | fallback record fails to save, flow continues |
| SC-13 | Finish genetic-report review | `DocumentProcessor.swift:235-237, 249` (`_ = await save…`) | reviewed decisions not saved; sheet closes |
| SC-14 | Queue / relaunch processing | `DocumentProcessor.swift:157-159, 1696-1698` | status stays stale; pending docs not reloaded |
| SC-15 | Quick Look a document | `DocumentDetailView.swift:814-816` | blank preview (14) |
| SC-16 | Complete lab import review | `ContentView.swift:1101-1107`; `DocumentDetailView.swift:563-569` | values dropped (05) |
| SC-17 | Undo auto-import | `ContentView.swift:1189-1191` | banner dismissed as if undone; values remain |
| SC-18 | Delete a vital reading | `ContentView.swift:491-493`; `VitalsListView.swift:94-96` | reading stays, no message (related to tracker 10 but a `catch`, not a `Task`) |
| SC-19 | Receive a chat reply | `AIChatManager.swift:789-791, 863-865, 935-937` | reply not saved; `errorMessage` unread (07) |
| SC-20 | Chat / Prep with documents | `AIChatManager.swift:1080-1083`; `AppointmentPrepManager.swift:250-252` | context silently shrinks (07) |
| SC-21 | Chat reply cut mid-way | `MLXOnDeviceClient.swift:394-399`; `OpenAICompatibleClient.swift:701-757` | truncated reply kept (08) |
| SC-22 | Open Appointment Prep | `AppointmentPrepManager.swift:75-77` | empty state (04) |
| SC-23 | Delete / edit an appointment prep | `AppointmentPrepView.swift:94`; `AppointmentPrepDetailView.swift:73, 145` (`try?`) | not deleted/saved, view closes anyway |
| SC-24 | Partial prep after failure | `AppointmentPrepManager.swift:205-207` (log) | partial prep not persisted, message already shown |
| SC-25 | Open Health records | `HealthDataManager.swift:117-135` (`errorMessage` unread; only the global alert) | empty sections (04) |
| SC-26 | Accept disclaimer | `AppSettingsManager.swift:63-65` | button does nothing (14) |
| SC-27 | Reset Disclaimer Acceptance | `AppSettingsManager.swift:80-82` + `SettingsView.swift:996-997` | "has been reset" shown regardless |
| SC-28 | Launch / Sync Now (Health) | `HealthAppApp.swift:300-306`; `HealthKitManager.swift:181-213, 282-310` | silent; failed types unread (11) |
| SC-29 | Share Diagnostic Logs | `LogExporter.swift:22-27, 72-73`; `SettingsView.swift:1028-1033`; `DatabaseUnavailableView.swift:242-247` | nothing / no attachment (10) |
| SC-30 | Change AI provider/model prefs | `SettingsManager.swift:322` (`_ = try? keychain.store`), `:252-267` (`try?` decode falls back to defaults) | settings revert to defaults after relaunch, no message |
| SC-31 | Preload on-device model on resume | `SettingsManager.swift:638-640` (log) | first message pays the load, failure surfaces late |

**31 distinct sites beyond the filed items** (SC-01…SC-31). Of the ~217 `catch` sites in the app, ~95 rethrow or surface correctly (`DatabaseManager*`, export alerts, settings alerts, `ChatDetailView` send/clear/rename), ~60 are intentional log-only on non-user flows (title generation, thumbnails, OSLog, cleanup), and the rest are above or already filed.

---

## Empty state versus error state (item 6)

| Screen | Empty-state view | Does a *failure* render differently? |
|---|---|---|
| Documents (`DocumentsEmptyStateView`) | `documents.isEmpty` | No. `lastError` unread. **Worst case.** |
| Chat (`ChatEmptyStateView`) | `currentConversation == nil` | No. Also shown for a returning user with existing chats; `isLoadingConversations` unread. |
| Health records (`EmptyBloodTestsView`, "No vitals data yet") | list/array empty | One-time global alert only; `errorMessage` unread. Plus DB-layer skip-and-return-`[]` (filed WS-02-02/08). |
| Appointment Prep | `preps.isEmpty` | No. |
| Genetic / imaging / visits sections | arrays empty | No. |

## Global error presentation layer (item 5), direct answers

- *Is there one?* Yes: `ErrorHandler.shared` + `.withErrorHandling()` once at `ContentView.swift:28`, used by only 4 producers. Every other flow rolls its own `@State` alert, with inconsistent titles.
- *Can an error be lost?* **Yes** — warnings never display, a second error overwrites the first, a fast re-failure after Retry is deduplicated away, and an alert raised under a presented sheet may not appear (WS-08-06).
- *Retry re-runs the failed operation?* On the two paths that pass an action, yes; on the two that don't, no (table at top).
- *Alert vs sheet?* PLAUSIBLE lost-alert case via `AppointmentPrepManager.swift:228`; other producers fire from tab content.
- *Dismiss leaves a consistent state?* Yes, `currentError`/`showErrorAlert` are reset and the queue advances.

## Structural risks

- Two parallel error-reporting systems (global `ErrorHandler` and per-view `@State` alerts) with different severities, titles and recovery handling; the cheapest fix is a single `FailureBanner`/alert model that every manager publishes into.
- Managers expose `lastError`/`errorMessage` as `@Published` properties that nothing observes (12 such properties); a lint check "published error property has no reader" would have caught most of this workstream.
- Rich, well-written error enums are defined but disconnected from the clients that should throw them (`NetworkError`, `BedrockError`, `AIChatError`, `HealthKitError`).
- Failure state is not modelled in the list managers (loading / loaded / failed), so every screen defaults to "empty".
- Local-first/offline claims in UI copy (`OfflineIndicatorView`, `AIChatError.notConnected`, `DocumentImportError.networkError`) predate the on-device provider and now misstate what works offline.

## Dropped (4, below the cap)

1. Appointment prep generation failing in step 2/3 saves the partial prep as `.complete` without the medical-disclaimer suffix (`AppointmentPrepManager.swift:195-209`) — P2.
2. Genetic-report review save failure is discarded (`DocumentProcessor.swift:249`) — listed as SC-13 only.
3. Settings "Reset … " text does not mention API-key deletion — folded into WS-08-09.
4. No plausibility check on manually entered lab values (accepts any text ≤ 20 chars) — P3, not an error-handling defect.

## Machine-readable summary
```json
[
  {"id":"WS-08-01","title":"Every document-import failure is invisible: lastError is write-only","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:966","HealthApp/HealthApp/ContentView.swift:991","HealthApp/HealthApp/Managers/DocumentManager.swift:186","HealthApp/HealthApp/Utils/DocumentImporter.swift:332","HealthApp/HealthApp/Views/DocumentCameraView.swift:43"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-02","title":"Failed document shows only a Failed badge; reason and recovery advice never rendered","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:643","HealthApp/HealthApp/Services/DocumentProcessor.swift:1646","HealthApp/HealthApp/Views/DocumentDetailView.swift:270","HealthApp/HealthApp/Views/BatchProcessingView.swift:191"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-03","title":"Chat composer disabled by stale isConnected; banner says Reconnecting; on-device chat declared unavailable offline","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:13","HealthApp/HealthApp/Managers/AIChatManager.swift:112","HealthApp/HealthApp/Managers/AIChatManager.swift:156","HealthApp/HealthApp/Views/ChatDetailView.swift:106","HealthApp/HealthApp/Views/ConnectionStatusBanner.swift:18","HealthApp/HealthApp/Views/OfflineIndicatorView.swift:72"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-04","title":"Failed loads render as 'no data' on Documents, Prep, Health records and Chat","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:768","HealthApp/HealthApp/Managers/DocumentManager.swift:107","HealthApp/HealthApp/Managers/AppointmentPrepManager.swift:75","HealthApp/HealthApp/Views/AppointmentPrepView.swift:19","HealthApp/HealthApp/Managers/HealthDataManager.swift:117","HealthApp/HealthApp/Views/ChatDetailView.swift:19"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-05","title":"User-confirmed lab values dropped silently when addBloodTest refuses them (review sheet and manual entry)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:1101","HealthApp/HealthApp/Views/DocumentDetailView.swift:563","HealthApp/HealthApp/ContentView.swift:411","HealthApp/HealthApp/Views/BloodTestEntryView.swift:167","HealthApp/HealthApp/Managers/HealthDataManager.swift:246"],"effort":"S","area":"error-ux"},
  {"id":"WS-08-06","title":"Global error layer can lose, replace, delay and misdirect errors","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/ErrorHandler.swift:74","HealthApp/HealthApp/Managers/ErrorHandler.swift:138","HealthApp/HealthApp/Managers/ErrorHandler.swift:171","HealthApp/HealthApp/Managers/AIChatManager.swift:482","HealthApp/HealthApp/Views/ChatDetailView.swift:238","HealthApp/HealthApp/Managers/AppointmentPrepManager.swift:228"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-07","title":"AI asked with less data than selected and unsaved replies lost silently (errorMessage unread, contextTooLarge never thrown)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:789","HealthApp/HealthApp/Managers/AIChatManager.swift:1080","HealthApp/HealthApp/Managers/AIChatManager.swift:1133","HealthApp/HealthApp/Managers/AppointmentPrepManager.swift:250"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-08","title":"Mid-stream drop can leave a truncated answer stored or shown as complete","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Services/OpenAICompatibleClient.swift:701","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:394","HealthApp/HealthApp/Managers/AIChatManager.swift:475"],"effort":"S","area":"error-ux"},
  {"id":"WS-08-09","title":"Destructive actions without confirmation; confirmations do not state what is destroyed","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentListView.swift:121","HealthApp/HealthApp/Views/DocumentGridView.swift:146","HealthApp/HealthApp/Views/AppointmentPrepView.swift:92","HealthApp/HealthApp/Views/BloodTestsSection.swift:184","HealthApp/HealthApp/Views/ConversationSidebarView.swift:95","HealthApp/HealthApp/Views/SettingsView.swift:1006"],"effort":"S","area":"error-ux"},
  {"id":"WS-08-10","title":"Share Diagnostic Logs sends an email without logs when Mail is not configured while claiming they are attached","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/LogExporter.swift:22","HealthApp/HealthApp/Utils/LogExporter.swift:63","HealthApp/HealthApp/Views/SettingsView.swift:1028"],"effort":"S","area":"error-ux"},
  {"id":"WS-08-11","title":"Apple Health denied/revoked/no-data indistinguishable; always 'Successfully synced'; prompt fires before disclaimer","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:277","HealthApp/HealthApp/Managers/HealthKitManager.swift:118","HealthApp/HealthApp/Views/SettingsView.swift:1060"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-12","title":"Failures labelled with the wrong cause: Bedrock as Network error, DB writes as Failed to encrypt, HTTP failures lose reason","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/BedrockClient.swift:474","HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:65","HealthApp/HealthApp/Database/DatabaseManager+AppointmentPrep.swift:49","HealthApp/HealthApp/Services/OpenAICompatibleClient.swift:693"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-13","title":"Pages that fail extraction are skipped silently and the import is reported as success","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:1099","HealthApp/HealthApp/Services/DocumentProcessor.swift:1130","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:833"],"effort":"M","area":"error-ux"},
  {"id":"WS-08-14","title":"Dead Share menu item and scan/preview/disclaimer failures that silently close the screen","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentListView.swift:107","HealthApp/HealthApp/Views/DocumentGridView.swift:132","HealthApp/HealthApp/Views/DocumentCameraView.swift:43","HealthApp/HealthApp/Views/DocumentDetailView.swift:814","HealthApp/HealthApp/Managers/AppSettingsManager.swift:63"],"effort":"S","area":"error-ux"},
  {"id":"WS-08-15","title":"Error-type inventory residue: dead error cases, developer-facing copy, misleading alert titles","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/SettingsView.swift:1111","HealthApp/HealthApp/Services/BedrockClient.swift:1100","HealthApp/HealthApp/Services/DocumentProcessor.swift:1926","HealthApp/HealthApp/Utils/Keychain.swift:171"],"effort":"S","area":"error-ux"}
]
```
