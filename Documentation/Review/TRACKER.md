# Review tracker — live worklist

**Status**: WS-00, Batch A (01, 02, 03, 07) and Batch B (04, 05, 06, 08) complete (2026-10-22).
Remaining: WS-09–WS-16, then WS-17 formal triage.
**Owner of this file**: WS-17 (triage) replaces the worklist wholesale; fix agents update
only the Status column of their own row; anyone may append to "Found during fixing".

**Filed**: 120 findings — P1=37, P2=55, P3=28, P0=0 as filed.
**After orchestrator re-grade: 2 P0.** See "Re-grades" below. The worklist merges the
P0/P1 set into 24 work items; the P2/P3 remainder stays in the findings files until WS-17.

---

## Workstream status

| WS | Name | Status | Findings file | P0 | P1 | P2 | P3 |
|---|---|---|---|---|---|---|---|
| 00 | Baseline | **complete** | [WS-00-baseline.md](findings/WS-00-baseline.md) | 0 | 1 | 1 | 0 |
| 01 | Prior-findings regression | **complete** | [WS-01-prior-findings.md](findings/WS-01-prior-findings.md) | 0 | 2 | 7 | 4 |
| 02 | Data integrity & encryption | **complete** | [WS-02-data-integrity.md](findings/WS-02-data-integrity.md) | 0 | 6 | 3 | 6 |
| 03 | Concurrency | **complete** | [WS-03-concurrency.md](findings/WS-03-concurrency.md) | 0 | 3 | 3 | 9 |
| 04 | AI providers & network | **complete** | [WS-04-ai-providers.md](findings/WS-04-ai-providers.md) | 0 | 5 | 8 | 2 |
| 05 | Document pipeline | **complete** | [WS-05-document-pipeline.md](findings/WS-05-document-pipeline.md) | 0 | 6 | 9 | 0 |
| 06 | SwiftUI state & memory | **complete** | [WS-06-swiftui-state.md](findings/WS-06-swiftui-state.md) | 0 | 3 | 9 | 3 |
| 07 | PHI & security | **complete** | [WS-07-phi-security.md](findings/WS-07-phi-security.md) | 0 | 6 | 6 | 3 |
| 08 | Error handling & failure UX | **complete** | [WS-08-error-ux.md](findings/WS-08-error-ux.md) | 0 | 5 | 9 | 1 |
| 09 | iPad & adaptive layout | not started | | | | | |
| 10 | Accessibility | not started | | | | | |
| 11 | Performance & memory | not started | | | | | |
| 12 | MLX model lifecycle | not started | | | | | |
| 13 | App Store compliance | not started | | | | | |
| 14 | Build, signing & TestFlight | not started | | | | | |
| 15 | Test coverage | not started | | | | | |
| 16 | Docs drift | not started | | | | | |
| 17 | Triage & sequencing | not started | | | | | |

---

## Re-grades by the orchestrating session

Every P1 was re-read against source before it entered this worklist. Changes made:

| ID | Filed | Re-graded | Reason |
|---|---|---|---|
| WS-05-01 | P1 | **P0** | `BloodTestMappingService.swift:573-578` falls back to the hardcoded registry for **both** unit and reference range, then computes `isAbnormal` against the substituted range. A value in mmol/L is stored with a mg/dL unit, judged against mg/dL limits, displayed as fact and sent to the AI as fact. Routine path for any non-US report or any report whose unit column does not parse. Data corruption on a path a normal tester hits. |
| WS-05-04 | P1 | **P0** | `DocumentProcessor.swift:1286-1300` fabricates a `"Lab Report Processed" / "Document imported successfully"` row for documents with zero parsed values, with the comment *"to pass validation / This ensures isValid returns true"*. The result is a real blood-test record summarised "All normal". A false clinical record created deliberately to defeat a validator. |
| WS-03-01 | P1 | P1, **first in order** | Vision double-resume trap reproduced independently (exit 133). Mechanism certain; production trigger frequency unestablished, so not promoted — but sequenced first because the fix is a resume guard at near-zero risk. |
| WS-00-01 (`AIChatManager:1027`) | — | **downgraded** | My own lead. WS-03 showed the dropped error cannot change what the current session sends, since context is built from live state. Correctly reduced to "a failed save is invisible". |
| WS-07 "39 SPM pins" | — | corrected to 36 | Recount. |
| WS-00 `db!` lead | — | **withdrawn** | My error: quoted a stale `SwiftLintBaseline.json` entry. No `db!` exists in app source. |
| WS-00 "@unchecked Sendable ×5" | — | corrected to 3 | Two grep hits were doc comments. |
| WS-00 "unit + UI suites pass" | — | **corrected** | 258 unit cases + 2 UI smoke tests; 113 UI test functions in 6 files are orphaned from the target. |

---

## Fix worklist

Ordered. One agent per row; **never two agents on rows that share a file.**
Classification: BB = beta-blocker, SB = submission-blocker, PP = pre-public.

### Clinical correctness — the app can state a wrong fact about the patient

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 1 | WS-05-01 +07 +08 +09 | Unit and reference range silently fall back to the hardcoded registry, and `isAbnormal` is computed from the substituted range. Also: a dashed date in a neighbouring cell becomes the reference range; `5,4` parses as 54 | **P0** | BB | M | `Services/BloodTestMappingService.swift`, `Services/LabReportParser.swift` | todo |
| 2 | WS-05-04 | A document with zero parsed values is saved as a real blood test holding a fabricated "Lab Report Processed" row, summarised "All normal" | **P0** | BB | S | `Services/DocumentProcessor.swift` | todo |
| 3 | WS-05-02 | Urinalysis section state never resets, so serum creatinine is auto-accepted as *Urine* Creatinine and ferritin is dropped | P1 | BB | M | `Services/LabReportParser.swift` | after 1 |
| 4 | WS-05-11 +12 +10 | Auto-accept UX: abnormal results default to "Will Ignore" so one tap saves a record reading "All normal"; the only notice is a 12 s toast published *before* the commit; the review sheet never shows the test date | P1 | BB | M | `Views/BloodTestImportReviewView.swift`, `Services/DocumentProcessor.swift` | after 2 |
| 5 | WS-05-03 | Duplicate heuristic compares analyte names only, plus an import-date fallback: five historical labs imported in one sitting save one | P1 | BB | M | `Managers/HealthDataManager.swift`, `Services/BloodTestMappingService.swift` | after 1 |
| 6 | WS-05-06 | Review queue is in-memory only: Cancel or relaunch discards the document's extracted values, including auto-accepted ones, and nothing re-opens them | P1 | BB | M | `Services/DocumentProcessor.swift` | after 2, 4 |

### Crash and data loss

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 7 | WS-03-01 | Vision continuation double-resumes → uncatchable `SWIFT TASK CONTINUATION MISUSE` trap on the import path; the page-loop `catch` written to degrade gracefully cannot catch it | P1 | BB | S | `Services/NativeDocumentExtractor.swift` | **do first** |
| 8 | WS-02-01 + WS-07-03 + WS-02-02 | Restore to a new device silently destroys all health data: the DB is in device backups, the `WhenUnlockedThisDeviceOnly` key is not, and the code mints a fresh key over the restored database | P1 | BB | M | `Database/DatabaseManager.swift`, `Utils/Keychain.swift` | todo |
| 9 | WS-06-01 + WS-06-04 | Tapping Records destroys `DocumentsView`; the review sheets fire only on `.onChange` with no `initial:`, so a review completed off-screen never appears and every later review jams behind it. Values needing review are never imported | P1 | BB | M | `Views/HealthTabView.swift`, `ContentView.swift` | after 4 |
| 10 | WS-06-02 + WS-02-06 + WS-02-07 | Reset Database says "All health data has been permanently deleted" while the PHI is still in memory and on screen, and a Save writes it back; it also promises a backup it never makes and leaves documents on disk; migration backups are undeletable | P1 | BB | M | `Views/SettingsView.swift`, `Database/DatabaseManager.swift` | after 8 |
| 11 | WS-01-02 + WS-03-06 | Extraction commit uses a pre-AI-call snapshot with no cancellation re-check before `INSERT OR REPLACE`: deleting mid-extraction resurrects a broken row, user edits overwritten | P1 | BB | M | `Services/DocumentProcessor.swift` | after 2, 6 |
| 12 | WS-02-03 + WS-01-04 | Unreadable fields read as empty then written back over stored data; `validationFailed` swallowed so an invalid report finishes "successfully" | P1 | BB | M | `Database/DatabaseManager+Documents.swift`, `Services/DocumentProcessor.swift` | after 11 |

### Failures the user cannot see

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 13 | WS-08-01 + WS-08-04 + WS-05-05 + WS-08-07 | **Systemic**: `lastError` is written at ~12 sites in `DocumentManager` and read by no view; same for `DocumentImporter`, `DocumentExporter`, `ConversationExporter`, `MLXOnDeviceClient`, and `AIChatManager.errorMessage`. Every import failure is invisible, and a *failed load* renders as "you have no documents" | P1 | BB | L | `Managers/DocumentManager.swift`, `Utils/Document*.swift`, `Views/DocumentListView.swift`, `Views/DocumentGridView.swift` | todo |
| 14 | WS-00-01 | 14 discarded error paths in `Task { try await … }`, incl. vitals that appear saved but are not | P1 | BB | M | `ContentView.swift`, `Views/VitalsListView.swift`, `Views/ChatDetailView.swift`, `Managers/AIChatManager.swift` | after 9, 17, 18 |
| 15 | WS-08-05 | Lab values the user just reviewed or typed are dropped silently when `addBloodTest` refuses them | P1 | BB | M | `Managers/HealthDataManager.swift` | after 5 |
| 16 | WS-08-06 + WS-08-12 | Global error layer: `.warning` severity is queued and never displayed (drains only when another alert is dismissed); 5 s dedupe can swallow a Retry failure; a second error overwrites an unacknowledged first. Causes are also mislabelled — Bedrock errors become "Network error" | P2 | BB | M | `Managers/ErrorHandler.swift` | after 13 |

### AI providers

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 17 | WS-04-01 | Bedrock model ID is `claude-sonnet-4.5-…` with a dotted version where Anthropic uses hyphens (`claude-sonnet-4-5-20250929-v1:0`); the same repo writes `claude-3-5-sonnet-…` correctly. Probably breaks all Bedrock chat *and* cloud vision extraction, reported as "check your internet" | P1 | BB | S | `Services/BedrockClient.swift` | **verify with one real call, then fix** |
| 18 | WS-04-02 + WS-08-03 | Offline gate is not provider-aware (`ChatDetailView.swift:200`), so airplane mode disables the on-device model — the one path that needs no network. Banner also claims document processing is unavailable | P1 | BB | M | `Views/ChatDetailView.swift`, `Managers/AIChatManager.swift` | todo |
| 19 | WS-04-03 | `compressHealthDataContext` blind-truncates a sorted JSON blob from the end, so `personal_info` (allergies, medications, conditions) is dropped before bulky document text | P1 | BB | M | `Managers/AIChatManager.swift` | after 18 |
| 20 | WS-04-04 + WS-07-01 | No "data, not instructions" guard on the Bedrock or OpenAI-compatible paths (only MLX has `compactChatRules`), and `textual`'s `ImageLoader.shared` fetches any model-emitted image URL with no allowlist — together an exfiltration chain | P1 | BB | M | `Services/BedrockClient.swift`, `Services/OpenAICompatibleClient.swift`, `Views/ChatDetailView.swift` | after 17, 18 |

### Privacy and claims

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 21 | WS-02-04 +05 +12 + WS-07-02 | Plaintext PHI at rest: `patient_name` in the `metadata` column, page-1 thumbnails on disk and in backups, free-text tags, original filenames in on-disk names | P1 | BB | M | `Database/DatabaseManager+HealthData.swift`, `Services/BloodTestMappingService.swift`, thumbnail writer | after 1, 8 |
| 22 | WS-07-06 | 11 privacy claims the code does not support: README "never leaves the device"; backup removed "for HIPAA compliance" contradicting the non-HIPAA disclaimer; `NSHealthUpdateUsageDescription` claims write access the app never uses (`toShare: []`) | P1 | SB | M | `README.md`, `Views/PrivacyPolicyView.swift`, `Views/TermsOfServiceView.swift`, `project.pbxproj` | feeds WS-13 |
| 23 | WS-07-04 | No cloud-versus-on-device indicator in chat, and nothing asks before the first cloud send | P1 | BB | M | `Views/ChatDetailView.swift`, provider settings views | after 18, 20 |
| 24 | WS-07-05 | Tapping a genetics reference sends gene + diplotype in a query string to `pharmdog.clinpgx.org`, undisclosed | P1 | BB | S | `Models/GeneticTestResult.swift` | todo |

### Test infrastructure

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 25 | WS-01-08 | 113 UI test functions in 6 files are orphaned from the UI test target and never compile; stale selectors must be fixed to re-add them. Blocks all UI and accessibility verification | P2 | PP | L | `HealthApp.xcodeproj/project.pbxproj`, `HealthAppUITests/*` | todo |
| — | WS-00-02 | Review plan's iPad build destination malformed | P2 | — | S | plan + fix protocol | **fixed** |

**File-ownership hot spots** — these serialise absolutely:
`Services/DocumentProcessor.swift` (2, 4, 6, 11, 12) · `Managers/AIChatManager.swift` (14, 19, 20) ·
`Database/DatabaseManager.swift` (8, 10) · `Views/ChatDetailView.swift` (14, 18, 20, 23) ·
`Services/BloodTestMappingService.swift` (1, 5, 21) · `Services/LabReportParser.swift` (1, 3).

**Needs runtime verification before fixing** (no agent could run the app this round):
item 17 (one real Bedrock call), item 6 (promoted review sheet reusing stale state),
WS-03-03 (background GPU cancellation), WS-06-12 (migration time on a large library),
WS-06-11 (`AIResponseCleaner` main-thread cost on device).

---

## Decisions needed from the owner

| # | Decision | Options | Recommendation | Answer |
|---|---|---|---|---|
| 1 | **Should the app auto-accept any parsed lab value without review?** Items 1–6 all stem from auto-accept plus a lossy parser. | (a) require review for every imported value until the parser is trusted; (b) keep auto-accept but only when unit *and* range came from the document, never from the registry; (c) keep as-is and fix the individual bugs | (b) — it preserves the feature and makes the P0 structurally impossible: no substituted unit or range may ever be auto-accepted | |
| 2 | The core privacy claim ("health data never leaves the device") is false whenever a cloud provider is configured. Fix the claim or the product? | (a) reword to "on-device by default, cloud only if you configure it"; (b) ship v1 on-device only | (a) | |
| 3 | Device backups hold the encrypted DB but not the key, so a restore yields unreadable data. | (a) exclude the DB from backup too — a restore starts clean and the loss is explicit; (b) keep it and move the key to a syncable class; (c) build an explicit encrypted export/import | (a) for beta, (c) before public release | |
| 4 | Re-enabling the 113 orphaned UI tests is L-sized with stale selectors. Before beta or after? | (a) before; (b) after, with manual walkthroughs for the beta | (b) for beta, (a) before submission — and WS-09/WS-10 must then be told the tests don't exist | |
| 5 | **Is Bedrock in scope for the beta at all?** If item 17 confirms it never worked, nobody has been using it. | (a) fix the ID and keep it; (b) hide Bedrock for the beta and ship MLX + OpenAI-compatible | (a) if the one-line fix works; (b) if it needs more, since items 19, 20 and 23 all get smaller | |

---

## Found during fixing

| Date | Found by | ID | Title | File:line | Sev | Status |
|---|---|---|---|---|---|---|
| | | | | | | |
