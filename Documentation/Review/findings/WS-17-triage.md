# WS-17 — Triage, dedupe & fix sequencing

- **Agent / model**: Claude Opus 5 (subagent, WS-17)
- **Date**: 2026-10-25
- **Commit reviewed**: `782b52db`, working tree clean
- **Scope actually covered**: all 18 findings files (218 machine-readable findings), `TRACKER.md` in full, `git log` + full commit bodies for the 25 fix commits since `84e8c0f7`, and source verification of every finding I claim is open or mis-graded
- **Scope not covered**: no simulator run (instructed), so no test-suite re-run and no runtime verification; I re-verified the Debug **device** build only (`generic/platform=iOS`, **BUILD SUCCEEDED**, 0 first-party warnings) and SwiftLint from `HealthApp/` (**5 violations**, baseline holds)
- **Verdict**: nothing in the repository blocks a beta on *data safety* any more — the P0s and the data-loss P1s are genuinely fixed and I confirmed each in source. Two things block it anyway: the 1024 app icon carries an alpha channel, so the TestFlight upload itself will be rejected before any tester sees it, and a fresh install's first document import now ends on a red "Failed" badge with no reason shown. Both are S-sized.
- **Counts (open, after re-grade)**: P0=0 P1=4 P2=14 (tracked) · 103 P2/P3 remain filed-but-untriaged by design

**Override compliance**: `TRACKER.md` was read, not written. This file is my only write.

---

## 1. Headline answers

### Is anything still open that you have mis-prioritised?

Yes — three things, all of which I am raising *above* where they sit today.

1. **The 1024 icon's alpha channel (WS-13-12 / WS-14-07, filed P2) is a hard upload blocker.** `AppIcon-BisonHealthAI-Pro-1024.png` is PNG colour type 6 (RGBA). App Store Connect rejects a large app icon with an alpha channel (ITMS-90717) at *upload validation*, not at review. Nobody has ever archived this app, so nobody has hit it. Everything else on the submission checklist — manifest, export compliance, build number — was fixed so that an upload could happen; this is the one that stops it. **Promoted to P1 / beta-blocker.**

2. **A fresh install's first import ends in a silent dead end (WS-08-02, filed P1, never given a tracker item number).** Item 26's fix made `maxRetryAttempts` actually bite, which was right. But the terminal state it now reaches is `.failed`, and `DocumentDetailView.swift:270-277` renders only a Retry button for `.failed` — the captured reason lives in `DocumentProcessor.processingErrors`, whose only reader is `BatchProcessingView`, which shows a *count*. Fixing the infinite retry converted an invisible hang into an unexplained failure. For an outside tester on a fresh install with no vision model — the default — this is the first thing they do in the app. **This is the one real beta-blocker in the behaviour of the app.**

3. **Background cancellation of on-device generation (WS-11-02 + WS-03-03, both filed P1) was never itemised and is the only open finding whose claimed consequence is a crash on an ordinary action.** `suspendForBackground()` sets `isSuspendedForBackground = true` and then `await MLXGPUGate.shared.acquire()` (`MLXOnDeviceClient.swift:658-672`), so it queues *behind* the running generation; nothing cancels it. `isSuspendedForBackground` is written in two places and **read nowhere** — I grepped the whole file, it has 4 occurrences, all in those two functions. No GPU submission consults it. The action is "press Home while the model is replying". I am not promoting it to beta-blocker because the harmful half (MLX aborting on a background Metal submission) is unverified and unverifiable without a physical device — but it should be the first thing tested on the device you archive from, and it should not stay un-itemised.

Two things I think you have *over*-weighted:

- **The migration test debt (item 41 / WS-15-01..04) does not block a beta handed to a new outside tester.** A new tester fresh-installs at v14 and runs no migration at all. The untested v11 data-rewrite step only executes on an upgrade from v10, and the only database you know exists is yours. This is real debt and it is correctly P1 for *you*, but it is not on the beta path. Sequence it after the beta goes out, not before.
- **Item 25 (113 orphaned UI tests) is correctly deferred and I would leave it deferred.** Verified exactly: `project.pbxproj` has no UI-test Sources phase entry for any file but `RegressionSmokeUITests.swift`, and the six orphaned files hold exactly **113** `func test` declarations. Decision 4 was right.

### What is the shortest honest path to a build safe to hand an outside tester?

**Four work items, S+S+M+S, about half a day of work, then one archive.**

| Order | Work item | Why it is on the path | Eff |
|---|---|---|---|
| 1 | **W-A** — strip the alpha channel from the 1024 icon (and delete the unused `AppIcon-Doctor-Dark` set), delete `aps-environment` from the entitlements | Without this the upload is rejected and there is no build to hand anyone. The `aps-environment=development` key rides along because it is the other thing that fails an App Store-profile archive, and it costs one line | S |
| 2 | **W-B** — render the failure reason on a failed document (detail view + list subtitle) | The first thing a fresh-install tester does now ends in an unexplained red badge. This is the difference between a useful beta report and "it didn't work" | S–M |
| 3 | **W-C** — archive once, on a device, and run the three things only a device can check: a background-mid-reply, one real Bedrock call (decision 5), and the keychain restore path | Three P1-class fixes (items 27, 28, 29, 37) are typechecked and unit-tested but **have never executed**. One archive attempt also settles W-A for real | M |
| 4 | **W-D** — tell testers in the TestFlight notes: no vision model on first launch means imports fail until one is downloaded; on-device AI needs a model download of up to 16 GB | Honest framing costs nothing and removes the single biggest source of noise in the first round of reports | S |

**Nothing else blocks it.** Said plainly: the two P0s are fixed, the restore-destroys-everything bug is fixed, PHI at rest is encrypted, the exfiltration chain is closed, consent is fail-closed, and the privacy copy now matches the code. I checked each of those in source rather than taking the tracker's word. The four P1s I am leaving open (§4) are all "the app does something wrong that the user can recover from", not "the app loses or leaks data".

One caveat on W-C that I cannot resolve from here: external TestFlight testers need Beta App Review, which applies guideline 1.4.1. Item 39's persona fix was the right call for that and I verified the personas no longer claim credentials. If you want to skip Beta App Review, use internal testers (your own team, up to 100) and W-A..W-D is the whole list.

---

## 2. Dedupe map

218 findings across 18 files collapse to the 47 tracker items plus 10 entries the tracker never numbered. The tracker's own worklist already carries the merge for items 1–32; I reproduce only the merges it does **not** record, plus corrections to ones it does.

### 2.1 Merges the tracker already records (unchanged, verified consistent)

Items 1–32 and 33–47 as written in `TRACKER.md` §"Fix worklist". I checked every source ID in those rows against the findings files and found no mis-attribution. The merge is sound.

### 2.2 Merges the tracker does not record — these are the un-itemised findings

| New merged ID | Source IDs | Title | Filed | My grade |
|---|---|---|---|---|
| **M-1** | WS-01-01 + WS-03-02 | Title generation writes a stale conversation snapshot back over live state | P1, P1 | P1 |
| **M-2** | WS-06-03 | `ChatView.task` reloads all conversations on every appearance, orphaning the streaming placeholder | P1 | P1 |
| **M-3** | WS-08-02 | A failed document shows a badge and no reason | P1 | **P1 → beta-blocker** |
| **M-4** | WS-11-02 + WS-03-03 | On-device generation is not cancelled when the app backgrounds; unload queues behind it | P1, P1 | P1 |
| **M-5** | WS-04-05 | Bedrock non-streaming: real 60 s idle timeout, dead 300 s config, SDK retries ×3 re-sending PHI | P1 | P1 |
| **M-6** | WS-13-12 + WS-14-07 | 1024 icon is RGBA; unused second icon set | P2, P2 | **P1 → beta-blocker** |
| **M-7** | WS-13-07 + WS-14-10 | `aps-environment=development` entitlement with no remote push | P2, P3 | P2 (do with M-6) |
| **M-8** | WS-10-02 | `BisonTheme.gold` as a *foreground* colour on light backgrounds, 2.7:1, ~25 sites | P2 | P2 |
| **M-9** | WS-14-04 | `textual` is pinned by **branch `main`**, not a version or revision | P2 | P2 |
| **M-10** | WS-15-09 + WS-15-10 + WS-15-11 + WS-15-12 | Test-coverage P2s left out of items 41–44 | P2 ×4 | P2 |

**M-1 and M-2 are one work item, not two.** Both are "a concurrent write to `AIChatManager.conversations` replaces live state with a snapshot", both end at the same guard (`"Discarding streamed reply: conversation cleared mid-stream"`, present three times at `AIChatManager.swift:833`, `:914`, `:1021`), and both live in `AIChatManager.swift` + `ContentView.swift`. Fixing one without the other leaves the symptom.

### 2.3 Where the un-triaged remainder went

103 P2/P3 findings remain in the findings files with no tracker item, by the design the tracker states ("the P2/P3 remainder stays in the findings files until WS-17"). I am **not** itemising them here: a worklist of 103 P2s is the 400-undifferentiated-bullets failure the plan warns about. They stay addressable by ID. The ten in §2.2 are the ones I pulled out because they are either mis-graded or on the beta path.

---

## 3. Re-grading record — three outcomes, never conflated

### 3.1 FIXED — the code changed; the commit is named

Verified in source at `782b52db`, not taken from the tracker.

| Item | Source IDs | Commit | What I checked |
|---|---|---|---|
| 1 | WS-05-01 +07 +08 +09 | `bf6aff50`, `65ec1f23` | registry fallback no longer feeds auto-accept |
| 2 | WS-05-04 | pass 1 (`866e246d`) | no fabricated row builder remains |
| 3 | WS-05-02 | `65ec1f23` | urinalysis section state resets |
| 4 | WS-05-11 +12 +10 | `90f34aa8`, `25e18670` | `unitWasSubstituted`/`referenceRangeWasSubstituted` gate `isRecommended` |
| 5 | WS-05-03 | `c58dd33d` | duplicate heuristic widened |
| 6 | WS-05-06 | `05c1d940` (schema v13) | durable review queue; v13→v14 migration tests present |
| 7 | WS-03-01 | pass 1 | `ContinuationGate` present |
| 8 | WS-02-01 + WS-07-03 + WS-02-02 | `3c857bbb` | synchronizable key class |
| 9 | WS-06-01 + WS-06-04 | `90f34aa8` | `.onChange(..., initial: true)` at `ContentView.swift:691-707` |
| 10 | WS-06-02 + WS-02-06/07 + WS-13-05 | `65ec1f23`, `b4e7d3ab` | `cleanupOrphanedFiles` now has a caller; backup promise removed |
| 11 | WS-01-02 + WS-03-06 | `ffc8c912` | `requireExistingRow` puts check + write in one transaction |
| 12 | WS-02-03 + WS-01-04 | `ffc8c912` | `unreadableFields` populated at `DatabaseManager+MedicalDocuments.swift:420-522`; writers refuse at `:33` and `:275` |
| 13 | WS-08-01 +04 +07 + WS-05-05 | `0fa45ec9` | exporters + 4 `errorMessage` sites report; `didFailToLoad` empty state |
| 14 | WS-00-01 | `c58dd33d`, `b4e7d3ab` | `emptyStateView` site closed |
| 15 | WS-08-05 | `8cf5ee97` | — |
| 16 | WS-08-06 + WS-08-12 | `d5c040cc` | `.warning` now presented, not queued (`ErrorHandler.swift:142-151`) |
| 17 | WS-04-01 | pass 1 | id corrected; **still needs one real call** |
| 18 | WS-04-02 + WS-08-03 | `a7c44147` | — |
| 19 | WS-04-03 | `a7c44147` | — |
| 20 | WS-04-04 + WS-07-01 | `21666379`, `782b52db` | `removingRemoteImages` retained behind `needsCleaning` |
| 21 | WS-02-04/05/12 + WS-07-02 + WS-01-07 | `df8cdc10`, `6ed354d3` (schema v14) | `FileSystemManager.swift:141` stores `<uuid>.<ext>`; tags encrypted; **legacy filename rename deliberately deferred** |
| 22 | WS-07-06 + WS-13-04 | `3c857bbb`, `ee3b994e` | — |
| 23 | WS-07-04 + WS-13-03 | `8cf5ee97`, `b4e7d3ab` | `CloudProcessingConsent.requireConsent(for:)` throws — fail-closed |
| 24 | WS-07-05 | `21666379` | — |
| 26 | WS-09-01 | pass 1 | `retryCount` carried at `DocumentProcessor.swift:197` |
| 27 | WS-12-02 | `6ad65405` | **never executed** |
| 28 | WS-12-01 | `330bebf9` | **never executed** |
| 29 | WS-12-03 + WS-12-07 | `e825f276` | **never executed** |
| 33 | WS-13-01 + WS-14-03 | `bc2d440b` | `PrivacyInfo.xcprivacy` present |
| 34 | WS-13-06 + WS-14-02 | `bc2d440b` | key present, value `false` — **owner sign-off outstanding** |
| 36 | WS-11-03 | `b4e7d3ab` | `ConversationContextBuilder` now called |
| 38 | WS-11-07 (+ corrects WS-06-11) | `782b52db` | `needsCleaning` pre-check |
| 39 | WS-13-02 | `cdcdf53f` | personas reworded |
| 40 | WS-10-01 | `cdcdf53f` | 5 white-on-gold sites → `inkOnGold` |
| 45 | WS-16 | `b4e7d3ab`, `a584fb86` | CLAUDE.md at v14 |
| 47 | — | `b4e7d3ab` | — |

**29 of the original 32 items plus 33, 34, 36, 38, 39, 40, 45, 47 — consistent with your count.** Items 10, 14 and 23, which spent a day wrongly marked fixed, are genuinely fixed now; I verified each at the specific site that was missed.

### 3.2 STILL OPEN — the code is as reported

Each verified at the cited line today.

| ID | Where | What I saw |
|---|---|---|
| 25 | `project.pbxproj` | no UI-test Sources entry except `RegressionSmokeUITests.swift`; 113 orphaned `func test` |
| 30 | `DocumentGridView.swift:11-14, 51` | 4 `.flexible()` columns, fixed 200 pt tiles; `HealthTabView.swift:31-33` still `embedInNavigation: false` |
| 31 | `ContentView.swift:737` | `restorePendingImportReviews()` is a `.task` inside `DocumentsView` (struct begins `:544`) |
| 32 | `BloodTestImportReviewView.swift:88-90` | dismiss-before-await mitigation in place, **never re-verified in the app** |
| 21 (rest) | `FileSystemManager.swift:129-141` | forward-only; pre-2026-10-24 filenames unchanged, migration deferred |
| 35 (rest) | repo | no `.github/`, no `*.xctestplan`, no `ExportOptions.plist`, no distribution identity; `Scripts/archive.sh` is the only piece that landed |
| 41 | `DatabaseTests.swift` | migration tests start at v11/v12/v13 — **no v10 fixture**, so the v11 data-rewrite step still never executes |
| 42 | `AIChatManagerTests.swift:94`, `AccessibilityTests.swift:11-18`, `NetworkingTests.swift:22-24` | `XCTAssertGreaterThanOrEqual(count, 0)`; `XCTAssertNotNil` on non-optionals |
| 43 | `HealthAppTests/` | **zero** references to `MLXModelDownloadManager` |
| 44 | `FileSystemTests.swift:15,374-375,436-437`, `DatabaseTests.swift:9` | 6 no-URL inits into the real container |
| 46 (rest) | `CONTRIBUTING.md:64,67`; `AGENTS.md:18-19`; `README.md:291,294` | CONTRIBUTING names scheme `BisonHealthAI`/`BisonHealthAIUITests` and iPhone 15 — wrong on every count; AGENTS/README omit `cd HealthApp` and `-project`, so they fail from the repo root. `.claude/claude.md` still tracked lowercase |
| M-1..M-5, M-6..M-10 | §2.2 | all verified; details in §4 |

### 3.3 EVIDENCE DID NOT SUPPORT — the code never said what the report claimed

You asked for these explicitly. Two are mine to add; the rest are ones the tracker already caught, listed so the record is in one place.

**New, found by me:**

- **WS-13-07's evidence is false while its conclusion stands.** It states that `grep -riE "push|APNs|registerForRemote|UNUserNotificationCenter|UIBackgroundModes"` finds no notification code, and that "the only 'push' hits are English comments". `UNUserNotificationCenter` appears **four times** in `DocumentProcessor.swift` (`:1683` requests authorization; `:1702`, `:1717`, `:1735` add requests). The app does use notifications — *local* ones, which need no `aps-environment` entitlement. So delete the key as recommended, but the finding's stated grep result is wrong, and the next reader would have concluded the app posts no notifications at all. That matters because WS-08-02's dead end partly depends on those notifications not being seen in the foreground.

- **Item 37's fix describes a mechanism the library does not have.** Covered in §5.1; it is a comment-vs-contract error in a fix, not a false finding, but it belongs in this list because an agent will reason from it.

**Already on the record, re-confirmed:**

| Claim | Verdict |
|---|---|
| WS-00's `db!` force-unwrap lead | withdrawn — quoted a stale `SwiftLintBaseline.json` entry; no `db!` in app source |
| WS-00 `@unchecked Sendable` ×5 | wrong; 3 at the time, 4 now (the item-7 `ContinuationGate`) |
| WS-00 "unit + UI suites pass" | wrong; 113 UI tests never compiled |
| WS-07 "39 SPM pins" | 36 at the time; **36 today** — I recounted `Package.resolved` |
| WS-14's `CURRENT_PROJECT_VERSION` ×8 | 6 |
| WS-16 "Terms date is stale" | wrong — `git log` shows the file genuinely unchanged since 2026-07-03; bumping it would have been the untruth |
| "The MLX files compile out entirely" (the orchestrator's own note) | too strong; only the load/generate/transfer **bodies** are stubbed |
| WS-15's own `MLXDownloadRetryBudget` reset test | asserted something unobservable; renamed |
| WS-06-11 (`AIResponseCleaner` repetition scan) | right defect, wrong function — WS-11-07 found the real cost |
| WS-16 "`MEDICAL_DOCUMENTS_IMPLEMENTATION.md` is referenced but absent" | **no longer holds**: the file is absent, but `b4e7d3ab` removed the dangling reference. Fixed, not wrong |
| Item 40 "a one-token swap at ~6 sites" closes the contrast finding | **incomplete**, not wrong: it closed WS-10-01 (white *on* gold, 5 sites). WS-10-02 (gold *as* foreground at 2.7:1) is a separate, still-open half at ~25 sites |

### 3.4 Severity moves, with the one-line reason required

| ID | From | To | Reason |
|---|---|---|---|
| WS-13-12 / WS-14-07 (M-6) | P2 | **P1 / beta-blocker** | An alpha channel on the 1024 icon fails upload validation, so it gates every build to every tester — not a polish item |
| WS-08-02 (M-3) | P1, unscheduled | **P1 / beta-blocker** | Item 26's fix made `.failed` reachable, which turned an invisible hang into the fresh-install tester's first and unexplained dead end |
| WS-10-02 (M-8) | P2 | P2, **re-opened** | Treated as closed by item 40; it is the other half and was not touched |
| WS-13-07 (M-7) | P2 | P2, **sequenced with M-6** | Only a signing-hygiene item, but it is the second thing that fails a distribution archive and costs one line |
| WS-15-01..04 (item 41) | P1 | P1, **moved after the beta** | A new tester fresh-installs at v14 and runs no migration; the untested v11 step is an upgrade-only path |
| WS-11-02 + WS-03-03 (M-4) | P1, unscheduled | P1, **itemised, device-test first** | Only open finding whose claimed consequence is a crash on an ordinary action; the harmful link needs a device |
| WS-04-05 (M-5) | P1 | P2 | The dead 300 s config is CONFIRMED; the harm (a >60 s generation re-sending PHI ×3) needs a Bedrock account nobody has exercised, and decision 5 leaves Bedrock in but unproven |

---

## 4. The open worklist, sequenced

Order: unblocks-others → data safety → crash/hang → compliance deadline → everything else. No two rows share a file.

| # | Merged ID | Title | Sev | Class | Eff | Files (ownership) | After | Migration? |
|---|---|---|---|---|---|---|---|---|
| **W-A** | M-6 + M-7 | Strip alpha from `AppIcon-BisonHealthAI-Pro-1024.png`; delete the unused `AppIcon-Doctor-Dark` set; delete `aps-environment` | P1 | **BB** | S | `Assets.xcassets/*.appiconset`, `HealthApp.entitlements`, `project.pbxproj` | — | no |
| **W-B** | M-3 | Render the failure reason and recovery advice on a failed document; persist a short filename-free reason with `.failed` | P1 | **BB** | S–M | `Views/DocumentDetailView.swift`, `Views/DocumentListView.swift`, `Services/DocumentProcessor.swift` | — | no |
| **W-C** | — | One device archive + the three owner-only runtime checks (background-mid-reply, one Bedrock call, keychain restore) | — | **BB** | M | none (verification) | W-A | no |
| **W-D** | — | TestFlight tester notes: no vision model on first launch, model download size | — | **BB** | S | tester notes only | W-B | no |
| W-E | M-4 | Cancel in-flight generation on `.background` before unloading; consult `isSuspendedForBackground` before GPU submission | P1 | PP | M | `HealthAppApp.swift`, `MLXOnDeviceLLM/MLXOnDeviceClient.swift`, `Managers/SettingsManager.swift` | W-C (needs the device result) | no |
| W-F | M-1 + M-2 | Apply only the title to live state; make `loadConversations` merge, not replace, while sending; persist the placeholder up front | P1 | PP | M | `Managers/AIChatManager.swift`, `ContentView.swift` | — | no |
| W-G | item 31 | Move `restorePendingImportReviews()` and its sheet to the root view | P2 | PP | M | `ContentView.swift`, `Views/HealthTabView.swift` | **W-F** (same file) | no |
| W-H | item 30 | iPad portrait grid: adaptive columns; revive or delete the dead master-detail | P2 | PP | M | `Views/DocumentGridView.swift`, `Views/HealthTabView.swift` | **W-G** (same file) | no |
| W-I | item 35 rest | CI workflow, shared test plan, `ExportOptions.plist`, distribution identity | P1 | SB | M | `.github/`, `*.xctestplan`, `project.pbxproj` | W-C (archive proves the identity) | no |
| W-J | item 41 | Migration tests: v10 fixture through to v14, backup deletion, step rollback | P1 | SB | L | `HealthAppTests/DatabaseTests.swift` | — | no (tests only) |
| W-K | items 42+43+44 + M-10 | Test hygiene: delete the tests that cannot fail, construct `MLXModelDownloadManager`, give hosted tests temp containers | P2 | SB | M | `HealthAppTests/*` | **W-J** (same file) | no |
| W-L | M-5 | Bedrock: honour `config.timeout`, `maxAttempts = 1` for non-streaming PHI calls | P2 | PP | M | `Services/BedrockClient.swift` | W-C (decision 5) | no |
| W-M | item 32 | Re-verify the Import-tap mitigation in the app | P2 | PP | S | none (verification) | W-C | no |
| W-N | M-8 | A darker gold for foreground use; audit the ~25 `foregroundColor(BisonTheme.gold)` sites | P2 | PP | M | `Utils/BisonTheme.swift` + ~14 views | — | no |
| W-O | item 46 rest | Fix the build commands in `CONTRIBUTING.md`, `AGENTS.md`, `README.md`; rename `.claude/claude.md` | P2 | PP | S | those 4 files | — | no |
| W-P | M-9 | Pin `textual` to a revision or version instead of branch `main` | P2 | PP | S | `project.pbxproj`, `Package.resolved` | — | no |
| W-Q | item 21 rest | Path-rewriting migration to rename legacy `<uuid>_<name>` files | P2 | PP | M | `Database/DatabaseManager.swift`, `Utils/FileSystemManager.swift` | **serialises with any other migration** | **YES — v15** |
| W-R | item 25 | Re-add the 113 orphaned UI tests | P2 | PP | L | `project.pbxproj`, `HealthAppUITests/*` | W-I (test plan) | no |
| W-S | WS-13-09, -10, -13 | Persistent in-session AI disclaimer; ASC declarations; public privacy/support URL | P2 | SB | M | `Views/ChatDetailView.swift`, ASC metadata | **W-F** (same file) | no |

**Only one migration is outstanding (W-Q, → v15).** Nothing else in the list touches schema, so the absolute-serialisation hazard the plan warns about does not currently exist. Keep it that way: W-Q claims v15 the moment it starts.

### File-ownership hot spots that still bite

`Managers/AIChatManager.swift` (W-F) · `ContentView.swift` (W-F, W-G) · `Views/HealthTabView.swift` (W-G, W-H) · `Views/ChatDetailView.swift` (W-S) · `Services/DocumentProcessor.swift` (W-B) · `HealthAppTests/DatabaseTests.swift` (W-J, W-K) · `project.pbxproj` (W-A, W-I, W-P, W-R — **four items, serialise them all**; and per your memory note, hand-editing it makes SourceKit noisy until the next build).

### Effort totals

| Classification | Items | S | M | L | Realistic total |
|---|---|---|---|---|---|
| **BETA-BLOCKER** | W-A..W-D | 3 | 1 | 0 | **~half a day** |
| PRE-PUBLIC | W-E..W-H, W-L..W-Q, W-N | 3 | 7 | 0 | ~4 days |
| SUBMISSION-BLOCKER | W-I, W-J, W-K, W-S | 0 | 3 | 1 | ~2.5 days |
| BACKLOG | W-R + the 103 untriaged P2/P3 | — | — | — | not estimated |

### ACCEPTED — real issues the project chooses to live with (each needs your yes or no)

| ID | Rationale offered |
|---|---|
| item 25 | Decision 4: manual walkthroughs for the beta, re-add before submission |
| item 21 (filenames) | Forward-only fix shipped; the legacy rename needs a schema-v15 path rewrite and the privacy policy now states the exception explicitly |
| `MLXOnDeviceClient.lastError` | One assignment site inside `testConnection()`, whose `Bool` return is the signal and which has no UI caller — wiring it would fire modal errors from a dead path |
| the `.retrying` orange contrast | Never measured; left alone rather than changed on a guess |
| 103 untriaged P2/P3 findings | Addressable by ID in the findings files; itemising them would bury the four that matter |

---

## 5. New risks the fixes introduced, and fixes that interact badly

This is the part that only a whole-picture read finds. Four, in descending order of how much I'd want you to know.

### 5.1 Item 37 sets `MLX.Memory.memoryLimit` below the weight size of the model the app deliberately enables — and the comment describing it is wrong

- **Severity**: P2 · **Confidence**: CONFIRMED on the arithmetic and the library contract; PLAUSIBLE on the user-visible outcome (nothing has run on a ≥24 GB Mac) · **Effort**: S
- **Location**: `MLXOnDeviceLLM/MLXOnDeviceModels.swift:113-117, 283-296`; `MLXOnDeviceLLM/MLXOnDeviceClient.swift:590-597`

`allocationLimitBytes` returns `0.55 × physicalMemory`. `medGemma27BTextIT4Bit` is gated to a Mac with ≥ 24 GB installed and its `estimatedSizeBytes` is `16_022_116_230`. On exactly 24 GiB the limit computes to **~14.2 GB — below the 16.02 GB of weights**, before a single KV-cache token.

And the stated mechanism is not the library's. The source comment says "above this MLX releases cached buffers rather than letting the footprint keep climbing". mlx-swift 0.31.3's own documentation for that property, in this project's resolved checkout, says:

> `Memory.swift:280` — "Calls to malloc will wait on scheduled tasks if the limit is exceeded. The memory limit defaults to 1.5 times the maximum recommended working set size reported by the device."

Releasing buffers is `cacheLimit`'s behaviour; `memoryLimit` makes allocation **wait**. So for MedGemma 27B the change does not bound the footprint — it makes every allocation past 14.2 GB block on scheduled work, on the path with the heaviest model. On an 8 GB iPhone the new limit (~4.4 GB) lands near MLX's own default, so it is roughly neutral there; on a 24 GB Mac MLX's default would be ~24 GB and the app now *lowers* it. The fix is plausibly a no-op where it was aimed and a pessimisation where it was not.

**Fix**: floor `allocationLimitBytes` above `selectedModel.estimatedSizeBytes` plus working room, and correct both comments to say what the property does. Then measure once on a device — which, as the commit itself says, is a single constant away.

### 5.2 Item 26's fix made item M-3's dead end reachable

Covered in §1. Not a regression — item 26 was right — but the two fixes have to ship together to be a net improvement for a fresh install, and only one of them has. This is the clearest case in the review of a fix being correct in isolation and incomplete in sequence.

### 5.3 One failed conversation load now raises two alerts

- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Managers/AIChatManager.swift:245-246`

```swift
ErrorHandler.shared.handle(error, context: "Loading conversations", severity: .error)
errorHandler.handle(error, context: "Load Conversations")
```

`errorHandler` is `ErrorHandler.shared` (`:50`), so both calls reach the same handler. `HandledError.isSimilar` dedupes on *identical* context **and** message within 5 s (`ErrorHandler.swift:73-79`) — and these two contexts differ only in wording, so dedupe does not fire. Item 16's fix also made `.warning` present immediately instead of queueing, so the second alert now reliably appears behind the first. The user dismisses one error and gets it again. Delete one of the two lines.

### 5.4 Items 12 + 13 together can make a document permanently read-only with no way out

- **Severity**: P3 (the trade is deliberate and correct) · **Confidence**: CONFIRMED · **Effort**: S if you want a message

Item 12 made full-row writers throw `DatabaseError.lossyWriteRefused` while any field is unreadable, and marked it `isRecoverableByErasingData = false` — both right, since the refusal exists to protect recoverable ciphertext. Item 13 then routes every such failure to a modal alert. Net effect for a user with one undecodable field: a modal error on every save attempt on that document, forever, with `launchRecoverySuggestion` ("share the diagnostic logs") deliberately *not* exposed as `recoverySuggestion`, so the runtime alert carries `errorDescription` alone.

I checked the trigger condition for false positives and found none: `decodeTagsColumn` returns `wasUnreadable: !stored.isEmpty` (`DatabaseManager.swift:667`), so an empty tags column is correctly treated as readable. The guard is sound. What is missing is a sentence telling the user this document is locked on purpose and their data is intact. One `recoverySuggestion` case.

---

## 6. Decisions needed from you

Decisions 1–5 are answered and recorded; these are the ones still live.

| # | Decision | Options | My recommendation |
|---|---|---|---|
| 6 | **`ITSAppUsesNonExemptEncryption = false`** (item 34) is a legal declaration, not an engineering default. swift-nio-ssl 2.36.1 vendors BoringSSL via the AWS SDK, so the binary may ship a non-system TLS implementation | (a) sign off on `false`; (b) declare `true` and file the annual self-classification; (c) drop Bedrock, which removes BoringSSL and the question with it | **(a)** for the beta — the app implements no cryptography of its own and uses CryptoKit + TLS. Revisit at submission if you keep Bedrock. This is yours, not mine |
| 7 | **Internal or external TestFlight testers for round one?** External triggers Beta App Review (guideline 1.4.1 applies; item 39 was the fix for that) | (a) internal only, ship after W-A..W-D; (b) external, add W-S's in-session disclaimer and the public privacy URL first | **(a)** — it makes W-A..W-D the complete list and gets real device feedback on the three never-executed MLX fixes days earlier |
| 8 | **The 384 KiB/token KV estimate has never been measured** (item 37). The floor means the cap currently does nothing on a phone, and §5.1 says it is actively wrong on a 24 GB Mac | (a) measure once on your device and set the real constant; (b) leave the floor and fix only the MedGemma inversion; (c) revert item 37's context clamp and keep only the 64K slider cap | **(a)** then **(b)** — one measurement during W-C retires the whole question |
| 9 | **Does the beta ship the MedGemma 27B Mac path at all?** It is 16 GB, reachable only on iOS-on-Mac at ≥24 GB, has never been run, and §5.1 says its memory limit is now set below its own weights | (a) hide it for the beta; (b) ship it and let §5.1 be found | **(a)** — zero testers can use it, and it is the one configuration where a fix is demonstrably mis-sized |
| 10 | **Item 32 was mitigated but never re-verified.** Shipping an unverified fix to a data-entry path is a judgement call | (a) re-verify during W-C; (b) accept it | **(a)** — it is minutes of work inside a run you are already doing |

---

## 7. What I could not verify

Said as plainly as the rest, because it bounds everything above.

- **No test run.** I was instructed not to use a simulator, so **324 tests passing is the commit messages' claim, not mine.** I verified the two things a simulator is not needed for: the Debug device build at `782b52db` (**BUILD SUCCEEDED**, the only build that typechecks the MLX bodies) and SwiftLint from `HealthApp/` (**5 violations**, baseline intact). The last commit to claim a *full* suite run after its own test edits is `ee3b994e` (307/307); `6ed354d3` explicitly says its full suite was **not** re-run after a test fix, and `782b52db` reports 324 without saying whether that was the whole bundle. **Run the suite once before W-C.**
- **Nothing in `MLXOnDeviceLLM/` has ever executed.** Items 27, 28, 29 and 37 are typechecked and unit-tested through extracted value types (`MLXContextBudget`, `MLXDownloadRetryBudget`, `MLXMemoryBudget`) and the wiring around them has never run. Item 43 is the same gap stated as test debt: there is literally no test that constructs `MLXModelDownloadManager`. My confidence in all four is "the rule is right"; it says nothing about whether anything consults the rule. §5.1 is an instance of exactly that.
- **M-4's harmful link is unverifiable from here.** Whether MLX aborts rather than throws on a background Metal submission needs a physical device.
- **M-5's harmful link is unverifiable from here.** Whether a Bedrock generation exceeds 60 s needs credentials and a real call. The dead config is confirmed; the consequence is not.
- **M-6's consequence is one step beyond what I checked.** The alpha channel is CONFIRMED (PNG colour type 6, read from the file's IHDR). That App Store Connect rejects it with ITMS-90717 is the documented behaviour and nobody has attempted an upload, so treat the rejection as PLAUSIBLE-with-a-named-link. One archive attempt settles it, which is why W-A sits before W-C rather than instead of it.
- **WS-14-09's three Release-configuration warnings** were not re-checked; I built Debug.
- **Items 30 and 31's user-visible behaviour** is WS-09's live observation, not mine. I confirmed the code is unchanged, which is all a static read can do.

## 8. Structural risks (capped at five)

1. **Confidence is concentrated in extracted pure functions.** The habit is right, but every defect this review found in `MLXOnDeviceLLM/` was a *wiring* bug, and wiring is exactly what the value-type tests do not cover. §5.1 is the third instance.
2. **`AIChatManager.conversations` is shared mutable state written from three streaming completion paths, a title generator and a view `.task`.** M-1 and M-2 are two symptoms of one design; a third will appear.
3. **Duplicated constants keep biting.** `782b52db` names it as the third occurrence (two `htmlEntities` tables). §5.3 is a fourth shape of the same thing: two error contexts that should be one string.
4. **Documentation drifts faster than it is corrected, and agents act on it.** `a584fb86` had to re-fix CLAUDE.md's version *hours* after the previous pass fixed it. §5.1's wrong comment is the same failure inside source.
5. **No CI means none of this runs unless you remember.** W-I is the only item on the list that changes that, and it is the one most easily deferred.
