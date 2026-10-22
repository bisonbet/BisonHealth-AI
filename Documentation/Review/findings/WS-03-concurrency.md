# WS-03 — Swift 6 concurrency & actor isolation

- **Agent / model**: WS-03 reviewer subagent (Sonnet 5.5), read-only; no xcodebuild run (per orchestrator constraint)
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (working tree has only uncommitted docs edits under `Documentation/Review/`)
- **Scope actually covered**: every `@unchecked Sendable`, `DispatchQueue`, `withChecked*Continuation`, `NSLock`, `nonisolated`, `@preconcurrency` site in `HealthApp/HealthApp` (grep-complete, each site read in context); full read of `AppLog.swift` (queue discipline), `MLXOnDeviceClient.swift` (gate, residency, streaming, vision loop), `MLXModelDownloadManager.swift` (task/cancel lifecycle, progress box), `AIChatManager.swift` (send / stream / title / context / retry), `DocumentProcessor.swift` (queue, drain, cancel, retry), `NativeDocumentExtractor.swift` (Vision OCR, page loops), `NetworkRetryManager.swift`, `NetworkManager.swift`, `OpenAICompatibleClient.swift` + `BedrockClient.swift` streaming paths, `DocumentImporter.swift` (PHPicker continuation), `HealthKitManager.swift` (both continuations), `DatabaseManager*.swift` (isolation + the 2 GCD offloads), `FileSystemManager.swift`, `HealthDataManager.swift` (merge/lock), `AppointmentPrepManager.swift`, `HealthAppApp.swift` (scene-phase, startup), and the `Task {}` call sites in `ContentView.swift`, `ChatDetailView.swift`, `VitalsListView.swift`, `PersonalInfoEditorView.swift`. I also ran two throwaway reproductions in the scratchpad (Vision double-callback; `CheckedContinuation` double-resume trap) and two micro-benchmarks (AES-GCM, log redaction).
- **Scope not covered**: all `#if !targetEnvironment(simulator)` MLX paths were read but cannot be exercised on the simulator or in the test suite, so MLX findings are code-trace only; no on-device (iPhone/iPad) run, so no Instruments evidence for hitch sizes; the other ~45 SwiftUI view files were grepped for `Task`/`DispatchQueue` but not read in full; `SettingsManager` and `ConversationExporter`/`DocumentExporter` only skimmed; SQLite connection thread discipline (WS-02) and PHI/logging content (WS-07) deliberately not assessed.
- **Verdict**: The unchecked-Sendable promises are sound and there is no deadlock or hang in the GCD or continuation code, but **not beta-ready until WS-03-01 and WS-03-02 are fixed**: one is a guaranteed process trap whenever Vision reports an error (the very case the surrounding `catch` was written to survive), the other silently drops a user's follow-up question and its answer from the chat UI on the default (streaming) path.
- **Counts**: P0=0 P1=3 P2=3 P3=9 (dropped: 3 — see "Structural risks" and the end of the inventory notes)

## Isolation inventory

### `@unchecked Sendable` — the five the baseline counted are three real declarations

`grep -c '@unchecked Sendable'` returns 5 because two hits are doc-comment mentions (`AppLog.swift:59`, `MedicalDocument.swift:16`). Three types actually carry the promise; all three hold.

| Site | Kind | Guarded by | Verdict |
|---|---|---|---|
| `MLXOnDeviceLLM/MLXModelDownloadManager.swift:1185` `DownloadProgressBox` | `@unchecked Sendable` final class, 3 mutable vars | private `NSLock`; every read and write (`configure`, `update`, `get`) takes it; `get()` returns a value-type `Sendable` snapshot, nothing escapes by reference | **ok** |
| `Managers/AppLog.swift:68` `AppLog` | `@unchecked Sendable` NSObject, `logFileURL` and `previousSessionCrashed` mutable | `logFileURL`: all reads and writes are on `logQueue` (`writeToFile`, `rotateLogsIfNeeded`, `cleanupOldLogs`, `clearAllLogsOnLogQueue` are only reachable from queue blocks; external readers go through `currentLogFileURL()` which `sync`s). `previousSessionCrashed`: written once in `markLaunch()` from `AppState.init` (`@MainActor`), read from `@MainActor` only (`HealthAppApp.swift:263`, `LogExporter.swift:93`). Everything else is `let`. Re-entrant `sync` is guarded with `DispatchSpecificKey` at all 5 sites. | **ok** — traced every access path; the comment's invariants are true today |
| `Models/MedicalDocument.swift:18` `NotificationObserverBag` | `@unchecked Sendable` final class, `var observers` | convention only: `insert` is called from two `@MainActor` initialisers (`DocumentManager.swift:161`, `HealthDataManager.swift:91`); `deinit` runs once after the last reference. `removeObserver` is thread-safe. | **ok**, unenforced — a third caller off the main actor would be a silent race; cheap hardening noted in WS-03-15 |

### `DispatchQueue` — 27 lines, 0 defects in the queue mechanics; 2 lines implicated in a (P3) logic bug

| Site (lines) | Kind | Guarded by / purpose | Verdict |
|---|---|---|---|
| `AppLog.swift:83` | serial queue | the log-file / error-buffer writer; `.sync` only for `.error`/`.critical` so the line is durable if the app dies | ok (blocks caller on I/O, see WS-03-13) |
| `AppLog.swift:276, 452, 720, 771, 854` | `getSpecific` re-entrancy checks | prevent `queue.sync` from the queue itself (self-deadlock) | ok — correctly placed at every `sync` |
| `NetworkManager.swift:21` | `NWPathMonitor` delivery queue | handler hops to `Task { @MainActor }` | ok |
| `AIChatManager.swift:1241` | second `NWPathMonitor` queue (legacy "for compatibility") | same hop | ok but duplicate monitor (WS-03-15) |
| `DatabaseManager+Chat.swift:271`, `DatabaseManager+Documents.swift:304`, `FileSystemManager.swift:564` | `global().async` inside `withChecked(Throwing)Continuation` | off-main scalar queries / directory walk; exactly one `resume` on every path (single `do`/`catch`) | ok (Connection thread-safety → WS-02) |
| `DocumentManager.swift:519, 523, 529` | `.receive(on: DispatchQueue.main)` on Combine pipelines | redundant: publisher source (`DocumentProcessor`) and subscriber (`DocumentManager`) are both `@MainActor`; the hop only delays delivery one run-loop turn | redundant, harmless |
| `HealthAppApp.swift:47, 76`; `ContentView.swift:726`; `ChatDetailView.swift:83, 692` | `main.asyncAfter` fire-and-forget (splash 5 s, share-sheet 0.3 s, focus/sheet re-presentation delays) | none; not cancellable, state written on the main thread only | benign UI timing (the `ContentView.swift:726` one sits inside the blocked Task of WS-03-04) |
| `PersonalInfoEditorView.swift:94, 167, 184, 200, 296, 312` | `main.asyncAfter` focus juggling | none | benign |
| `PersonalInfoEditorView.swift:456, 463` | `main.asyncAfter(execute: DispatchWorkItem)` 0.15 s debounce | `@State` work-item handle, cancel-and-replace | **defect (P3)** — Save does not flush the pending debounce (WS-03-11) |

Tally: 11 legitimate (6 AppLog + 1 + 1 monitor queues + 3 offloads), 14 redundant/benign UI timing, 2 implicated in a real (P3) defect. Zero `.sync` from a concurrent context onto a queue that can call back; zero queue hops inside `async` functions that break cancellation (the three `global().async` hops are inside continuations, not around `await`s).

### Continuations — 9 sites, none can double-resume except the two Vision ones, none can hang

| Site | Resumes | Verdict |
|---|---|---|
| `DatabaseManager+Chat.swift:270`, `DatabaseManager+Documents.swift:303`, `FileSystemManager.swift:563` | once per path (single `do`/`catch` in the GCD block) | ok |
| `HealthKitManager.swift:540, 665` | `HKSampleQuery.resultsHandler` fires once; handler is `NS_SWIFT_SENDABLE` in the iOS 27.1 SDK headers (checked), so no MainActor-isolation trap | ok (query is not stopped on task cancel — benign) |
| `DocumentImporter.swift:426` (PHPicker) | every branch of the callback and the non-image `else` resume exactly once | ok |
| `MLXOnDeviceClient.swift:44` (`MLXGPUGate`) | `release()` resumes one waiter per call; all 7 `acquire` sites pair with `defer { release() }`; the manual pair in `extractFromDocument` has no early exit between them | ok for resume discipline; waiter ignores cancellation (WS-03-08) |
| `NativeDocumentExtractor.swift:463` (`performOCR`) | handler resumes **and** the `catch` around `perform` resumes again | **defect P1 — traps** (WS-03-01) |
| `NativeDocumentExtractor.swift:592` (`perspectiveCorrectedImage`) | same pattern | **defect P1 — traps** (WS-03-01) |

### Other isolation facts

| Item | Finding |
|---|---|
| `Task.detached`, `MainActor.assumeIsolated`, `AsyncStream`, `nonisolated(unsafe)`, `DispatchSemaphore`, `.wait()` | 0 each |
| `nonisolated` (28 grep hits) | 19 in `MLXModelDownloadManager` (pure static constants/helpers), 2 real elsewhere (`NetworkMonitor.stopMonitoring`, `EnhancedMessageBubbleView.==`), 7 are comments. All sound. |
| `NSLock` | `DownloadProgressBox` (needed); `HealthDataManager.swift:43` `syncLock` wraps purely synchronous code inside a `@MainActor` class — redundant, and its "async-safe" comment is misleading (WS-03-15) |
| `@preconcurrency` | `import SQLite` ×4 (the `Connection` Sendable promise lives in the library), conformances on `MailComposeDelegate` and `DocumentCameraView.Coordinator` (UIKit delegates, main-thread delivery) — acceptable |
| Isolation of the data layer | `DatabaseManager`, `FileSystemManager`, `HealthDataManager`, `DocumentProcessor`, `AIChatManager`, every provider client are `@MainActor`. Consequence used throughout this report: **their `async` methods almost never actually suspend** (the only real suspension points in `Database/` are the 2 GCD continuations), so a `Task { try await databaseManager.x() }` is effectively one atomic main-actor slice. Real interleaving only happens across network calls, MLX generation, `Task.sleep`, and Vision/OCR. |

### Answer to the WS-00-01 follow-on question (isolation / ordering / cancellation / lifetime of the 14 unstructured `Task {}` sites)

No additional hazard beyond the discarded error. Each of the 14 sites inherits `@MainActor`, calls a non-suspending DB method, and therefore runs to completion in FIFO order as a single slice; nothing outlives anything it needs, and two of them cannot race on the same record. I specifically checked `AIChatManager.swift:1027-1031` (writes a `ChatConversation` snapshot back into `conversations[index]`): the snapshot is taken in the same turn the Task body runs, so there is no stale-snapshot window there. **The unstructured-Task lifetime/ordering problems that do exist are elsewhere:** the detached title-generation write-back (WS-03-02), the UI continuation that is parked for the whole processing run (WS-03-04), and the chat send Task that is never stored or cancellable (WS-03-05).

## Findings

### WS-03-01 — Vision OCR continuations resume twice on any Vision error → process trap
- **Severity**: P1 · **Confidence**: CONFIRMED (double callback reproduced against the real Vision framework; the trap reproduced with the identical code shape) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:463-511` (`performOCR`) and `:592-610` (`perspectiveCorrectedImage`)
- **Scenario**: `VNImageRequestHandler.perform(_:)` is synchronous and, when the request fails, Vision invokes the request's completion handler **with the error and then also throws from `perform`**. Both paths here call `continuation.resume`. A user imports a scanned PDF or photo; on any page where Vision reports an error (unsupported/oversized image, memory pressure while an MLX model is resident, a corrupt page, `Could not create inference context`-class failures) the first resume is accepted and the second is a fatal `SWIFT TASK CONTINUATION MISUSE … tried to resume its continuation more than once`. `CheckedContinuation` traps in release builds too. The page loop one level up (`:372-376`, `catch { … "Vision OCR failed for page …" … Keep whatever PDFKit got }`) shows the author intended this to be a survivable per-page failure; because a trap is not catchable, the app instead dies in the core import flow. Reproduction I ran (macOS, same Vision framework): invalid `revision` → handler called once with the error **and** `perform` threw; wrapping the same shape in `withCheckedThrowingContinuation` exits with signal 133 and the message above. Script: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/vt/t2.swift`. Trigger frequency on a physical iPhone is not measured; the mechanism is certain.
- **Evidence**:
  ```swift
  // NativeDocumentExtractor.swift:463-467, 506-511
  let ocrResult: OCRResult = try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
          if let error = error {
              continuation.resume(throwing: NativeExtractionError.ocrFailed(error.localizedDescription))
              return
          }
  ...
      do {
          try handler.perform([request])
      } catch {
          continuation.resume(throwing: NativeExtractionError.ocrFailed(error.localizedDescription))
      }
  ```
  ```swift
  // :592-609 — same shape, resumes nil from the handler and again from the catch
  let quad: DocumentQuad? = await withCheckedContinuation { continuation in
      let request = VNDetectDocumentSegmentationRequest { request, error in
          guard error == nil, let observation = … else { continuation.resume(returning: nil); return }
  ...
      do { try handler.perform([request]) } catch { continuation.resume(returning: nil) }
  ```
- **Fix**: `perform` is already synchronous, so drop the continuation: create the request without a completion handler, call `try handler.perform([request])`, then read `request.results` after it returns (throw the mapped error from the `catch`). If a handler is kept, make the resume idempotent (a one-shot flag/box) and let only one of the two paths win. Run the synchronous `perform` off the caller's executor as it is today.
- **Blast radius**: every image/PDF import and every photo-library import goes through `performOCR` (and `preprocessImageForOCR` for photos); `DocumentProcessor.processDocumentOnDevice` and the vision-pass pre-processing. No other code shares the helper.
- **Verification**: add an internal seam so a test can force the request to fail (e.g. inject an unsupported `revision`) and assert `performOCR` throws `NativeExtractionError.ocrFailed` and the page loop continues with PDFKit text, instead of trapping. Re-run the scratch repro against the fixed shape.

### WS-03-02 — Title generation writes a stale conversation snapshot back, dropping the user's follow-up and discarding its reply
- **Severity**: P1 · **Confidence**: CONFIRMED (whole path traced; timing window is the title round-trip, so likelihood depends on provider latency) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:240-253` (`updateConversationTitle`), called via `generateTitleIfNeeded` from the streaming `onComplete` Tasks at `:787`, `:861`, `:933`; input-enable condition `Views/ChatDetailView.swift:199-202`
- **Scenario**: On the default streaming path, the first assistant reply completes → `sendMessage` returns and `isSendingMessage` becomes `false` (the `onComplete` work is a detached `Task { @MainActor }`). That Task then `await`s `generateTitleIfNeeded(for: self.conversations[i])`, capturing a **value copy** of the conversation, and makes a real network/LLM call (1–3 s on Bedrock; seconds to tens of seconds on a LAN OpenAI-compatible server; on-device it also queues behind the MLX gate). The message input is enabled throughout (`isGeneratingTitle` is not part of `isEnabled`). If the user sends a follow-up in that window, `conversations[i]` gains the user message and a streaming placeholder. When the title returns, `updateConversationTitle` does `conversations[index] = updatedConversation` and `currentConversation = updatedConversation` using the **pre-follow-up snapshot**: the follow-up and placeholder vanish from the UI mid-stream. The follow-up's `onComplete` then hits its own guard (`"Discarding streamed reply: conversation cleared mid-stream"`) and the assistant answer is thrown away and never persisted (the DB keeps the user row only). The same overwrite also writes the snapshot's `includedHealthDataTypes` / `includedPersonalInfoCategories` back to the DB row (`updateConversation`), so a privacy opt-out toggled in that window reverts on the next `selectConversation` / relaunch — the P1-5 failure class. The non-streaming path awaits title generation *inside* `sendMessage` (`:999`) so it is not affected, and UI tests run non-streaming (`useStreaming: !AppTestRuntime.isUITesting`), so none of this is covered.
- **Evidence**:
  ```swift
  // AIChatManager.swift:240-252
  func updateConversationTitle(_ conversation: ChatConversation, newTitle: String) async throws {
      var updatedConversation = conversation          // stale snapshot, taken before the title await
      updatedConversation.updateTitle(newTitle)
      try await databaseManager.updateConversation(updatedConversation)   // rewrites privacy columns too
      if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
          conversations[index] = updatedConversation  // drops messages added since the snapshot
      }
      if currentConversation?.id == conversation.id {
          currentConversation = updatedConversation
      }
  }
  // :786-787 (identical at :860 and :932)
  if let conversationIndex = self.conversations.firstIndex(where: { $0.id == conversationId }) {
      await self.generateTitleIfNeeded(for: self.conversations[conversationIndex])
  ```
- **Fix**: apply only the title to the live state: after the awaits, mutate `conversations[index].updateTitle(newTitle)` (and `currentConversation` the same way) rather than assigning the snapshot, and persist a title-only column update instead of `updateConversation(snapshot)`. Optionally also include `isGeneratingTitle` in the input-enabled condition, though the in-place merge is the real fix.
- **Blast radius**: `updateConversationTitle` is also called from the rename UI (`ChatDetailView.swift:835`, no suspension between snapshot and write, safe). Touches `AIChatManager` (also WS-04 / WS-00-01's `:1027` site) and any test that asserts `conversations[i]` identity.
- **Verification**: unit test using the testing AI-client override with a delayed title response: complete exchange 1 (streaming), start exchange 2 while the title call is pending, release the title, assert `conversations[i].messages.count == 4`, reply 2 is persisted, and the persisted `includedPersonalInfoCategories` equals the value toggled during the window.

### WS-03-03 — On-device generation is not stopped when the app backgrounds
- **Severity**: P1 · **Confidence**: PLAUSIBLE (unverified link: that this version of mlx-swift aborts the process when a Metal command buffer is committed after the app loses GPU permission; MLX paths are compiled out of the simulator so I could not run it) · **Effort**: M
- **Location**: `HealthApp/HealthApp/HealthAppApp.swift:331-336`; `Managers/SettingsManager.swift:646-654`; `MLXOnDeviceLLM/MLXOnDeviceClient.swift:596-613`
- **Scenario**: User asks a question with the on-device provider (replies take tens of seconds) and switches to another app. `handleScenePhaseChange(.background)` only schedules `suspendOnDeviceLLMForBackground()`, which *waits for the GPU gate* — the gate is held for the whole reply by `sendStreamingChatMessage`, and nothing cancels that generation. The model keeps submitting Metal work after iOS has revoked background GPU access. On iOS this is rejected ("Insufficient Permission (to submit GPU work from background)") and MLX surfaces it as an uncaught C++ error → crash while backgrounded, with `markCleanShutdown()` already written so the crash is not even flagged on next launch. The same applies to a document-extraction page running on the VLM. `.inactive` is ignored entirely. There is no `beginBackgroundTask` or cancellation anywhere in the repo for this.
- **Evidence**:
  ```swift
  // HealthAppApp.swift:331-336
  case .background:
      AppLog.shared.markCleanShutdown()
      Task {
          await settingsManager.suspendOnDeviceLLMForBackground()
      }
  // MLXOnDeviceClient.swift:605-608 — queues behind the in-flight reply
  #if !targetEnvironment(simulator)
  await MLXGPUGate.shared.acquire()
  defer { MLXGPUGate.shared.release() }
  performUnloadModel()
  ```
- **Fix**: keep a handle to the in-flight send/generation Task (see WS-03-05) and cancel it on `.inactive`/`.background` *before* waiting on the gate; make `collectResponse`/the stream loop exit promptly on cancellation so the gate frees; only then unload. Same for the VLM page loop.
- **Blast radius**: `AIChatManager.sendMessage`, `MLXOnDeviceClient` (chat, vision extraction, title generation), `DocumentProcessor` extraction runs, `SettingsManager` lifecycle hooks.
- **Verification**: on a physical device with an on-device model, start a long reply, press Home, wait 10 s, return: app must not crash and the partial reply must be saved or discarded cleanly. Add a unit test with a fake client asserting `.background` cancels the in-flight send Task.

### WS-03-04 — `addToQueue` awaits the entire queue drain, parking UI continuations for minutes
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:162-168` (`addToQueue` → `await startProcessing()`), `:268-333` (`startProcessing` drains the whole queue); callers `Managers/DocumentManager.swift:252`, `ContentView.swift:715-731`, `Services/DocumentProcessor.swift:1691-1693` (`loadPendingDocuments`)
- **Scenario**: the user imports three lab PDFs; the category sheet appears for the first. On Confirm, the view dismisses itself (`DocumentTypeSelectorView.swift` calls `dismiss()`), but the `Task` in `ContentView` is still suspended inside `setDocumentCategoryAndProcess` → `addToQueue` → `startProcessing`, which does not return until every queued document has finished OCR + extraction (minutes on-device). Only then does the Task run `pendingDocumentForCategory = nil`, `pendingCategoryDocuments.removeAll`, and present the next document's category sheet. Consequences: (a) documents 2 and 3 get no category prompt and are not queued until document 1 finishes; (b) if the user imports another file meanwhile, `handleFileImportResult` sees `pendingDocumentForCategory != nil` and re-opens the sheet for the *already processing* document 1; (c) `loadPendingDocuments` (app launch) adds queued documents strictly serially because its `for … await addToQueue` blocks on the first drain, so the `maxConcurrentProcessing = 3` cloud concurrency is unreachable on that path; (d) a failed document's retry `Task` (`:625-630`) hosts a whole drain loop and cannot clear its `retryTasks` entry until the drain ends, so cancelling that entry cancels the drain host rather than a sleep.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:162-168
  if !isProcessing {
      AppLog.shared.documents("Starting processing queue")
      await startProcessing()          // returns only when the queue is empty
  }
  // ContentView.swift:715-721
  Task {
      await documentManager.setDocumentCategoryAndProcess(document.id, category: category)
      pendingDocumentForCategory = nil          // runs only after processing finished
      showingDocumentTypeSelector = false
      pendingCategoryDocuments.removeAll { $0.id == document.id }
      if let next = pendingCategoryDocuments.first { … presents next sheet … }
  ```
- **Fix**: make `addToQueue` enqueue and kick the drain in a stored `Task` (`drainTask`) without awaiting it; keep `startProcessing()` awaitable only for tests. Callers then return as soon as the row is queued.
- **Blast radius**: `DocumentProcessor` (WS-05 reads it), `DocumentManager` import/process entry points, `ContentView` document flows, `DocumentProcessingIntegrationTests` which may rely on `await addToQueue` meaning "done".
- **Verification**: test that `addToQueue` returns while the first document is still `.processing` (use a stub extractor that suspends); UI test importing 2 files and confirming both category sheets in sequence without waiting for processing.

### WS-03-05 — A chat reply cannot be cancelled; a stalled provider locks the composer for up to 5 minutes
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/Views/ChatDetailView.swift:225-232` (send `Task` never stored), `Managers/AIChatManager.swift:392-415` (`isSendingMessage` guard), `Services/OpenAICompatibleClient.swift:232-233` (`timeoutIntervalForRequest = 300`)
- **Scenario**: the send is a bare `Task {}` with no handle, no Stop button anywhere in `Views/`, and no cancel API on `AIChatManager`. (1) An OpenAI-compatible server (LM Studio/Ollama on the LAN) that accepts the connection and then stalls keeps `isSendingMessage == true` for up to the 300 s idle timeout, with the composer disabled and no way out short of killing the app. (2) A runaway on-device generation holds `MLXGPUGate` for its whole length, blocking document extraction and title generation. (3) `deleteConversation` during a stream leaves the stream running to completion (tokens/GPU spent, reply then discarded by the placeholder guard). This is the same class as prior items P1-8/P1-9 (cancellation) recurring in the chat path. Streaming itself is single-flight (`isSendingMessage` check-and-set has no `await` between them), so "two streams at once" cannot happen — the problem is the absence of any off-switch.
- **Evidence**:
  ```swift
  // ChatDetailView.swift:225-228
  Task {
      do {
          try await chatManager.sendMessage(message, useStreaming: !AppTestRuntime.isUITesting)
  // AIChatManager.swift:397-399
  guard !isSendingMessage else { throw AIChatError.messageInFlight }
  ```
- **Fix**: store the send Task on `AIChatManager` (`currentSendTask`), expose `cancelCurrentSend()`, add a Stop button bound to `isSendingMessage`, make the three provider stream loops treat `CancellationError` as "keep partial text, finalize". Also cancel it from `deleteConversation` for the active conversation and on background (WS-03-03).
- **Blast radius**: `AIChatManager`, the three provider clients' streaming methods, `ChatDetailView`, MLX gate hold time.
- **Verification**: unit test with a stalled fake stream: `cancelCurrentSend()` returns the manager to `isSendingMessage == false` within one run-loop turn and persists the partial reply; UI test for the Stop button.

### WS-03-06 — Extraction commit uses a pre-await snapshot and has no cancellation re-check before a full-row `INSERT OR REPLACE`
- **Severity**: P2 · **Confidence**: PLAUSIBLE (the unverified link is whether the cloud extraction call honours task cancellation; the Bedrock SDK path was not confirmed to) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:404` (snapshot fetch), `:408-415` (long AI call), `:470` (`saveMedicalDocument`); `Database/DatabaseManager+MedicalDocuments.swift:21` (`insert(or: .replace, …)`)
- **Scenario**: `existingDocument` is fetched, then `getAIClientForDocument` + `extractor.extractFromText(… aiClient: …)` run (seconds to a minute for a cloud provider), then the whole row is rewritten from the snapshot plus extraction output. (a) The user toggles "Include in AI Context" off, edits tags/notes, or changes the date on that document while it is processing: the save overwrites those edits with the stale values — for an already-included document being re-processed, an opt-out silently reverts to included. (b) The user deletes the document during that call: `DocumentManager.deleteDocument` cancels the task and removes the row, but the only `checkCancellation()` is at `:395`, *before* this window; if the provider call returns instead of throwing, `INSERT OR REPLACE` resurrects the row with the file already deleted (ghost entry, "file not found" on open). The comment at `:407-409` says "User edits win over re-extraction" but only edits made before the fetch.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:404-415
  let existingDocument = try await databaseManager.fetchMedicalDocument(id: currentItem.document.id)
  do {
      let extractor = MedicalDocumentExtractor()
      let aiClient = try await getAIClientForDocument(currentItem.document)
      …
      let extractionResult = try await extractor.extractFromText(
  // :470
  try await databaseManager.saveMedicalDocument(medicalDocument!)
  ```
- **Fix**: move the `fetchMedicalDocument` to immediately before the save (DB methods do not suspend, so fetch-merge-save becomes atomic on the main actor) and add `try Task.checkCancellation()` plus an existence check immediately before the save.
- **Blast radius**: `DocumentProcessor.processQueueItem` fallback save path (`:522`) has the same shape; `MedicalDocument` edit flows (`MedicalDocumentDetailViewModel.saveDocument`). Data-integrity framing belongs to WS-02; flagged here because the cause is an interleaving across an `await`.
- **Verification**: test with a stub AI client that suspends: mutate `includeInAIContext` and delete the document during the suspension and assert the opt-out survives / no row is resurrected.

### WS-03-07 — Main-actor residency of the data and file layers puts heavy synchronous work on the UI thread
- **Severity**: P3 · **Confidence**: PLAUSIBLE (sizes derived from the code's own limits; no on-device profile; AES-GCM measured at ~13 ms per 50 MB on an Apple-silicon Mac, so crypto is *not* the problem — I/O, JSON decode and PDF rasterization are) · **Effort**: L
- **Location**: `Database/DatabaseManager.swift:6` (`@MainActor`), `Utils/FileSystemManager.swift:7` (`@MainActor`); main-thread rasterization at `Services/DocumentProcessor.swift:1058-1096` (`makePageImageSource`, `pageSource.image(atPageIndex:)`); `Utils/DocumentImporter.swift:389-407` (scan→PDF)
- **Scenario**: every SQLite query, field decrypt and JSON decode runs on the main thread (their `async` methods contain no real suspension). `DocumentManager.loadDocuments()` → `fetchDocuments()` decrypts and JSON-decodes `extracted_text`, sections and health data of *every* document on each refresh (launch, and again after every processed document). `FileSystemManager.copyFile/retrieveDocument` read, encrypt/decrypt and write up to the 50 MB import cap on main. The vision pass renders and JPEG-encodes pages on main in a loop: 6 pages on-device, up to `maxPages = 50` for cloud vision, each a visible hitch between network awaits. Chat history (`fetchConversations`) decrypts every message at launch — already acknowledged by a `ponytail:` comment, so not re-reported as new. The `ponytail:` notes cover scale, not the main-thread placement.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:1085-1096 (inside @MainActor class)
  for pageIndex in 0..<pageSource.renderedPageCount {
      if Task.isCancelled { break }
      do {
          guard let pageImage = try pageSource.image(atPageIndex: pageIndex) else { … }
  ```
- **Fix**: for rasterization, make the page-render step `nonisolated` and `await` it from the loop (the type is already non-isolated, so the hop is mechanical). For DB/FS, fix: unknown — needs design (moving `DatabaseManager` off the main actor touches every manager; start by moving the document-list decode and `copyFile` into detached-by-design helpers).
- **Blast radius**: very wide for the DB/FS part (every manager); narrow for rasterization.
- **Verification**: Instruments Time Profiler / hang detector on an iPhone with ~50 documents and a 50-page scanned PDF; assert main-thread hangs stay under 100 ms during import and processing.

### WS-03-08 — `MLXGPUGate` waiters ignore cancellation and lose their queue position
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:34-56`
- **Scenario**: `acquire()` parks on a plain `withCheckedContinuation` with no `withTaskCancellationHandler`, so a cancelled caller (a paused/deleted document, a dismissed title request) stays parked behind a long chat reply, and when it finally wakes it still loads the model (`performLoadModel`, ~3 s, up to 2.4 GB) and starts work before anything notices it was cancelled. Also, `release()` clears `isBusy` before the woken waiter runs, so a newly arriving `acquire()` can take the gate first and the woken waiter re-appends at the *back* (`while isBusy { … waiters.append }`), so under steady chat traffic a queued extraction page can be starved. No deadlock or lost wakeup: every release resumes at most one waiter and every acquirer releases via `defer`.
- **Evidence**:
  ```swift
  func acquire() async {
      while isBusy {
          await withCheckedContinuation { waiters.append($0) }
      }
      isBusy = true
  }
  ```
- **Fix**: hand the gate directly to the first waiter in `release()` (keep `isBusy = true`, resume the waiter) and wrap the wait in `withTaskCancellationHandler` that removes the waiter and resumes it with a thrown `CancellationError` (make `acquire` `throws`).
- **Blast radius**: 7 `acquire` call sites in `MLXOnDeviceClient`.
- **Verification**: unit test with a fake gate holder: cancel a waiter and assert it returns without ever holding the gate; FIFO order test for three waiters.

### WS-03-09 — OCR and page-render loops never observe cancellation
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:295-406` (no `Task.isCancelled`/`checkCancellation` anywhere in the file)
- **Scenario**: pausing the queue or deleting a document mid-extraction cancels the `Task`, but the loop still renders and OCRs the remaining pages (up to 50 at the code's own estimate of 1–2 s per page plus `detectTables` per page) before `processQueueItem`'s first checkpoint at `:395`. The processor's comment acknowledges this ("OCR/Vision don't observe task cancellation"); I could not find a reason it cannot add a per-page check. Cost is CPU/battery and delayed model release, not corruption.
- **Evidence**:
  ```swift
  for pageIndex in 0..<pageCount {
      guard let page = pdfDocument.page(at: pageIndex) else { continue }
      …
      let cgImage = try renderPDFPageToImage(page)
      let ocrResult = try await performOCR(on: cgImage)
  ```
- **Fix**: `try Task.checkCancellation()` at the top of each page iteration (and make the `catch` rethrow `CancellationError` instead of swallowing it as a page failure).
- **Blast radius**: `NativeDocumentExtractor` only; callers already handle `CancellationError`.
- **Verification**: test that cancels the task after page 1 of a 5-page fixture and asserts only 1–2 pages were OCR'd.

### WS-03-10 — `NetworkRetryManager` swallows cancellation and retries a cancelled request
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/NetworkRetryManager.swift:94` (sleep), `:168-170` (`URLSession` errors retryable), `RetryResult.cancelled` never produced
- **Scenario**: `try? await Task.sleep` turns task cancellation into a no-op, and `isRetryableError` returns `true` for any `NSURLErrorDomain` error including `URLError.cancelled`, so a cancelled operation is retried up to three times instantly and reported as `.failure(…, attempts: 3)`, never `.cancelled`. Today only `retryFailedMessage` and `loadHealthData` (a local DB read wrapped in a *network* retry) use it, and nothing cancels them, so there is no user-visible effect yet — it becomes a real bug the moment WS-03-05's Stop button exists.
- **Evidence**:
  ```swift
  try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
  ```
- **Fix**: `try Task.checkCancellation()` at the top of each attempt and `try await Task.sleep` inside the `do`; map `CancellationError` / `URLError.cancelled` to `.cancelled`.
- **Blast radius**: 2 callers in `AIChatManager` / `HealthDataManager`.
- **Verification**: unit test cancelling a retrying operation and asserting `.cancelled` with one attempt.

### WS-03-11 — Height/weight debounce is not flushed on Save
- **Severity**: P3 · **Confidence**: CONFIRMED (path traced; needs a ≤150 ms gap between the last picker change and Save) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/PersonalInfoEditorView.swift:452-463` (debounce), `:424` (`onSave(editedInfo)`)
- **Scenario**: picker changes call `debounceHeightUpdate()/debounceWeightUpdate()`, which only writes `editedInfo.height/weight` 0.15 s later via `DispatchQueue.main.asyncAfter`. Save reads `editedInfo` immediately with no flush of the pending work item, so tapping Save right after the last wheel tick persists the previous height/weight, and the stale work item then fires into a dismissed view.
- **Evidence**:
  ```swift
  private func debounceHeightUpdate() {
      heightUpdateWorkItem?.cancel()
      let work = DispatchWorkItem { updateHeight() }
      heightUpdateWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  ```
- **Fix**: in the Save action, run `heightUpdateWorkItem?.perform()` / `weightUpdateWorkItem?.perform()` (or call `updateHeight()`/`updateWeight()` directly) before `onSave`.
- **Blast radius**: this view only.
- **Verification**: UI/unit test that changes the weight wheel and taps Save within 100 ms, asserting the saved weight.

### WS-03-12 — `BedrockClient` caches a client built from a configuration that was replaced mid-await
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified: whether `BedrockRuntimeClientConfig` init actually suspends) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/BedrockClient.swift:158-176`
- **Scenario**: `getBedrockClient()` reads `config`, awaits `makeClientConfig`, then assigns `self.bedrockClient`. If `updateConfig(_:)` (which sets `bedrockClient = nil`) runs during that await, the late assignment re-caches a client built from the *old* credentials/region, and requests keep using them until the next `updateConfig`. Two concurrent first callers also both build a client (harmless duplicate).
- **Evidence**:
  ```swift
  let clientConfig = try await Self.makeClientConfig(for: config)
  let client = BedrockRuntimeClient(config: clientConfig)
  self.bedrockClient = client
  ```
- **Fix**: capture a config generation counter before the await and only assign if it is unchanged.
- **Blast radius**: Bedrock chat and vision extraction.
- **Verification**: test that calls `updateConfig` between the await and the assignment (inject a suspending config builder) and asserts the next request uses the new config.

### WS-03-13 — `AppLog` does its expensive work on the caller's thread
- **Severity**: P3 · **Confidence**: PLAUSIBLE (regex cost measured on a Mac; fsync/file-rewrite cost on device not measured) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AppLog.swift:402-460`, `:809-851`, `:497-512`
- **Scenario**: every `log()` call — on the main thread for most callers — allocates an `ISO8601DateFormatter`, then runs `redactForSupport`, which *compiles 14 `NSRegularExpression`s per call* (measured 0.22 ms per typical line on Apple silicon, before any I/O) before dispatching. `.error`/`.critical` additionally `logQueue.sync` onto a block that appends + `fsync`s the log and rewrites the whole error-buffer file (read all ≤500 lines, filter, atomic write), so the caller blocks for that. No deadlock exists (the block never calls back into main or takes another lock; re-entrancy is guarded), but a burst of errors (e.g. per-page Vision failures) stalls whichever thread logs.
- **Evidence**:
  ```swift
  if isDurableEvent {
      if DispatchQueue.getSpecific(key: logQueueKey) != nil { writeBlock() }
      else { logQueue.sync(execute: writeBlock) }
  ```
- **Fix**: cache the compiled regexes in a `static let` array and move redaction + formatting onto `logQueue`; keep the synchronous durable write only for `.critical`.
- **Blast radius**: `AppLog` only; WS-07 owns the redaction *content*.
- **Verification**: micro-benchmark `log()` on main before/after; unit test that redacted output is byte-identical.

### WS-03-14 — Leftover debug "verification" sleep and re-fetch on the processing hot path
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:473-479`
- **Scenario**: after every successful save the pipeline does `try? await Task.sleep(500 ms)` then re-fetches and decrypts the whole document just to log whether `extractedText` is nil. It adds half a second per document while the extraction model is still resident (the model is released only after this block), burns a full decrypt on the main actor, and the `try?` also swallows cancellation, so a cancel arriving during the sleep is ignored until the next checkpoint.
- **Evidence**:
  ```swift
  // CRITICAL: Verify the document is still in DB correctly AFTER potential UI interactions
  try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds
  if let verifiedDoc = try? await databaseManager.fetchMedicalDocument(id: medicalDocument!.id) {
  ```
- **Fix**: delete the block (the save already `throws` on failure).
- **Blast radius**: none beyond the processor; frees ~0.5 s per document.
- **Verification**: processing integration test still passes; per-document wall time drops by ~0.5 s.

### WS-03-15 — Redundant or misleading synchronization primitives
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Managers/HealthDataManager.swift:43, 613` (`syncLock`); `Managers/AIChatManager.swift:1238-1262` + `:109-115` (second `NWPathMonitor`); `Managers/DocumentManager.swift:519-529` (`receive(on: .main)`); `Models/MedicalDocument.swift:18`
- **Scenario**: `syncLock.withLock { … }` wraps only synchronous code inside a `@MainActor` class, so it can never contend, while its comment ("async-safe scoped locking to prevent race conditions during sync") invites a future maintainer to rely on it across an `await`, where it would not protect anything. `AIChatManager` runs its own legacy `NWPathMonitor` alongside `NetworkManager`; both write `isOffline` from separate `Task`s, so ordering rests on executor FIFO. `NotificationObserverBag.insert` is unlocked and relies on caller convention.
- **Evidence**:
  ```swift
  // HealthDataManager.swift:612-613
  // Use async-safe scoped locking to prevent race conditions during sync
  let info = syncLock.withLock { () -> PersonalHealthInfo in
  ```
- **Fix**: delete `syncLock` and the legacy monitor; mark `NotificationObserverBag` `@MainActor`-confined (or lock `observers`).
- **Blast radius**: three managers; no behaviour change.
- **Verification**: existing `HealthDataManagerTests` / `AIChatManagerTests` still pass.

## Structural risks (max 5 bullets)

- **Everything stateful is `@MainActor` and effectively synchronous** (database, file system, all managers, all provider clients). This is why most races I looked for do not exist (no suspension between read and write), but it also means every heavy operation is on the UI thread and any future real `await` inside a manager silently opens read-modify-write windows that nothing guards. WS-03-02 and WS-03-06 are the first two examples.
- **Completion callbacks hop through fresh unstructured `Task { @MainActor }`s** (`onUpdate` per chunk, `onComplete` once). Correctness of "last update before final" relies on executor FIFO, not on any structured guarantee; a reordered `onUpdate` would re-apply raw streamed text over the finalized message. Not observed; worth replacing with an `AsyncThrowingStream` consumed on the main actor.
- **Long-running work has no owner**: chat send, document drain, retry, thumbnail and MLX title tasks are all fire-and-forget `Task {}` with no handle, which is the root of WS-03-03/04/05. A small `TaskRegistry`/stored-handle pattern would address the family.
- **Launch-time database open + migration run synchronously on the main thread inside SwiftUI scene construction** (`AppStartupHealth.shared` → `DatabaseManager.shared`); the v11 migration loads and re-encrypts every document row. Dropped from the findings as it is upgrade-only and data-integrity territory (WS-02), but it is a watchdog/jetsam risk for testers upgrading from pre-v11 builds with many documents.
- **MLX behaviour is untested by CI**: every MLX path is compiled out of the simulator, so the gate, residency eviction, background handling and cancellation have zero automated coverage.

Dropped (3, below the cap threshold for this workstream): (1) stale whole-object `PersonalHealthInfo` overwrites from long-lived edit sheets vs. HealthKit merge (data-integrity, WS-02); (2) `MLXModelDownloadManager.cancelDownload()` cleanup racing the unwinding transfer task's final `moveItem` (theoretical, sub-second window); (3) launch-time migration on the main thread (see structural risks).

## Machine-readable summary
```json
[
  {"id":"WS-03-01","title":"Vision OCR continuations resume twice on any Vision error (process trap)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:463","HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:506","HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:592","HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:607"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-02","title":"Title generation writes stale conversation snapshot back, dropping follow-up message and discarding its reply","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:240","HealthApp/HealthApp/Managers/AIChatManager.swift:787","HealthApp/HealthApp/Managers/AIChatManager.swift:861","HealthApp/HealthApp/Managers/AIChatManager.swift:933","HealthApp/HealthApp/Views/ChatDetailView.swift:199"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-03","title":"On-device generation is not stopped when the app backgrounds (GPU work from background)","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:331","HealthApp/HealthApp/Managers/SettingsManager.swift:646","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:596"],"effort":"M","area":"concurrency"},
  {"id":"WS-03-04","title":"addToQueue awaits the whole queue drain, parking UI continuations and serialising batch imports","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:162","HealthApp/HealthApp/Services/DocumentProcessor.swift:268","HealthApp/HealthApp/Services/DocumentProcessor.swift:1691","HealthApp/HealthApp/Managers/DocumentManager.swift:252","HealthApp/HealthApp/ContentView.swift:715"],"effort":"M","area":"concurrency"},
  {"id":"WS-03-05","title":"Chat reply cannot be cancelled; stalled provider locks the composer up to 5 minutes","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:225","HealthApp/HealthApp/Managers/AIChatManager.swift:397","HealthApp/HealthApp/Services/OpenAICompatibleClient.swift:233"],"effort":"M","area":"concurrency"},
  {"id":"WS-03-06","title":"Extraction commit uses pre-await snapshot and lacks cancellation re-check before full-row INSERT OR REPLACE","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:404","HealthApp/HealthApp/Services/DocumentProcessor.swift:470","HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:21"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-07","title":"Main-actor residency of data/file layers puts I/O, JSON decode and PDF rasterization on the UI thread","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:6","HealthApp/HealthApp/Utils/FileSystemManager.swift:7","HealthApp/HealthApp/Services/DocumentProcessor.swift:1085"],"effort":"L","area":"concurrency"},
  {"id":"WS-03-08","title":"MLXGPUGate waiters ignore cancellation and lose queue position","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:41"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-09","title":"OCR and page-render loops never observe cancellation","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:295"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-10","title":"NetworkRetryManager swallows cancellation and retries cancelled URLSession requests","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/NetworkRetryManager.swift:94","HealthApp/HealthApp/Managers/NetworkRetryManager.swift:168"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-11","title":"Height/weight debounce is not flushed on Save","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/PersonalInfoEditorView.swift:424","HealthApp/HealthApp/Views/PersonalInfoEditorView.swift:452"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-12","title":"BedrockClient may cache a client built from a config replaced mid-await","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Services/BedrockClient.swift:158","HealthApp/HealthApp/Services/BedrockClient.swift:171"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-13","title":"AppLog does regex compilation and synchronous file I/O on the caller's thread","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Managers/AppLog.swift:402","HealthApp/HealthApp/Managers/AppLog.swift:809","HealthApp/HealthApp/Managers/AppLog.swift:497"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-14","title":"Leftover debug verification sleep and re-fetch on the document processing hot path","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:474"],"effort":"S","area":"concurrency"},
  {"id":"WS-03-15","title":"Redundant or misleading synchronization primitives (syncLock, duplicate NWPathMonitor, unlocked observer bag)","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthDataManager.swift:43","HealthApp/HealthApp/Managers/AIChatManager.swift:1238","HealthApp/HealthApp/Managers/DocumentManager.swift:519","HealthApp/HealthApp/Models/MedicalDocument.swift:18"],"effort":"S","area":"concurrency"}
]
```
