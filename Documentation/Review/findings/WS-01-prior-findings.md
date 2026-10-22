# WS-01 — Prior-findings regression verification

- **Agent / model**: Claude Sonnet 5.5 (WS-01 sub-agent), read-only review; no builds run
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (branch `main`, working tree has only Documentation/Review edits)
- **Scope actually covered**: every P0/P1 in `PRE-BETA-REVIEW.md` (P0-1, P0-2, P1-1..P1-15) traced to today's code; the four fresh-eyes items (review-selection P0, queue-jam P1, delete-during-AI-extraction P1, overlapping-drain-loop P1); `git show` of `28fe453b` (Docling) and `4dfde676` (dead code, all non-view diffs read, deleted views checked for string/identifier/behavior dependencies); the v11/v12 migration path read in `DatabaseManager.swift`; the WS-00 lead on `AIChatManager.swift:1027`; the scheme/target membership of the test suites; a scratch-DB simulation of `ALTER TABLE ... DROP COLUMN` on system SQLite 3.54 (scratchpad only).
- **Scope not covered**: P2 fix claims other than where a P1 fix depended on them; behavior of `QuickLook`/Vision/MLX at runtime (no device/simulator run); whether the manual "v10 -> v11 on a seeded device" upgrade test requested by the Fix Status section was ever performed (UNVERIFIABLE from the repo); database/encryption-at-rest depth (WS-02), actor isolation (WS-03), logging/egress audit beyond the specific P0-2 sites (WS-07).
- **Verdict**: The prior review largely holds — 12 of 17 P0/P1 items are verifiably fixed with the enforcing code still present, 0 regressed, 5 partial — and neither refactor commit removed a fix; but two partial fixes (P1-5 privacy opt-outs, P1-8 delete-resurrects-row) are still reachable by a second path and should be closed before the beta widens.
- **Counts**: P0=0 P1=2 P2=7 P3=4 (dropped: 0)

## Regression matrix

HOLDS = fix present, defect cannot recur by the described path. PARTIAL = fixed on the described path, reachable by another. REGRESSED = guard gone. No item is REGRESSED or UNVERIFIABLE as to code; the one UNVERIFIABLE item is procedural (manual upgrade test), listed after the table.

| Prior ID | Title (short) | Claimed fix | Today | Evidence |
|---|---|---|---|---|
| P0-1 | PDF page index crash | Dead page appends empty `PageText`, indices stay aligned | **HOLDS** | `NativeDocumentExtractor.swift:308-313` — every iteration of `0..<pageCount` appends exactly once (`guard ... else { pdfKitPages.append(PageText(pageNumber: i + 1, text: "", observations: nil)); continue }`), so `finalPages.count == pageCount` and `finalPages[pageIndex]` at `:364` cannot go out of range. Loop 2 also `continue`s on a nil page (`:346`). |
| P0-2 | PHI in durable plaintext logs | Length-only MLX log; titles not logged; quoted filenames; generic notifications | **PARTIAL** | MLX tail now length-only (`MLXOnDeviceClient.swift:862`); title logs removed (`AIChatManager.swift:282`); `AppLog.log` now redacts every persisted line (`AppLog.swift:411`) and the file-name/value patterns exist (`:818-824`). Residuals: failure notification still embeds `error.localizedDescription` which contains the file name (WS-01-03); invalid LLM title logged at `.warning` (`AIChatManager.swift:340`, WS-01-11). Success/complete notifications are generic (`DocumentProcessor.swift:1634,1667`). |
| P1-1 | Streaming dies after first reply | Clear throttle slot on cancel; ignore cancelled task | **HOLDS** | `AIChatManager.swift:604` (`if let existing = streamingUpdateTask, !existing.isCancelled { return }`) and `:643-646` (`catch is CancellationError { self.streamingUpdateTask = nil }`). A cancelled task can no longer block a new one. |
| P1-2 | Conversation snap-back mid-stream | Only refresh `currentConversation` when ids match | **HOLDS** | `:631-633` (throttle tick) and `:667-669` (finalize) both guard `self.currentConversation?.id == ids.conversationId`. The remaining unguarded assignments (`:430`, `:709`) run only for the conversation the user just sent in. |
| P1-3 | UTF-8 mojibake in SSE | `bytes.lines` | **HOLDS** | `OpenAICompatibleClient.swift:701` `for try await rawLine in bytes.lines`; no `Character(UnicodeScalar(byte))` remains anywhere in the app (`grep` clean). Bedrock decodes whole `Data` chunks (`BedrockClient.swift:434-437`), so no byte-wise path exists there either. |
| P1-4 | Error-alert Retry no-op | Re-resolve message state by id | **HOLDS** | `AIChatManager.swift:499-511` re-reads the current message from `conversations` before `guard resolvedMessage.canRetry`; covered by `PreBetaRegressionTests.testRetryFailedMessageResolvesCurrentStateFromConversation`. |
| P1-5 | Privacy opt-outs revert | New column + persist in save/update + decode | **PARTIAL** | DB layer is correct: written at `DatabaseManager+Chat.swift:18-28` and `:128-140`, read at `:313-320`, in fresh schema `DatabaseManager.swift:219`, migration `:569`, round-trip test `PreBetaRegressionTests:72`. But the manager-level write path is a stale-snapshot read-modify-write with its error discarded: WS-01-01. Answers the WS-00 lead. |
| P1-6 | Reprocess fails deterministically | Duplicate-import `validationFailed` is a skip | **HOLDS** | `HealthDataManager.swift:376-384`; covered by `testLinkExtractedDataIsIdempotentForSameDocument`. Side effect: the catch is broader than "duplicate" — WS-01-04. |
| P1-7 | Reprocess wipes user metadata | Merge existing row fields | **HOLDS** | `DocumentProcessor.swift:404` fetches `existingDocument`; `:439-462` takes date/provider/AI-context/priority/lastEditedAt/tags/notes from it first. |
| P1-8 | Cancel not propagated / delete resurrects row | Cancellation classified in catch; checkpoints after OCR and after LLM passes | **PARTIAL** | Catch classification holds: `:577-584` (`if Task.isCancelled \|\| error is CancellationError { ... .pending; return }`) and checkpoints `:382`, `:395`, `:554`. Gap: no checkpoint between `extractFromText` (`:415`, which swallows cancellation, `MedicalDocumentExtractor.swift:68-71`) and the `INSERT OR REPLACE` at `:470`: WS-01-02. |
| P1-9 | Stuck in `.processing` | Startup sweep to `.failed` | **HOLDS** | `DocumentProcessor.swift:1686-1688` runs from `init` (`:124`): `fetchDocuments(with: .processing)` then `updateDocumentStatus(..., .failed)`; detail view offers Retry for `.failed`. (Sweep and queued-restore share one `do/catch`; one undecryptable row aborts both — noted in passing.) |
| P1-10 | Share hands out encrypted file | Decrypt to temp copy | **HOLDS** | `DocumentDetailView.swift:84-92` calls `FileSystemManager.retrieveDocument` (decrypts, `FileSystemManager.swift:154-161`) and shares the temp URL; `DocumentManager.shareDocument*` deleted; the only other share sheets take generated exports/chat files. Temp-file hygiene: WS-01-12. |
| P1-11 | Blank PDF export | Real `UIGraphicsPDFRenderer` | **HOLDS** | `DocumentExporter.swift:243-288` (explicit `beginPage()` at `:263`); `testPDFExportContainsRealContent` asserts extracted text. |
| P1-12 | Documents table plaintext PHI | AES-GCM columns + v11 migration | **PARTIAL** | All four named columns (+ extracted_data/sections) are encrypted on every write path (`DatabaseManager+MedicalDocuments.swift:28,35,36`, `:238-246`; `+Documents.swift:50-56`, `:187-189`) and by the v11 pass (`DatabaseManager.swift:586-632`). Residual plaintext PHI in the same table/files: user `tags` column and the page-1 thumbnail JPEGs — WS-01-07. |
| P1-13 | Single review slot | Review queue | **HOLDS** | `DocumentProcessor.swift:52-67` (`enqueueImportReview` appends behind a presented review; `finishPendingImportReview` promotes); `ContentView.swift:1109-1113` always advances. Memory-only persistence is the documented `ponytail:` deferral (`:24-26`) and is not worse than documented. |
| P1-14 | `thumbnail_path` nulled | Merge + dedicated updater | **HOLDS** | `DocumentProcessor.swift:434` (`thumbnailPath: existingDocument?.thumbnailPath ?? ...`), `DatabaseManager+Documents.swift:213-225` single-column update, used at `DocumentImporter.swift:150,232,305`. Theoretical overwrite window if the thumbnail finishes after `:404` and before `:470` (cloud AI call between them); thumbnails normally finish within the OCR phase. |
| P1-15 | Multi-file import processes one | Queue all for category selection | **PARTIAL** | All imported docs are appended to `pendingCategoryDocuments` (`ContentView.swift:957-962`), so the original defect is fixed; but each next sheet is gated on the previous document finishing processing — WS-01-05. |
| FE-P0 | Review-sheet selections discarded | `resolvedGroups` | **HOLDS** | `BloodTestImportReviewView.swift:446-470`; `testReviewSelectionPropagation`. |
| FE-P1a | Review save failure jams queue | Always advance | **HOLDS** | `ContentView.swift:1109-1113`. |
| FE-P1b | Delete-during-AI-extraction resurrects row | Re-check cancellation after LLM passes | **PARTIAL** | Same as P1-8 gap — WS-01-02. |
| FE-P1c | Overlapping drain loops | Generation token | **HOLDS** | `DocumentProcessor.swift:273-274`, `:284`, `:311`, `:318`: a superseded loop returns at the top-of-loop check and skips the registry wipe. |

Procedural item, not a code verdict: the Fix Status section asks for one real v10 -> v11 upgrade on a seeded device before shipping. Nothing in the repo (no test, no log, no doc) shows it happened, and there is no migration test at all (`grep -in migrat HealthAppTests` returns only unrelated Keychain/UserDefaults tests). **UNVERIFIABLE** — see WS-01-09.

### Docling removal (`28fe453b`) — verdict: migration mechanically safe, one data-loss edge

- **Mechanism**: `case 12: try db.run("ALTER TABLE documents DROP COLUMN raw_docling_output")` (`DatabaseManager.swift:574-577`), inside the per-step `db.transaction { performMigration; setDatabaseVersion }` loop (`:398-402`). This is a native SQLite `DROP COLUMN` (>= 3.35; iOS 26 ships newer), not a table rebuild. I reproduced it on a scratch table with an index on a sibling column and data in `extracted_text`/`thumbnail_path`: sibling data and index survived. The column is not referenced by any index (`idx_documents_*` cover status/imported/type/date/category/ai_context only), view or trigger (none exist).
- **Ordering on a v10 database**: step 11 still reads and re-encrypts `raw_docling_output` through a local `Expression` (`:588`, `:605`, `:628`) *before* step 12 drops it, so a v10 -> v12 jump in one launch works. Fresh installs never create the column (`createTables` edited at both copies, `:203` and `:815`) and are stamped v12 directly (`:381-383`).
- **Why no brick**: the column was added to `createTables` and to migration 4 in the same commit (`17e38052`), so no v>=4 database can lack it; a failed v12 step rolls back and leaves the stored version at 11.
- **Nothing still reads it**: `grep -ri "raw_docling\|rawDocling\|docling" --include=*.swift` finds only the migration code above.
- **Version bump**: `currentDatabaseVersion = 12` (`:43`), matches CLAUDE.md.
- **Edge**: the same commit deleted the loader's "extractedText is NULL but rawDoclingOutput exists -> recover md_content" branch, so any row that depended on that recovery loses its text permanently when the column drops: WS-01-06.

### Dead-code removal (`4dfde676`) — verdict: no removed guard found; siblings of the TypingIndicator miss not found

Read every non-view hunk: `fetchRecentHealthData`/`AnyHealthDataItem`, `attemptDataRecovery` (the read-only `scanDatabaseForRecovery` and `exportCorruptedRecordsForAnalysis` remain), `getChatStatistics`/offline-capability types, `DocumentStatistics`/`StorageUsage`/metadata export, `AIConnectionStatus`/`AuthCredentials`, `BloodTestMappingServiceError`, `AccessibilityLabelBuilder`, `UserDefaults+FirstLaunch` (its `hasAcceptedDisclaimer` key was dead; the live disclaimer gate is DB-backed, `AppSettingsManager.swift:32`, `HealthAppApp.swift:64`), `ValidationHelper` (+28 tests; test-only, the app validates through `BloodTestResult.isValid` etc.). None was a guard on a live path. Type-level dependencies are proven by the green build; I additionally checked the string/identifier-level dependencies a build cannot catch: the 87 identifiers/labels referenced by UI tests against app source. The mismatches pre-date this commit and are in test files that do not compile (WS-01-08). The ~27-case drop from the 285 tests quoted in Fix Status to the 258 in the baseline is explained by the 28 `ValidationHelperTests` and 2 `AccessibilityTests` cases this commit deleted.

---

## Findings

### WS-01-01 — P1-5 privacy opt-outs can still silently revert: stale-snapshot write-back plus a discarded persistence error
- **Severity**: P1 · **Confidence**: CONFIRMED (mechanism traced end to end; the trigger is a timing window, see Scenario) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:240-253` (`updateConversationTitle`), `:256`/`:284` (`generateTitleIfNeeded`), `:787`/`:861`/`:933`/`:999` (snapshot call sites), `:1021-1031` (`selectHealthDataForContext`, the WS-00 dropped-error site)
- **Scenario**: This is the WS-00 hypothesis, tested. Two defects combine.
  1. **Lost update (the real hole).** After the first exchange, `generateTitleIfNeeded(for: self.conversations[i])` captures a `ChatConversation` value, then `await`s an LLM title call (seconds on an on-device model). `updateConversationTitle(conversation, ...)` then copies that *old* snapshot and calls `databaseManager.updateConversation`, which writes every column including `included_personal_info_categories` and `included_health_data_types` (`DatabaseManager+Chat.swift:132-139`), and assigns the snapshot back into `conversations[index]` and `currentConversation`. If the user opens the context sheet and excludes, say, Medications during that window, `selectHealthDataForContext` persists the opt-out (`:1026`), and then the title write overwrites it with the pre-opt-out values, in the DB and in memory. The next `selectConversation` (`:207-210`) reloads all categories, so the exclusion is gone after any conversation switch or relaunch. The same read-modify-write exists in `archiveConversation` (`:233`).
  2. **Discarded error (WS-00 lead).** `Task { try await databaseManager.updateConversation(conversation) ... }` at `:1027` drops any thrown error (`notFound`, `connectionFailed`, `encryptionFailed` from `encryptString`). On failure `conversations[index]` is not updated either (the assignment is after the `try`), so memory and DB both keep the old value and the user is never told. **What the dropped error cannot do**: change what is sent in the *current* session — the outgoing context is built from the manager's `@Published selectedPersonalInfoCategories` (`updateHealthDataContext`, `:1050-1051`, `:1092`), not from the persisted copy. The failure only shows up on the next conversation switch/relaunch. A further small gap: on success the Task updates `conversations[index]` but never `currentConversation` (`:1028-1030`), which is the object `ChatDetailView` and the iPad header read (`ChatDetailView.swift:118-120`).
  I did not find a *deterministic* revert (the original P1-5 was deterministic); the title window is real but timing dependent, hence CONFIRMED mechanism / user-visible frequency unknown.
- **Evidence**:
  ```swift
  // AIChatManager.swift:240-249 — snapshot param, written back wholesale
  func updateConversationTitle(_ conversation: ChatConversation, newTitle: String) async throws {
      var updatedConversation = conversation
      updatedConversation.updateTitle(newTitle)
      try await databaseManager.updateConversation(updatedConversation)
      if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
          conversations[index] = updatedConversation
      }
  ```
  ```swift
  // AIChatManager.swift:1021-1031 — error discarded, currentConversation not refreshed
  if var conversation = currentConversation {
      conversation.includedHealthDataTypes = types
      conversation.includedPersonalInfoCategories = personalInfoCategories
      Task {
          try await databaseManager.updateConversation(conversation)
          if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
              conversations[index] = conversation
          }
  ```
- **Fix**: Make the title/archive writes column-scoped (a `updateConversationTitle(id:title:)` DB method that updates only `title`/`updated_at`), or re-read the live `conversations[index]` after the `await` and apply only the changed field. Replace the discarded `Task` at `:1027` with a `do/catch` that sets `errorMessage`/`errorHandler` and also assigns `currentConversation = conversation`. Sequence with the WS-00-01 sweep, as WS-00 advised.
- **Blast radius**: `AIChatManager` is read by WS-03/WS-04/WS-06; `updateConversation` is also used by archive and title paths; `ChatDetailView.swift:148` is another discarded-Task site (already WS-00-01).
- **Verification**: Unit test (the harness in `PreBetaRegressionTests` is enough): create a conversation, call `selectHealthDataForContext(types, personalInfoCategories: [.basicInfo])`, then run `updateConversationTitle` with a snapshot taken *before* the selection, reload via `fetchConversations()`, and assert categories are still `[.basicInfo]`. Second test with a `DatabaseManager` that throws, asserting an error surfaces.

### WS-01-02 — P1-8 / fresh-eyes P1: deleting (or pausing) during the AI-enhancement step still resurrects the deleted document row
- **Severity**: P1 · **Confidence**: CONFIRMED (code path); runtime timing depends on a non-on-device extraction provider · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:395-470`; swallow at `HealthApp/HealthApp/Services/MedicalDocumentExtractor.swift:51-72`; persistence at `HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:21`
- **Scenario**: Provider is Bedrock or OpenAI-compatible (`textEnhancementClient != nil`, `:408-411`). A lab PDF finishes OCR and `extractHealthData`; the last checkpoint passes at `:395`. `existingDocument` is fetched at `:404`. `extractFromText` now makes a cloud call (seconds). During that call the user deletes the document: `DocumentManager.deleteDocument` cancels the task, deletes the row and the file (`DocumentManager.swift:368-385`). The cancelled URLSession call throws, but `extractFromText` catches *every* error and falls through to basic extraction (`MedicalDocumentExtractor.swift:68-71`), so it returns normally. `:470` then runs `saveMedicalDocument(medicalDocument!)`, an `insert(or: .replace)` of the stale `existingDocument` fields: the row is recreated with `filePath` pointing at the deleted file. The next checkpoint (`:554`) throws, and the cancellation handler (`:577-581`) calls `updateDocumentStatus(.pending)`, which now *succeeds* because the row exists again. Result: a broken, "pending" ghost document in the library — the P1-8 symptom, partially fixed. The relink step is protected (`:554`), so no blood test is imported from it.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:415-420, 470 — no cancellation check between these
  let extractionResult = try await extractor.extractFromText(text: result.extractedText, fileName: ..., aiClient: textEnhancementClient, ...)
  ...
  try await databaseManager.saveMedicalDocument(medicalDocument!)
  ```
  ```swift
  // MedicalDocumentExtractor.swift:68-71
  } catch {
      AppLog.shared.documents("AI enhancement failed, falling back to basic extraction: ...", level: .warning)
      // Fall through to basic extraction
  }
  ```
- **Fix**: Add `try Task.checkCancellation()` immediately before `saveMedicalDocument` at `:470` and before the fallback save at `:521`; better, have `extractFromText` rethrow `CancellationError`/`URLError.cancelled`. Longer term, make the final save an `UPDATE` that fails on a missing row instead of `INSERT OR REPLACE`.
- **Blast radius**: all document processing; `saveMedicalDocument` is also called from the fallback path and `+MedicalDocuments` update paths.
- **Verification**: integration test with a stub `AIProviderInterface` that suspends, delete the document while it is suspended, resume, and assert `fetchMedicalDocument(id:)` is nil afterwards.

### WS-01-03 — P0-2 "lock-screen notifications genericized" is not true for the failure notification
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:1649`; `HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:123-128`
- **Scenario**: A scanned/damaged PDF fails to load three times. The terminal handler calls `sendProcessingFailureNotification` (`:652`), whose body is `"A document failed to process: \(error.localizedDescription)"`. For `NativeExtractionError.pdfLoadFailed(name)` that string is `"Failed to load PDF document: <file name>"`, and `fileNotFound(path)` embeds a full path. Lab-report file names routinely contain patient names, so the name appears on the lock screen — exactly what the original P0-2 notification item described. Visibility depends on the user's notification-preview setting.
- **Evidence**:
  ```swift
  content.title = "Document Processing Failed"
  content.body = "A document failed to process: \(error.localizedDescription)"
  ```
  ```swift
  case .pdfLoadFailed(let name):
      return "Failed to load PDF document: \(name)"
  ```
- **Fix**: Use a fixed body ("A document failed to process. Open the app to retry.") and keep the specifics in the (redacted) log.
- **Blast radius**: only this notification; `ProcessingError.documentName` already carries the name for in-app display.
- **Verification**: unit test that the notification content body contains neither the file name nor `localizedDescription` for a `pdfLoadFailed("Jane Doe labs.pdf")` error (the method is private; expose a content-builder helper).

### WS-01-04 — The P1-6 fix swallows every `validationFailed`, so invalid or "similar" lab reports are marked successfully processed with no data
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/HealthDataManager.swift:376-384` (throw sites `:230`, `:242`, `:251`); same pattern at `HealthApp/HealthApp/ContentView.swift:1101-1104`
- **Scenario**: `addBloodTest` throws `validationFailed` for three different reasons: incomplete/invalid data (`:230`), same source document (`:242`, the intended skip), and "a very similar blood test already exists for this date" (`:251`). The new `catch HealthDataError.validationFailed` treats all three as a harmless skip. A document whose extracted `BloodTestResult` fails `isValid`, or that is >80% similar to another report within 24 hours, therefore finishes as `.completed`, fires "Document Processed ... successfully" and imports nothing; only a `.warning` log records it. Before the fix this surfaced as a Failed document. Same shape in the review-sheet save: after the user has explicitly picked values and tapped Import, an invalid or duplicate result — and any other error (`:1105-1106`) — is logged and dropped with no UI feedback, and the user's selections are gone.
- **Evidence**:
  ```swift
  } catch HealthDataError.validationFailed(let reason) {
      // ... a duplicate lab report must not fail the whole document
      AppLog.shared.healthData("Blood test import skipped: \(reason)", level: .warning)
  }
  ```
- **Fix**: Introduce a dedicated `HealthDataError.duplicateImport` for the same-document case and catch only that; let genuine validation failures and the review-save failure reach the user (error alert or a visible "Needs attention" document state).
- **Blast radius**: `addBloodTest` callers (manual entry uses the same validation), `linkExtractedDataToDocument`, the review completion handler.
- **Verification**: tests for (a) invalid blood test during link -> document ends non-success or surfaces an error; (b) same-document re-link still skips silently.

### WS-01-05 — P1-15 fix serializes the category sheets behind full document processing
- **Severity**: P2 · **Confidence**: CONFIRMED (await chain read; not run) · **Effort**: S
- **Location**: `HealthApp/HealthApp/ContentView.swift:712-731`; `HealthApp/HealthApp/Managers/DocumentManager.swift:252`; `HealthApp/HealthApp/Services/DocumentProcessor.swift:162-164`
- **Scenario**: User imports five lab PDFs. All five are queued for category selection. They confirm the first; `onConfirm` runs `await documentManager.setDocumentCategoryAndProcess(...)`, which awaits `documentProcessor.addToQueue`, which — because nothing is processing — `await`s `startProcessing()`, i.e. the entire drain loop. The `Task` therefore does not reach `pendingCategoryDocuments.removeAll` / "present the next document" until document 1 has finished OCR/extraction (seconds with Vision, many minutes with the on-device VLM). The second sheet then pops up out of nowhere. If the app is backgrounded/terminated in between, documents 2..5 stay imported but unprocessed with no category — the original P1-15 symptom for the tail of the batch.
- **Evidence**:
  ```swift
  Task {
      await documentManager.setDocumentCategoryAndProcess(document.id, category: category)  // blocks for the whole drain
      pendingDocumentForCategory = nil
      showingDocumentTypeSelector = false
      pendingCategoryDocuments.removeAll { $0.id == document.id }
  ```
  ```swift
  if !isProcessing { await startProcessing() }   // DocumentProcessor.swift:162-164
  ```
- **Fix**: Make `addToQueue` return after enqueueing and start the drain in a detached/stored `Task` (or have `onConfirm` advance the sheet queue before awaiting processing).
- **Blast radius**: every `addToQueue` caller, including `loadPendingDocuments` (`DocumentProcessor.swift:1690-1694`, which also processes queued rows one at a time because of this), `DocumentManager.swift:208,295`.
- **Verification**: UI/integration test importing three documents with a stubbed slow processor; assert the second category sheet is presented without waiting for the first document's completion.

### WS-01-06 — Docling removal permanently drops text that only the removed recovery branch could surface
- **Severity**: P2 · **Confidence**: PLAUSIBLE (link not verified: whether any beta/dev database actually contains rows with NULL `extracted_text` and a populated `raw_docling_output`) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:574-577`; removed code visible in `git show 28fe453b -- HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift`
- **Scenario**: Before `28fe453b`, `buildMedicalDocument` recovered `extractedText` from `raw_docling_output.document.md_content` when `extracted_text` was NULL/empty. The commit deleted that branch and v12 drops the column in the same launch, with no copy step. A database from a pre-removal build that holds such a row (the exact situation the branch was written for) loses the document's text silently; the AI context for that document becomes empty and nothing flags it. The source file is still on disk, so a Reprocess recovers it, but the user is not told.
- **Evidence**:
  ```swift
  case 12:
      // Migration for version 12: drop legacy Docling raw_docling_output column.
      try db.run("ALTER TABLE documents DROP COLUMN raw_docling_output")
  ```
- **Fix**: In case 12, before dropping, run the old recovery once: for rows with NULL/empty `extracted_text` and non-NULL `raw_docling_output`, decrypt (`decryptDataField`), pull `md_content`, strip base64 images, re-encrypt into `extracted_text`. Or accept the loss explicitly for an unreleased app and note it in the release notes.
- **Blast radius**: only pre-removal databases (developer devices and any TestFlight builds that ever shipped Docling).
- **Verification**: seed a v11 test DB with such a row, open it, assert `extractedText` is populated after migration.

### WS-01-07 — Remaining plaintext PHI in the documents table and thumbnail files
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M (thumbnail encryption) / S (tags)
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:31,241`; `HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:51`; `HealthApp/HealthApp/Utils/FileSystemManager.swift:244,272,294`
- **Scenario**: The P1-12 fix encrypts file name, notes, provider, text, sections and extracted data, but `tags` is still written as plain JSON (`documentTags <- tagsString`), and user tags are free text via `TagEditorSheet` (e.g. "diabetes", "oncology"). Separately, every thumbnail is a JPEG render of page 1 of the document, written with a bare `thumbnailData.write(to:)` — i.e. unencrypted image content of the lab report on disk, while the document itself is AES-GCM. `document_category` and `provider_type` are also plaintext metadata. This matters for the honesty of the "encrypted at rest" claim. (The file_path/thumbnail_path *names* are the documented deferral and are not re-reported.)
- **Evidence**:
  ```swift
  documentTags <- tagsString,                      // plaintext JSON, +Documents.swift:51
  ...
  try thumbnailData.write(to: thumbnailURL)        // FileSystemManager.swift:272, page-1 render
  ```
- **Fix**: Encrypt `tags` with `encryptTextField` (as notes); encrypt thumbnails with the same `encryptData` used for documents and decrypt on display, or apply `.completeFileProtection` and state in the privacy copy that thumbnails are protected by iOS file protection only. Overlaps WS-02.
- **Blast radius**: `searchDocuments`/tag filters (already in-memory after v11), thumbnail display views, migration for existing thumbnails (would be a v13 step).
- **Verification**: write a document with a tag, read the raw SQLite column, assert it is not valid JSON containing the tag; list the thumbnails directory and assert files are not decodable as JPEG without decryption.

### WS-01-08 — Five of the six UI test files are not compiled into the UI test target; WS-00's "UI suites pass" is really 2 smoke tests
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp.xcodeproj/project.pbxproj` (only `UITESTBUILD007` / `RegressionSmokeUITests.swift` has a `PBXBuildFile` and Sources-phase entry, `:158`, `:939`); `HealthApp/HealthAppUITests/ChatInterfaceUITests.swift:154-165,404-410`
- **Scenario**: `AccessibilityUITests`, `BloodTestEntryUITests`, `ChatInterfaceUITests`, `DocumentManagementUITests`, `HealthAppUITests` and `PersonalInfoEditorUITests` appear in the file group but have no build-file entry, so about 102 of 104 UI test functions never compile or run. The WS-00 iPad log shows `Executed 2 tests` for the UI runner, and the 258 results contain 2 of the 104 UI test names. Consequence for this workstream: the dead-code commit's "update stale context UITest" (`ChatInterfaceUITests.swift` one line) was cosmetic — `testIPadContextSelector` and `testContextSelectorPerformance` still expect the deleted title "Health Data Context" and a Cmd+K shortcut that no longer exists in source. If the files are re-added they will fail. The baseline statement "unit + UI suites" overstates coverage; there is no automated UI coverage of the chat, document or accessibility flows this review verifies.
- **Evidence**:
  ```text
  pbxproj: 158: UITESTBUILD007 /* RegressionSmokeUITests.swift in Sources */ = {isa = PBXBuildFile; ...}
           (no PBXBuildFile for UITESTFILE003 ChatInterfaceUITests.swift, nor 001/002/004/005/006)
  ```
  ```swift
  // ChatInterfaceUITests.swift:164
  let contextTitle = app.staticTexts["Health Data Context"]   // string no longer exists in app source
  ```
- **Fix**: Either add the files to the UI test target and repair them, or delete them and the CLAUDE.md claims; decide before the beta. Correct the WS-00 baseline wording.
- **Blast radius**: test target membership; WS-15 (test quality) and the Phase 5 fix-agent protocol, which uses "all tests pass" as a gate.
- **Verification**: `xcodebuild test` output lists > 2 UI test cases; or `grep -c "in Sources" ` shows the files in the UI target.

### WS-01-09 — No automated upgrade test for the v10/v11 -> v12 migration path; the manual upgrade test is unverifiable
- **Severity**: P2 · **Confidence**: CONFIRMED (absence) · **Effort**: M
- **Location**: `HealthApp/HealthAppTests/DatabaseTests.swift` (4 cases); `HealthApp/HealthApp/Database/DatabaseManager.swift:374-413`
- **Scenario**: The Fix Status section says to "test one real v10 -> v11 upgrade on a seeded device before shipping". There is no migration test in the suite and nothing recording that the manual run happened. The v11 step rewrites every documents row and every chat title with Keychain-derived encryption and v12 then drops a column; an error in either, on a beta tester's real data, is exactly the "app unusable after upgrade / data loss" class. My read of the code (see Docling section) found no defect, and the per-step transaction means a failure rolls back, but "reads correct" is not "ran".
- **Evidence**:
  ```swift
  for version in (currentVersion + 1)...Self.currentDatabaseVersion {
      try db.transaction { try performMigration(db: db, toVersion: version); try setDatabaseVersion(db: db, version: version) }
  ```
- **Fix**: Add a test that builds a v10-shaped SQLite file (legacy schema incl. `raw_docling_output`, plaintext document and conversation rows), opens it through `DatabaseManager`, and asserts version 12, readable decrypted fields, `included_personal_info_categories` present, `raw_docling_output` absent, and that the plaintext backup is deleted. Overlaps WS-02/WS-15.
- **Blast radius**: `DatabaseManager` init; test helper to construct legacy files.
- **Verification**: the test above, run on both destinations.

### WS-01-10 — Empty data-type selection fails open to "all flagged documents"
- **Severity**: P3 · **Confidence**: PLAUSIBLE (reaching an empty set requires an undecodable `included_health_data_types` value or a flagged document outside the sheet) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:1062-1073`; `HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:307`
- **Scenario**: `updateHealthDataContext` treats `requestedDataTypes.isEmpty` as "backward compatibility, return all documents" and passes `categories: nil` to `fetchDocumentsForAIContext`, which returns every document with `include_in_ai_context = true`. The context sheet blocks saving an empty selection while documents are selected (`UnifiedContextSelectorView.swift:1095-1105`), so the UI path is guarded. But a conversation whose `included_health_data_types` fails to decode becomes `[]` (`(try? decode) ?? []`), and a document flagged from Records after the sheet was last saved is included in a conversation the user set to "nothing". The two decode defaults also disagree: data types fail closed to empty (which then fails open to documents), personal-info categories fail open to all (`:313-320`).
- **Evidence**:
  ```swift
  } else {
      // No types selected - backward compatibility, return all
      categoriesToFilter = nil
  }
  ```
- **Fix**: Treat an explicitly empty selection as "no documents"; keep `nil` only for a never-configured state.
- **Blast radius**: context building for chat; `AppointmentPrepManager` uses its own path.
- **Verification**: unit test: selection `[]` with one flagged document -> context contains no documents.

### WS-01-11 — Invalid generated title is still logged at warning level
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Managers/AIChatManager.swift:340` (also `:266`, debug only)
- **Scenario**: The P0-2 fix removed the success-path title logs, but when the model's title is empty/too short/over 60 characters the raw title is logged at `.warning` (persisted in release). Titles are LLM summaries of the user's health message. After the 7-word truncation (`:331-334`) the over-60-character case is rare, so exposure is small — the redaction regexes do not cover free text.
- **Evidence**:
  ```swift
  AppLog.shared.ai("LLM title was invalid ('\(title)'), falling back to heuristic", level: .warning)
  ```
- **Fix**: Log `title.count` only.
- **Blast radius**: none.
- **Verification**: grep for `'\(title)'` in `AppLog` calls.

### WS-01-12 — Decrypted share/QuickLook temp files are only removed on normal teardown
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/DocumentDetailView.swift:84-90,115-120,739-810`
- **Scenario**: The P1-10 fix writes decrypted PHI to `temporaryDirectory` (`share_<uuid>_<name>`, `quicklook_<uuid>_<name>`) and deletes it on sheet dismiss / `deinit`. If the app is killed while a sheet is open, the plaintext copy stays until iOS purges tmp; there is no launch-time sweep. The writes use default file protection and `data.write` runs on the main actor for up to the 50 MB cap.
- **Evidence**:
  ```swift
  let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("share_\(UUID().uuidString)_\(document.fileName)")
  try data.write(to: tempURL)
  ```
- **Fix**: Write with `.completeFileProtection`, and delete `share_*`/`quicklook_*` leftovers at launch.
- **Blast radius**: `DocumentDetailView` only.
- **Verification**: leave a `share_x_y.pdf` in tmp, relaunch, assert it is gone.

### WS-01-13 — "All documents have been processed" notification fires after the user pauses or clears the queue
- **Severity**: P3 · **Confidence**: CONFIRMED (read) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:318-323,1661-1669`
- **Scenario**: Pause/Clear cancels the running tasks; the drain loop exits normally, the generation still matches, and `sendProcessingCompletionNotification` only checks `processingQueue.isEmpty`. With nothing left queued after a clear, the user gets "Processing Complete — All documents have been processed" for documents that were cancelled back to `.pending`.
- **Evidence**:
  ```swift
  guard processingQueue.isEmpty else { return }
  content.body = "All documents have been processed"
  ```
- **Fix**: Track whether the loop ended by cancellation (or whether any item completed) before notifying.
- **Blast radius**: notification only.
- **Verification**: pause mid-run with an empty queue; assert no completion notification is added.

## New defects noticed in passing (not investigated deeply)

- `AIChatManager.swift:457` — `try? await databaseManager.markMessageFailed(...)` discards the error that the "failed status persisted so retry survives restart" P2 fix relies on; if it throws, the message looks sent after restart. Not in the WS-00 14 (it is `try?`, not a discarded `Task`).
- `DocumentProcessor.swift:1686-1693` — the `.processing` sweep and the `.queued` restore share one `do/catch`; a single undecryptable `.processing` row aborts both, leaving the other stuck documents unrecovered.
- `DocumentProcessor.swift:1690-1694` calls `addToQueue` in a loop, and `addToQueue` blocks until the queue drains (see WS-01-05), so restored `.queued` documents are admitted one at a time.

## Structural risks (max 5 bullets)

- `INSERT OR REPLACE` of whole `documents`/`chat_conversations` rows from stale in-memory snapshots is the common root of WS-01-01 and WS-01-02 (and the original P1-7/P1-14). Every future full-row save reintroduces the class; column-scoped updates are the durable fix.
- `addToQueue` both enqueues and runs the whole drain loop in the caller's task; most processing-flow oddities (WS-01-05, the restore loop, sheet sequencing) follow from that coupling.
- Fix-status confidence rests on 11 regression tests that cover the DB layer, SSE parsing, PDF export and idempotent linking, but nothing exercises the streaming throttle, cancellation/delete races, the startup sweep, the share path, or migrations, and the UI suite is effectively disabled (WS-01-08).
- Privacy-opt-out state has two sources of truth (manager `@Published` state and the persisted conversation) synchronised by fire-and-forget `Task`s.
- Errors on save/delete paths are routinely downgraded to a `.warning` log (WS-01-04, WS-00-01, `markMessageFailed`), so "success" UI states can follow failed persistence.

## Machine-readable summary
```json
[
  {"id":"WS-01-01","title":"P1-5 privacy opt-outs can revert: stale-snapshot title/archive write-back plus discarded persistence error","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:240","HealthApp/HealthApp/Managers/AIChatManager.swift:284","HealthApp/HealthApp/Managers/AIChatManager.swift:1027"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-02","title":"Delete/pause during AI-enhancement step resurrects the deleted document row (no cancellation check before INSERT OR REPLACE)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:415","HealthApp/HealthApp/Services/DocumentProcessor.swift:470","HealthApp/HealthApp/Services/MedicalDocumentExtractor.swift:68"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-03","title":"Failure notification still puts the document file name on the lock screen via localizedDescription","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:1649","HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:127"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-04","title":"Duplicate-skip catch swallows all validationFailed; invalid or similar lab reports finish as successful with no data","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthDataManager.swift:378","HealthApp/HealthApp/ContentView.swift:1101"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-05","title":"Multi-import category sheets are gated on full processing of the previous document (addToQueue awaits the drain loop)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:712","HealthApp/HealthApp/Managers/DocumentManager.swift:252","HealthApp/HealthApp/Services/DocumentProcessor.swift:162"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-06","title":"Docling v12 migration drops raw output with no copy; removed recovery branch means NULL-text rows lose text","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:574"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-07","title":"Documents table tags and page-1 thumbnail JPEGs remain plaintext PHI at rest","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:31","HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:51","HealthApp/HealthApp/Utils/FileSystemManager.swift:272"],"effort":"M","area":"prior-findings"},
  {"id":"WS-01-08","title":"Five of six UI test files are not in the UI test target; baseline 'UI suites pass' is 2 smoke tests; stale context test strings","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:939","HealthApp/HealthAppUITests/ChatInterfaceUITests.swift:164"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-09","title":"No automated v10/v11 to v12 upgrade test; requested manual upgrade test unverifiable","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/DatabaseTests.swift","HealthApp/HealthApp/Database/DatabaseManager.swift:398"],"effort":"M","area":"prior-findings"},
  {"id":"WS-01-10","title":"Empty data-type selection fails open to all flagged documents","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:1072","HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:307"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-11","title":"Invalid generated conversation title logged at warning level","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:340"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-12","title":"Decrypted share/QuickLook temp files survive a crash; default protection; no launch sweep","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/DocumentDetailView.swift:86","HealthApp/HealthApp/Views/DocumentDetailView.swift:803"],"effort":"S","area":"prior-findings"},
  {"id":"WS-01-13","title":"'All documents processed' notification fires after Pause/Clear with an empty queue","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:1661"],"effort":"S","area":"prior-findings"}
]
```
