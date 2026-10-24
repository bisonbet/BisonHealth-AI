# WS-15 — Test suite quality & coverage gaps

- **Agent / model**: Claude Sonnet 5.5 (WS-15 sub-agent). Read-only on the repo; mutation experiments ran on a scratch copy under the session scratchpad.
- **Date**: 2026-10-24
- **Commit reviewed**: `f95cf804` (branch `main`; the only working-tree changes are other workstreams' untracked findings files)
- **Scope actually covered**: all 16 unit-test files and 7 UI-test files read or grepped (every test name listed; the files holding the claims below read in full); `DatabaseManager.swift` migration code (`:395-640`); `AIChatManager` streaming/retry/context paths; `ErrorHandler`; the MLX value types and their call sites; `AppTestRuntime`; `ScriptedAIProvider`; the scheme's test configuration. Ran the full suite once with coverage (`-enableCodeCoverage YES`), the UI bundle twice more, and four mutation runs of the unit bundle, all on simulator `226EE851-…` only.
- **Scope not covered**: no run on a physical device, so nothing in the `#if !targetEnvironment(simulator)` regions executed. The 113 orphaned UI tests were read, not compiled. `LabReportParserTests` (59 tests, 1,020 LOC) were skimmed, not audited line by line. The prior-findings table marks which verdicts were proven by mutation and which are reasoning only. I did not verify whether unit-test residue persists in a simulator container that holds real data (see WS-15-08).
- **Verdict**: The suite is strong where the last fix passes put their effort (credential storage, endpoint validation, log redaction, lab-report parsing, context assembly) and blind where the data and the default AI path live: **nine independent regressions injected at once, across migrations, streaming, the import pipeline and privacy persistence, left all 291 unit tests green.** It is not beta-ready as a safety net; the first five backlog tests are the ones to write before the beta goes out.
- **Counts**: P0=0 P1=4 P2=8 P3=3 (dropped: 0; several lower-value items were merged into WS-15-06 rather than listed separately)

## Test counts, read correctly

Read from the `.xcresult` (`xcrun xcresulttool get test-results summary`), not stdout: **293 tests, 293 passed, 0 failed, 0 skipped** = 291 unit + 2 UI. The unit-bundle sum of `func test` across the 16 files is also 291. Stdout printed "Executed 2 tests" as warned. The two UI smoke tests passed on all three runs I made (run 1 with the unit bundle, then two UI-only runs, 25.0 s and 25.3 s); nothing changed between runs.

Line coverage (merged unit + UI smoke, `xccov`): **`HealthApp.app` 24.13 % (17,870 / 74,051)**. The numbers that matter:

| File | Coverage | | File | Coverage |
|---|---|---|---|---|
| `Services/MedicalDocumentExtractor.swift` | 0 % (0/685) | | `Services/DocumentProcessor.swift` | 24.5 % (456/1858) |
| `Database/DatabaseManager+Recovery.swift` | 0 % | | `Managers/AIChatManager.swift` | 40.4 % (696/1723) |
| `Views/BloodTestImportReviewView.swift` | 3.3 % (34/1032) | | `Database/DatabaseManager.swift` | 49.0 % (564/1152) |
| `Services/BedrockClient.swift` | 7.3 % (57/779) | | `Managers/HealthDataManager.swift` | 37.1 % (332/894) |
| `Services/OpenAICompatibleClient.swift` | 24.2 % (265/1097) | | `Managers/DocumentManager.swift` | 31.0 % (180/580) |
| `MLXOnDeviceLLM/MLXModelDownloadManager.swift` | 11.9 % | | `ContentView.swift` | 48.7 % (1689/3471) |

## Risk coverage map

| Risk area | Status | Evidence (test names) and what is missing |
|---|---|---|
| Migrations | **Partial, thin** | `DatabaseMigrationTests`: `testUpgradingFromVersion11PreservesDocuments`, `testUpgradingFromVersion12CreatesThePendingReviewTable`, `testAPendingReviewSurvivesReopeningTheDatabase`, `testOpeningAFutureVersionIsRefusedRatherThanCrashing`. Steps 12 and 13 and the downgrade refusal only. Steps 2-11 never run; backup deletion, rollback and fresh-vs-migrated schema equality untested (WS-15-01, -11). |
| Encryption at rest | **Partial** | `testChatTitleEncryptedAtRest`, `testMedicalDocumentPHIEncryptedAtRestAndRoundTrips`, `testDocumentEncryption` (files). Wrong key, tampered ciphertext, missing keychain item and undecryptable rows are untested (WS-15-10). |
| Document pipeline state machine | **Not covered** | `DocumentProcessor` 24.5 %. Only enqueue/finish of the review queue (`testPendingImportReviewQueueSemantics`) and one scripted end-to-end (`testFakeLabPDFImportAndExtractionProducesBloodTestOrReview`). No cancel, sweep, reprocess-merge, drain-loop or page-alignment test (WS-15-03, -04). |
| Parsing / reconciliation | **Covered** | 59 `LabReportParserTests`, 22 `DocumentProcessingIntegrationTests` (genetic). The best-covered area. |
| Provider error paths | **Partial** | Credential handling and error-text redaction are thorough (`ServiceClientTests` 33, `SettingsManagerTests` 33). No HTTP status mapping, retry, timeout or auth-failure test for either cloud client; no `URLProtocol` stub exists (WS-15-09). |
| Streaming | **Not covered** | Every chat test passes `useStreaming: false`; `ScriptedAIProvider` reports `supportsStreaming: false` (WS-15-02). Only `testSSEDataPayloadParsing`, a line-parsing helper. |
| Privacy toggles | **Partial** | `testConversationPersonalInfoCategoriesPersistRoundTrip` (DB layer), `testContextSelectionIncludesOnlyRequestedDataTypes`. The manager write path is uncovered (mutation passed, WS-15-04). |
| Context assembly | **Covered** | `testCompressionDropsDocumentsBeforePersonalInfo`, `testContextBuilderKeepsContiguousHistorySuffix`, `testScriptedDoctorConversationReceivesSelectedHealthContext`, `testScriptedGeneticDoctor…`, `MLXContextBudgetTests`. |
| Cancellation | **Not covered** | No test cancels anything: not extraction, not a stream, not a download. |
| Logging / PHI redaction | **Mostly covered** | `testAppLogRedactsSyntheticProviderContent…`, `testRedactionCoversJSONQuotedProviderValues`, `testProviderRequestIdentifier…`. The P0-2 call sites themselves (MLX tail, notification body, title log) are not. |
| Error surfacing | **Covered** | `ErrorHandlerTests` (4); positive control confirmed it goes red on regression. |
| On-device AI | **Rule only** | Value types tested; wiring and the generation path are not (WS-15-07). |
| UI flows | **2 smoke tests** | See WS-15-05. |

## Prior-findings regression table

"Reverts red" = a test exists that I believe fails if the fix is reverted. **Proven** = I confirmed it by injecting the regression in a scratch copy (mutation) or a positive control; **reasoned** = judged from reading the test and the fix.

| Prior ID | Test that guards it | Goes red if reverted? |
|---|---|---|
| P0-1 PDF page-index crash | none (`LabReportParserTests` only render valid PDFs) | **No. Proven**: fix reverted, 291/291 green |
| P0-2 PHI in logs | `ServiceClientTests` redaction tests cover `AppLog` redaction; not the specific sites fixed | **Partial**, reasoned |
| P1-1 streaming dies after first reply | none | **No. Proven** (throttle-slot clear and entry guard reverted) |
| P1-2 conversation snap-back | none | **No. Proven** (id guards removed) |
| P1-3 SSE mojibake | `testSSEDataPayloadParsing` tests line parsing only, not the `bytes.lines` decode that was the fix | **No**, reasoned (a byte-wise decode would still pass) |
| P1-4 retry no-op | `testRetryFailedMessageResolvesCurrentStateFromConversation` | Yes, reasoned (stale snapshot has `canRetry == false`, so no assistant message appears) |
| P1-5 privacy opt-outs revert | `testConversationPersonalInfoCategoriesPersistRoundTrip` (DB layer) | DB layer yes, reasoned. **Manager write path: No. Proven** (assignment removed, green) |
| P1-6 reprocess fails | `testLinkExtractedDataIsIdempotentForSameDocument` | Yes, reasoned (second link would throw) |
| P1-7 reprocess wipes metadata | none | **No. Proven** |
| P1-8 cancel not propagated | none | **No** (no test cancels anything) |
| P1-9 stuck in `.processing` | none | **No. Proven** (sweep disabled) |
| P1-10 share hands out encrypted file | `FileSystemTests.testDocumentEncryption` covers decrypt only; the share sheet is view code | **No**, reasoned |
| P1-11 blank PDF export | `testPDFExportContainsRealContent` (asserts extracted text) | Yes, reasoned |
| P1-12 plaintext documents table | `testMedicalDocumentPHIEncryptedAtRestAndRoundTrips` for new writes; **the v11 migration of existing rows: none** | New writes yes. **Migration: No. Proven** (v11 encryption no-op'd, green) |
| P1-13 single review slot | `testPendingImportReviewQueueSemantics`, `testAPendingReviewSurvivesReopeningTheDatabase` | Yes, reasoned |
| P1-14 `thumbnail_path` nulled | none | **No. Proven** |
| P1-15 multi-file import | none (view code) | **No** |
| FE-P0 review selections discarded | `testReviewSelectionPropagation` tests the extracted pure function, not the view wiring that was broken | Weak, see WS-15-05 |
| FE-P1a review save failure jams queue | none (`ContentView`) | **No** |
| FE-P1b delete during AI extraction | none | **No** |
| FE-P1c overlapping drain loops | none | **No** |

Positive controls (same method, to show it works): breaking the v12 `DROP COLUMN`, removing the `ErrorHandler` retry grace window, and breaking `MLXDownloadRetryBudget.recordProgress` turned exactly `testUpgradingFromVersion11PreservesDocuments`, `testRetryFailureIsNotDeduplicatedAway`, `testRealProgressEarnsTheBudgetBack` and `testResetClearsBothCounterAndBaseline` red, and nothing else.

## Findings

### WS-15-01 — The migration harness covers 2 of 12 steps; the one that rewrites user data (v11) has never been run by a test
- **Severity**: P1 · **Confidence**: CONFIRMED (mutation) · **Effort**: M
- **Location**: `HealthApp/HealthAppTests/DatabaseTests.swift:145-176` (the "v11" test); `HealthApp/HealthApp/Database/DatabaseManager.swift:590-591`
- **Scenario**: A beta tester (or the owner) holds a v10/v11 database from an earlier build. The v11 step re-encrypts every document row's file name, notes, provider, text, extracted data and sections, and every chat title, in place. A bug there (a double-encrypt, a NULL column, a changed nonce layout) corrupts or loses data on upgrade, and nothing in CI notices. `testUpgradingFromVersion11PreservesDocuments` does not exercise it: the fixture is a fresh current-schema file with one column re-added and the stored version wound back to 11 (`:165-167`), so the loop starts at 12 and never calls `encryptDocumentPHIColumns`. Steps 2-10 (documents columns, defaults, genetic-URL normalisation) are likewise never run.
  **Proof**: in a scratch copy I commented out `try encryptDocumentPHIColumns(db: db)` and `try encryptChatTitles(db: db)`. All 291 unit tests passed.
  A real v12 to v13 upgrade was verified by hand (`V13-RESTORE-VERIFICATION.md`), which is good, but it covers one step on one device; the encryption step carries the data risk. Argued as P1: the beta migrates real health data, and the plan's own rubric calls "a migration that degrades data" P1.
- **Evidence**:
  ```swift
  // DatabaseTests.swift:165-167 — the fixture skips straight to v11's *successor*
  try execute("ALTER TABLE documents ADD COLUMN raw_docling_output BLOB")
  try execute("DELETE FROM database_version")
  try execute("INSERT INTO database_version (version, created_at) VALUES (11, 0)")
  ```
  ```swift
  // DatabaseManager.swift:590-591 — mutated to a no-op, suite stayed green
  try encryptDocumentPHIColumns(db: db)
  try encryptChatTitles(db: db)
  ```
- **Fix**: Add a v10 fixture built from hand-written `CREATE TABLE` SQL (the v10 `documents` has plaintext `file_name`, `notes`, `provider_name`, `extracted_text` and the `raw_docling_output` column; `chat_conversations` has a plaintext `title`). Insert plaintext rows with raw SQL (no key needed), open with `DatabaseManager(databaseURL:)`, then assert the raw columns no longer equal the plaintext, `fetchMedicalDocument` and `fetchConversations` return the originals, the version is 13, and the row counts match. Add a second case that seeds a genetic-URL row to cover steps 9-10, and one with an empty `documents` table.
- **Blast radius**: `DatabaseTests.swift` only. Every future schema change (open tracker items 11, 12, 21 each want one) reuses the harness.
- **Verification**: Re-run the mutation above; the new test must go red. Re-run with the fix; green.

### WS-15-02 — The streaming chat path has no test, and the default AI provider streams
- **Severity**: P1 · **Confidence**: CONFIRMED (mutation) · **Effort**: M
- **Location**: `HealthApp/HealthAppTests/AIChatManagerTests.swift:116,212`; `HealthApp/HealthApp/Services/AIProviderInterface.swift:108`; `HealthApp/HealthApp/Managers/AIChatManager.swift:656,693,744-790`
- **Scenario**: Prior P1-1 (streaming dies after the first reply) and P1-2 (the view snaps back to another conversation mid-stream) were both fixed in `updateStreamingMessage`/`finalizeStreamingMessage`. No test enters that code. Every chat test calls `sendMessage(…, useStreaming: false)`. `sendStreamingMessage` switches on three concrete clients (`getBedrockClient()`, the OpenAI client, the MLX client), not on `AIProviderInterface`, and `ScriptedAIProvider` implements only the non-streaming `sendMessage` and reports `supportsStreaming: false`, so the test double cannot reach the streaming branch even if a test wanted to. On-device is the default provider (`testDefaultModelPreferencesUseOnDeviceProvider`) and streams, so this is the path a tester hits first.
  **Proof**: in a scratch copy I restored the pre-fix entry guard (`if streamingUpdateTask != nil { return }`), stopped clearing the slot on `CancellationError` and on success, and removed both `currentConversation?.id ==` guards (replaced with `if true`). 291/291 passed.
- **Evidence**:
  ```swift
  // AIChatManagerTests.swift:116 (and :212) — the only way chat is ever sent in a test
  try await chatManager.sendMessage("What should I ask my doctor about these labs?", useStreaming: false)
  ```
  ```swift
  // AIProviderInterface.swift:108 — ScriptedAIProvider
  supportsStreaming: false,
  ```
- **Fix**: Introduce one streaming seam: a small protocol (for example `StreamingChatProvider` with `sendStreamingMessage(_:context:conversationHistory:systemPrompt:onUpdate:onComplete:)`, which the three clients already effectively expose) that `sendStreamingMessage` calls through, resolved from `SettingsManager` the way `setAIClientOverrideForTesting` already works. Give `ScriptedAIProvider` a streaming form that emits N chunks with controllable pauses. Then test: two consecutive streamed turns both update the visible message before completion (P1-1); changing `currentConversation` mid-stream does not change it back (P1-2); cancelling mid-stream leaves no empty assistant bubble.
- **Blast radius**: `AIChatManager.sendStreamingMessage`, `SettingsManager` client resolution, the three clients' signatures. Medium refactor, behaviour-neutral.
- **Verification**: The mutation above must turn the new tests red.

### WS-15-03 — The P0-1 crash fix (PDF with an unloadable page) has no test and no fixture
- **Severity**: P1 · **Confidence**: CONFIRMED (mutation) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:308-313`; tests: none (`HealthAppTests/LabReportParserTests.swift:970-1020` render only valid PDFs)
- **Scenario**: The only P0 crash in the prior review. A PDF whose second page fails to load makes `pdfDocument.page(at: 1)` return nil; the fix appends an empty `PageText` so `finalPages[pageIndex]` stays in range. Revert it and every test still passes, because every PDF in the suite is a clean `UIGraphicsPDFRenderer` output. A user importing a damaged scan from a fax or phone app is exactly who hits it, and the failure is a crash on import.
  **Proof**: in a scratch copy I deleted the `pdfKitPages.append(…)` line so the loop only `continue`s (the original bug). 291/291 passed.
- **Evidence**:
  ```swift
  for i in 0..<pageCount {
      guard let page = pdfDocument.page(at: i) else {
          // Keep finalPages indices aligned with pageCount even when a
          // page fails to load — the OCR loop below indexes by page number.
          pdfKitPages.append(PageText(pageNumber: i + 1, text: "", observations: nil))
          continue
      }
  ```
- **Fix**: Preferred: pull the page-loading step behind a closure or tiny protocol (`pageCount`, `page(at:) -> PageLike?`) so a test can return nil for index 1 without crafting a corrupt file. Alternative: byte-patch a 3-page PDF generated in the test so one page object is unreadable; whether PDFKit then returns nil for exactly that page I could **not** verify here (PLAUSIBLE), so confirm before relying on it. Assert the extraction completes, `pages.count == 3`, and page 2's text is empty.
- **Blast radius**: `NativeDocumentExtractor` only.
- **Verification**: Re-run the mutation; the test must go red.

### WS-15-04 — Six more import-pipeline and privacy fixes can be reverted without a red test
- **Severity**: P1 · **Confidence**: CONFIRMED (mutation) · **Effort**: L
- **Location**: `HealthApp/HealthApp/Services/DocumentProcessor.swift:501-520` (P1-7, P1-14), `:1715` (P1-9); `HealthApp/HealthApp/Managers/AIChatManager.swift:1078` (P1-5 manager path); P1-8, FE-P1b, FE-P1c (no test touches cancellation or drain loops at all)
- **Scenario**: In one scratch build I reverted, simultaneously: the reprocess merge (`thumbnailPath`, `documentDate`, `providerName`, `includeInAIContext`, `tags`, `notes` now come from the fresh extraction, not `existingDocument`), the startup sweep of stuck `.processing` rows, the conversation's personal-info-category assignment in `selectHealthDataForContext`, plus the WS-15-01, -02 and -03 mutations and two others (below). **All 291 unit tests passed.** Real consequences: reprocessing a document silently resets the user's AI-context toggle and notes (P1-7); a force-quit mid-import leaves a spinner forever (P1-9); a privacy exclusion chosen in the chat sheet is not saved (P1-5). `DocumentProcessor` sits at 24.5 % coverage and `MedicalDocumentExtractor` at 0 %.
  Two further mutations in the same batch also passed: the MLX retry budget's `reset()` no longer clearing its baseline (WS-15-06) and the migration backup no longer being deleted (WS-15-11).
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:502-520 — each `existingDocument?.x ??` is a user-data guard with no test
  thumbnailPath: existingDocument?.thumbnailPath ?? currentItem.document.thumbnailPath,
  documentDate: existingDocument?.documentDate ?? extractionResult.documentDate,
  includeInAIContext: existingDocument?.includeInAIContext ?? false, // User must explicitly enable
  tags: existingDocument?.tags ?? currentItem.document.tags,
  notes: existingDocument?.notes ?? currentItem.document.notes
  ```
- **Fix**: Add, using the existing `makeRegressionHarness()` pattern: (a) save a document with notes, tags, date, AI-context on and a thumbnail path; reprocess it via `processDocumentAndExtractHealthDataForTesting`'s sibling that performs the commit; assert each survives. (b) Insert a row at `.processing`, construct a `DocumentProcessor`, assert `.failed`. (c) Cancel a queued item between OCR and commit; assert the row is not re-created after `deleteDocument`. (d) Call `selectHealthDataForContext` on an active conversation, reload from the database, assert the category set. The processor's commit step may need a small `internal` entry point; the sweep runs from `init`, so (b) needs no seam.
- **Blast radius**: `DocumentProcessor`, `AIChatManager`; tests only for (b) and (d).
- **Verification**: Each mutation above becomes a red test.

### WS-15-05 — 113 orphaned UI tests: what their absence costs (quantification of tracker item 25, not a new finding)
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: L
- **Location**: `HealthApp/HealthAppUITests/` (6 orphaned files, 113 tests: Accessibility 10, BloodTestEntry 19, ChatInterface 19, DocumentManagement 28, HealthAppUITests 17, PersonalInfoEditor 20); live: `RegressionSmokeUITests.swift` (2)
- **Scenario**: Only two UI paths execute: the seeded lab report appears in Documents, and a scripted reply appears in chat. Flows with **zero executable coverage** that a tester or App Review will touch:
  - first launch and the disclaimer gate (the smoke test passes `--skip-disclaimer`, `RegressionSmokeUITests.swift:11`, so no test ever sees it);
  - every import route (scan, Files, Photos) and the lab **import-review sheet**, where the last three view-state bugs lived ("Will Ignore" pre-marked, restore only on the Documents tab, review selections dropped);
  - manual blood-test entry, the personal-info editor, document detail/delete/export/share;
  - Settings (provider configuration, API key entry, clear data) and the `DatabaseUnavailableView` fallback;
  - the chat context selector, which is where the privacy toggles are set;
  - every iPad layout, Dynamic Type, and VoiceOver (the plan requires iPad, and open tracker item 30 is a layout bug nothing would catch).
  Two of the review-sheet bugs in this list are partly guarded only by unit tests of extracted pure functions, which the tests' own comments call out as not covering the view (`PreBetaRegressionTests.swift:403-405`, WS-15-12). Reviving the orphans is not free: WS-01-08 found their identifiers already out of step with the app, so some will fail on first compile.
- **Evidence**:
  ```swift
  // RegressionSmokeUITests.swift:9-15 — the disclaimer gate is bypassed in the only live UI test
  app.launchArguments = [
      "--ui-testing", "--reset-test-data", "--skip-disclaimer",
      "--seed-lab-report", "--scripted-ai-provider", ...
  ```
- **Fix**: Deferred by owner decision 4. Cheapest slice if reconsidered before wider beta: add three new tests to the live target, not the old files: disclaimer-gate-blocks-until-accepted; import-review sheet leaves an abnormal group undecided and saves the picked value; relaunch restores the pending review. Run them on the iPad destination as well.
- **Blast radius**: `project.pbxproj` target membership; the app's accessibility identifiers.
- **Verification**: `xcrun xcresulttool … summary` shows the new test count; the tests fail when the covered fix is reverted.

### WS-15-06 — Tests that cannot fail, or that assert something other than what they claim
- **Severity**: P2 · **Confidence**: CONFIRMED (reading; the MLX case also by mutation) · **Effort**: S
- **Location / scenario** (each can pass with the behaviour broken):
  1. `HealthAppTests/DocumentProcessingIntegrationTests.swift:8-27` — `testProcessingQueueItemSortsByPriority` builds three queue items and sorts them with its own `.sorted { $0.priority.rawValue > $1.priority.rawValue }`. It tests Swift's `sorted` and an enum raw value; `DocumentProcessor`'s real queue ordering is never invoked, so it cannot fail from a processor regression.
  2. `HealthAppTests/AIChatManagerTests.swift:538-549` — `testResetClearsBothCounterAndBaseline` passes for the wrong reason. `bytesAtLastRetry` is only read when `retriesUsed > 0`, and every path to that state goes through `recordRetry`, which overwrites it. **Proven**: I removed `bytesAtLastRetry = 0` from `reset()` and the test stayed green. The comment claims it checks the baseline is cleared; it cannot.
  3. `HealthAppTests/AIChatManagerTests.swift:94` — `XCTAssertGreaterThanOrEqual(result.conversationHistory.count, 0)`; an array count is never negative.
  4. `HealthAppTests/DatabaseTests.swift:10` — `XCTAssertNotNil(databaseManager)` on a non-optional `try DatabaseManager()`. The test passes if init does not throw, and it opens the real app database (WS-15-08).
  5. `HealthAppTests/AccessibilityTests.swift:12,15,18,88` — `XCTAssertNotNil` on non-optional `Font` / `SwiftUI.AccessibilityTraits` values. `:46-66` (`testAccessibilityColorsExist`) has **no assertions**; it only compiles.
  6. `HealthAppTests/NetworkingTests.swift:24` — `XCTAssertNotNil(manager.currentStatus)`; `currentStatus` is a non-optional `NetworkStatus`.
  7. `HealthAppTests/NetworkingTests.swift:83-106` — `testOfflinePathDoesNotRetainChatContentOrHealthContext` claims to test the offline path. It calls `removeLegacyPendingOperations(from:)`, the same function and the same assertion as `testLegacyPendingOperationsKeyIsRemovedDuringMigration` (`:66`). No offline code runs.
  8. `HealthAppTests/ModelTests.swift:449-460` — `testJSONTokenEfficiency` asserts both estimates are `> 0`; the name promises a comparison.
  9. `HealthAppTests/DocumentProcessingIntegrationTests.swift:560-566` — `testMedicalDocumentCapturesCurrentDocumentState` asserts the values passed to the test's own `makeDocument` helper; also `ModelTests.swift:7-33` (memberwise-init getters and setters). These inflate the count, not the confidence.
  10. `HealthAppTests/AccessibilityTests.swift:28-35` — `XCTAssertTrue(isIPad || isIPhone)`: `DeviceAccessibilityHelper.isIPhone` is defined as the exact negation of `isIPad` (`Utils/AccessibilityManager.swift:51-57`), so this is true by construction.
- **Evidence**:
  ```swift
  // DocumentProcessingIntegrationTests.swift:23-26
  let sorted: [ProcessingQueueItem] = [low, urgent, normal]
      .sorted { $0.priority.rawValue > $1.priority.rawValue }
  XCTAssertEqual(sorted.map { $0.priority }, [.urgent, .normal, .low])
  ```
  ```swift
  // AIChatManagerTests.swift:540-548 — passes whether or not reset() clears the baseline
  _ = budget.recordRetry(atBytes: 9_000_000)
  budget.reset()
  ...
  _ = budget.recordRetry(atBytes: 0)        // overwrites the baseline anyway
  budget.recordProgress(bytes: slice)
  XCTAssertEqual(budget.retriesUsed, 0)
  ```
- **Fix**: Delete 3, 4 (replace with a real fixture-DB open), 5, 6, 8; rename or rewrite 7 to call the real offline path (`AIChatManager.sendMessage` with `isOffline = true` and assert nothing is persisted); rewrite 1 to enqueue on a `DocumentProcessor` and read its queue order; for 2, either drop the claim or make `bytesAtLastRetry` observable (it is dead state reachable only through `recordRetry`, so `reset()` may simply not need to clear it).
- **Blast radius**: tests only. Net effect on the 293 count: about -8.
- **Verification**: for each rewritten test, revert the behaviour it names and confirm red (the project's own method).

### WS-15-07 — The extract-the-rule pattern for MLX is right, but it tests the rule, not that anything consults it
- **Severity**: P2 · **Confidence**: CONFIRMED (grep); wiring consequence PLAUSIBLE · **Effort**: M
- **Location**: `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceModels.swift:100-157`; `MLXModelDownloadManager.swift:64-97,948,1005,1028,1067`; `MLXOnDeviceClient.swift:472-480`; tests `AIChatManagerTests.swift:358-538`
- **Scenario**: **Premise correction first.** `MLXOnDeviceLLM/` is not wholesale `#if`-wrapped. Only the MLX imports (`MLXOnDeviceClient.swift:12-17`, `MLXModelDownloadManager.swift:11-14`) and the generation, loading and transfer bodies are; the files compile in the simulator with `simulatorNotSupported` stubs. That is why `MLXOnDeviceModels` shows 57 % and `MLXOnDeviceClient` 13.9 % coverage in the simulator run. The untestable part is the generation and download *bodies*, not the whole directory.
  **Assessment.** The pattern is the right first move, and two of the tests are genuinely good: `testTheRealInstructionTextFitsItsReserve` ties the real persona and rules strings to the constant that budgets them, so growing the rules fails a test; `testTheOnDeviceThresholdIsTighter…` tests the wiring into `AIChatManager.patientDataThreshold`, the one call site that is reachable in the simulator. The limits:
  1. The retry-budget bug that motivated the fix was a **wiring** bug (the counter was never restored). `MLXDownloadRetryBudgetTests` prove the arithmetic; no test constructs `MLXModelDownloadManager` (grep of `HealthAppTests` finds zero references), so deleting `self.retryBudget.recordProgress(bytes: bytes)` at `:948`, or the `recordRetry` calls at `:1028,1071`, leaves every test green. The same is true of `budget.nextTurnWouldOverflow` at `MLXOnDeviceClient.swift:477`.
  2. Some tests restate the formula (`testFixedCostsAreReservedBeforePatientData`) or have a vacuous upper bound (`testEverythingFitsInsideTheWindow` passes for an allowance of 0).
  3. Value types only help for decisions that are pure. Several decisions in these files still are not extracted.
  **Where else to apply it** (each is a pure function of values, in code the simulator skips):
  - `MLXModelDownloadManager.downloadModelFile` (`:139-257`): per-file action from `(existingBytes, expectedBytes, httpStatus, rangeHonoured)` to `{skip, resume, restart, fail}`. The 416 and 200-instead-of-206 branches are where a 16 GB download wastes or corrupts data, and they are inline in an `#if` region.
  - `MLXOnDeviceClient`'s session-rebuild rule (`stoppedForRepetition || reachedLengthLimit || windowPressure`, `:491`) and `makeChatSessionSignature` (when instructions change).
  - The stall watchdog's phase decisions (`:935-955`: idle > 5 s, > 60 s) as a function of `(now, lastMovement, lastBytes)`.
  For the wiring, take a second, small seam: inject the transfer (`protocol ModelTransfer`) and a clock into the download manager so the manager itself, which is not MLX-dependent, runs in the simulator against a fake transfer.
- **Evidence**:
  ```swift
  // MLXModelDownloadManager.swift:948 — the line the fix depends on; no test reaches it
  self.retryBudget.recordProgress(bytes: bytes)
  ```
  ```swift
  // MLXOnDeviceClient.swift:477-482 — likewise
  budget.nextTurnWouldOverflow(promptTokens: $0.promptTokenCount, generatedTokens: $0.generationTokenCount)
  ```
- **Fix**: Keep the pattern; add the three extractions above plus the transfer/clock seam; add one test per call site that a fake transfer reporting progress restores the budget and that the terminal path keeps shards.
- **Blast radius**: `MLXModelDownloadManager` (1,403 LOC), `MLXOnDeviceClient`. All device-only code paths; typecheck with the `generic/platform=iOS` command in the tracker.
- **Verification**: delete the `recordProgress` call in a scratch copy; the new manager test must go red.

### WS-15-08 — Unit tests run against the real app container and shared singletons
- **Severity**: P2 · **Confidence**: CONFIRMED (code paths); persistence of residue PLAUSIBLE · **Effort**: S
- **Location**: `HealthAppTests/DatabaseTests.swift:9`; `FileSystemTests.swift:15,338-339,400-401` (`FileSystemManager()` and `DatabaseManager()` with no URL); `FileSystemTests.swift:419,440` (`databaseManager.save(personalInfo)`); `AIChatManagerReliabilityTests.swift:11-14,44-46` (`DatabaseManager.shared`, `HealthDataManager.shared`, `SettingsManager.shared`); `HealthDataManagerTests.swift:24,44` (`HealthDataManager.shared`); the four copies of `makeRegressionHarness`/`makeHarness` call `SettingsManager()` with default `UserDefaults` and keychain
- **Scenario**: `DatabaseManager(databaseURL: nil)` resolves to Application Support in the test host's container, and `FileSystemManager(baseDirectory: nil)` to `Documents/HealthApp`, because `AppTestRuntime` redirects storage only for `--ui-testing`, which unit tests do not pass (`HealthAppApp.swift:416-438`). Unit tests are hosted inside the app, so they share its container. `DocumentExporterTests.testJSONExport` saves a "Test User" `PersonalHealthInfo`, `DocumentImporterTests.testImageImport` inserts a document and writes encrypted files, and none of it is removed in `tearDown`. On a simulator the owner is also using for manual verification, running the suite writes into the same database; the exports also assert on whatever else is already there.
  **Not verified**: after my runs the container on my simulator held no `health_data.sqlite` or imported files, so the residue is either reset per run or lands elsewhere. I did not trace why, so treat persistence as unconfirmed; the code paths and the absence of cleanup are not in doubt.
- **Evidence**:
  ```swift
  // FileSystemTests.swift:338-342
  fileSystemManager = try FileSystemManager()
  databaseManager = try DatabaseManager()
  documentImporter = DocumentImporter(fileSystemManager: fileSystemManager, databaseManager: databaseManager)
  ```
- **Fix**: Give those classes the harness the newer tests already use (temp root, injected URL), and delete the four copies of the harness in favour of one `TestHarness` helper that also passes `SettingsManager(userDefaults:keychain:)` with the in-memory fakes `SettingsManagerTests` already define.
- **Blast radius**: `FileSystemTests`, `DatabaseTests`, `AIChatManagerReliabilityTests`, `HealthDataManagerTests`. Test-only.
- **Verification**: run the suite and diff the simulator container before and after; it must be unchanged.

### WS-15-09 — Provider error paths and the networking seam are untested; no `URLProtocol` stub exists
- **Severity**: P2 · **Confidence**: CONFIRMED (coverage) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Services/OpenAICompatibleClient.swift` (24.2 %), `BedrockClient.swift` (7.3 %); tests `ServiceClientTests.swift:420-470`
- **Scenario**: The suite proves credentials are stored safely and error text is redacted. It does not prove behaviour on the first real call: 401/403 mapping, 429 and 5xx retry and delay, timeout, a cancelled request, a truncated stream, or a malformed SSE event (only the one-line parser has a test). Owner-only check 5 (one real Bedrock call) is outstanding for the same reason: there is no stubbed path that exercises `BedrockClient` above credential handling. No test touches a real network (confirmed by grep: no `URLSession`/external host use outside `.example.test` strings), which is correct; the gap is that nothing replaces the network either.
- **Evidence**: `xccov`: `OpenAICompatibleClient.swift 24.16% (265/1097)`, `BedrockClient.swift 7.32% (57/779)`.
- **Fix**: Add a session seam to `OpenAICompatibleClient` (it already takes a `baseURL` in the initialiser: add `session: URLSession = .shared`) and a `StubURLProtocol` in the test target. Write the tests listed as backlog items 10-12. For Bedrock, the minimum seam is whatever wraps the AWS SDK call; name it before writing tests.
- **Blast radius**: both clients' initialisers; `SettingsManager.getBedrockClient()`.
- **Verification**: stubbed 429 then 200 shows one retry and one delivered reply; coverage of the client files rises above 60 %.

### WS-15-10 — Encryption failure paths are untested, including the "key missing, database exists" case
- **Severity**: P2 · **Confidence**: CONFIRMED (coverage and grep) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:915-945` (`getOrCreateEncryptionKey`); `HealthApp/HealthApp/Utils/FileSystemManager.swift:57-63`; `DatabaseManager+Recovery.swift` (0 %)
- **Scenario**: When the keychain item is missing but the database file exists (a restore to a new device, a keychain wipe), the code logs "CRITICAL … data unreadable", creates a new key and carries on, so every existing row becomes undecryptable. Tracker item 12 (open, P1) is the sibling hazard: unreadable fields are written back over stored data. Neither has a test, and neither can be written today because both managers construct `Keychain()` directly while a `KeychainStoring` protocol and `InMemoryKeychain` fake already exist for `SettingsManager` (`SettingsManagerTests.swift:6`). The suite tests that encryption happens, never what happens when it cannot.
- **Evidence**:
  ```swift
  // DatabaseManager.swift:915-917
  private static func getOrCreateEncryptionKey() throws -> SymmetricKey {
      let keychain = Keychain()
  ```
- **Fix**: Pass a `KeychainStoring` into `DatabaseManager.init` and `FileSystemManager.init` (default `Keychain()`); then test wrong key (rows come back flagged unreadable, not blank), tampered ciphertext, and missing key with an existing database (no silent new key). Do it as part of the tracker-12 fix so the test lands with it.
- **Blast radius**: `DatabaseManager`, `FileSystemManager` initialisers; `Keychain.swift`.
- **Verification**: the three tests above fail against current behaviour for the missing-key case, which is the point.

### WS-15-11 — Migration backup retention and step rollback are untested
- **Severity**: P2 · **Confidence**: CONFIRMED (mutation) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:430,455-475`; tests: none
- **Scenario**: `createBackupBeforeMigration` copies the whole database, which for a v10 file is plaintext PHI, and `deleteMigrationBackups()` is the only thing that removes it. Delete that call and every test passes (**proven**: line commented in the scratch copy, green). A regression leaves a plaintext copy of the user's health data beside the encrypted database indefinitely, on exactly the upgrade path the encryption work was meant to protect. The converse (a step that throws must leave the stored version unchanged and keep the backup) is also unchecked.
- **Evidence**:
  ```swift
  // DatabaseManager.swift:427-430
  // The pre-migration backup is a plaintext-PHI snapshot — delete it
  // once the migration has committed.
  deleteMigrationBackups()
  ```
- **Fix**: In `DatabaseMigrationTests`, after each successful upgrade assert the directory contains no `*.backup.*`; add a case with a deliberately failing step (for example a `documents` table with a conflicting column) asserting the version is unchanged and one backup remains.
- **Blast radius**: `DatabaseTests.swift`; the failing-step case needs a test-only hook or a crafted fixture.
- **Verification**: re-run the mutation; red.

### WS-15-12 — The review-sheet regression tests cover the extracted function, not the wiring that failed
- **Severity**: P2 · **Confidence**: CONFIRMED (the test's own comment concedes it) · **Effort**: M
- **Location**: `HealthAppTests/PreBetaRegressionTests.swift:347-390,403-434`
- **Scenario**: FE-P0 was a no-op `Binding` in `BloodTestImportReviewView`: the user's pick never reached the saved record. The fix extracted `resolvedGroups(…)`, and the test calls it with `selectedIds` supplied directly. The function was never the broken part; if the view stops feeding `selectedIds` from its state again, this test stays green. `testUndecidedGroupIsNotImported` is explicit that the half that regressed ("`onAppear` no longer marks them ignored") is not covered (`:403-405`). That is honest, and it leaves the clinically important half (an abnormal potassium dropped silently) guarded by nothing.
- **Evidence**:
  ```swift
  // PreBetaRegressionTests.swift:403-405
  /// Not covered here: that `onAppear` no longer marks them ignored. That is view state
  /// and would need a UI test, and the UI test target currently compiles only
  /// `RegressionSmokeUITests`.
  ```
- **Fix**: Move the view's selection state into a small `@Observable` model (`ReviewSelectionModel`) that owns `selectedIds`/`ignoredGroupIds`, with `onAppear` logic as a method, and test the model; or cover it in the live UI target (WS-15-05).
- **Blast radius**: `BloodTestImportReviewView` (3.3 % covered, 1,032 LOC).
- **Verification**: put the `onAppear` pre-marking back in a scratch copy; the model test must go red.

### WS-15-13 — UI smoke tests depend on English strings and one SF-symbol name; no iPad or large-text run exists
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthAppUITests/RegressionSmokeUITests.swift:50-52,57-59,95-97`; orphaned files: `AccessibilityUITests.swift:69-203` (seven `sleep(1)`), `ChatInterfaceUITests.swift:387` (`Thread.sleep`)
- **Scenario**: Navigation uses visible labels ("Health", "Documents", "AI Chat", "Start New Conversation") and the status text "Completed"; the fallback new-conversation button is found by `identifier: "plus"`, an SF Symbol name rather than an accessibility identifier. A copy edit or a localisation breaks the live tests while the app is fine. The suite runs only on the single destination given, so the iPad sidebar branch (handled in code) and larger Dynamic Type are never exercised. The two live tests have no `sleep`; they use `waitForExistence`. They passed on all three runs, so no flakiness was observed.
- **Evidence**:
  ```swift
  // RegressionSmokeUITests.swift:95-97
  let newConversationButton = app.buttons.matching(identifier: "plus").firstMatch
  ```
- **Fix**: Add identifiers (`tab.health`, `documents.segment`, `chat.newConversation`, `document.row.status`) and query by them; run the smoke pair on the iPad destination in the beta checklist.
- **Blast radius**: view files that gain identifiers; the smoke test.
- **Verification**: run on iPhone and iPad destinations; both pass.

### WS-15-14 — "Encrypted at rest" assertions use `NotEqual`, which passes for many broken states
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthAppTests/PreBetaRegressionTests.swift:106,147`
- **Scenario**: The tests assert the raw column is **not equal** to the plaintext. That is true for an empty string, a base64 copy of the plaintext, a truncated value, or `nil`. The round-trip assertions that follow catch the nil and empty cases, but not "base64 of plaintext" (a plausible regression if someone swaps `encryptString(…).base64EncodedString()` for a bare `base64EncodedString()` helper). Low probability; cheap to harden.
- **Evidence**:
  ```swift
  XCTAssertNotEqual(rawNotes, "Patient notes with details", "notes must be encrypted at rest")
  ```
- **Fix**: Also assert the raw value does not contain the plaintext or its base64 form, and that it decodes to at least 28 bytes (nonce + tag) as `DatabaseManager+HealthData.swift` itself requires.
- **Blast radius**: tests only.
- **Verification**: temporarily store base64(plaintext); the test must go red.

### WS-15-15 — Test process: no test plan, Debug only, no CI, and a stdout summary that misreports by 146x
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp.xcodeproj/xcshareddata/xcschemes/HealthApp.xcscheme` (Testables `:31-53`)
- **Scenario**: The scheme runs the unit bundle parallelised and the UI bundle serially, with no `.xctestplan`, so there is no way to say "pre-beta gate = these suites on these two destinations" or to turn on coverage by default. `xcodebuild test` prints "Executed 2 tests" (the UI bundle), so anyone reading the log sees 2 where the real number is 293. Combined with no CI, the gate is whatever the owner remembers to run. Debug only means optimiser-dependent behaviour (the Release `#if DEBUG` branches in `AppTestRuntime`) is not exercised.
- **Fix**: Add `HealthApp.xctestplan` with a Unit configuration (iPhone) and a Smoke configuration (iPhone + iPad), coverage on; add a one-line script that prints the `xcresulttool` summary.
- **Blast radius**: scheme/test plan files; no source.
- **Verification**: `xcodebuild test -testPlan …` prints the correct totals.

## Test backlog (25, ordered; first five before the beta goes out)

| # | Test | Risk covered | File | Setup | Kind |
|---|---|---|---|---|---|
| **1** | v10 plaintext database upgrades to current: ciphertext on disk, originals decrypt, row counts and version right, no `*.backup.*` left | v11 data rewrite; backup retention (WS-15-01, -11) | `DatabaseTests.swift` (`DatabaseMigrationTests`) | hand-written v10 schema SQL, plaintext rows via raw SQL | unit |
| **2** | Two consecutive streamed turns both show live updates; switching conversation mid-stream does not switch back | P1-1, P1-2 (WS-15-02) | `AIChatManagerTests.swift` | streaming seam + scripted streaming provider | unit |
| **3** | PDF with an unloadable page imports without a crash; page count preserved | P0-1 (WS-15-03) | `LabReportParserTests.swift` or new `NativeDocumentExtractorTests.swift` | page-source seam (or byte-patched PDF, to be confirmed) | unit |
| **4** | Reprocessing keeps notes, tags, date, provider, AI-context flag and thumbnail path | P1-7, P1-14 (WS-15-04) | `DocumentProcessingIntegrationTests.swift` | `makeRegressionHarness`, saved document with user edits | unit |
| **5** | Stuck `.processing` rows become `.failed` at processor start; deleting a document mid-extraction does not resurrect the row | P1-9, P1-8, FE-P1b (WS-15-04) | `DocumentProcessingIntegrationTests.swift` | harness; a cancellable fake extractor | unit |
| 6 | Opt-out chosen in the chat sheet survives a later title write-back and a reload | P1-5 manager path, WS-01-01 | `AIChatManagerTests.swift` | harness, scripted provider with a delayed title | unit |
| 7 | Two overlapping drain loops: the superseded one does not clear the registry | FE-P1c | `DocumentProcessingIntegrationTests.swift` | harness, two queue starts | unit |
| 8 | Review save failure still advances the queue | FE-P1a | `PreBetaRegressionTests.swift` | processor with a failing save | unit |
| 9 | A step that throws leaves the version unchanged and one backup remains | migration rollback (WS-15-11) | `DatabaseTests.swift` | crafted conflicting fixture | unit |
| 10 | HTTP 401/403/429/500 and timeout map to the right `AIChatError`/`NetworkError`, with retry and delay on 429 | provider error paths (WS-15-09) | `ServiceClientTests.swift` | `StubURLProtocol` + `session:` seam | unit |
| 11 | A multi-byte UTF-8 character split across two chunks decodes intact | P1-3 | `ServiceClientTests.swift` | stubbed byte stream | unit |
| 12 | Truncated stream and malformed SSE event surface an error, not a partial saved reply | streaming errors | `ServiceClientTests.swift` | stub | unit |
| 13 | Wrong key and tampered ciphertext are reported unreadable, never blank, never written back | encryption failure, tracker item 12 | `DatabaseTests.swift` | `KeychainStoring` injected into `DatabaseManager` | unit |
| 14 | Missing keychain item with an existing database does not silently mint a new key | key loss (WS-15-10) | `DatabaseTests.swift` | same injection | unit |
| 15 | Fresh-install schema equals a fully migrated schema (`sqlite_master` diff) | migration drift | `DatabaseTests.swift` | v10 fixture migrated vs fresh | unit |
| 16 | `MLXDownloadFileDecision` table test: skip, resume, restart, fail by size, status 416/200/206 | 16 GB download waste | `AIChatManagerTests.swift` (MLX section) | new value type | unit |
| 17 | `MLXSessionRebuildPolicy` table test over repetition, length limit, window pressure | on-device persona eviction | same | new value type | unit |
| 18 | Download manager restores retries on progress and keeps shards on give-up, via a fake transfer and clock | retry wiring (WS-15-07) | new `MLXModelDownloadManagerTests.swift` | `ModelTransfer` seam | unit |
| 19 | Notification and log text for a failed document contains no file name | P0-2 sites | `ServiceClientTests.swift` | content-builder extracted | unit |
| 20 | UI: first launch shows the disclaimer and blocks until accepted | disclaimer gate | new live UI test | launch without `--skip-disclaimer` | UI |
| 21 | UI: review sheet leaves an abnormal group undecided; Import saves the picked value | FE-P0, "Will Ignore" | new live UI test | `--seed-lab-report` variant with an abnormal value | UI |
| 22 | UI: force-quit and relaunch restores a pending review | v13, tracker 31 | new live UI test | persistent store + relaunch | UI |
| 23 | UI: Documents grid at iPad portrait and at accessibility Dynamic Type | tracker 30 | new live UI test | iPad destination | UI |
| 24 | UI: manual blood-test entry saves and appears | core entry flow | revive from `BloodTestEntryUITests` | identifiers | UI |
| 25 | UI: chat context selector opt-out is honoured in the next request | privacy toggle UI to model | new live UI test | scripted provider echoing context | UI |

### Minimum seam set

Exists already: `AIProviderInterface` (non-streaming only), `ScriptedAIProvider`, `setAIClientOverrideForTesting`, `KeychainStoring` + `InMemoryKeychain` (for `SettingsManager` only), injectable `databaseURL`/`baseDirectory`, `HealthDataManager(automaticallyLoad:)`, `AIChatManager(automaticallyLoadConversations:)`. To introduce: (1) a **streaming provider protocol** the three clients conform to; (2) **`URLSession` injection** in the two cloud clients; (3) **`KeychainStoring` injection** into `DatabaseManager` and `FileSystemManager`; (4) a **page-source protocol** in `NativeDocumentExtractor`; (5) a **`ModelTransfer` + clock** seam in `MLXModelDownloadManager`; (6) one shared **`TestHarness`** replacing four copies.

## Structural risks

- The suite's confidence is concentrated in pure functions that were extracted to be testable. That is the right habit, but it means fixes whose defect was in the wiring (the review sheet, the retry budget, the throttle) are guarded only by tests that pass without the wiring.
- Hosted unit tests share the app's real container and singletons (`DatabaseManager.shared`, `SettingsManager.shared`); isolation is by convention in the newer tests and absent in the older ones.
- 24 % line coverage with the two largest risk files (`DocumentProcessor`, `AIChatManager`) at 24.5 % and 40 % means most regressions in them are caught, if at all, by the owner's manual runs.
- Every "tests catch it" claim in the fix passes was verified by hand-reverting one fix; mutation runs like the ones here (cheap: one scratch copy, one build) are the only systematic check, and nothing automates them.
- There is no CI and no test plan, so none of this runs unless the owner remembers to.

## Machine-readable summary

```json
[
  {"id":"WS-15-01","title":"Migration tests cover 2 of 12 steps; v11 data-rewrite step never run (no-op mutation passed)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/DatabaseTests.swift:145","HealthApp/HealthApp/Database/DatabaseManager.swift:590"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-02","title":"Streaming chat path has no test; P1-1/P1-2 revertable with all tests green","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/AIChatManagerTests.swift:116","HealthApp/HealthApp/Services/AIProviderInterface.swift:108","HealthApp/HealthApp/Managers/AIChatManager.swift:656"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-03","title":"P0-1 PDF unloadable-page crash fix has no test or fixture","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:308"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-04","title":"Reprocess merge, stuck-processing sweep, cancel, drain loops and privacy persistence are revertable without a red test","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:501","HealthApp/HealthApp/Services/DocumentProcessor.swift:1715","HealthApp/HealthApp/Managers/AIChatManager.swift:1078"],"effort":"L","area":"test-coverage"},
  {"id":"WS-15-05","title":"113 orphaned UI tests: flows with zero executable coverage (quantifies tracker item 25)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthAppUITests/RegressionSmokeUITests.swift:11"],"effort":"L","area":"test-coverage"},
  {"id":"WS-15-06","title":"Tests that cannot fail or assert something other than what they claim","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/DocumentProcessingIntegrationTests.swift:8","HealthApp/HealthAppTests/AIChatManagerTests.swift:538","HealthApp/HealthAppTests/AIChatManagerTests.swift:94","HealthApp/HealthAppTests/DatabaseTests.swift:10","HealthApp/HealthAppTests/AccessibilityTests.swift:12","HealthApp/HealthAppTests/AccessibilityTests.swift:28","HealthApp/HealthAppTests/NetworkingTests.swift:24","HealthApp/HealthAppTests/NetworkingTests.swift:83"],"effort":"S","area":"test-coverage"},
  {"id":"WS-15-07","title":"MLX value-type pattern tests the rule, not that anything consults it; extend to download-file and session-rebuild decisions","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:948","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:477"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-08","title":"Unit tests write to the real app container and shared singletons","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/FileSystemTests.swift:338","HealthApp/HealthAppTests/DatabaseTests.swift:9","HealthApp/HealthAppTests/AIChatManagerReliabilityTests.swift:11"],"effort":"S","area":"test-coverage"},
  {"id":"WS-15-09","title":"Provider error paths untested; no URLProtocol/session seam","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/OpenAICompatibleClient.swift","HealthApp/HealthApp/Services/BedrockClient.swift"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-10","title":"Encryption failure paths untested (wrong key, tamper, key missing with existing DB); Keychain not injectable","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:915"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-11","title":"Migration backup deletion and step rollback untested (plaintext PHI backup could be retained)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:430"],"effort":"S","area":"test-coverage"},
  {"id":"WS-15-12","title":"Review-sheet regression tests cover the extracted function, not the view wiring that failed","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/PreBetaRegressionTests.swift:403"],"effort":"M","area":"test-coverage"},
  {"id":"WS-15-13","title":"UI smoke tests rely on English labels and an SF-symbol name; no iPad or large-text run","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthAppUITests/RegressionSmokeUITests.swift:95"],"effort":"S","area":"test-coverage"},
  {"id":"WS-15-14","title":"At-rest encryption assertions use NotEqual only","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthAppTests/PreBetaRegressionTests.swift:147"],"effort":"S","area":"test-coverage"},
  {"id":"WS-15-15","title":"No test plan, Debug only, no CI; stdout reports 2 tests for a 293-test run","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/xcshareddata/xcschemes/HealthApp.xcscheme:31"],"effort":"S","area":"test-coverage"}
]
```
